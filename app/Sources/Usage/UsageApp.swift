import AppKit
import Combine
import SwiftUI

/// Borderless floating panel that behaves like a popover (no arrow, rounded, closes on outside click).
final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Lets the very first click act on a control instead of only focusing the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var item: NSStatusItem!
    private var panel: PopoverPanel!
    private var bag = Set<AnyCancellable>()
    private var timers: [Timer] = []
    private var clickMonitor: Any?
    private var topY: CGFloat = 0          // screen y of the panel's top edge
    private var panelHeight: CGFloat = 320
    private var targetHeight: CGFloat = 0
    private var heightConstraint: NSLayoutConstraint!
    private var measurer: NSHostingController<AnyView>!   // same content off-screen: gives its natural height
    private var syncPending = false
    private var detailsWindow: NSWindow?
    private let panelWidth: CGFloat = 340

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageOnly

        buildPanel()
        store.showDetails = { [weak self] in self?.showDetails() }

        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateLabel()
                self?.scheduleSync()   // after the change has landed
            }
            .store(in: &bag)

        store.load()
        updateLabel()
        if CommandLine.arguments.contains("--check") {   // prints what the app would show, then quits (no UI)
            Task { await store.check(); NSApp.terminate(nil) }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(into: CommandLine.arguments[i + 1])  // renders the popover to PNGs and quits
            return
        }
        store.refresh()
        if CommandLine.arguments.contains("--show") {  // handy for testing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.show() }
            if CommandLine.arguments.contains("--details") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.showDetails() }
            }
        }
        timers = [
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.load() }
            },
            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in   // every account has its own minimum interval
                MainActor.assumeIsolated { self?.store.refresh() }
            },
        ]
    }

    // MARK: panel

    private func buildPanel() {
        panel = PopoverPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)   // always the dark palette

        let effect = NSVisualEffectView()
        effect.material = .hudWindow   // darkest system material
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        let tint = NSView()   // deep tint over the blur: darker, more solid
        tint.wantsLayer = true
        tint.layer?.backgroundColor = Theme.base.withAlphaComponent(0.78).cgColor
        tint.autoresizingMask = [.width, .height]
        tint.frame = effect.bounds
        effect.addSubview(tint)

        let host = FirstMouseHostingView(rootView: PopoverView().environmentObject(store))
        host.sizingOptions = []   // the hosting view must not dictate the window size; we animate it
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        heightConstraint = host.heightAnchor.constraint(equalToConstant: panelHeight)
        NSLayoutConstraint.activate([   // content is laid out at its natural height, pinned to the top, and clipped by the window
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            heightConstraint,
        ])
        measurer = NSHostingController(rootView: AnyView(PopoverView().environmentObject(store)))
        panel.contentView = effect
    }

    private func naturalHeight() -> CGFloat {
        measurer.sizeThatFits(in: NSSize(width: panelWidth, height: 10_000)).height.rounded(.up)
    }

    private func applyHeight(_ h: CGFloat) {
        panelHeight = h
        guard panel.isVisible else { return }
        var f = panel.frame
        f.size.height = h
        f.origin.y = topY - h
        panel.setFrame(f, display: false)      // no synchronous redraw per frame
        panel.invalidateShadow()
    }

    /// Coalesce bursts of store changes into one measurement per run-loop turn.
    private func scheduleSync() {
        guard !syncPending else { return }
        syncPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncPending = false
            if self.panel.isVisible { self.syncHeight() }
        }
    }

    /// Fit the panel to its content (e.g. the alert strip appears). Instant — no resize animation.
    private func syncHeight() {
        let target = naturalHeight()
        guard target > 40, abs(target - targetHeight) > 0.5 else { return }
        targetHeight = target
        heightConstraint.constant = target
        applyHeight(target)
    }

    // MARK: details window

    private func showDetails() {
        hide()
        if detailsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Usage"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = Theme.base
            w.contentView = NSHostingView(rootView: DetailsView().environmentObject(store))
            w.setContentSize(NSSize(width: 460, height: 720))
            w.center()
            w.setFrameAutosaveName("UsageDetails")
            detailsWindow = w
        }
        store.load()
        NSApp.activate(ignoringOtherApps: true)
        detailsWindow?.makeKeyAndOrderFront(nil)
    }

    private func show() {
        guard let button = item.button, let window = button.window else { return }
        let r = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        topY = r.minY - 4
        var x = r.midX - panelWidth / 2
        if let vf = screen?.visibleFrame { x = min(max(x, vf.minX + 8), vf.maxX - panelWidth - 8) }

        store.load()
        if store.isStale || (store.updatedAt.map { Date().timeIntervalSince($0) > 120 } ?? true) { store.refresh() }

        targetHeight = 0
        panelHeight = naturalHeight()
        heightConstraint.constant = panelHeight
        targetHeight = panelHeight
        panel.setFrame(NSRect(x: x, y: topY - panelHeight, width: panelWidth, height: panelHeight), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func hide() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        panel.orderOut(nil)
    }

    @objc private func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func updateLabel() {
        let pct = store.mainFive
        item.button?.image = MenuBarImage.make(five: pct, week: store.mainWeek, attention: store.needsAttention)
        item.button?.setAccessibilityLabel("Usage" + (pct.map { ", \(store.menuBarName ?? "") 5 hour \(Int($0.rounded())) percent" } ?? ""))
    }

    /// Debug: render the popover (light, dark) and the details window to PNG files.
    private func snapshot(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let variants: [(String, NSAppearance.Name, Bool)] = [("light", .aqua, false), ("dark", .darkAqua, false), ("details-dark", .darkAqua, true)]
        for (name, appearance, details) in variants {
            let bg = appearance == .darkAqua ? Theme.base : NSColor(white: 0.95, alpha: 1)
            let content = details
                ? AnyView(VStack(spacing: 0) { HeaderView(title: "Usage details"); ForEach(store.claude) { ClaudeCard(account: $0) }
                    ForEach(store.agy) { AgyDetailCard(account: $0) } }.padding(16).frame(width: 460).fixedSize())
                : AnyView(PopoverView())
            let host = NSHostingView(rootView: content.environmentObject(store).background(Color(nsColor: bg)))
            host.appearance = NSAppearance(named: appearance)
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.appearance = host.appearance
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
        // menu bar states on light and dark bars
        let states: [(Double, Double, Bool)] = [(59, 27, false), (74, 40, false), (88, 74, false), (96, 90, false), (59, 27, true)]
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let ap = NSAppearance(named: appearance)!
            let sheet = NSImage(size: NSSize(width: 5 * 80, height: 30), flipped: false) { _ in
                (appearance == .darkAqua ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSRect(x: 0, y: 0, width: 400, height: 30).fill()
                for (i, st) in states.enumerated() {
                    ap.performAsCurrentDrawingAppearance {
                        MenuBarImage.make(five: st.0, week: st.1, attention: st.2).draw(at: NSPoint(x: 8 + 80 * i, y: 4), from: .zero, operation: .sourceOver, fraction: 1)
                    }
                }
                return true
            }
            if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/menubar-\(name).png"))
            }
        }
        NSApp.terminate(nil)
    }
}
