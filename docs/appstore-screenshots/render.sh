#!/bin/zsh
set -euo pipefail

# 用 Chrome 无头模式把 screenshot.html 的各场景渲染成 2880×1800（Mac App Store 16:10）。
source_dir="${0:A:h}"
project_dir="${source_dir:h:h}"
out_dir="$project_dir/dist/AppStore/screenshots"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [[ ! -x "$chrome" ]]; then
    print -u2 "需要 Google Chrome：$chrome"
    exit 1
fi

mkdir -p "$out_dir"

# 系统 App 图标版权归 Apple，不入库；渲染时从本机导出到被 git 忽略的 icons/。
icons_dir="$source_dir/icons"
mkdir -p "$icons_dir"
cp "$project_dir/site/icon.png" "$icons_dir/rightscreen.png"
/usr/bin/swift - "$icons_dir" <<'SWIFT'
import AppKit
let out = CommandLine.arguments[1]
let apps = [
    "safari": "/Applications/Safari.app", "textedit": "/System/Applications/TextEdit.app",
    "terminal": "/System/Applications/Utilities/Terminal.app", "finder": "/System/Library/CoreServices/Finder.app",
    "notes": "/System/Applications/Notes.app", "xcode": "/Applications/Xcode.app",
    "calendar": "/System/Applications/Calendar.app", "preview": "/System/Applications/Preview.app",
]
for (name, path) in apps {
    // /Applications/Safari.app 是符号链接，直接取图标会带替身箭头。
    let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    let icon = NSWorkspace.shared.icon(forFile: resolved)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: 128, height: 128))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
SWIFT
profile_dir="$(mktemp -d "${TMPDIR:-/tmp}/rightscreen-shot.XXXXXX")"
trap 'rm -rf "$profile_dir"' EXIT

index=1
for scene in split quad grid drag; do
    output="$out_dir/$index-$scene.png"
    "$chrome" --headless=new --disable-gpu --hide-scrollbars \
        --user-data-dir="$profile_dir" \
        --allow-file-access-from-files \
        --window-size=1440,900 --force-device-scale-factor=2 \
        --virtual-time-budget=2000 \
        --screenshot="$output" \
        "file://$source_dir/screenshot.html?scene=$scene" >/dev/null 2>&1
    size="$(sips -g pixelWidth -g pixelHeight "$output" | awk '/pixel/{printf "%s ", $2}')"
    if [[ "$size" != "2880 1800 " ]]; then
        print -u2 "尺寸不对：$output（$size）"
        exit 1
    fi
    print -- "$output"
    index=$((index + 1))
done
