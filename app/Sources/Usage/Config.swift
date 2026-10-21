import Foundation

/// ~/.config/usage-bar/config.json — see config.example.json and the README.
struct ClaudeConfig: Codable, Equatable {
    var name: String
    var label: String?
    var configDir: String
    var keychainService: String?
}

struct AgyConfig: Codable, Equatable {
    var name: String
    var home: String?
    var enabled: Bool

    init(name: String, home: String? = nil, enabled: Bool = true) {
        self.name = name; self.home = home; self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        home = try c.decodeIfPresent(String.self, forKey: .home)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

struct AppConfig: Codable, Equatable {
    var refreshMinutes: Int = 5
    var menuBarAccount: String?
    var claude: [ClaudeConfig] = []
    var agy: [AgyConfig] = []
    var quotaFile: String?

    enum CodingKeys: String, CodingKey { case refreshMinutes, menuBarAccount, claude, agy, quotaFile }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? 5
        menuBarAccount = try c.decodeIfPresent(String.self, forKey: .menuBarAccount)
        claude = try c.decodeIfPresent([ClaudeConfig].self, forKey: .claude) ?? []
        agy = try c.decodeIfPresent([AgyConfig].self, forKey: .agy) ?? []
        quotaFile = try c.decodeIfPresent(String.self, forKey: .quotaFile)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(refreshMinutes, forKey: .refreshMinutes)
        try c.encodeIfPresent(menuBarAccount, forKey: .menuBarAccount)
        try c.encode(claude, forKey: .claude)
        try c.encode(agy, forKey: .agy)
        try c.encode(quotaFile, forKey: .quotaFile)   // explicit null
    }

    // MARK: location

    static var url: URL {
        if let p = ProcessInfo.processInfo.environment["USAGE_BAR_CONFIG"], !p.isEmpty {
            return URL(fileURLWithPath: Paths.expand(p))
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/usage-bar/config.json")
    }

    // MARK: load / save

    /// Reads the config; on first run writes an auto-detected one. A broken file is reported, never overwritten.
    static func load() -> (config: AppConfig, error: String?) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            let cfg = autodetect()
            cfg.save()
            return (cfg, nil)
        }
        do {
            let data = try Data(contentsOf: url)
            return (try JSONDecoder().decode(AppConfig.self, from: data), nil)
        } catch {
            return (autodetect(), "Config error in \(url.lastPathComponent): \(describe(error))")
        }
    }

    func save() {
        // Hand-written so keys stay in a readable order (JSONEncoder sorts or shuffles them).
        func q(_ v: String?) -> String {
            guard let v, let d = try? JSONEncoder().encode(v) else { return "null" }
            return String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
        }
        func fields(_ f: [(String, String?)]) -> String { f.compactMap { k, v in v.map { "\"\(k)\": \($0)" } }.joined(separator: ", ") }
        let claudeLines = claude.map { "    { " + fields([("name", q($0.name)), ("label", $0.label.map { q($0) }), ("configDir", q($0.configDir)),
                                                         ("keychainService", $0.keychainService.map { q($0) })]) + " }" }
        let agyLines = agy.map { "    { " + fields([("name", q($0.name)), ("home", $0.home.map { q($0) }), ("enabled", $0.enabled ? "true" : "false")]) + " }" }
        let text = """
        {
          "refreshMinutes": \(refreshMinutes),
          "menuBarAccount": \(q(menuBarAccount)),
          "claude": [
        \(claudeLines.joined(separator: ",\n"))
          ],
          "agy": [
        \(agyLines.joined(separator: ",\n"))
          ],
          "quotaFile": \(q(quotaFile))
        }

        """
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.data(using: .utf8)?.write(to: Self.url, options: .atomic)
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? DecodingError {
            switch e {
            case .dataCorrupted(let c): return c.debugDescription
            case .keyNotFound(let k, _): return "missing key \"\(k.stringValue)\""
            case .typeMismatch(_, let c), .valueNotFound(_, let c):
                return "wrong value at \(c.codingPath.map(\.stringValue).joined(separator: "."))"
            @unknown default: break
            }
        }
        return error.localizedDescription
    }

    // MARK: auto-detect

    static func autodetect() -> AppConfig {
        var cfg = AppConfig()
        let home = NSHomeDirectory()
        let fm = FileManager.default

        var dirs: [String] = []
        if looksLikeClaudeDir(home + "/.claude") { dirs.append(home + "/.claude") }
        if let names = try? fm.contentsOfDirectory(atPath: home) {
            for n in names.sorted() where n.hasPrefix(".claude-") && looksLikeClaudeDir(home + "/" + n) {
                dirs.append(home + "/" + n)
            }
        }
        var used = Set<String>()
        for d in dirs {
            let base = (d as NSString).lastPathComponent
            var name = base == ".claude" ? "main" : String(base.dropFirst(".claude-".count)).lowercased()
            if name.isEmpty || used.contains(name) { name = "claude\(used.count + 1)" }
            used.insert(name)
            cfg.claude.append(ClaudeConfig(name: name, label: nil, configDir: d.replacingOccurrences(of: home, with: "~"), keychainService: nil))
        }
        if Paths.find("agy") != nil { cfg.agy.append(AgyConfig(name: "agy", home: nil, enabled: true)) }
        cfg.menuBarAccount = cfg.claude.first?.name
        return cfg
    }

    private static func looksLikeClaudeDir(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }
        return ["settings.json", ".credentials.json", "projects", "sessions", "statsig", "todos", "shell-snapshots", "CLAUDE.md"]
            .contains { FileManager.default.fileExists(atPath: path + "/" + $0) }
    }
}

enum Paths {
    /// GUI apps get a minimal PATH, so look in the usual install locations too.
    static var searchDirs: [String] {
        let home = NSHomeDirectory()
        let env = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return env + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.claude/local", home + "/.npm-global/bin", home + "/.bun/bin"]
    }

    static func find(_ binary: String) -> String? {
        for d in searchDirs {
            let p = d + "/" + binary
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Absolute, tilde-expanded, no trailing slash.
    static func absolute(_ path: String) -> String {
        var p = URL(fileURLWithPath: expand(path)).standardizedFileURL.path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
