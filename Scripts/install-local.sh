#!/bin/zsh
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--build-only" ) ]]; then
    print -u2 "用法：$0 [--build-only]"
    exit 2
fi

project_dir="${0:A:h:h}"
install_app="/Applications/RightScreen.app"

cd "$project_dir"
swift build
bin_dir="$(swift build --show-bin-path)"

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/rightscreen-install.XXXXXX")"
staging_app="$staging_root/RightScreen.app"
cleanup() {
    rm -rf "$staging_root"
}
trap cleanup EXIT

"$project_dir/Scripts/package-app.sh" "$bin_dir/RightScreen" "$staging_app"

running_pids=("${(@f)$(pgrep -x RightScreen 2>/dev/null || true)}")
for pid in "${running_pids[@]}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
done
for _ in {1..50}; do
    pgrep -x RightScreen >/dev/null 2>&1 || break
    sleep 0.1
done

# 先把旧 Contents 挪到临时目录，替换失败（如缺少「App 管理」权限）时还原，避免留下空壳 App。
mkdir -p "$install_app"
previous_contents="$staging_root/previous-Contents"
if [[ -d "$install_app/Contents" ]]; then
    mv "$install_app/Contents" "$previous_contents"
fi
if ! mv "$staging_app/Contents" "$install_app/Contents"; then
    [[ -d "$previous_contents" ]] && mv "$previous_contents" "$install_app/Contents"
    print -u2 "无法写入 $install_app，已保留原有版本。请在“系统设置 → 隐私与安全性 → App 管理”中允许当前终端后重试。"
    exit 1
fi

# 移动已签名 bundle 不会改变签名。此处只做验证，避免安装后再次访问私钥。
codesign --verify --deep --strict --verbose=2 "$install_app"

installed_bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$install_app/Contents/Info.plist")"
installed_requirement="$(codesign -d -r- "$install_app" 2>&1 | awk -F' => ' '/designated/{print $2; exit}')"
print -- "已安装：$install_app"
print -- "Bundle ID：$installed_bundle_identifier"
print -- "DR：$installed_requirement"

if [[ "${1:-}" != "--build-only" ]]; then
    open "$install_app"
fi
