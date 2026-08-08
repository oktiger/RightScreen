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

if [[ ! -x "$executable_path" ]]; then
    print -u2 "找不到可执行文件：$executable_path"
    exit 2
fi

rm -rf "$contents_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$project_dir/RightScreen/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/RightScreen/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
cp "$executable_path" "$contents_dir/MacOS/RightScreen"

# Accessibility 的 TCC 授权绑定 Designated Requirement；禁止直接留下 SwiftPM 的 adhoc 签名。
"$project_dir/Scripts/sign-app.sh" "$app_path"

print -- "已生成并验证：$app_path"
