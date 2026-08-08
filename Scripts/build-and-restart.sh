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

# 在目标目录旁组装，避免直接写半成品；最终原地替换 Contents，保持 .app 路径稳定。
staging_root="$(mktemp -d "${app_path}.staging.XXXXXX")"
staging_app="$staging_root/RightScreen.app"
staging_contents="$staging_app/Contents"

cleanup() {
    rm -rf "$staging_root"
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

mkdir -p "$app_path"
# 原地替换 Contents，避免把旧 bundle 挪成 .backup，造成 TCC/LaunchServices 多份身份。
rm -rf "$app_path/Contents"
mv "$staging_contents" "$app_path/Contents"

# 移动后必须再签最终路径，确保 DR 绑定到实际运行的 bundle。
"$repository_root/Scripts/sign-app.sh" "$app_path"

open "$app_path"
