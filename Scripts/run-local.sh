#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

swift build
bin_dir="$(swift build --show-bin-path)"
app_dir="$project_dir/.build/RightScreen.app"
contents_dir="$app_dir/Contents"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$project_dir/RightScreen/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/RightScreen/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
cp "$bin_dir/RightScreen" "$contents_dir/MacOS/RightScreen"
"$project_dir/Scripts/sign-app.sh" "$app_dir"

if [[ "${1:-}" != "--build-only" ]]; then
    open "$app_dir"
fi
