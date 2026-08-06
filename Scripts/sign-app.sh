#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
    print -u2 "用法：$0 <app-path>"
    exit 2
fi

app_path="$1"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"

if [[ -n "${RIGHTSCREEN_CODE_SIGN_IDENTITY:-}" ]]; then
    signing_identity="$RIGHTSCREEN_CODE_SIGN_IDENTITY"
else
    signing_name="RightScreen Local Development"
    signing_directory="$HOME/Library/Application Support/RightScreen/CodeSigning"
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
        security set-key-partition-list \
            -S apple-tool:,apple:,codesign: \
            -s \
            -k "$keychain_password" \
            "$signing_keychain" \
            >/dev/null

        # 仅首次创建本地开发身份时，macOS 可能要求确认信任此证书。
        security add-trusted-cert \
            -r trustRoot \
            -p codeSign \
            -k "$signing_keychain" \
            "$certificate_file"
    fi

    security unlock-keychain -p "$keychain_password" "$signing_keychain"

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

codesign \
    --force \
    --deep \
    --sign "$signing_identity" \
    --identifier "$bundle_identifier" \
    "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
