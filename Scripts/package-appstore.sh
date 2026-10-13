#!/bin/zsh
set -euo pipefail

# 构建 Mac App Store 上传包：universal release → 沙盒 + 分发证书签名 → 安装器签名 .pkg。
#
# 用法：Scripts/package-appstore.sh <Mac App Store 描述文件.provisionprofile> [--upload]
#
# 可选环境变量：
#   RIGHTSCREEN_BUILD_NUMBER          CFBundleVersion，默认取 git 提交数（单调递增，满足每次上传须更大）
#   RIGHTSCREEN_APP_SIGN_IDENTITY     默认自动查找 "Apple Distribution" / "3rd Party Mac Developer Application"
#   RIGHTSCREEN_INSTALLER_SIGN_IDENTITY 默认自动查找 "3rd Party Mac Developer Installer" / "Mac Installer Distribution"
#
# --upload：把签好的 app 包成 xcarchive，交给 xcodebuild -exportArchive 上传，
# 使用 Xcode → 设置 → Accounts 里已登录的开发者账号，无需 API Key 或密码。

if [[ $# -lt 1 || $# -gt 2 || ( $# -eq 2 && "$2" != "--upload" ) ]]; then
    print -u2 "用法：$0 <Mac App Store 描述文件.provisionprofile> [--upload]"
    exit 2
fi

profile_path="${1:A}"
upload="${2:-}"
project_dir="${0:A:h:h}"
bundle_identifier="com.rightscreen.RightScreenApp"
entitlements_src="$project_dir/RightScreen/Resources/RightScreen.entitlements"
dist_dir="$project_dir/dist/AppStore"
app_path="$dist_dir/RightScreen.app"
pkg_path="$dist_dir/RightScreen.pkg"

if [[ ! -f "$profile_path" ]]; then
    print -u2 "找不到描述文件：$profile_path"
    exit 2
fi

# 按名称前缀在钥匙串中查找有效签名身份，输出完整名称。
find_identity() {
    local policy_args=(${=1}) prefix
    shift
    for prefix in "$@"; do
        local name="$(
            security find-identity -v "${policy_args[@]}" |
                awk -v p="\"$prefix" 'index($0, p) { sub(/^[^"]*"/, ""); sub(/"$/, ""); print; exit }'
        )"
        if [[ -n "$name" ]]; then
            print -r -- "$name"
            return 0
        fi
    done
    return 1
}

app_identity="${RIGHTSCREEN_APP_SIGN_IDENTITY:-$(find_identity "-p codesigning" "Apple Distribution" "3rd Party Mac Developer Application" || true)}"
installer_identity="${RIGHTSCREEN_INSTALLER_SIGN_IDENTITY:-$(find_identity "" "3rd Party Mac Developer Installer" "Mac Installer Distribution" || true)}"
if [[ -z "$app_identity" ]]; then
    print -u2 "缺少 App 分发证书（Apple Distribution）。在 Xcode → 设置 → Accounts → Manage Certificates 中添加。"
    exit 1
fi
if [[ -z "$installer_identity" ]]; then
    print -u2 "缺少安装器证书（Mac Installer Distribution）。在 Xcode → 设置 → Accounts → Manage Certificates 中添加。"
    exit 1
fi

# 校验描述文件：必须是 macOS、App Store 分发（无设备列表）、且 App ID 与 Bundle ID 一致。
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/rightscreen-appstore.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
profile_plist="$work_dir/profile.plist"
cp "$profile_path" "$work_dir/profile.provisionprofile"
security cms -D -i "$work_dir/profile.provisionprofile" > "$profile_plist"
profile_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$profile_plist" 2>/dev/null
}

team_identifier="$(profile_value 'TeamIdentifier:0')"
application_identifier="$(profile_value 'Entitlements:com.apple.application-identifier')"
if [[ "$(profile_value 'Platform')" != *OSX* ]]; then
    print -u2 "描述文件不是 macOS 平台：$(profile_value Name)"
    exit 1
fi
if profile_value 'ProvisionedDevices' >/dev/null || profile_value 'ProvisionsAllDevices' >/dev/null; then
    print -u2 "描述文件含设备列表，不是 Mac App Store 分发描述文件：$(profile_value Name)"
    exit 1
fi
if [[ "$application_identifier" != "$team_identifier.$bundle_identifier" ]]; then
    print -u2 "描述文件 App ID 为 $application_identifier，预期 $team_identifier.$bundle_identifier"
    exit 1
fi

cd "$project_dir"
build_flags=(-c release --arch arm64 --arch x86_64)
swift build "${build_flags[@]}"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"

# 只清理本脚本的产物；描述文件、截图等可能也放在 dist/AppStore 下。
rm -rf "$app_path" "$pkg_path"
mkdir -p "$dist_dir"
"$project_dir/Scripts/package-app.sh" --unsigned "$bin_dir/RightScreen" "$app_path"

build_number="${RIGHTSCREEN_BUILD_NUMBER:-$(git -C "$project_dir" rev-list --count HEAD)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app_path/Contents/Info.plist"
cp "$profile_plist:h/profile.provisionprofile" "$app_path/Contents/embedded.provisionprofile"

# 签名用的 entitlements = 仓库里的沙盒声明 + 描述文件要求的 App ID / Team ID。
entitlements="$work_dir/RightScreen.entitlements"
cp "$entitlements_src" "$entitlements"
/usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string $application_identifier" \
    -c "Add :com.apple.developer.team-identifier string $team_identifier" \
    "$entitlements"

codesign --force --options runtime --timestamp \
    --sign "$app_identity" \
    --identifier "$bundle_identifier" \
    --entitlements "$entitlements" \
    "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

signed_entitlements="$work_dir/signed.plist"
codesign -d --entitlements - --xml "$app_path" 2>/dev/null > "$signed_entitlements"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$signed_entitlements" 2>/dev/null)" != "true" ]]; then
    print -u2 "签名后未包含 App Sandbox entitlement，App Store 会拒收。"
    exit 1
fi

productbuild --component "$app_path" /Applications --sign "$installer_identity" "$pkg_path"
pkgutil --check-signature "$pkg_path" >/dev/null

print -- "已生成：$pkg_path"
print -- "版本：$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist") ($build_number)"
print -- "架构：$(lipo -archs "$app_path/Contents/MacOS/RightScreen")"

if [[ "$upload" == "--upload" ]]; then
    # xcodebuild 按名称查找描述文件，需先装到 Xcode 的描述文件目录。
    profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$profile_plist")"
    installed_profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    mkdir -p "$installed_profiles"
    cp "$work_dir/profile.provisionprofile" "$installed_profiles/$profile_uuid.provisionprofile"

    archive_path="$work_dir/RightScreen.xcarchive"
    mkdir -p "$archive_path/Products/Applications"
    ditto "$app_path" "$archive_path/Products/Applications/RightScreen.app"
    short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
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
        <key>SigningIdentity</key><string>$app_identity</string>
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
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>$app_identity</string>
    <key>installerSigningCertificate</key><string>$installer_identity</string>
    <key>provisioningProfiles</key>
    <dict><key>$bundle_identifier</key><string>$profile_uuid</string></dict>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$work_dir/export" \
        -exportOptionsPlist "$work_dir/ExportOptions.plist" \
        -allowProvisioningUpdates
    print -- "已上传 $short_version ($build_number)，处理完成后可在 App Store Connect 版本页的「构建版本」中选择。"
fi
