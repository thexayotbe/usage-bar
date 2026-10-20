import AppKit
import Foundation
import ServiceManagement

struct Window {
    var used: Double          // % used, 0...100
    var resets: Date?
}

struct ClaudeAccount: Identifiable {
    var id: String            // "main", "second"
    var role: String          // "primary" / "reserve"
    var five: Window?
    var week: Window?
    var error: String?
    var name: String { id.uppercased() }
    var tag: String { role == "reserve" ? "Reserve" : "Primary" }
}

struct AgyGroup {
    var week: Window?
    var five: Window?
}

struct AgyAccount: Identifiable {
    var id: String
    var enabled: Bool
    var needsLogin: Bool
    var gemini: AgyGroup?
    var claude: AgyGroup?
    var error: String?
}

/// Reads ~/.claude-control/state/quota.json (written by `ctl.py quota`) and drives the controls.
@MainActor
final class UsageStore: ObservableObject {
    @Published var claude: [ClaudeAccount] = []
    @Published var agy: [AgyAccount] = []
    @Published var updatedAt: Date?
    @Published var isRefreshing = false
    /// Set by the app delegate: opens the details window.
    var showDetails: (() -> Void)?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude-control")
    private var quotaURL: URL { root.appendingPathComponent("state/quota.json") }
    private var ctl: String { root.appendingPathComponent("bin/ctl.py").path }
    private var ai: String { root.appendingPathComponent("bin/ai").path }

    // MARK: derived

    /// MAIN's 5h window drives the number and the arc in the menu bar.
    var mainFive: Double? { claude.first(where: { $0.id == "main" })?.five?.used ?? claude.first?.five?.used }

    var mainWeek: Double? { claude.first(where: { $0.id == "main" })?.week?.used ?? claude.first?.week?.used }

    /// Worst of all Claude limits drives the ring colour.
    var worstClaude: Double { claude.flatMap { [$0.five?.used, $0.week?.used] }.compactMap { $0 }.max() ?? 0 }

    var isStale: Bool { updatedAt.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true }

    var needsAttention: Bool {
        isStale || agy.contains { $0.enabled && $0.needsLogin } || claude.contains { $0.error != nil && $0.five == nil }
    }

    /// One line, only when a Claude limit is >= 85%; worst first.
    var alertText: String? {
        var hits: [(Double, String)] = []
        for a in claude {
            for (label, w) in [("5h", a.five), ("week", a.week)] {
                if let w, w.used >= 85 {
                    hits.append((w.used, "\(a.name) \(label) at \(Int(w.used.rounded()))%" + (w.resets.map { " — resets \(Fmt.resetShort($0))" } ?? "")))
                }
            }
        }
        return hits.max(by: { $0.0 < $1.0 })?.1
    }

    // MARK: loading

    func load() {
        let now = Date()
        guard let data = try? Data(contentsOf: quotaURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        updatedAt = (json["ts"] as? Double).map { Date(timeIntervalSince1970: $0) }

        let config = readJSON(root.appendingPathComponent("config.json"))
        let roles = (config["accounts"] as? [String: Any]) ?? [:]
        let claudeJSON = (json["claude"] as? [String: Any]) ?? [:]
        let keys = Set(roles.keys).union(claudeJSON.keys).sorted { a, b in
            let order = ["main": 0, "second": 1]
            return (order[a] ?? 9, a) < (order[b] ?? 9, b)
        }
        claude = keys.map { k in
            let q = (claudeJSON[k] as? [String: Any]) ?? [:]
            let role = ((roles[k] as? [String: Any])?["role"] as? String) ?? "primary"
            return ClaudeAccount(id: k, role: role,
                                 five: claudeWindow(q["five_hour"], now), week: claudeWindow(q["seven_day"], now),
                                 error: q["error"] as? String)
        }

        let agyJSON = (json["agy"] as? [String: Any]) ?? [:]
        let state = (readJSON(root.appendingPathComponent("state/agy.json"))["accounts"] as? [String: Any]) ?? [:]
        let list = ((config["agy"] as? [String: Any])?["accounts"] as? [[String: Any]]) ?? []
        agy = list.compactMap { a in
            guard let name = a["name"] as? String else { return nil }
            let q = (agyJSON[name] as? [String: Any]) ?? [:]
            let st = (state[name] as? [String: Any]) ?? [:]
            return AgyAccount(id: name, enabled: (a["enabled"] as? Bool) ?? true,
                              needsLogin: (q["needs_login"] as? Bool ?? false) || (st["needs_login"] as? Bool ?? false),
                              gemini: agyGroup(q["gemini"], now), claude: agyGroup(q["claude"], now),
                              error: q["error"] as? String)
        }
    }

    private func readJSON(_ url: URL) -> [String: Any] {
        guard let d = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    /// A window whose reset time has passed has reset: 0% used.
    private func live(_ used: Double, _ reset: Double?, _ now: Date) -> Window {
        let date = reset.map { Date(timeIntervalSince1970: $0) }
        if let date, date < now { return Window(used: 0, resets: nil) }
        return Window(used: used, resets: date)
    }

    private func claudeWindow(_ any: Any?, _ now: Date) -> Window? {
        guard let d = any as? [String: Any], let p = d["pct"] as? Double else { return nil }
        return live(p, d["resets"] as? Double, now)
    }

    private func agyGroup(_ any: Any?, _ now: Date) -> AgyGroup? {
        guard let d = any as? [String: Any] else { return nil }
        func w(_ key: String) -> Window? {
            guard let x = d[key] as? [String: Any], let rem = x["remaining"] as? Double else { return nil }
            return live(100 - rem, x["resets"] as? Double, now)   // agy reports % left; the app always shows % used
        }
        return AgyGroup(week: w("week"), five: w("five"))
    }

    // MARK: actions

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let script = ctl
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [script, "quota"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
            await MainActor.run {
                self.isRefreshing = false
                self.load()
            }
        }
    }

    func setEnabled(_ name: String, _ on: Bool) {
        runAI(["agy", on ? "on" : "off", name])
    }

    func turnOffAll() {
        for a in agy where a.enabled { runAI(["agy", "off", a.id]) }
    }

    private func runAI(_ args: [String]) {
        let script = ai
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [script] + args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
            await MainActor.run { self.load() }
        }
    }

    func signIn(_ name: String) { Terminal.run("\(ai) agy login \(name)") }
    func startClaude() { Terminal.run("\(ai) main") }
    func tokenReport() { Terminal.run("/usr/bin/python3 \(ctl) report; echo; read -n 1 -s -r -p 'Press any key to close'") }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

enum Terminal {
    static func run(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err { NSLog("Terminal script failed: \(err)") }
    }
}

enum Fmt {
    /// "3h 23m" inside 20 hours, otherwise "Sun 15:00".
    static func reset(_ date: Date?) -> String {
        guard let date else { return "—" }
        let s = date.timeIntervalSinceNow
        if s <= 0 { return "—" }
        if s < 20 * 3600 {
            let h = Int(s) / 3600, m = (Int(s) % 3600 + 59) / 60
            if h == 0 { return "\(m)m" }
            return m == 60 ? "\(h + 1)h 00m" : String(format: "%dh %02dm", h, m)
        }
        return weekday.string(from: date)
    }

    /// Clock time for the alert strip: "17:50" or "Thu 04:00".
    static func resetShort(_ date: Date) -> String {
        (date.timeIntervalSinceNow < 20 * 3600 ? clock : weekday).string(from: date)
    }

    static func ago(_ date: Date?) -> String {
        guard let date else { return "no data" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "updated just now" }
        if s < 60 { return "updated \(s)s ago" }
        if s < 3600 { return "updated \(s / 60)m ago" }
        return "updated \(s / 3600)h ago"
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE HH:mm"; return f
    }()
    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}
