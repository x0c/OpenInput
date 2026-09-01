#!/usr/bin/env bash
# 对外发行：Developer ID 导出、苹果公证、DMG、Sparkle 更新包与公开发布。
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="SHZQ3MWP3B"
SIGN_IDENTITY="Developer ID Application"
SOURCE_REPOSITORY="x0c/OpenInput"
UPDATE_FEED_URL="https://github.com/${SOURCE_REPOSITORY}/releases/latest/download/appcast.xml"
# 迁移前旧更新源；仅用于首轮继承历史清单与防回退校验，勿在新发布里再引用
LEGACY_FEED_URL="https://raw.githubusercontent.com/x0c/OpenInput-updates/main/appcast.xml"
NOTARY_KEY="${NOTARY_KEY:-${HOME}/Documents/P8 密钥/发布公证密钥/AuthKey_D7YQ9HD7D6_Notarize.p8}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-D7YQ9HD7D6}"
NOTARY_ISSUER="${NOTARY_ISSUER:-c98fe4b8-d1bf-4b4a-b998-9eb8f3be9fe4}"
SPARKLE_ACCOUNT="openinput.x0c"
BUILD_DIR="${ROOT_DIR}/build/release"

die() { printf '\n发布失败：%s\n' "$*" >&2; exit 1; }
step() { printf '\n▶ %s\n' "$*"; }

notarize_and_wait() {
  local file="$1" response submission status waited=0
  response="$(xcrun notarytool submit "${file}" --key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER}" --output-format json)"
  submission="$(jq -r '.id // empty' <<<"${response}")"
  [[ -n "${submission}" ]] || die "苹果未返回公证提交编号"
  printf '公证提交编号：%s\n' "${submission}"
  while (( waited < 7200 )); do
    sleep 30; waited=$((waited + 30))
    status="$(xcrun notarytool info "${submission}" --key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER}" --output-format json 2>/dev/null | jq -r '.status // empty' || true)"
    [[ "${status}" == "In Progress" || -z "${status}" ]] && continue
    [[ "${status}" == "Accepted" ]] && return 0
    xcrun notarytool log "${submission}" --key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER}" || true
    die "苹果公证被拒：${status}"
  done
  die "公证超过两小时仍未完成；提交编号为 ${submission}"
}

cd "${ROOT_DIR}"
mkdir -p "${BUILD_DIR}"
grep -q "${SIGN_IDENTITY}" <<<"$(security find-identity -v -p codesigning)" || die "本机缺少 Developer ID 发布证书"
[[ -f "${NOTARY_KEY}" ]] || die "找不到苹果公证密钥"
gh repo view "${SOURCE_REPOSITORY}" --json isPrivate --jq '.isPrivate' | grep -qx false || die "源码仓不存在或不是公开"

version="$(awk '/MARKETING_VERSION:/ { gsub(/\"/, "", $2); print $2; exit }' project.yml)"
build_number="$(awk '/CURRENT_PROJECT_VERSION:/ { gsub(/\"/, "", $2); print $2; exit }' project.yml)"
[[ "${build_number}" =~ ^[1-9][0-9]*$ ]] || die "内部构建号必须是正整数"
archive_path="${BUILD_DIR}/OpenInput.xcarchive"
export_dir="${BUILD_DIR}/export"
app_path="${export_dir}/OpenInput.app"
dmg_path="${BUILD_DIR}/OpenInput-${version}.dmg"
zip_path="${BUILD_DIR}/OpenInput-${version}.zip"

step "归档发布版本 v${version}（内部构建号 ${build_number}）"
xcodegen generate
rm -rf "${archive_path}" "${export_dir}" "${dmg_path}" "${zip_path}"
xcodebuild -project OpenInput.xcodeproj -scheme OpenInput -configuration Release -destination 'platform=macOS' -derivedDataPath "${BUILD_DIR}/DerivedData" -archivePath "${archive_path}" -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath "${archive_path}" -exportOptionsPlist ExportOptions.plist -exportPath "${export_dir}"
[[ -d "${app_path}" ]] || die "发布应用产物不存在"

step "验证签名与发布权限"
sign_info="$(codesign -dv --verbose=2 "${app_path}" 2>&1)"
entitlements="$(codesign -d --entitlements - "${app_path}" 2>/dev/null || true)"
grep -q "Authority=${SIGN_IDENTITY}" <<<"${sign_info}" || die "不是 Developer ID 签名"
grep -q 'flags=.*runtime' <<<"${sign_info}" || die "没有启用加固运行时"
! grep -q 'get-task-allow' <<<"${entitlements}" || die "发布包含调试权限"
codesign --verify --deep --strict --verbose=2 "${app_path}"

step "制作拖拽安装镜像并提交苹果公证"
stage="$(mktemp -d)"
updates_dir="$(mktemp -d)"
trap 'rm -rf "${stage}" "${updates_dir}"' EXIT
ditto "${app_path}" "${stage}/OpenInput.app"
ln -s /Applications "${stage}/Applications"
hdiutil create -volname "OpenInput" -srcfolder "${stage}" -ov -format UDZO "${dmg_path}"
notarize_and_wait "${dmg_path}"
xcrun stapler staple "${dmg_path}"
xcrun stapler validate "${dmg_path}"
spctl -a -vvv -t open "${dmg_path}"

step "覆盖安装到本机并启动验证"
pkill -x OpenInput 2>/dev/null || true
rm -rf /Applications/OpenInput.app
ditto "${app_path}" /Applications/OpenInput.app
codesign --verify --deep --strict --verbose=2 /Applications/OpenInput.app
open /Applications/OpenInput.app
sleep 2
pgrep -x OpenInput >/dev/null || die "本机安装后没有成功启动"

step "生成已装订 Sparkle 更新包与清单"
ditto -c -k --keepParent "${app_path}" "${zip_path}"
sparkle_bin="$(find "${BUILD_DIR}/DerivedData/SourcePackages/artifacts" -path '*/Sparkle/bin/generate_appcast' -type f | head -1)"
[[ -n "${sparkle_bin}" ]] || die "找不到 Sparkle 发布工具"
sparkle_dir="$(dirname "${sparkle_bin}")"
public_key="$("${sparkle_dir}/generate_keys" --account "${SPARKLE_ACCOUNT}" -p)"
plist_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' OpenInput/Resources/Info.plist)"
[[ "${public_key}" == "${plist_key}" ]] || die "Sparkle 私钥与应用公钥不匹配"
cp "${zip_path}" "${updates_dir}/"
# 继承上一份清单：优先源码仓，首轮迁移回退旧更新源（历史条目的旧地址在旧仓归档后仍可匿名下载）
if curl -fsSL "${UPDATE_FEED_URL}" -o "${updates_dir}/appcast.xml" 2>/dev/null \
  || curl -fsSL "${LEGACY_FEED_URL}" -o "${updates_dir}/appcast.xml" 2>/dev/null; then :; fi
# Sparkle 直接拼接前缀与文件名，结尾必须保留斜杠；缺它会生成匿名 404 的更新地址。
"${sparkle_dir}/generate_appcast" --account "${SPARKLE_ACCOUNT}" --download-url-prefix "https://github.com/${SOURCE_REPOSITORY}/releases/download/v${version}/" "${updates_dir}"
grep -q 'sparkle:edSignature=' "${updates_dir}/appcast.xml" || die "更新清单缺少 EdDSA 签名"

step "发布首装镜像与更新包到源码仓"
# 清单、更新包、首装包全部发在同一源码仓 Release；禁止另建更新仓。
# 同一版本可安全重跑：已经存在的公开资产先复用并在最后做匿名下载验证，
# 不重复上传，以免慢链路空耗时间或触发平台的“文件已存在”错误。
if ! gh release view "v${version}" --repo "${SOURCE_REPOSITORY}" >/dev/null 2>&1; then
  gh release create "v${version}" "${dmg_path}" "${updates_dir}/OpenInput-${version}.zip" "${updates_dir}/appcast.xml#appcast.xml" --repo "${SOURCE_REPOSITORY}" --title "OpenInput ${version}" --notes "OpenInput ${version} 已签名、公证的 macOS 安装包与应用内自动更新。"
else
  for asset_path in "${dmg_path}" "${updates_dir}/OpenInput-${version}.zip" "${updates_dir}/appcast.xml"; do
    asset_name="$(basename "${asset_path}")"
    if ! gh release view "v${version}" --repo "${SOURCE_REPOSITORY}" --json assets --jq '.assets[].name' | grep -qx "${asset_name}"; then
      gh release upload "v${version}" "${asset_path}" --repo "${SOURCE_REPOSITORY}"
    fi
  done
fi

git add -A
git commit -m "发布 OpenInput ${version} 正式自分发"
git tag "v${version}"
git push origin main --tags

step "匿名下载验收"
curl -fsSL "${UPDATE_FEED_URL}" -o /dev/null
curl -fsSL "https://github.com/${SOURCE_REPOSITORY}/releases/download/v${version}/OpenInput-${version}.zip" -o /dev/null
curl -fsSL "https://github.com/${SOURCE_REPOSITORY}/releases/download/v${version}/OpenInput-${version}.dmg" -o /dev/null
printf '发布完成：v%s（内部构建号 %s）\n' "${version}" "${build_number}"
