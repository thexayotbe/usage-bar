import AppKit

/// Menu bar item: two concentric gradient "activity rings" + one number.
/// Outer ring = MAIN 5h, inner ring = MAIN week; each ring uses its own severity gradient.
/// Drawn per appearance so it stays legible on light and dark menu bars.
enum MenuBarImage {
    static func make(five: Double?, week: Double?, attention: Bool) -> NSImage {
        let text = five.map { "\(Int($0.rounded()))%" } ?? "–"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .kern: -0.2]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let height: CGFloat = 22, left: CGFloat = 2, box: CGFloat = 17, gap: CGFloat = 5
        let size = NSSize(width: ceil(left + box + gap + textSize.width) + 2, height: height)

        return NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let c = CGPoint(x: left + box / 2, y: height / 2)
            ring(ctx, center: c, radius: 7, width: 2.2, pct: five)
            ring(ctx, center: c, radius: 3.6, width: 2.2, pct: week)

            (text as NSString).draw(at: NSPoint(x: left + box + gap, y: (height - textSize.height) / 2), withAttributes: attrs)

            if attention {  // small dot top-right of the rings, with a cut-out halo
                let d = CGPoint(x: left + box - 0.5, y: c.y + box / 2 - 0.5)
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: CGRect(x: d.x - 4.2, y: d.y - 4.2, width: 8.4, height: 8.4))
                ctx.restoreGState()
                Theme.orangeNS.setFill()
                NSBezierPath(ovalIn: NSRect(x: d.x - 2.8, y: d.y - 2.8, width: 5.6, height: 5.6)).fill()
            }
            return true
        }
    }

    /// Faint full track, then the used arc (from 12 o'clock, clockwise) filled with a severity gradient.
    private static func ring(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat, width w: CGFloat, pct: Double?) {
        let track = CGMutablePath()
        track.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.saveGState()
        ctx.addPath(track)
        ctx.setLineWidth(w)
        ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.2).cgColor)
        ctx.strokePath()
        ctx.restoreGState()

        let frac = min(max((pct ?? 0) / 100, 0), 1)
        guard frac > 0.005 else { return }
        let arc = CGMutablePath()
        arc.addArc(center: c, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 2 * frac, clockwise: true)
        let stroke = arc.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)

        let (a, b) = Severity(pct ?? 0).stops
        let colors = [Theme.hex(a).cgColor, Theme.hex(b).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.addPath(stroke)
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: CGPoint(x: c.x - r, y: c.y + r), end: CGPoint(x: c.x + r, y: c.y - r), options: [])
        ctx.restoreGState()
    }
}
