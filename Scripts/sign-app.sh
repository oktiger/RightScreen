#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
    print -u2 "用法：$0 <app-path>"
    exit 2
fi

app_path="$1"
if [[ ! -d "$app_path/Contents" ]]; then
    print -u2 "不是有效的 app bundle：$app_path"
    exit 2
fi

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
expected_bundle_identifier="com.rightscreen.RightScreenApp"
signing_directory="$HOME/Library/Application Support/RightScreen/CodeSigning"
requirement_file="$signing_directory/designated-requirement"
signing_keychain=""

if [[ "$bundle_identifier" != "$expected_bundle_identifier" ]]; then
    print -u2 "拒绝签名：Bundle ID 必须保持为 $expected_bundle_identifier，实际为 $bundle_identifier"
    print -u2 "修改 Bundle ID 会让 macOS 将升级版本视为另一个应用，并丢失辅助功能授权。"
    exit 1
fi

if [[ -n "${RIGHTSCREEN_CODE_SIGN_IDENTITY:-}" ]]; then
    signing_identity="$RIGHTSCREEN_CODE_SIGN_IDENTITY"
else
    signing_name="RightScreen Local Development"
    signing_keychain="$signing_directory/RightScreen.keychain-db"
    password_file="$signing_directory/keychain-password"
    certificate_file="$signing_directory/RightScreen.cer"

    umask 077
    mkdir -p "$signing_directory"

    if [[ ! -f "$password_file" ]]; then
        print -rn -- "$(uuidgen)$(uuidgen)" > "$password_file"
    fi
    keychain_password="$(<"$password_file")"

    if [[ ! -f "$signing_keychain" ]]; then
        temporary_directory="$(mktemp -d /tmp/rightscreen-signing.XXXXXX)"
        trap 'rm -rf "$temporary_directory"' EXIT

        /usr/bin/openssl req \
            -new \
            -newkey rsa:2048 \
            -x509 \
            -days 3650 \
            -nodes \
            -subj "/CN=$signing_name/O=RightScreen" \
            -addext "basicConstraints=critical,CA:FALSE" \
            -addext "keyUsage=critical,digitalSignature" \
            -addext "extendedKeyUsage=critical,codeSigning" \
            -keyout "$temporary_directory/private-key.pem" \
            -out "$certificate_file" \
            >/dev/null 2>&1

        /usr/bin/openssl pkcs12 \
            -export \
            -out "$temporary_directory/identity.p12" \
            -inkey "$temporary_directory/private-key.pem" \
            -in "$certificate_file" \
            -passout pass:RightScreenImport \
            -name "$signing_name" \
            >/dev/null 2>&1

        security create-keychain -p "$keychain_password" "$signing_keychain"
        security unlock-keychain -p "$keychain_password" "$signing_keychain"
        security import "$temporary_directory/identity.p12" \
            -k "$signing_keychain" \
            -P RightScreenImport \
            -T /usr/bin/codesign \
            >/dev/null
        # 仅首次创建本地开发身份时，macOS 可能要求确认信任此证书。
        security add-trusted-cert \
            -r trustRoot \
            -p codeSign \
            -k "$signing_keychain" \
            "$certificate_file" || true
    fi

    # 每次签名前都修复专用钥匙串状态，兼容旧版脚本创建的钥匙串。
    # partition list 明确允许 Apple 签名工具非交互访问私钥，
    # 避免本地重建时反复弹出“codesign 想使用 RightScreen 钥匙串”。
    security unlock-keychain -p "$keychain_password" "$signing_keychain"
    security set-keychain-settings -l -u -t 21600 "$signing_keychain"
    security set-key-partition-list \
        -S apple-tool:,apple:,codesign: \
        -s \
        -k "$keychain_password" \
        "$signing_keychain" \
        >/dev/null

    existing_keychains=("${(@f)$(security list-keychains -d user | sed -E 's/^[[:space:]]*"(.*)"$/\1/')}")
    if (( ${existing_keychains[(Ie)$signing_keychain]} == 0 )); then
        security list-keychains -d user -s "$signing_keychain" "${existing_keychains[@]}"
    fi

    signing_identity="$(
        security find-identity -v -p codesigning "$signing_keychain" |
            awk -v name="$signing_name" 'index($0, "\"" name "\"") { print $2; exit }'
    )"
    if [[ -z "$signing_identity" ]]; then
        print -u2 "无法使用 RightScreen 的本地开发签名身份。"
        exit 1
    fi
fi

# 禁止 adhoc（-）：否则 TCC 按 CDHash 绑定，每次重建都会丢辅助功能授权。
if [[ "$signing_identity" == "-" ]]; then
    print -u2 "拒绝使用 adhoc 签名。辅助功能授权需要稳定的代码签名身份。"
    exit 1
fi

codesign_arguments=(
    --force
    --options runtime
    --sign "$signing_identity"
    --identifier "$bundle_identifier"
)
if [[ "${RIGHTSCREEN_SANDBOX:-}" == "1" ]]; then
    # 与 App Store 版相同的沙盒，用于本地验证沙盒下的 AX / 快捷键行为；签名身份不变，辅助功能授权仍有效。
    codesign_arguments+=(--entitlements "${0:A:h:h}/RightScreen/Resources/RightScreen.entitlements")
fi
if [[ -n "$signing_keychain" ]]; then
    # 避免同名身份或其他钥匙串干扰本地签名。
    codesign_arguments+=(--keychain "$signing_keychain")
fi
codesign "${codesign_arguments[@]}" "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"

requirement="$(codesign -d -r- "$app_path" 2>&1 | awk -F' => ' '/designated/{print $2; exit}')"
if [[ -z "$requirement" ]]; then
    print -u2 "无法读取 Designated Requirement：$app_path"
    exit 1
fi
if [[ "$requirement" != *'certificate'* ]]; then
    print -u2 "签名后仍不是证书身份（当前 DR：$requirement）"
    print -u2 "adhoc/linker-signed 会导致每次构建都要重新授权辅助功能。"
    exit 1
fi
if [[ "$requirement" != *"$bundle_identifier"* ]]; then
    print -u2 "Designated Requirement 未包含 Bundle ID $bundle_identifier"
    print -u2 "当前 DR：$requirement"
    exit 1
fi

# TCC 使用 Designated Requirement 识别同一个应用。首次成功签名后将其锁定；
# 后续即使有人改用另一张证书，打包也会直接失败，而不是产出一个会丢权限的升级包。
umask 077
mkdir -p "$signing_directory"
if [[ -f "$requirement_file" ]]; then
    pinned_requirement="$(<"$requirement_file")"
    if [[ "$requirement" != "$pinned_requirement" ]]; then
        if [[ "${RIGHTSCREEN_ALLOW_SIGNING_MIGRATION:-}" == "1" ]]; then
            print -rn -- "$requirement" > "$requirement_file"
            print -- "已显式迁移签名身份；macOS 将需要最后一次重新授权辅助功能。"
        else
            print -u2 "拒绝产出签名身份漂移的升级包。"
            print -u2 "已锁定 DR：$pinned_requirement"
            print -u2 "当前 DR：$requirement"
            print -u2 "只有计划更换证书时才可设置 RIGHTSCREEN_ALLOW_SIGNING_MIGRATION=1，并接受一次重新授权。"
            exit 1
        fi
    fi
else
    print -rn -- "$requirement" > "$requirement_file"
fi

print -- "已使用稳定身份签名：$app_path"
print -- "DR：$requirement"
