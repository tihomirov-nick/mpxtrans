// Renders the app icon into Resources/AppIcon.icon (the Icon Composer format) and Resources/AppIcon-1024.png
// Usage: swift scripts/make_icon.swift
//
// Speech becoming text: a sound wave of upright pills settles into three lines of text, and a caret after the last
// line is still typing. Flat and black and white like the icons of the author's other apps: a pure black body and
// pure white marks of Subline's thickness, with no gradients, glass, glows or shadows.
import AppKit

let bodyColor: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0, 0, 0)

/// The mark, drawn with the current (white) colours in the flat drawing's coordinates: a 1024 square whose body is the
/// squircle at 100...924, y growing upwards.
func drawMark(_ ctx: CGContext) {
    /// A capsule, upright or lying.
    func pill(_ rect: CGRect) -> CGPath {
        let radius = min(rect.width, rect.height) / 2
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    // Pills 84 thick like Subline's marks.
    let thickness: CGFloat = 84
    // The wave: three upright pills, the loudest in the middle, quieting toward the text.
    let wave = zip([188, 308, 428] as [CGFloat], [330, 540, 270] as [CGFloat]).map { x, height in
        CGRect(x: x, y: 512 - height / 2, width: thickness, height: height)
    }
    // The text: three lines, the last one short and being typed, with the caret after it.
    let lines = [CGRect(x: 572, y: 602, width: 264, height: thickness),
                 CGRect(x: 572, y: 470, width: 196, height: thickness),
                 CGRect(x: 572, y: 338, width: 100, height: thickness)]
    let caret = CGRect(x: lines[2].maxX + 40, y: lines[2].midY - 62, width: 44, height: 124)
    for rect in wave + lines + [caret] { ctx.addPath(pill(rect)) }
    ctx.fillPath()
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
    ctx.scaleBy(x: 1024 / 824, y: 1024 / 824)
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
    ctx.addPath(squircle(CGRect(x: 100, y: 100, width: 824, height: 824)))
    ctx.setFillColor(CGColor(colorSpace: space, components: [bodyColor.red, bodyColor.green, bodyColor.blue, 1])!)
    ctx.fillPath()
    ctx.setFillColor(white)
    drawMark(ctx)
}, to: root.appendingPathComponent("Resources/AppIcon-1024.png"))
print("Resources/AppIcon.icon and Resources/AppIcon-1024.png written")
