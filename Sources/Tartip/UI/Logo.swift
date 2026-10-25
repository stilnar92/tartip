import AppKit

// The Tartip mark: a person shaped like a tulip. The bloom is the body, a dot above it the
// head, and the stem with two leaves roots it: someone growing, undistracted. The tulip is
// also the Tatar ornament's flower. AppKit only, so scripts/make-icon.swift draws the same
// mark into the app icon.
enum Logo {
    // The mark's parts inside `r` (y up), each to be filled on its own: where parts overlap
    // (leaves over the stem) one combined path would cancel out and leave holes.
    static func parts(in r: CGRect) -> [CGPath] {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var parts: [CGPath] = []

        // Head.
        let head = r.width * 0.13
        parts.append(CGPath(ellipseIn: CGRect(x: p(0.5, 0).x - head / 2, y: p(0, 0.80).y, width: head, height: head), transform: nil))

        // Bloom: three petals over a cup.
        let out = CGMutablePath()
        out.move(to: p(0.50, 0.36))
        out.addCurve(to: p(0.27, 0.70), control1: p(0.31, 0.39), control2: p(0.25, 0.55))
        out.addCurve(to: p(0.42, 0.61), control1: p(0.33, 0.68), control2: p(0.39, 0.65))
        out.addCurve(to: p(0.50, 0.74), control1: p(0.45, 0.67), control2: p(0.47, 0.72))
        out.addCurve(to: p(0.58, 0.61), control1: p(0.53, 0.72), control2: p(0.55, 0.67))
        out.addCurve(to: p(0.73, 0.70), control1: p(0.61, 0.65), control2: p(0.67, 0.68))
        out.addCurve(to: p(0.50, 0.36), control1: p(0.75, 0.55), control2: p(0.69, 0.39))
        out.closeSubpath()
        parts.append(out)

        // Stem, as a filled shape.
        let stem = CGMutablePath()
        stem.move(to: p(0.50, 0.37))
        stem.addLine(to: p(0.50, 0.09))
        parts.append(stem.copy(strokingWithWidth: r.width * 0.065, lineCap: .round, lineJoin: .round, miterLimit: 4))

        // Two leaves low on the stem.
        for s: CGFloat in [-1, 1] {
            let leaf = CGMutablePath()
            leaf.move(to: p(0.50, 0.13))
            leaf.addCurve(to: p(0.50 + 0.22 * s, 0.30), control1: p(0.50 + 0.04 * s, 0.25), control2: p(0.50 + 0.13 * s, 0.30))
            leaf.addCurve(to: p(0.50, 0.13), control1: p(0.50 + 0.18 * s, 0.19), control2: p(0.50 + 0.09 * s, 0.13))
            leaf.closeSubpath()
            parts.append(leaf)
        }
        return parts
    }

    static func draw(in r: CGRect, color: NSColor, on ctx: CGContext) {
        ctx.setFillColor(color.cgColor)
        for part in parts(in: r) { ctx.addPath(part); ctx.fillPath() }
    }

    // The mark as an image. A template image takes the menu bar's own colour, light or dark.
    static func image(size: CGFloat, color: NSColor = .black, template: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: rect, color: color, on: ctx)
            return true
        }
        img.isTemplate = template
        return img
    }

    // Menu bar size: macOS lays out status items at 18 pt.
    @MainActor static let menuBar = image(size: 18, template: true)
}
