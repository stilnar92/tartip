// Draws the app icon (1024×1024 PNG): the Tartip mark (Sources/Tartip/UI/Logo.swift) in white
// on a green squircle, the green of the flag of Tatarstan.
// Built with Logo.swift by scripts/build.sh: swiftc Logo.swift make-icon.swift → build/make-icon out.png

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

// Flag green to a deep forest green.
ctx.saveGState()
shape.addClip()
let gradient = NSGradient(colors: [
    NSColor(red: 0.00, green: 0.55, blue: 0.33, alpha: 1),
    NSColor(red: 0.02, green: 0.33, blue: 0.27, alpha: 1),
])!
gradient.draw(in: body, angle: -70)

// Soft top highlight.
let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
gloss.draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
ctx.restoreGState()

// The mark, white, with room to breathe.
let mark = body.insetBy(dx: 140, dy: 125)
Logo.draw(in: mark, color: .white, on: ctx)

img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
