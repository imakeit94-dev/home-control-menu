import AppKit
import ImageIO
import UniformTypeIdentifiers

// Canonical vector source for the smart-home mark. No external images or fonts.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let iconset = assets.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func mark(_ context: CGContext, tint: CGColor, windows: Bool = true) {
    context.setStrokeColor(tint)
    context.setLineWidth(64)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 270, y: 554))
    context.addLine(to: CGPoint(x: 512, y: 752))
    context.addLine(to: CGPoint(x: 754, y: 554))
    context.strokePath()
    context.move(to: CGPoint(x: 336, y: 572))
    context.addLine(to: CGPoint(x: 336, y: 340))
    context.addQuadCurve(to: CGPoint(x: 388, y: 288), control: CGPoint(x: 336, y: 288))
    context.addLine(to: CGPoint(x: 636, y: 288))
    context.addQuadCurve(to: CGPoint(x: 688, y: 340), control: CGPoint(x: 688, y: 288))
    context.addLine(to: CGPoint(x: 688, y: 572))
    context.strokePath()
    if windows {
        for (x, y) in [(412, 492), (532, 492), (412, 372), (532, 372)] {
            context.setFillColor(x == 532 && y == 372 ? color(0x8BF0DD) : tint)
            context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: 80, height: 80),
                                   cornerWidth: 20, cornerHeight: 20, transform: nil))
            context.fillPath()
        }
    }
}

func bitmap(size: Int, draw: (CGContext) -> Void) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(context)
    return context.makeImage()!
}

func appIcon(size: Int) -> CGImage {
    bitmap(size: size) { context in
        let tile = CGPath(roundedRect: CGRect(x: 96, y: 96, width: 832, height: 832),
                          cornerWidth: 186, cornerHeight: 186, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 20,
                          color: color(0x12285B, alpha: 0.22))
        context.addPath(tile)
        context.setFillColor(color(0x1C5AD8))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(tile)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [color(0x1979F5), color(0x244DC9)] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 280, y: 928),
                                   end: CGPoint(x: 740, y: 96),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 7,
                          color: color(0x102F83, alpha: 0.18))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        mark(context, tint: color(0xF8FCFF))
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

func write(_ image: CGImage, to url: URL) throws {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    let properties = [kCGImagePropertyPNGDictionary: [
        kCGImagePropertyPNGDescription: "Original code-drawn smart-home icon. Origin: scripts/generate-icon.swift; house outline and four device windows, blue app tile; 2026-10-18."
    ]] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    // Keep origin inside every derivative, in the provenance key Impeccable reads.
    let origin = "Origin: original Core Graphics vector artwork in scripts/generate-icon.swift, 2026-10-18. Smart-home house and device windows. Rendered locally without an image model or external source."
    let text = Data(("impeccable:prompt\0" + origin).utf8)
    var chunk = Data()
    var length = UInt32(text.count).bigEndian
    withUnsafeBytes(of: &length) { chunk.append(contentsOf: $0) }
    let payload = Data("tEXt".utf8) + text
    chunk.append(payload)
    var crc: UInt32 = 0xFFFFFFFF
    for byte in payload {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0) }
    }
    var checksum = (crc ^ 0xFFFFFFFF).bigEndian
    withUnsafeBytes(of: &checksum) { chunk.append(contentsOf: $0) }
    var png = try Data(contentsOf: url)
    png.insert(contentsOf: chunk, at: png.count - 12) // Before the final IEND chunk.
    try png.write(to: url, options: .atomic)
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try write(appIcon(size: points * scale), to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try write(appIcon(size: 1024), to: assets.appendingPathComponent("AppIcon.png"))

// The menu-bar variant has no colored tile. Increase the mark's optical size,
// omit tiny windows, and use one central window that survives at 18 points.
let menu = bitmap(size: 72) { context in
    context.translateBy(x: -256, y: -282)
    context.scaleBy(x: 1.5, y: 1.5)
    mark(context, tint: color(0x000000), windows: false)
    context.setFillColor(color(0x000000))
    context.addPath(CGPath(roundedRect: CGRect(x: 452, y: 390, width: 120, height: 120),
                           cornerWidth: 24, cornerHeight: 24, transform: nil))
    context.fillPath()
}
try write(menu, to: assets.appendingPathComponent("MenuBarIcon.png"))

// Actual-size inspection sheet, on light and dark backgrounds.
let sheetSize = CGSize(width: 1000, height: 620)
let sheet = CGContext(data: nil, width: Int(sheetSize.width), height: Int(sheetSize.height),
                      bitsPerComponent: 8, bytesPerRow: Int(sheetSize.width) * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(color(0xF1F2F5)); sheet.fill(CGRect(origin: .zero, size: sheetSize))
sheet.setFillColor(color(0x202329)); sheet.fill(CGRect(x: 0, y: 0, width: 1000, height: 210))
sheet.draw(appIcon(size: 512), in: CGRect(x: 24, y: 170, width: 440, height: 440))
for (x, size) in [(510, 256), (810, 128)] {
    sheet.draw(appIcon(size: size), in: CGRect(x: x, y: 330, width: size, height: size))
}
for (x, size) in [(510, 64), (610, 32), (680, 16)] {
    sheet.draw(appIcon(size: size), in: CGRect(x: x, y: 246, width: size, height: size))
    sheet.draw(appIcon(size: size), in: CGRect(x: x, y: 90, width: size, height: size))
}
sheet.draw(menu, in: CGRect(x: 780, y: 258, width: 18, height: 18))
sheet.saveGState()
sheet.setBlendMode(.screen)
sheet.setFillColor(color(0xFFFFFF))
sheet.clip(to: CGRect(x: 780, y: 100, width: 18, height: 18), mask: menu)
sheet.fill(CGRect(x: 780, y: 100, width: 18, height: 18))
sheet.restoreGState()
let review = root.appendingPathComponent(".impeccable/review/icon", isDirectory: true)
try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
try write(sheet.makeImage()!, to: review.appendingPathComponent("sizes.png"))
print("Generated AppIcon, menu-bar template, and size review sheet")
