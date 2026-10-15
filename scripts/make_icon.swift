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
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.45))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x0A1020))
    ctx.fillPath()
    ctx.restoreGState()

    // Court-navy gradient
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x22355C), color(0x0B1224)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Faint court lines: key, free-throw circle, three-point arc
    ctx.setStrokeColor(color(0xF07A2A, 0.22))
    ctx.setLineWidth(10)
    ctx.stroke(CGRect(x: 392, y: 100, width: 240, height: 300))
    ctx.strokeEllipse(in: CGRect(x: 392, y: 280, width: 240, height: 240))
    ctx.addArc(center: CGPoint(x: 512, y: 100), radius: 380, startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()

    // Hardwood glow behind the ball
    let glow = CGGradient(colorsSpace: space, colors: [color(0xF07A2A, 0.45), color(0xF07A2A, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 470), endRadius: 360, options: [])
    ctx.restoreGState()

    // Basketball
    let center = CGPoint(x: 512, y: 450)
    let radius: CGFloat = 235
    let ball = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.5))
    ctx.setFillColor(color(0xC4561A))
    ctx.fillEllipse(in: ball)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: ball)
    ctx.clip()
    let ballGradient = CGGradient(colorsSpace: space, colors: [color(0xFFA25A), color(0xF07A2A), color(0xB24A12)] as CFArray,
                                  locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(ballGradient, startCenter: CGPoint(x: center.x - 80, y: center.y + 90), startRadius: 0,
                           endCenter: center, endRadius: radius * 1.15, options: [.drawsAfterEndLocation])
    // Seams
    ctx.setStrokeColor(color(0x24120A, 0.9))
    ctx.setLineWidth(15)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: center.x, y: center.y - radius))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + radius))
    ctx.move(to: CGPoint(x: center.x - radius, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x + radius, y: center.y))
    ctx.strokePath()
    ctx.addArc(center: CGPoint(x: center.x - radius * 1.12, y: center.y), radius: radius * 0.98,
               startAngle: -.pi / 3, endAngle: .pi / 3, clockwise: false)
    ctx.strokePath()
    ctx.addArc(center: CGPoint(x: center.x + radius * 1.12, y: center.y), radius: radius * 0.98,
               startAngle: .pi * 2 / 3, endAngle: .pi * 4 / 3, clockwise: false)
    ctx.strokePath()
    // Highlight
    let shine = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(shine, startCenter: CGPoint(x: center.x - 90, y: center.y + 110), startRadius: 0,
                           endCenter: CGPoint(x: center.x - 90, y: center.y + 110), endRadius: 170, options: [])
    ctx.restoreGState()

    // Scoreboard-amber "gain" chevron above the ball
    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: 392, y: 742))
    chevron.addLine(to: CGPoint(x: 512, y: 842))
    chevron.addLine(to: CGPoint(x: 632, y: 742))
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 22, color: color(0xFFB224, 0.6))
    ctx.addPath(chevron)
    ctx.setStrokeColor(color(0xFFB224))
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Tile rim
    ctx.addPath(tilePath)
    ctx.setStrokeColor(color(0xF07A2A, 0.35))
    ctx.setLineWidth(6)
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
