#!/usr/bin/env swift
import AppKit

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let iconsetPath = "Resources/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for entry in sizes {
    let s = CGFloat(entry.size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Background: dark charcoal with subtle rounded rect
    let bgColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
    let cornerRadius = s * 0.18
    let bgRect = NSRect(x: 0, y: 0, width: s, height: s)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    bgColor.setFill()
    bgPath.fill()

    // Subtle inner border
    let borderColor = NSColor(calibratedRed: 0.85, green: 0.55, blue: 0.08, alpha: 0.25)
    borderColor.setStroke()
    let inset = s * 0.02
    let borderRect = bgRect.insetBy(dx: inset, dy: inset)
    let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: cornerRadius - inset, yRadius: cornerRadius - inset)
    borderPath.lineWidth = max(1, s * 0.015)
    borderPath.stroke()

    // "wut" text — amber/orange, monospace bold
    let amber = NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.12, alpha: 1.0)
    let fontSize = s * 0.34
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    let text = "wut"
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: amber,
    ]
    let textSize = (text as NSString).size(withAttributes: attrs)
    let textX = (s - textSize.width) / 2
    let textY = (s - textSize.height) / 2 + s * 0.02
    (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

    // Small "?" accent — positioned bottom-right, dimmer
    let accentAmber = NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.12, alpha: 0.5)
    let qFontSize = s * 0.18
    let qFont = NSFont.monospacedSystemFont(ofSize: qFontSize, weight: .medium)
    let qAttrs: [NSAttributedString.Key: Any] = [
        .font: qFont,
        .foregroundColor: accentAmber,
    ]
    let qText = "?"
    let qSize = (qText as NSString).size(withAttributes: qAttrs)
    let qX = s * 0.72
    let qY = s * 0.15
    (qText as NSString).draw(at: NSPoint(x: qX, y: qY), withAttributes: qAttrs)

    image.unlockFocus()

    // Save as PNG
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(entry.name)")
    }
    let filePath = "\(iconsetPath)/\(entry.name).png"
    try! png.write(to: URL(fileURLWithPath: filePath))
    print("Generated \(entry.name) (\(entry.size)x\(entry.size))")
}

print("Iconset created at \(iconsetPath)")
print("Run: iconutil -c icns \(iconsetPath) -o Resources/AppIcon.icns")
