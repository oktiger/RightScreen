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

mkdir -p "$install_app"
rm -rf "$install_app/Contents"
mv "$staging_app/Contents" "$install_app/Contents"

# 最终安装位置再次验证，防止复制或升级步骤破坏签名。
"$project_dir/Scripts/sign-app.sh" "$install_app"
codesign --verify --deep --strict --verbose=2 "$install_app"

installed_bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$install_app/Contents/Info.plist")"
installed_requirement="$(codesign -d -r- "$install_app" 2>&1 | awk -F' => ' '/designated/{print $2; exit}')"
print -- "已安装：$install_app"
print -- "Bundle ID：$installed_bundle_identifier"
print -- "DR：$installed_requirement"

if [[ "${1:-}" != "--build-only" ]]; then
    open "$install_app"
fi
