#!/bin/zsh
set -euo pipefail

# 上传到 App Store Connect（TestFlight / 审核共用同一构建）：universal release → 沙盒归档 → Xcode 云签名上传。
#
# 用法：Scripts/upload-testflight.sh
#
# 与 package-appstore.sh 的区别：不需要本机安装 Apple Distribution / Installer 证书或下载描述文件，
# 分发证书由 Apple 云端托管，描述文件由 xcodebuild 自动生成，账号取 Xcode → 设置 → Accounts。
#
# 可选环境变量：
#   RIGHTSCREEN_TEAM_ID       默认 9THF4SEGPY
#   RIGHTSCREEN_BUILD_NUMBER  CFBundleVersion，默认取 git 提交数（每次上传须更大）

if [[ $# -ne 0 ]]; then
    print -u2 "用法：$0"
    exit 2
fi

project_dir="${0:A:h:h}"
bundle_identifier="com.rightscreen.RightScreenApp"
team_identifier="${RIGHTSCREEN_TEAM_ID:-9THF4SEGPY}"
entitlements="$project_dir/RightScreen/Resources/RightScreen.entitlements"

# 归档里的 App 只需本团队任一有效身份的临时签名（携带沙盒 entitlements），导出时 Xcode 改签为分发证书。
archive_identity="$(
    security find-identity -v -p codesigning |
        awk -v t="($team_identifier)" '/"(Apple Distribution|Developer ID Application|Apple Development): / && index($0, t) { sub(/^[^"]*"/, ""); sub(/"$/, ""); print; exit }'
)"
if [[ -z "$archive_identity" ]]; then
    print -u2 "缺少团队 $team_identifier 的签名证书。在 Xcode → 设置 → Accounts → Manage Certificates 中添加任一证书。"
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/rightscreen-testflight.XXXXXX")"
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
codesign --force --options runtime --sign "$archive_identity" --identifier "$bundle_identifier" \
    --entitlements "$entitlements" "$archived_app"

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
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$team_identifier</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

print -- "正在云签名并上传 $short_version ($build_number)…"
xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$work_dir/export" \
    -exportOptionsPlist "$work_dir/ExportOptions.plist" \
    -allowProvisioningUpdates

print -- "已上传 $short_version ($build_number)，架构：$(lipo -archs "$archived_app/Contents/MacOS/RightScreen")"
print -- "处理完成（通常 5–30 分钟）后出现在 App Store Connect → TestFlight，其他 Mac 用 TestFlight App 安装。"
