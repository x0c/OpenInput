#!/usr/bin/env bash
# 对外发行：Developer ID 导出、苹果公证、DMG、Sparkle 更新包与公开发布。
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="SHZQ3MWP3B"
SIGN_IDENTITY="Developer ID Application"
UPDATE_REPOSITORY="x0c/OpenInput-updates"
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
gh repo view "${UPDATE_REPOSITORY}" --json isPrivate --jq '.isPrivate' | grep -qx false || die "公开更新仓不存在或不是公开"

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
update_checkout="$(mktemp -d)"
trap 'rm -rf "${stage}" "${updates_dir}" "${update_checkout}"' EXIT
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
printf 'OpenInput %s\n\n- 正式提供已签名、公证的安装包与应用内自动更新。\n' "${version}" > "${updates_dir}/OpenInput-${version}.md"
# Sparkle 直接拼接前缀与文件名，结尾必须保留斜杠；缺它会生成匿名 404 的更新地址。
"${sparkle_dir}/generate_appcast" --account "${SPARKLE_ACCOUNT}" --download-url-prefix "https://github.com/${UPDATE_REPOSITORY}/releases/download/v${version}/" "${updates_dir}"

step "发布公开更新包和首装镜像"
gh release create "v${version}" "${updates_dir}/OpenInput-${version}.zip" --repo "${UPDATE_REPOSITORY}" --title "OpenInput ${version}" --notes "OpenInput ${version} 自动更新包。" || gh release upload "v${version}" "${updates_dir}/OpenInput-${version}.zip" --repo "${UPDATE_REPOSITORY}" --clobber
gh repo clone "${UPDATE_REPOSITORY}" "${update_checkout}" -- --depth 1
cp "${updates_dir}/appcast.xml" "${update_checkout}/appcast.xml"
(cd "${update_checkout}" && git add appcast.xml && git commit -m "发布 OpenInput ${version} 更新清单" && git push)

git add -A
git commit -m "发布 OpenInput ${version} 正式自分发"
git tag "v${version}"
git push origin main --tags
gh release create "v${version}" "${dmg_path}" --repo x0c/OpenInput --title "OpenInput ${version}" --notes "OpenInput ${version} 已签名、公证的 macOS 安装包。" || gh release upload "v${version}" "${dmg_path}" --repo x0c/OpenInput --clobber

step "匿名下载验收"
curl -fsSL "https://github.com/${UPDATE_REPOSITORY}/raw/refs/heads/main/appcast.xml" -o /dev/null
curl -fsSL "https://github.com/${UPDATE_REPOSITORY}/releases/download/v${version}/OpenInput-${version}.zip" -o /dev/null
curl -fsSL "https://github.com/x0c/OpenInput/releases/download/v${version}/OpenInput-${version}.dmg" -o /dev/null
printf '发布完成：v%s（内部构建号 %s）\n' "${version}" "${build_number}"
