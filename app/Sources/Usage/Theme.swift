import AppKit
import SwiftUI

/// Design tokens from the "Usage — macOS menu bar app" spec (light / dark).
enum Theme {
    static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    // Severity
    static let calmNS = dyn(hex(0x10B981), hex(0x34D399))
    static let amberNS = dyn(hex(0xD97706), hex(0xFBBF24))
    static let orangeNS = dyn(hex(0xEA580C), hex(0xFB923C))
    static let redNS = dyn(hex(0xDC2626), hex(0xF87171))

    // Surfaces
    static let fg2 = Color(nsColor: dyn(hex(0x5F5F66), hex(0x8B8D98)))
    static let card = Color(nsColor: dyn(NSColor.white.withAlphaComponent(0.60), NSColor.white.withAlphaComponent(0.045)))
    static let cardQuiet = Color(nsColor: dyn(NSColor.white.withAlphaComponent(0.30), NSColor.white.withAlphaComponent(0.025)))
    static let cardBorder = Color(nsColor: dyn(NSColor.black.withAlphaComponent(0.06), NSColor.white.withAlphaComponent(0.07)))
    static let sep = Color(nsColor: dyn(NSColor.black.withAlphaComponent(0.08), NSColor.white.withAlphaComponent(0.06)))
    static let track = Color(nsColor: dyn(hex(0x3C3C43, 0.14), NSColor.white.withAlphaComponent(0.08)))
    static let press = Color(nsColor: dyn(NSColor.black.withAlphaComponent(0.08), NSColor.white.withAlphaComponent(0.10)))
    static let dot = Color(nsColor: dyn(hex(0x3C3C43, 0.35), NSColor.white.withAlphaComponent(0.35)))

    // Accent + alert
    static let accentText = Color(nsColor: dyn(hex(0x4F46E5), hex(0xA5B4FC)))
    static let accentTint = Color(nsColor: dyn(hex(0x6366F1, 0.12), hex(0x6366F1, 0.22)))
    static let alertFill = Color(nsColor: dyn(hex(0xF26B1D, 0.14), hex(0xFF8A3D, 0.18)))
    static let orange = Color(nsColor: orangeNS)

    /// Deep near-black surface used by the panel tint and the details window.
    static let base = NSColor(srgbRed: 0.043, green: 0.047, blue: 0.063, alpha: 1)   // #0B0C10
}

enum Severity {
    case calm, amber, orange, red

    init(_ p: Double) {
        switch p {
        case ..<70: self = .calm
        case ..<85: self = .amber
        case ..<95: self = .orange
        default: self = .red
        }
    }

    var color: Color { Color(nsColor: ns) }

    /// Modern two-stop fill for bars and rings (start → end).
    var stops: (UInt32, UInt32) {
        switch self {
        case .calm: return (0x22D3EE, 0x34D399)     // cyan → emerald
        case .amber: return (0xFDE047, 0xF59E0B)
        case .orange: return (0xFDBA74, 0xF97316)
        case .red: return (0xFCA5A5, 0xEF4444)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [Color(nsColor: Theme.hex(stops.0)), Color(nsColor: Theme.hex(stops.1))], startPoint: .leading, endPoint: .trailing)
    }

    var ns: NSColor {
        switch self {
        case .calm: return Theme.calmNS
        case .amber: return Theme.amberNS
        case .orange: return Theme.orangeNS
        case .red: return Theme.redNS
        }
    }
}
