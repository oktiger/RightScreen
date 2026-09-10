#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
    print -u2 "用法：$0 <executable-path> <app-path>"
    exit 2
fi

executable_path="$1"
app_path="$2"
project_dir="${0:A:h:h}"
contents_dir="$app_path/Contents"
resources_src="$project_dir/RightScreen/Resources"
icon_src="$resources_src/AppIcon.icns"
plist_src="$resources_src/Info.plist"

if [[ ! -x "$executable_path" ]]; then
    print -u2 "找不到可执行文件：$executable_path"
    exit 2
fi

if [[ ! -f "$plist_src" ]]; then
    print -u2 "缺少 Info.plist：$plist_src"
    exit 1
fi

# 所有打包入口都经此脚本；缺图标时本地生成，避免换机器后 Dock/访达无 logo。
if [[ ! -f "$icon_src" ]]; then
    print -- "未找到 AppIcon.icns，正在生成…"
    /usr/bin/swift "$project_dir/Scripts/generate-app-icon.swift"
fi

if [[ ! -f "$icon_src" ]]; then
    print -u2 "应用图标生成失败，仍缺少：$icon_src"
    exit 1
fi

rm -rf "$contents_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$plist_src" "$contents_dir/Info.plist"
cp "$icon_src" "$contents_dir/Resources/AppIcon.icns"
cp "$executable_path" "$contents_dir/MacOS/RightScreen"

icon_dst="$contents_dir/Resources/AppIcon.icns"
if [[ ! -f "$icon_dst" ]]; then
    print -u2 "打包失败：图标未写入 $icon_dst"
    exit 1
fi

bundle_icon="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$contents_dir/Info.plist" 2>/dev/null || true)"
if [[ "$bundle_icon" != "AppIcon" ]]; then
    print -u2 "打包失败：Info.plist 的 CFBundleIconFile 应为 AppIcon，实际为：${bundle_icon:-<空>}"
    exit 1
fi

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$contents_dir/Info.plist" 2>/dev/null || true)"
if [[ "$bundle_identifier" != "com.rightscreen.RightScreenApp" ]]; then
    print -u2 "打包失败：CFBundleIdentifier 必须为 com.rightscreen.RightScreenApp，实际为：${bundle_identifier:-<空>}"
    exit 1
fi

# Accessibility 的 TCC 授权绑定 Designated Requirement；禁止直接留下 SwiftPM 的 adhoc 签名。
"$project_dir/Scripts/sign-app.sh" "$app_path"

print -- "已生成并验证：$app_path（含 AppIcon.icns）"
