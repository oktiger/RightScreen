#!/usr/bin/env swift
import AppKit
import Foundation

/// Renders AppIcon.svg design into AppIcon.icns for the macOS bundle.
/// Design matches status-bar SF Symbol `rectangle.split.2x1` on system blue.

let blue = NSColor(srgbRed: 0, green: 122 / 255, blue: 1, alpha: 1) // #007AFF
let white = NSColor.white

func drawIcon(in bounds: CGRect) {
    let corner = bounds.width * 0.22265625 // 228 / 1024
    let background = NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner)
    blue.setFill()
    background.fill()

    let insetX = bounds.width * (196.0 / 1024.0)
    let insetY = bounds.height * (268.0 / 1024.0)
    let symbolRect = CGRect(
        x: bounds.minX + insetX,
        y: bounds.minY + insetY,
        width: bounds.width * (632.0 / 1024.0),
        height: bounds.height * (488.0 / 1024.0)
    )
    let stroke = bounds.width * (56.0 / 1024.0)
    let symbolCorner = bounds.width * (56.0 / 1024.0)

    let frame = NSBezierPath(
        roundedRect: symbolRect.insetBy(dx: stroke / 2, dy: stroke / 2),
        xRadius: max(symbolCorner - stroke / 2, 0),
        yRadius: max(symbolCorner - stroke / 2, 0)
    )
    frame.lineWidth = stroke
    white.setStroke()
    frame.stroke()

    let divider = CGRect(
        x: symbolRect.midX - stroke / 2,
        y: symbolRect.minY,
        width: stroke,
        height: symbolRect.height
    )
    white.setFill()
    NSBezierPath(rect: divider).fill()
}

func pngData(size: Int) -> Data {
    let scale: CGFloat = 1
    let pixelSize = CGFloat(size) * scale
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixelSize),
        pixelsHigh: Int(pixelSize),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repositoryRoot = scriptURL
    .deletingLastPathComponent() // Scripts
    .deletingLastPathComponent() // repo root
let resources = repositoryRoot.appendingPathComponent("RightScreen/Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
let icns = resources.appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// iconutil expects icon_<pt>x<pt>.png and icon_<pt>x<pt>@2x.png; App Store requires the 1024px 512@2x slice.
let entries: [(String, Int)] = [16, 32, 128, 256, 512].flatMap { points in
    [
        ("icon_\(points)x\(points).png", points),
        ("icon_\(points)x\(points)" + "@2x.png", points * 2),
    ]
}

for (name, size) in entries {
    let url = iconset.appendingPathComponent(name)
    try pngData(size: size).write(to: url)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(1)
}

try FileManager.default.removeItem(at: iconset)
print("Generated \(icns.path)")
