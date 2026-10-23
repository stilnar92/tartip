// Draws the app icon (1024×1024 PNG): a bright gradient squircle with a white target.
// Usage: swift make-icon.swift out.png

import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824 px body centered on a 1024 canvas, with a soft shadow.
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
shape.fill()
ctx.restoreGState()

// Hot orange → magenta → violet: stands out among blue/grey Dock icons.
ctx.saveGState()
shape.addClip()
let gradient = NSGradient(colors: [
    NSColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1),
    NSColor(red: 0.96, green: 0.18, blue: 0.45, alpha: 1),
    NSColor(red: 0.45, green: 0.20, blue: 0.95, alpha: 1),
])!
gradient.draw(in: body, angle: -60)

// Glossy top highlight.
let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
gloss.draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
ctx.restoreGState()

// White target: rings + center dot.
let c = CGPoint(x: size / 2, y: size / 2)
NSColor.white.setStroke()
for (r, w) in [(270.0, 52.0), (165.0, 46.0)] {
    let ring = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    ring.lineWidth = w
    ring.stroke()
}
NSColor.white.setFill()
NSBezierPath(ovalIn: CGRect(x: c.x - 62, y: c.y - 62, width: 124, height: 124)).fill()

// Crosshair ticks outside the outer ring.
for angle in stride(from: 0.0, to: 360.0, by: 90.0) {
    let a = angle * .pi / 180
    let p = NSBezierPath()
    p.move(to: CGPoint(x: c.x + cos(a) * 300, y: c.y + sin(a) * 300))
    p.line(to: CGPoint(x: c.x + cos(a) * 375, y: c.y + sin(a) * 375))
    p.lineWidth = 46
    p.lineCapStyle = .round
    p.stroke()
}

img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
