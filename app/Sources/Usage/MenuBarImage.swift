import AppKit

/// Menu bar item: 16pt ring (arc = MAIN 5h, colour = worst Claude limit) + one number.
/// Drawn per appearance so it stays legible on light and dark menu bars.
enum MenuBarImage {
    static func make(pct: Double?, worst: Double, attention: Bool) -> NSImage {
        let text = pct.map { "\(Int($0.rounded()))%" } ?? "–"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .kern: -0.1]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let height: CGFloat = 22, left: CGFloat = 2, ring: CGFloat = 16, gap: CGFloat = 5
        let size = NSSize(width: ceil(left + ring + gap + textSize.width) + 2, height: height)
        let sev = Severity(worst)

        return NSImage(size: size, flipped: false) { _ in
            let cx = left + ring / 2, cy = height / 2 - 1
            let track = NSBezierPath()
            track.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: 6, startAngle: 0, endAngle: 360)
            track.lineWidth = 2
            NSColor.labelColor.withAlphaComponent(0.28).setStroke()
            track.stroke()

            let frac = min(max((pct ?? 0) / 100, 0), 1)
            if frac > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: 6, startAngle: 90,
                              endAngle: 90 - 360 * frac, clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                (sev == .calm ? NSColor.labelColor : sev.ns).setStroke()
                arc.stroke()
            }

            (text as NSString).draw(at: NSPoint(x: left + ring + gap, y: (height - textSize.height) / 2 - 1), withAttributes: attrs)

            if attention {  // 6pt dot, top-right of the ring, 1.5pt halo; never changes ring colour
                let dot = NSPoint(x: left + ring, y: cy + ring / 2)
                if let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.saveGState()
                    ctx.setBlendMode(.clear)
                    ctx.fillEllipse(in: CGRect(x: dot.x - 4.5, y: dot.y - 4.5, width: 9, height: 9))
                    ctx.restoreGState()
                }
                Theme.orangeNS.setFill()
                NSBezierPath(ovalIn: NSRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)).fill()
            }
            return true
        }
    }
}
