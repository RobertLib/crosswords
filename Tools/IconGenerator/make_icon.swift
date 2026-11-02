// Renders the app icon variants (light, dark, tinted) as 1024×1024 PNGs.
// Usage: swift Tools/IconGenerator/make_icon.swift crosswords/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum Variant { case light, dark, tinted }

let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// SplitMix64: the stars come out the same on every run, so the committed icon is the one
/// this script draws.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func hills(_ ctx: CGContext, base: CGFloat, amplitude: CGFloat, waves: CGFloat, phase: CGFloat, fill: CGColor) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    for i in 0...64 {
        let x = CGFloat(i) / 64 * size
        let t = CGFloat(i) / 64
        let y = base + amplitude * (sin(t * .pi * waves + phase) * 0.6 + sin(t * .pi * waves * 2.3 + phase * 1.7) * 0.4)
        path.addLine(to: CGPoint(x: x, y: y))
    }
    path.addLine(to: CGPoint(x: size, y: 0))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
}

func roundedFont(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .black)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

func render(_ variant: Variant) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!  // App Store icons must not have alpha
    // Core Graphics origin is bottom-left.
    switch variant {
    case .light:
        ctx.drawLinearGradient(gradient([color(0xFFD9A0), color(0xFF9F7A), color(0x6E7FD8)]),
                               start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
        let sun = CGPoint(x: size * 0.74, y: size * 0.78)
        ctx.drawRadialGradient(gradient([color(0xFFF4D0, 0.9), color(0xFFF4D0, 0)]), startCenter: sun, startRadius: 0,
                               endCenter: sun, endRadius: 260, options: [])
        ctx.setFillColor(color(0xFFF6DC))
        ctx.fillEllipse(in: CGRect(x: sun.x - 85, y: sun.y - 85, width: 170, height: 170))
        hills(ctx, base: 330, amplitude: 60, waves: 2.2, phase: 0.4, fill: color(0xB97AA8))
        hills(ctx, base: 230, amplitude: 50, waves: 1.6, phase: 2.1, fill: color(0x8A5A96))
        hills(ctx, base: 130, amplitude: 40, waves: 2.6, phase: 4.0, fill: color(0x5E3F7A))
    case .dark:
        ctx.drawLinearGradient(gradient([color(0x3B2160), color(0x1E2A5A), color(0x0B1230)]),
                               start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
        var rng = SeededRandom(state: 20261102)
        for _ in 0..<70 {
            let r = CGFloat.random(in: 1.5...4.5, using: &rng)
            ctx.setFillColor(color(0xFFFFFF, CGFloat.random(in: 0.35...0.9, using: &rng)))
            ctx.fillEllipse(in: CGRect(x: CGFloat.random(in: 0...size, using: &rng),
                                       y: CGFloat.random(in: size * 0.45...size, using: &rng), width: r, height: r))
        }
        let moon = CGPoint(x: size * 0.76, y: size * 0.8)
        // A crescent: the moon disk clipped by everything outside an offset disk.
        ctx.saveGState()
        ctx.addRect(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.addEllipse(in: CGRect(x: moon.x - 40, y: moon.y - 50, width: 140, height: 140))
        ctx.clip(using: .evenOdd)
        ctx.setFillColor(color(0xFFF3D6))
        ctx.fillEllipse(in: CGRect(x: moon.x - 70, y: moon.y - 70, width: 140, height: 140))
        ctx.restoreGState()
        hills(ctx, base: 330, amplitude: 60, waves: 2.2, phase: 0.4, fill: color(0x2C3768))
        hills(ctx, base: 230, amplitude: 50, waves: 1.6, phase: 2.1, fill: color(0x1D2550))
        hills(ctx, base: 130, amplitude: 40, waves: 2.6, phase: 4.0, fill: color(0x111733))
    case .tinted:
        ctx.setFillColor(color(0x000000))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }

    // A small crossword: WORD across, WON down through the O.
    let tile: CGFloat = 176, gap: CGFloat = 18
    let cells: [(Int, Int, String)] = [(0, 1, "W"), (1, 0, "W"), (1, 1, "O"), (1, 2, "R"), (1, 3, "D"), (2, 1, "N")]
    let gridWidth = 4 * tile + 3 * gap
    let originX = (size - gridWidth) / 2
    let originY = size * 0.5 + (tile + gap) * 1.5 - 20
    for (row, col, letter) in cells {
        let rect = CGRect(x: originX + CGFloat(col) * (tile + gap), y: originY - CGFloat(row + 1) * (tile + gap) + gap,
                          width: tile, height: tile)
        let path = CGPath(roundedRect: rect, cornerWidth: tile * 0.24, cornerHeight: tile * 0.24, transform: nil)
        if variant != .tinted {
            // The tile casts its shadow from a plain fill before the clip below, which would cut
            // away anything drawn outside the tile, its shadow included.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.3))
            ctx.addPath(path)
            ctx.setFillColor(variant == .light ? color(0xE8552B) : color(0xE8782A))
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        switch variant {
        case .light:
            ctx.drawLinearGradient(gradient([color(0xFF8A3D), color(0xE8552B)]),
                                   start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
        case .dark:
            ctx.drawLinearGradient(gradient([color(0xFFB04D), color(0xE8782A)]),
                                   start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
        case .tinted:
            ctx.setFillColor(color(0xFFFFFF, row == 1 ? 1 : 0.75))
            ctx.fill(rect)
        }
        ctx.restoreGState()
        if variant != .tinted {
            ctx.addPath(path)
            ctx.setStrokeColor(color(0xFFFFFF, 0.35))
            ctx.setLineWidth(5)
            ctx.strokePath()
        }

        let font = roundedFont(tile * 0.62)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: variant == .tinted ? NSColor.black : NSColor.white,
        ]
        let text = NSAttributedString(string: letter, attributes: attributes)
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: rect.midX - bounds.width / 2 - bounds.minX,
                                   y: rect.midY - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    // A folder that does not exist or cannot be written fails here, rather than
    // after "Icons written" has been printed.
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("make_icon: cannot create \(url.path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("make_icon: writing \(url.path) failed\n".utf8))
        exit(1)
    }
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
write(render(.light), to: output.appendingPathComponent("AppIcon.png"))
write(render(.dark), to: output.appendingPathComponent("AppIcon-Dark.png"))
write(render(.tinted), to: output.appendingPathComponent("AppIcon-Tinted.png"))
print("Icons written to \(output.path)")
