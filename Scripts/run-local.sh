#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

swift build
bin_dir="$(swift build --show-bin-path)"
app_dir="$project_dir/.build/RightScreen.app"
"$project_dir/Scripts/package-app.sh" "$bin_dir/RightScreen" "$app_dir"

if [[ "${1:-}" != "--build-only" ]]; then
    open "$app_dir"
fi
