# OpenInput

macOS native floating input panel for awkward single-line fields (URL bars, chat boxes, subject lines, etc.). Edit comfortably in a small window, then press **Return** to paste back into the original field.

Display name: **智能输入小窗**

## Features

- Global hotkey show / hide (default `⌥⌘I`)
- Remembers focus target and pastes on submit
- Voice dictation on macOS 26+ (on-device; older systems show the control disabled)
- Optional on-device cleanup at submit; revert from the menu bar if cleanup changed the text
- Newline with `⇧↩`, Tab as tab character
- History browse (`↑↓`), search, delete
- Per-app memory: auto-open after you use it in an app; active close disables auto-open for that app
- Resizable panel with remembered size, border color, opacity
- Launch at login (optional)
- Hide the menu bar icon; a small recovery window can show it again

## Install

Download the latest `OpenInput-*.dmg` from the [releases page](https://github.com/x0c/OpenInput/releases), open it, and drag OpenInput to Applications. The app is signed and notarized by Apple. Future versions are offered inside the app automatically.

Requirements: macOS 14+. Voice dictation requires macOS 26 or later.

## Build from source

```bash
git clone https://github.com/x0c/OpenInput.git
cd OpenInput
xcodegen generate
open OpenInput.xcodeproj
```

Or from the CLI:

```bash
xcodegen generate
xcodebuild -scheme OpenInput -configuration Debug build
```

## Usage

1. Run the app — a menu bar icon appears (no Dock icon).
2. Grant **Accessibility** in Settings → Privacy & Security (needed to paste into other apps). Voice dictation also needs the **Microphone**; the system asks the first time you turn it on.
3. Default hotkey: `⌥⌘I`.
4. In the panel: `↩` insert & close, `⇧↩` newline, `esc` close, `↑↓` history when empty / browsing. The microphone button, when on, starts listening every time the panel opens.

## Privacy & permissions

- Accessibility is required to inject text via paste (`⌘V`) into other apps.
- Microphone is used only to turn speech into text on this Mac. Dictation and cleanup do not send audio or text to a network service.
- History and app-memory are stored locally under Application Support.
- The app is intentionally **not sandboxed** for global hotkeys and cross-app paste.

## License

MIT — see [LICENSE](LICENSE).
