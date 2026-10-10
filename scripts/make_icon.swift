// Renders the app icon into Resources/AppIcon.icon (the Icon Composer format) and Resources/AppIcon-1024.png
// Usage: swift scripts/make_icon.swift
//
// Sound becoming a word: on the left half thin sound waves weave through each other and calm down, meeting in the middle
// in one point, from which a single straight line goes on to the right. Flat and strictly black and white like the icons
// of the author's other apps: a pure black body, pure white lines, no grays, gradients or shadows.
import AppKit

let bodyColor: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0, 0, 0)

/// The side of the body, the squircle of the flat drawing, in a 1024 square: it lies at 100...924.
let bodySize: CGFloat = 824
/// How much of the body's width the mark spans, round ends included. The mark is a strip in the middle of the tile (the
/// waves, its tallest part, are 38 % of the body high), so it stays far from the rounded corners, and only the margin at
/// the sides limits it: 10 % of the body on each side.
let markShare: CGFloat = 0.80

/// The mark, drawn with the current (white) colours in the flat drawing's coordinates: a 1024 square whose body is the
/// squircle at 100...924, y growing upwards.
func drawMark(_ ctx: CGContext) {
    // Designed 632 across with its round ends (196...828), the waves filling the left half up to the middle, 512, and
    // scaled about the middle of the tile to `markShare` of the body.
    let left: CGFloat = 208, middle: CGFloat = 512, right: CGFloat = 816, axis: CGFloat = 512
    let designedWidth: CGFloat = 632
    /// A sine wave whose swing holds on the left and fades smoothly to nothing in the middle, where the wave lies
    /// down on the axis and becomes the line.
    func wave(amplitude: CGFloat, cycles: CGFloat, phase: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0...400 {
            let t = CGFloat(i) / 400
            let point = CGPoint(x: left + (middle - left) * t,
                                y: axis + amplitude * pow(cos(.pi / 2 * t), 1.6) * sin(2 * .pi * cycles * t + phase))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
    ctx.saveGState()
    let scale = bodySize * markShare / designedWidth
    ctx.translateBy(x: middle, y: axis)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -middle, y: -axis)
    // Thin lines, still a pixel at 32 px.
    ctx.setLineWidth(24)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    // Two waves of slightly different lengths and almost opposite phases so that they cross each other, and the
    // word's line, all white.
    let strokes = CGMutablePath()
    strokes.addPath(wave(amplitude: 170, cycles: 1.6, phase: 0))
    strokes.addPath(wave(amplitude: 120, cycles: 1.9, phase: 3.6))
    strokes.move(to: CGPoint(x: middle, y: axis))
    strokes.addLine(to: CGPoint(x: right, y: axis))
    ctx.addPath(strokes)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - The icon files (the same in every app of the family)

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let white = CGColor(colorSpace: space, components: [1, 1, 1, 1])!

/// Apple-style continuous corners (superellipse).
func squircle(_ rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / exponent)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / exponent)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// A transparent 1024 × 1024 image, drawn into with white as the colour.
func image(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(white)
    ctx.setStrokeColor(white)
    draw(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
}

// Resources/AppIcon.icon. In the Icon Composer format the 1024 canvas is the whole tile: the system cuts the squircle and
// leaves the margins itself. So the mark, laid out on the body of the flat drawing (824 of 1024 from 100), is scaled by
// 1024 / 824 to take the same part of the tile. One layer, the white mark on transparent; a solid fill in the body's
// colour; no glass, shadow, translucency or specular highlights, so the icon stays flat. On macOS 26 such an icon shows
// without the grey plate that the system puts around plain .icns icons.
let package = root.appendingPathComponent("Resources/AppIcon.icon")
try? FileManager.default.removeItem(at: package)
try FileManager.default.createDirectory(at: package.appendingPathComponent("Assets"), withIntermediateDirectories: true)
try writePNG(image { ctx in
    ctx.scaleBy(x: 1024 / bodySize, y: 1024 / bodySize)
    ctx.translateBy(x: -100, y: -100)
    drawMark(ctx)
}, to: package.appendingPathComponent("Assets/mark.png"))
let fill = String(format: "srgb:%.5f,%.5f,%.5f,1.00000", bodyColor.red, bodyColor.green, bodyColor.blue)
try Data("""
{
  "fill" : {
    "solid" : "\(fill)"
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : false,
          "image-name" : "mark.png",
          "name" : "mark"
        }
      ],
      "shadow" : {
        "kind" : "none",
        "opacity" : 0
      },
      "specular" : false,
      "translucency" : {
        "enabled" : false,
        "value" : 0
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

""".utf8).write(to: package.appendingPathComponent("icon.json"))

// Resources/AppIcon-1024.png: the whole icon, the body in the squircle with the mark, for the README.
try writePNG(image { ctx in
    ctx.addPath(squircle(CGRect(x: 100, y: 100, width: bodySize, height: bodySize)))
    ctx.setFillColor(CGColor(colorSpace: space, components: [bodyColor.red, bodyColor.green, bodyColor.blue, 1])!)
    ctx.fillPath()
    ctx.setFillColor(white)
    drawMark(ctx)
}, to: root.appendingPathComponent("Resources/AppIcon-1024.png"))
print("Resources/AppIcon.icon and Resources/AppIcon-1024.png written")
