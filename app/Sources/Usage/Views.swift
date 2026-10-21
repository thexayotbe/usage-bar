import SwiftUI

// MARK: building blocks

struct UsageBar: View {
    var used: Double
    var height: CGFloat = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(Severity(used).gradient)
                    .frame(width: g.size.width * min(max(used, 0), 100) / 100)
                    .shadow(color: Severity(used).color.opacity(0.45), radius: 3)   // soft glow
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: used)
    }
}

/// label · bar · percent · reset time
struct LimitRow: View {
    var label: String
    var window: Window?
    var barHeight: CGFloat
    var pctWidth: CGFloat = 32
    var resetWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.fg2).frame(width: 32, alignment: .leading)
            UsageBar(used: window?.used ?? 0, height: barHeight)
            Text(window.map { "\(Int($0.used.rounded()))%" } ?? "–")
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                .frame(width: pctWidth, alignment: .trailing)
            Text((window?.used ?? 0) < 0.5 ? "—" : Fmt.reset(window?.resets))
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.fg2)
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(width: resetWidth, alignment: .trailing)
        }
        .frame(height: 16)
    }
}

struct SectionLabel: View {
    var text: String
    var top: CGFloat = 6
    var bottom: CGFloat = 6
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.fg2)
            .padding(.horizontal, 4).padding(.top, top).padding(.bottom, bottom)
    }
}

// MARK: header, alert

struct HeaderView: View {
    @EnvironmentObject var store: UsageStore
    var title = "Usage"

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 15, weight: .semibold)).tracking(-0.2).frame(height: 20)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(store.isRefreshing ? "refreshing…" : Fmt.ago(store.updatedAt))
                        .font(.system(size: 11)).foregroundStyle(Theme.fg2).frame(height: 14)
                }
            }
            Spacer()
            // Spins only while a refresh runs; stops dead (angle 0) when it ends.
            TimelineView(.animation(paused: !store.isRefreshing)) { ctx in
                IconButton(symbol: "arrow.clockwise", help: "Refresh") { store.refresh(force: true) }
                    .rotationEffect(.degrees(store.isRefreshing ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 : 0))
            }
            .disabled(store.isRefreshing)
        }
        .padding(.horizontal, 4).padding(.top, 12).padding(.bottom, 8)
    }
}

struct IconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.fg2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Theme.press : .clear))
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}

struct AlertStrip: View {
    var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.orange)
                .frame(width: 14)
            Text(text).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.alertFill))
        .padding(.bottom, 4)
    }
}

// MARK: Claude

struct ClaudeCard: View {
    var account: ClaudeAccount
    private var quiet: Bool { account.quiet }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(account.name)
                    .font(.system(size: quiet ? 12 : 13, weight: quiet ? .medium : .semibold))
                    .foregroundStyle(quiet ? Theme.fg2 : .primary)
                if !account.tag.isEmpty { Text(account.tag).font(.system(size: 11)).foregroundStyle(Theme.fg2) }
            }
            .frame(height: 18)
            VStack(spacing: 6) {
                LimitRow(label: "5h", window: account.five, barHeight: quiet ? 4 : 5)
                LimitRow(label: "Week", window: account.week, barHeight: quiet ? 4 : 5)
            }
            .padding(.top, 8)
            if let e = account.error, account.five == nil {
                Text(e).font(.system(size: 11)).foregroundStyle(Theme.orange).lineLimit(2).padding(.top, 6)
            }
        }
        .padding(quiet ? EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12) : EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(quiet ? Theme.cardQuiet : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 0.5))
    }
}

// MARK: Agy

/// Compact "title … 4%" over a thin bar, used in the collapsed agy rows.
struct MiniMeter: View {
    var title: String
    var window: Window?

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 10)).foregroundStyle(Theme.fg2).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(window.map { "\(Int($0.used.rounded()))%" } ?? "–")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
            }
            UsageBar(used: window?.used ?? 0, height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AgyRow: View {
    var account: AgyAccount
    var openDetails: () -> Void
    var signIn: () -> Void
    @State private var hover = false

    private var statusText: String? {
        if !account.enabled { return "Off" }
        if account.needsLogin { return "Needs login" }
        return nil
    }

    private var dot: some View {
        Group {
            if !account.enabled {
                Circle().strokeBorder(Theme.dot, lineWidth: 1)
            } else {
                Circle().fill(account.needsLogin ? Theme.orange : Theme.dot)
            }
        }
        .frame(width: 6, height: 6)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: openDetails) {
                HStack(spacing: 8) {
                    dot
                    Text(account.id).font(.system(size: 13, weight: .medium)).frame(width: 40, alignment: .leading)
                    if let t = statusText {
                        Text(t).font(.system(size: 11)).foregroundStyle(Theme.fg2)
                        Spacer(minLength: 0)
                    } else {
                        HStack(spacing: 14) {
                            MiniMeter(title: "Gemini", window: account.gemini?.week)
                            MiniMeter(title: "Claude & GPT", window: account.claude?.week)
                        }
                    }
                    if !account.needsLogin || !account.enabled {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.fg2)
                            .frame(width: 12)
                    }
                }
                .padding(.leading, 12).frame(height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show details")

            if account.enabled && account.needsLogin {
                Button(action: signIn) {
                    Text("Sign in").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accentTint))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.trailing, 12)
        .background(hover ? Theme.press.opacity(0.5) : .clear)
        .onHover { hover = $0 }
    }
}

struct AgyList: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.agy.enumerated()), id: \.element.id) { i, a in
                if i > 0 { Rectangle().fill(Theme.sep).frame(height: 0.5) }
                AgyRow(account: a, openDetails: { store.showDetails?() }, signIn: { store.signIn(a.id) })
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: footer menu

struct FooterView: View {
    @EnvironmentObject var store: UsageStore
    @State private var hover = false

    var body: some View {
        HStack {
            Button { store.showDetails?() } label: {
                Text("Details").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accentTint))
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button("Show details") { store.showDetails?() }.keyboardShortcut("d", modifiers: .command)
                Button("Refresh now") { store.refresh(force: true) }.keyboardShortcut("r", modifiers: .command)
                Divider()
                Menu("Agy accounts") {
                    ForEach(store.agy) { a in
                        if a.needsLogin {
                            Button("\(a.id)  Sign in…") { store.signIn(a.id) }
                        } else {
                            Toggle(a.id, isOn: Binding(get: { a.enabled }, set: { store.setEnabled(a.id, $0) }))
                        }
                    }
                    Divider()
                    Button("Turn off all") { store.turnOffAll() }
                }
                if !store.claude.isEmpty {
                    Menu("Claude accounts") {
                        ForEach(store.claude) { a in
                            Button(a.error != nil && a.five == nil ? "\(a.name)  Sign in…" : "\(a.name)  Open session") { store.startClaude(a.id) }
                        }
                    }
                }
                Divider()
                Button("Open config…") { store.openConfig() }
                Button("Reload config") { store.reloadConfig() }
                Divider()
                Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                Divider()
                Button("Quit Usage") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.fg2)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Theme.press : .clear))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .onHover { hover = $0 }
        }
        .padding(.horizontal, 12).frame(height: 40)
        .overlay(alignment: .top) { Rectangle().fill(Theme.sep).frame(height: 0.5) }
    }
}

// MARK: popover

struct PopoverView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HeaderView()
                if let alert = store.alertText { AlertStrip(text: alert) }
                if !store.claude.isEmpty {
                    SectionLabel(text: "Claude")
                    VStack(spacing: 8) {
                        ForEach(store.claude) { ClaudeCard(account: $0) }
                    }
                }
                if !store.agy.isEmpty {
                    SectionLabel(text: "Agy", top: store.claude.isEmpty ? 6 : 14)
                    AgyList()
                }
            }
            .padding(.horizontal, 12)
            FooterView().padding(.top, 10)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)   // content keeps its own height; the popover window grows around it
        .onAppear { store.load() }
    }
}

// MARK: details window

/// Full breakdown of every account, opened from the popover.
struct DetailsView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeaderView(title: "Usage details")
                if let alert = store.alertText { AlertStrip(text: alert) }
                if !store.claude.isEmpty {
                    SectionLabel(text: "Claude")
                    VStack(spacing: 8) {
                        ForEach(store.claude) { ClaudeCard(account: $0) }
                    }
                }
                if !store.agy.isEmpty {
                    SectionLabel(text: "Agy", top: store.claude.isEmpty ? 6 : 14)
                    VStack(spacing: 8) {
                        ForEach(store.agy) { AgyDetailCard(account: $0) }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 420, idealHeight: 720)
        .background(Color(nsColor: Theme.base))
        .onAppear { store.load() }
    }
}

struct AgyDetailCard: View {
    @EnvironmentObject var store: UsageStore
    var account: AgyAccount

    private var state: String {
        if !account.enabled { return "Off" }
        if account.needsLogin { return "Needs login" }
        return "On"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(account.id).font(.system(size: 13, weight: .semibold))
                Text(state).font(.system(size: 11)).foregroundStyle(account.needsLogin ? Theme.orange : Theme.fg2)
                Spacer()
                if account.needsLogin {
                    Button("Sign in") { store.signIn(account.id) }.controlSize(.small)
                } else {
                    Toggle("", isOn: Binding(get: { account.enabled }, set: { store.setEnabled(account.id, $0) }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                }
            }
            if account.enabled && !account.needsLogin {
                group("Gemini", account.gemini)
                group("Claude & GPT", account.claude)
            }
            if let e = account.error {
                Text(e).font(.system(size: 11)).foregroundStyle(Theme.orange).lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 0.5))
    }

    private func group(_ title: String, _ g: AgyGroup?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.fg2).frame(height: 14)
            LimitRow(label: "Week", window: g?.week, barHeight: 5, resetWidth: 72)
            LimitRow(label: "5h", window: g?.five, barHeight: 5, resetWidth: 72)
        }
    }
}
