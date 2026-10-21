import AppKit
import Foundation
import ServiceManagement

struct Window {
    var used: Double          // % used, 0...100
    var resets: Date?
}

struct ClaudeAccount: Identifiable {
    var id: String            // account name from the config
    var label: String?        // optional free text, e.g. "reserve"
    var five: Window?
    var week: Window?
    var error: String?
    var stale = false         // last fetch failed; numbers are from an earlier one
    var name: String { id.uppercased() }
    var tag: String { label ?? "" }
    /// Accounts labelled "reserve" are drawn quieter.
    var quiet: Bool { label?.lowercased() == "reserve" }
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

/// Fetches Claude + agy limits natively (or reads an optional quotaFile) and drives the controls.
@MainActor
final class UsageStore: ObservableObject {
    @Published var claude: [ClaudeAccount] = []
    @Published var agy: [AgyAccount] = []
    @Published var updatedAt: Date?
    @Published var isRefreshing = false
    @Published var problem: String?       // config / quotaFile trouble, shown in the alert strip
    /// Set by the app delegate: opens the details window.
    var showDetails: (() -> Void)?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private(set) var config = AppConfig()
    private var cache = Cache.load()

    init() {
        let r = AppConfig.load()
        config = r.config
        problem = r.error
    }

    // MARK: derived

    private var menuBarClaude: ClaudeAccount? {
        claude.first(where: { $0.id.lowercased() == config.menuBarAccount?.lowercased() }) ?? claude.first
    }

    /// The menu bar account's 5h window drives the number and the arc in the menu bar.
    var mainFive: Double? { menuBarClaude?.five?.used }
    var mainWeek: Double? { menuBarClaude?.week?.used }
    var menuBarName: String? { menuBarClaude?.name }

    /// Worst of all Claude limits drives the ring colour.
    var worstClaude: Double { claude.flatMap { [$0.five?.used, $0.week?.used] }.compactMap { $0 }.max() ?? 0 }

    var isStale: Bool { updatedAt.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true }

    var needsAttention: Bool {
        isStale || agy.contains { $0.enabled && $0.needsLogin } || claude.contains { $0.error != nil && ($0.five == nil || $0.stale) }
    }

    /// One line: a config problem, else the worst Claude limit that is >= 85%.
    var alertText: String? {
        if let p = problem { return p }
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

    private var quotaFile: String? {
        guard let q = config.quotaFile?.trimmingCharacters(in: .whitespaces), !q.isEmpty else { return nil }
        return q
    }

    // MARK: loading (no network: rebuilds the view model from the cache or quotaFile)

    func load() {
        let now = Date()
        var cRecs = cache.claude, aRecs = cache.agy
        var names = config.claude.map(\.name)
        if let q = quotaFile {
            if let r = QuotaFile.read(q) {
                cRecs = r.claude; aRecs = r.agy
                updatedAt = r.ts.map { Date(timeIntervalSince1970: $0) }
                problem = problem?.hasPrefix("Can't read quotaFile") == true ? nil : problem
                let known = Set(names.map { $0.lowercased() })
                names += r.claude.keys.filter { !known.contains($0) }.sorted()
            } else {
                problem = problem ?? "Can't read quotaFile \((q as NSString).lastPathComponent)"
            }
        } else {
            let stamps = config.claude.compactMap { cRecs[$0.name.lowercased()]?.fetchedAt }
                + config.agy.filter(\.enabled).compactMap { aRecs[$0.name.lowercased()]?.fetchedAt }
            updatedAt = stamps.max().map { Date(timeIntervalSince1970: $0) }
        }

        claude = names.map { n in
            let rec = cRecs[n.lowercased()] ?? ClaudeRec()
            let label = config.claude.first { $0.name == n }?.label
            return ClaudeAccount(id: n, label: label?.isEmpty == true ? nil : label,
                                 five: live(rec.five, now), week: live(rec.week, now),
                                 error: rec.error, stale: rec.error != nil && rec.five != nil)
        }
        agy = config.agy.map { a in
            let rec = aRecs[a.name.lowercased()] ?? AgyRec()
            return AgyAccount(id: a.name, enabled: a.enabled, needsLogin: rec.needsLogin,
                              gemini: group(rec.gemini, now), claude: group(rec.claude, now), error: rec.error)
        }
    }

    /// A window whose reset time has passed has reset: 0% used.
    private func live(_ w: WinRec?, _ now: Date) -> Window? {
        guard let w else { return nil }
        let date = w.resets.map { Date(timeIntervalSince1970: $0) }
        if let date, date < now { return Window(used: 0, resets: nil) }
        return Window(used: w.used, resets: date)
    }

    private func group(_ g: AgyGroupRec?, _ now: Date) -> AgyGroup? {
        g.map { AgyGroup(week: live($0.week, now), five: live($0.five, now)) }
    }

    // MARK: refreshing

    private var claudeInterval: TimeInterval { Double(max(config.refreshMinutes, 5)) * 60 }   // never poll the API faster than 5 min
    private var agyInterval: TimeInterval { Double(max(config.refreshMinutes, 1)) * 60 }

    private func claudeDue(_ a: ClaudeConfig, force: Bool, _ now: Double) -> Bool {
        guard let r = cache.claude[a.name.lowercased()], r.source == a.configDir else { return true }
        if let b = r.backoffUntil, b > now { return false }
        if force && r.lastAPICall == nil { return true }   // never reached the API (e.g. not signed in yet): retry on demand
        return now >= (r.lastAttempt ?? 0) + claudeInterval
    }

    private func agyDue(_ a: AgyConfig, force: Bool, _ now: Double) -> Bool {
        guard let r = cache.agy[a.name.lowercased()], r.source == a.home else { return true }
        return now >= (r.lastAttempt ?? 0) + (force ? 30 : agyInterval)
    }

    private enum Fetched {
        case claude(String, ClaudeRec)
        case agy(String, AgyRec)
    }

    /// Fetches whatever is due. Cheap to call often: every account has its own minimum interval.
    func refresh(force: Bool = false) {
        if quotaFile != nil { load(); return }
        guard !isRefreshing else { return }
        let now = Date().timeIntervalSince1970
        let claudeJobs = config.claude.filter { claudeDue($0, force: force, now) }
        let agyJobs = config.agy.filter { $0.enabled && agyDue($0, force: force, now) }
        guard !claudeJobs.isEmpty || !agyJobs.isEmpty else { load(); return }
        isRefreshing = true
        let priorC = cache.claude, priorA = cache.agy
        Task {
            var results: [Fetched] = []
            await withTaskGroup(of: Fetched.self) { g in
                for a in claudeJobs { g.addTask { .claude(a.name.lowercased(), await ClaudeFetcher.fetch(a, prior: priorC[a.name.lowercased()])) } }
                for a in agyJobs { g.addTask { .agy(a.name.lowercased(), await AgyFetcher.fetch(a, prior: priorA[a.name.lowercased()])) } }
                for await r in g { results.append(r) }
            }
            for r in results {
                switch r {
                case .claude(let k, let rec): cache.claude[k] = rec
                case .agy(let k, let rec): cache.agy[k] = rec
                }
            }
            cache.save()
            isRefreshing = false
            load()
        }
    }

    /// Debug (`--check`): fetch everything that is due, print a token-free summary.
    func check() async {
        refresh(force: true)
        while isRefreshing { try? await Task.sleep(nanoseconds: 200_000_000) }
        load()
        for a in claude {
            print("claude \(a.id): 5h=\(a.five.map { "\(Int($0.used.rounded()))%" } ?? "-") week=\(a.week.map { "\(Int($0.used.rounded()))%" } ?? "-")" + (a.error.map { " error=\($0)" } ?? ""))
        }
        for a in agy {
            func s(_ g: AgyGroup?) -> String { "wk=\(g?.week.map { "\(Int($0.used.rounded()))%" } ?? "-") 5h=\(g?.five.map { "\(Int($0.used.rounded()))%" } ?? "-")" }
            print("agy \(a.id): enabled=\(a.enabled) needsLogin=\(a.needsLogin) gemini[\(s(a.gemini))] claude[\(s(a.claude))]" + (a.error.map { " error=\($0)" } ?? ""))
        }
    }

    // MARK: config actions

    func reloadConfig() {
        let r = AppConfig.load()
        config = r.config
        problem = r.error
        load()
        refresh(force: true)
    }

    func openConfig() {
        if !FileManager.default.fileExists(atPath: AppConfig.url.path) { config.save() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", AppConfig.url.path]   // default text editor
        try? p.run()
    }

    func setEnabled(_ name: String, _ on: Bool) {
        guard let i = config.agy.firstIndex(where: { $0.name == name }) else { return }
        config.agy[i].enabled = on
        config.save()
        load()
        if on { refresh() }
    }

    func turnOffAll() {
        for i in config.agy.indices { config.agy[i].enabled = false }
        config.save()
        load()
    }

    // MARK: sign-in / sessions (open Terminal)

    func signIn(_ name: String) {
        guard let a = config.agy.first(where: { $0.name == name }) else { return }
        var cmd = Paths.shellQuote(Paths.find("agy") ?? "agy")
        if let h = a.home, !h.isEmpty, Paths.absolute(h) != Paths.absolute("~") { cmd = "HOME=\(Paths.shellQuote(Paths.absolute(h))) " + cmd }
        Terminal.run(cmd)
    }

    func startClaude(_ name: String) {
        guard let a = config.claude.first(where: { $0.name == name }) else { return }
        var cmd = Paths.shellQuote(Paths.find("claude") ?? "claude")
        if Paths.absolute(a.configDir) != Paths.absolute("~/.claude") { cmd = "CLAUDE_CONFIG_DIR=\(Paths.shellQuote(Paths.absolute(a.configDir))) " + cmd }
        Terminal.run(cmd)
    }

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
