// Draws the BulkBoard app icon and writes every macOS size into the asset catalog.
// Usage: swift scripts/make_icon.swift
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appendingPathComponent("BulkBoard/Resources/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(size: CGFloat) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824×824 tile centered in 1024 with a soft drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x18181B))
    ctx.fillPath()
    ctx.restoreGState()

    // Graphite gradient
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x3A3A40), color(0x16161A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Three rising bars
    let bars: [(height: CGFloat, color: CGColor)] = [(220, color(0xFFFFFF, 0.55)), (330, color(0xFFFFFF, 0.85)), (450, color(0x4C8DFF))]
    let width: CGFloat = 118
    let gap: CGFloat = 58
    let total = CGFloat(bars.count) * width + CGFloat(bars.count - 1) * gap
    var x = 512 - total / 2
    let baseline: CGFloat = 290
    for bar in bars {
        let rect = CGRect(x: x, y: baseline, width: width, height: bar.height)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.setFillColor(bar.color)
        ctx.fillPath()
        x += width + gap
    }

    // Hairline rim
    ctx.addPath(tilePath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.08))
    ctx.setLineWidth(4)
    ctx.strokePath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [String] = []
for (points, scale) in sizes {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try writePNG(drawIcon(size: CGFloat(pixels)), to: iconSet.appendingPathComponent(name))
    images.append("""
        { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
    """)
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try writePNG(drawIcon(size: 1024), to: root.appendingPathComponent("docs/icon.png"))
print("Wrote \(sizes.count) icon sizes and docs/icon.png")
