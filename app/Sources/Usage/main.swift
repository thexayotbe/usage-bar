import AppKit

// Plain AppKit entry point: no SwiftUI scenes, so no stray windows (only the status item + popover).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
