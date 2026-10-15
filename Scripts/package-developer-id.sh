#!/bin/zsh
set -euo pipefail

# 构建 App Store 以外分发的 DMG：universal release → Developer ID 签名 → Apple 公证 → staple → DMG。
#
# 用法：Scripts/package-developer-id.sh [输出目录，默认 ~/Downloads]
#
# 签名与公证都经 xcodebuild 完成，使用 Xcode → 设置 → Accounts 中已登录的账号：
# Developer ID 证书由 Apple 云端托管（本机无需安装），也不需要 notarytool 凭据。
#
# 可选环境变量：
#   RIGHTSCREEN_TEAM_ID       默认 9THF4SEGPY
#   RIGHTSCREEN_BUILD_NUMBER  CFBundleVersion，默认取 git 提交数
#
# 注意：Developer ID 版与本地开发版的签名身份不同，安装后需在系统设置中重新授权辅助功能。

if [[ $# -gt 1 ]]; then
    print -u2 "用法：$0 [输出目录]"
    exit 2
fi

output_dir="${1:-$HOME/Downloads}"
project_dir="${0:A:h:h}"
bundle_identifier="com.rightscreen.RightScreenApp"
team_identifier="${RIGHTSCREEN_TEAM_ID:-9THF4SEGPY}"

# 归档里的 App 需要一个临时签名，导出时 Xcode 会改签为 Developer ID。
archive_identity="$(
    security find-identity -v -p codesigning |
        awk -v t="($team_identifier)" '/"Apple Distribution: / && index($0, t) { sub(/^[^"]*"/, ""); sub(/"$/, ""); print; exit }'
)"
if [[ -z "$archive_identity" ]]; then
    print -u2 "缺少团队 $team_identifier 的 Apple Distribution 证书。在 Xcode → 设置 → Accounts → Manage Certificates 中添加。"
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/rightscreen-devid.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
archive_path="$work_dir/RightScreen.xcarchive"
archived_app="$archive_path/Products/Applications/RightScreen.app"

cd "$project_dir"
build_flags=(-c release --arch arm64 --arch x86_64)
swift build "${build_flags[@]}"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"

mkdir -p "${archived_app:h}"
"$project_dir/Scripts/package-app.sh" --unsigned "$bin_dir/RightScreen" "$archived_app"

build_number="${RIGHTSCREEN_BUILD_NUMBER:-$(git -C "$project_dir" rev-list --count HEAD)}"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$archived_app/Contents/Info.plist")"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$archived_app/Contents/Info.plist"
codesign --force --options runtime --sign "$archive_identity" --identifier "$bundle_identifier" "$archived_app"

cat > "$archive_path/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>ApplicationProperties</key>
    <dict>
        <key>ApplicationPath</key><string>Applications/RightScreen.app</string>
        <key>CFBundleIdentifier</key><string>$bundle_identifier</string>
        <key>CFBundleShortVersionString</key><string>$short_version</string>
        <key>CFBundleVersion</key><string>$build_number</string>
        <key>SigningIdentity</key><string>$archive_identity</string>
        <key>Team</key><string>$team_identifier</string>
    </dict>
    <key>ArchiveVersion</key><integer>2</integer>
    <key>CreationDate</key><date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
    <key>Name</key><string>RightScreen</string>
    <key>SchemeName</key><string>RightScreen</string>
</dict>
</plist>
PLIST
cat > "$work_dir/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$team_identifier</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

print -- "正在用 Developer ID 签名并提交 Apple 公证…"
xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$work_dir/submitted" \
    -exportOptionsPlist "$work_dir/ExportOptions.plist" \
    -allowProvisioningUpdates

# 公证通常几分钟完成；完成前 exportNotarizedApp 会失败，最多等 30 分钟。
notarized_dir="$work_dir/notarized"
for attempt in {1..60}; do
    if xcodebuild -exportNotarizedApp -archivePath "$archive_path" -exportPath "$notarized_dir" > "$work_dir/notarize.log" 2>&1; then
        break
    fi
    if (( attempt == 60 )); then
        cat "$work_dir/notarize.log" >&2
        print -u2 "等待公证超时；可在 Xcode → Organizer 查看状态。"
        exit 1
    fi
    print -- "公证处理中，30 秒后重试（$attempt/60）…"
    sleep 30
done

notarized_app="$notarized_dir/RightScreen.app"
xcrun stapler validate "$notarized_app"
spctl --assess --type exec -vv "$notarized_app"

dmg_root="$work_dir/dmg"
mkdir -p "$dmg_root"
ditto "$notarized_app" "$dmg_root/RightScreen.app"
ln -s /Applications "$dmg_root/Applications"

mkdir -p "$output_dir"
dmg_path="$output_dir/RightScreen-$short_version-$build_number.dmg"
rm -f "$dmg_path"
hdiutil create -volname RightScreen -srcfolder "$dmg_root" -fs HFS+ -format UDZO "$dmg_path" >/dev/null
hdiutil verify "$dmg_path" >/dev/null

print -- "已生成：$dmg_path"
print -- "版本：$short_version ($build_number)，架构：$(lipo -archs "$notarized_app/Contents/MacOS/RightScreen")"
