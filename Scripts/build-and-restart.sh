#!/bin/zsh
set -euo pipefail

if [[ $# -ne 3 ]]; then
    print -u2 "用法：$0 <repository-root> <app-path> <running-pid>"
    exit 2
fi

repository_root="$1"
app_path="$2"
running_pid="$3"

cd "$repository_root"

swift build
bin_dir="$(swift build --show-bin-path)"
staging_app="${app_path}.building-$$.app"
staging_contents="$staging_app/Contents"

cleanup() {
    if [[ -d "$staging_app" ]]; then
        rm -rf "$staging_app"
    fi
}
trap cleanup EXIT

mkdir -p "$staging_contents/MacOS" "$staging_contents/Resources"
cp "$repository_root/RightScreen/Resources/Info.plist" "$staging_contents/Info.plist"
cp "$repository_root/RightScreen/Resources/AppIcon.icns" "$staging_contents/Resources/AppIcon.icns"
cp "$bin_dir/RightScreen" "$staging_contents/MacOS/RightScreen"
"$repository_root/Scripts/sign-app.sh" "$staging_app"

# 让旧进程先退出，避免新旧实例同时创建菜单栏状态项。
kill "$running_pid" 2>/dev/null || true
for _ in {1..50}; do
    kill -0 "$running_pid" 2>/dev/null || break
    sleep 0.1
done

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_path="${app_path}.backup-${timestamp}"
if [[ -e "$app_path" ]]; then
    mv "$app_path" "$backup_path"
fi
mv "$staging_app" "$app_path"

open "$app_path"
