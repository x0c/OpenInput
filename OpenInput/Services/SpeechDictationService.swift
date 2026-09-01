@preconcurrency import AVFoundation
import AppKit
import Foundation
import Speech
import os

/// 麦克风授权：查状态、显式请求、跳转系统设置。
enum MicrophonePermission {
    static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var isAuthorized: Bool { status == .authorized }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

/// 实时听写：小窗打开且开关开启时自动开始，文字边说边进编辑框。
@MainActor
@Observable
final class SpeechDictationService {
    static let shared = SpeechDictationService()

    enum Status: Equatable {
        case idle
        case preparing
        case installingAssets
        case listening
        case unavailable
        case failed
    }

    private(set) var status: Status = .idle
    private(set) var statusMessage: String?
    /// 已确认的听写正文（不含正在说的那一截）。
    private(set) var committedText: String = ""
    /// 正在说、尚未落定的预览。
    private(set) var volatilePreview: String = ""
    /// 输入电平 0...1，给面板状态指示用。
    private(set) var inputLevel: Float = 0
    private(set) var assetProgress: Double = 0

    var isListening: Bool {
        status == .listening || status == .preparing || status == .installingAssets
    }

    var isSupportedByOS: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private let logger = Logger(subsystem: "com.x0c.openinput", category: "听写")
    private let mic = MicrophoneTap()
    private let relay = BufferRelay()
    private var startGeneration: UInt64 = 0
    private var lastLevelPosted: TimeInterval = 0

    private var analyzer: Any?
    private var continuation: Any?
    private var resultPump: Task<Void, Never>?
    private var usingDictationTranscriber = true

    private init() {}

    /// 开始听写。失败时 `status` 会落到 `unavailable` / `failed`，并写好人话原因。
    func start() async {
        guard !isListening else { return }
        committedText = ""
        volatilePreview = ""
        inputLevel = 0
        assetProgress = 0
        statusMessage = nil

        guard isSupportedByOS else {
            status = .unavailable
            statusMessage = String(localized: "panel.voice.unavailable.os")
            return
        }

        status = .preparing
        startGeneration += 1
        let generation = startGeneration

        switch MicrophonePermission.status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await MicrophonePermission.request()
            guard generation == startGeneration else { return }
            guard granted else {
                status = .unavailable
                statusMessage = String(localized: "panel.voice.mic.denied")
                return
            }
        case .denied, .restricted:
            status = .unavailable
            statusMessage = String(localized: "panel.voice.mic.denied")
            return
        @unknown default:
            status = .unavailable
            statusMessage = String(localized: "panel.voice.mic.denied")
            return
        }

        guard #available(macOS 26.0, *) else { return }
        await startModernSession(generation: generation)
    }

    /// 立刻关掉麦克风指示灯；把尚未落定的预览并进正文。
    func stop() {
        guard isListening || status == .failed else {
            foldVolatile()
            mic.stop()
            relay.reset()
            return
        }
        startGeneration += 1
        foldVolatile()
        tearDownCapture()
        status = .idle
        statusMessage = nil
        inputLevel = 0
    }

    /// 提交前调用：尽量让识别器吐出最后一句，再把预览并进正文。
    func stopAndCommit() async {
        guard isListening else {
            foldVolatile()
            return
        }
        startGeneration += 1
        tearDownCapture(finalize: true)
        if #available(macOS 26.0, *) {
            await finalizeAnalyzer()
        }
        foldVolatile()
        status = .idle
        statusMessage = nil
        inputLevel = 0
    }

    private func foldVolatile() {
        if !volatilePreview.isEmpty {
            committedText += volatilePreview
            volatilePreview = ""
        }
    }

    @available(macOS 26.0, *)
    private func startModernSession(generation: UInt64) async {
        do {
            let preferred = resolvedPreferredLocale()
            let dictationMatch = await DictationTranscriber.supportedLocale(equivalentTo: preferred)
            let speechMatch = await SpeechTranscriber.supportedLocale(equivalentTo: preferred)
            guard let locale = dictationMatch ?? speechMatch else {
                status = .unavailable
                statusMessage = String(localized: "panel.voice.locale.unsupported")
                return
            }
            usingDictationTranscriber = dictationMatch != nil

            let dictation = DictationTranscriber(
                locale: locale,
                contentHints: [],
                transcriptionOptions: [.punctuation, .etiquetteReplacements],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [.etiquetteReplacements],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            let module: any SpeechModule = usingDictationTranscriber ? dictation : transcriber

            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                status = .installingAssets
                statusMessage = String(localized: "panel.voice.installing")
                observeAssetProgress(request.progress, generation: generation)
                try await request.downloadAndInstall()
                guard generation == startGeneration else { return }
            }

            _ = try? await AssetInventory.reserve(locale: locale)

            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                throw DictationFailure.audioFormatUnavailable
            }

            let analyzer = SpeechAnalyzer(modules: [module])
            let phrases = PreferencesStore.shared.voiceReplacements
                .map(\.to)
                .filter { !$0.isEmpty }
            if !phrases.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = phrases
                try? await analyzer.setContext(context)
            }

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.analyzer = analyzer
            self.continuation = continuation

            if usingDictationTranscriber {
                pumpDictationResults(dictation, generation: generation)
            } else {
                pumpSpeechResults(transcriber, generation: generation)
            }

            try await analyzer.start(inputSequence: stream)
            guard generation == startGeneration else {
                try? await analyzer.cancelAndFinishNow()
                return
            }

            let converter = FormatConverter()
            let feeder = BufferFeeder { buffer in
                guard let converted = try? converter.convert(buffer, to: format) else { return }
                continuation.yield(AnalyzerInput(buffer: converted))
            }

            relay.reset()
            let relay = self.relay
            try mic.start(
                bufferSink: { buffer in relay.receive(buffer) },
                levelSink: { level in
                    let now = ProcessInfo.processInfo.systemUptime
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            SpeechDictationService.shared.applyInputLevel(level, at: now)
                        }
                    }
                }
            )
            relay.attach { feeder.feed($0) }

            status = .listening
            statusMessage = nil
            logger.info("听写已开始，语言 \(locale.identifier(.bcp47), privacy: .public)")
        } catch {
            guard generation == startGeneration else { return }
            logger.error("听写启动失败：\(error.localizedDescription, privacy: .public)")
            tearDownCapture()
            status = .failed
            statusMessage = String(localized: "panel.voice.failed")
        }
    }

    @available(macOS 26.0, *)
    private func pumpDictationResults(_ transcriber: DictationTranscriber, generation: UInt64) {
        resultPump = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        guard let self, self.startGeneration == generation else { return }
                        self.handleResult(text: text, isFinal: isFinal)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, self.startGeneration == generation, self.isListening else { return }
                    self.logger.error("听写结果流结束：\(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @available(macOS 26.0, *)
    private func pumpSpeechResults(_ transcriber: SpeechTranscriber, generation: UInt64) {
        resultPump = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        guard let self, self.startGeneration == generation else { return }
                        self.handleResult(text: text, isFinal: isFinal)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, self.startGeneration == generation, self.isListening else { return }
                    self.logger.error("听写结果流结束：\(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func handleResult(text: String, isFinal: Bool) {
        if isFinal {
            committedText += text
            volatilePreview = ""
        } else {
            volatilePreview = text
        }
    }

    private func applyInputLevel(_ level: Float, at now: TimeInterval) {
        guard now - lastLevelPosted >= 0.05 else { return }
        lastLevelPosted = now
        inputLevel = level
    }

    private func tearDownCapture(finalize: Bool = false) {
        mic.stop()
        relay.reset()
        if #available(macOS 26.0, *) {
            finishInputStream()
        }
        if !finalize {
            resultPump?.cancel()
            resultPump = nil
            if #available(macOS 26.0, *) {
                cancelAnalyzer()
            }
            analyzer = nil
            continuation = nil
        }
    }

    @available(macOS 26.0, *)
    private func finishInputStream() {
        (continuation as? AsyncStream<AnalyzerInput>.Continuation)?.finish()
    }

    @available(macOS 26.0, *)
    private func cancelAnalyzer() {
        let analyzer = self.analyzer as? SpeechAnalyzer
        Task {
            await analyzer?.cancelAndFinishNow()
        }
    }

    @available(macOS 26.0, *)
    private func finalizeAnalyzer() async {
        finishInputStream()
        if let analyzer = analyzer as? SpeechAnalyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        try? await Task.sleep(for: .milliseconds(280))
        resultPump?.cancel()
        resultPump = nil
        analyzer = nil
        continuation = nil
    }

    @available(macOS 26.0, *)
    private func observeAssetProgress(_ progress: Progress, generation: UInt64) {
        Task { [weak self] in
            while !progress.isFinished, !progress.isCancelled {
                await MainActor.run {
                    guard let self, self.startGeneration == generation else { return }
                    self.assetProgress = progress.fractionCompleted
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func resolvedPreferredLocale() -> Locale {
        let stored = PreferencesStore.shared.voiceLocaleIdentifier
        if !stored.isEmpty {
            return Locale(identifier: stored)
        }
        return .current
    }

    @available(macOS 26.0, *)
    func supportedLocales() async -> [Locale] {
        let dictation = await DictationTranscriber.supportedLocales
        if dictation.isEmpty {
            return await SpeechTranscriber.supportedLocales
        }
        return dictation.sorted { $0.identifier(.bcp47) < $1.identifier(.bcp47) }
    }
}

private enum DictationFailure: Error {
    case audioFormatUnavailable
}

// MARK: - 麦克风采集

/// 不要标 MainActor：tap 在音频实时队列回调，隔离到主线程会 SIGTRAP 闪退。
private final class MicrophoneTap: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private var configObserver: NSObjectProtocol?
    private var rebuilding = false
    private var bufferSink: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var levelSink: (@Sendable (Float) -> Void)?
    private(set) var isRunning = false

    func start(
        bufferSink: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        levelSink: @escaping @Sendable (Float) -> Void
    ) throws {
        removeObserver()
        self.bufferSink = bufferSink
        self.levelSink = levelSink
        engine = AVAudioEngine()
        installTap()
        addObserver()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeObserver()
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
    }

    func stop() {
        removeObserver()
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        bufferSink = nil
        levelSink = nil
    }

    private func installTap() {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        guard let bufferSink else { return }
        let handler = TapForwarder(bufferSink: bufferSink, levelSink: levelSink)
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: handler.block)
    }

    private func addObserver() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigChange()
        }
    }

    private func removeObserver() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
    }

    private func handleConfigChange() {
        guard isRunning, !rebuilding else { return }
        rebuilding = true
        defer { rebuilding = false }
        installTap()
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }
    }
}

/// 把 tap 闭包做成非隔离转发，避免它继承调用方的 actor。
private struct TapForwarder: @unchecked Sendable {
    let bufferSink: @Sendable (AVAudioPCMBuffer) -> Void
    let levelSink: (@Sendable (Float) -> Void)?

    var block: (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            bufferSink(buffer)
            if let levelSink {
                levelSink(AudioLevel.normalized(from: buffer))
            }
        }
    }
}

/// 音频线程直投。内部只调跨线程安全的接口。
private final class BufferFeeder: @unchecked Sendable {
    private let handler: (AVAudioPCMBuffer) -> Void
    init(_ handler: @escaping (AVAudioPCMBuffer) -> Void) { self.handler = handler }
    func feed(_ buffer: AVAudioPCMBuffer) { handler(buffer) }
}

/// 识别栈初始化期间缓存音频，挂上投喂器后回灌，避免吞掉第一个字。
private final class BufferRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [AVAudioPCMBuffer] = []
    private var sink: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private let ceiling = 250

    func receive(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        if let sink {
            lock.unlock()
            sink(buffer)
            return
        }
        if pending.count < ceiling { pending.append(buffer) }
        lock.unlock()
    }

    func attach(_ sink: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        lock.lock()
        let buffered = pending
        pending.removeAll()
        self.sink = sink
        lock.unlock()
        for buffer in buffered { sink(buffer) }
    }

    func reset() {
        lock.lock()
        sink = nil
        pending.removeAll()
        lock.unlock()
    }
}

/// 麦克风原生格式几乎不会等于分析器要求的格式，逐 buffer 转换。
private final class FormatConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard buffer.format != format else { return buffer }
        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { throw DictationFailure.audioFormatUnavailable }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(capacity, 1)) else {
            throw DictationFailure.audioFormatUnavailable
        }
        let consumed = OSAllocatedUnfairLock(initialState: false)
        var nsError: NSError?
        let status = converter.convert(to: output, error: &nsError) { _, statusPtr in
            let already = consumed.withLock { flag -> Bool in
                let previous = flag
                flag = true
                return previous
            }
            statusPtr.pointee = already ? .noDataNow : .haveData
            return already ? nil : buffer
        }
        guard status != .error else { throw DictationFailure.audioFormatUnavailable }
        return output
    }
}

private enum AudioLevel {
    static func normalized(from buffer: AVAudioPCMBuffer) -> Float {
        let length = Int(buffer.frameLength)
        guard length > 0 else { return 0 }
        if let channel = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<length {
                let s = channel[i]
                sum += s * s
            }
            let rms = sqrt(sum / Float(length))
            let db = 20 * log10(max(rms, 1e-8))
            return min(max((db + 50) / 50, 0), 1)
        }
        if let channel = buffer.int16ChannelData?[0] {
            var sum: Float = 0
            for i in 0..<length {
                let s = Float(channel[i]) / 32768
                sum += s * s
            }
            let rms = sqrt(sum / Float(length))
            let db = 20 * log10(max(rms, 1e-8))
            return min(max((db + 50) / 50, 0), 1)
        }
        return 0
    }
}
