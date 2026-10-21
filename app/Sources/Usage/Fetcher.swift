import CryptoKit
import Foundation

// MARK: records (also the on-disk cache format)

struct WinRec: Codable {
    var used: Double          // % used, 0...100
    var resets: Double?       // epoch seconds
}

struct ClaudeRec: Codable {
    var source: String?       // configDir the numbers came from
    var five: WinRec?
    var week: WinRec?
    var fetchedAt: Double?    // last successful fetch
    var lastAttempt: Double?  // last fetch attempt of any kind
    var lastAPICall: Double?  // last time the API was actually called
    var backoffUntil: Double?
    var backoffSecs: Double?
    var error: String?
}

struct AgyGroupRec: Codable {
    var week: WinRec?
    var five: WinRec?
}

struct AgyRec: Codable {
    var source: String?
    var gemini: AgyGroupRec?
    var claude: AgyGroupRec?
    var fetchedAt: Double?
    var lastAttempt: Double?
    var needsLogin = false
    var error: String?
}

struct Cache: Codable {
    var claude: [String: ClaudeRec] = [:]
    var agy: [String: AgyRec] = [:]

    static var url: URL {
        var dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/dev.thexayotbe.usage")
        if let p = ProcessInfo.processInfo.environment["USAGE_BAR_CACHE"], !p.isEmpty { dir = URL(fileURLWithPath: Paths.expand(p)) }
        return dir.appendingPathComponent("cache.json")
    }

    static func load() -> Cache {
        guard let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Cache.self, from: d) else { return Cache() }
        return c
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: Self.url, options: .atomic) }
    }
}

// MARK: running processes

struct ProcResult {
    var status: Int32 = -1
    var output = ""
    var timedOut = false
    var launchError: String?
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

func runProcess(_ exe: String, _ args: [String], env: [String: String] = [:], cwd: String? = nil,
                timeout: TimeInterval, mergeStderr: Bool) async -> ProcResult {
    await withCheckedContinuation { cont in
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            var e = ProcessInfo.processInfo.environment
            e["PATH"] = Paths.searchDirs.joined(separator: ":")
            for (k, v) in env { e[k] = v }
            p.environment = e
            if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
            let pipe = Pipe()
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = pipe
            p.standardError = mergeStderr ? pipe : FileHandle.nullDevice

            let exited = DispatchSemaphore(value: 0)
            p.terminationHandler = { _ in exited.signal() }
            do { try p.run() } catch {
                cont.resume(returning: ProcResult(launchError: error.localizedDescription))
                return
            }
            let box = Box()
            let readDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                box.set(pipe.fileHandleForReading.readDataToEndOfFile())
                readDone.signal()
            }
            var res = ProcResult()
            if exited.wait(timeout: .now() + timeout) == .timedOut {
                res.timedOut = true
                p.terminate()
                if exited.wait(timeout: .now() + 2) == .timedOut { kill(p.processIdentifier, SIGKILL) }
            }
            _ = readDone.wait(timeout: .now() + 1)   // a grandchild holding the pipe must not block us
            res.status = p.isRunning ? -1 : p.terminationStatus
            res.output = String(decoding: box.get(), as: UTF8.self)
            cont.resume(returning: res)
        }
    }
}

// MARK: Claude

enum ClaudeFetcher {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Keychain service names Claude Code uses for a config dir.
    static func services(for a: ClaudeConfig) -> [String] {
        if let s = a.keychainService, !s.isEmpty { return [s] }
        let dir = Paths.absolute(a.configDir)
        let hashed = "Claude Code-credentials-" + sha8(dir)
        return dir == Paths.absolute("~/.claude") ? ["Claude Code-credentials", hashed] : [hashed]
    }

    static func sha8(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    enum Token { case ok(String), expired, missing }

    /// Reads the OAuth access token from the keychain, falling back to <configDir>/.credentials.json. Never logged.
    static func token(for a: ClaudeConfig) async -> Token {
        var blobs: [Data] = []
        for svc in services(for: a) {
            let r = await runProcess("/usr/bin/security", ["find-generic-password", "-s", svc, "-w"], timeout: 120, mergeStderr: false)
            if r.status == 0, let d = r.output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8), !d.isEmpty { blobs.append(d) }
        }
        if let d = try? Data(contentsOf: URL(fileURLWithPath: Paths.absolute(a.configDir) + "/.credentials.json")) { blobs.append(d) }

        var sawExpired = false
        for d in blobs {
            guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            let o = (j["claudeAiOauth"] as? [String: Any]) ?? j
            guard let t = o["accessToken"] as? String, !t.isEmpty else { continue }
            if let exp = o["expiresAt"] as? Double, exp / 1000 < Date().timeIntervalSince1970 { sawExpired = true; continue }
            return .ok(t)
        }
        return sawExpired ? .expired : .missing
    }

    enum Outcome {
        case ok(five: WinRec?, week: WinRec?)
        case rateLimited(retryAfter: Double?)
        case unauthorized
        case failed(String)
    }

    static func callAPI(token: String) async -> Outcome {
        var req = URLRequest(url: usageURL, timeoutInterval: 20)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("usage-bar", forHTTPHeaderField: "User-Agent")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        do {
            let (data, resp) = try await URLSession(configuration: cfg).data(for: req)
            let http = resp as? HTTPURLResponse
            switch http?.statusCode ?? 0 {
            case 200:
                guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failed("Unexpected response from the usage API") }
                return .ok(five: window(j["five_hour"]), week: window(j["seven_day"]))
            case 429:
                return .rateLimited(retryAfter: http?.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0.trimmingCharacters(in: .whitespaces)) })
            case 401, 403:
                return .unauthorized
            case let c:
                return .failed("Usage API returned HTTP \(c)")
            }
        } catch {
            return .failed("Network error: \((error as NSError).localizedDescription)")
        }
    }

    private static func window(_ any: Any?) -> WinRec? {
        guard let d = any as? [String: Any], let u = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
        return WinRec(used: u, resets: (d["resets_at"] as? String).flatMap(parseISO))
    }

    /// One fetch for one account, folded into its previous record (last good numbers are kept on failure).
    static func fetch(_ a: ClaudeConfig, prior: ClaudeRec?) async -> ClaudeRec {
        var rec = prior ?? ClaudeRec()
        let now = Date().timeIntervalSince1970
        rec.source = a.configDir
        rec.lastAttempt = now
        switch await token(for: a) {
        case .missing:
            rec.error = "No Claude login found for this account. Use … → Claude accounts → Sign in."
            return rec
        case .expired:
            rec.error = "Claude token expired. Open a Claude Code session on this account to refresh it."
            return rec
        case .ok(let t):
            rec.lastAPICall = now
            switch await callAPI(token: t) {
            case .ok(let five, let week):
                rec.five = five; rec.week = week
                rec.fetchedAt = now; rec.error = nil
                rec.backoffUntil = nil; rec.backoffSecs = nil
            case .rateLimited(let retry):
                let secs: Double
                if let r = retry, r > 0 { secs = min(r, 6 * 3600) }
                else { secs = min((rec.backoffSecs ?? 450) * 2, 3600) }   // 15 min, then doubling, max 1 h
                rec.backoffSecs = secs
                rec.backoffUntil = now + secs
                rec.error = "Rate limited by Anthropic. Showing the last known numbers."
            case .unauthorized:
                rec.error = "Claude token rejected. Open a Claude Code session on this account to sign in again."
            case .failed(let m):
                rec.error = m
            }
            return rec
        }
    }
}

// MARK: agy

enum AgyFetcher {
    static func fetch(_ a: AgyConfig, prior: AgyRec?) async -> AgyRec {
        var rec = prior ?? AgyRec()
        rec.source = a.home
        rec.lastAttempt = Date().timeIntervalSince1970
        guard let bin = Paths.find("agy") else {
            rec.error = "agy not found. Install it or check your PATH."
            return rec
        }
        var env: [String: String] = [:]
        if let h = a.home, !h.isEmpty { env["HOME"] = Paths.absolute(h) }
        let r = await runProcess(bin, ["-p", "/quota"], env: env, cwd: "/tmp", timeout: 60, mergeStderr: true)
        if let e = r.launchError { rec.error = e; return rec }

        let groups = parse(r.output)
        if groups.gemini != nil || groups.claude != nil {
            rec.gemini = groups.gemini; rec.claude = groups.claude
            rec.fetchedAt = rec.lastAttempt; rec.needsLogin = false; rec.error = nil
            return rec
        }
        let low = r.output.lowercased()
        if ["authentication", "not signed in", "sign in", "not logged in", "log in", "login"].contains(where: low.contains) {
            rec.needsLogin = true; rec.error = nil
        } else if r.timedOut {
            rec.error = "agy /quota timed out"
        } else {
            let tail = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            rec.error = tail.isEmpty ? "agy returned no quota data" : String(tail.suffix(200))
        }
        return rec
    }

    /// Lines look like `Group<TAB>Label<TAB>NN%<TAB>ISO-UTC`, NN = REMAINING percent. Returns used %.
    static func parse(_ text: String) -> (gemini: AgyGroupRec?, claude: AgyGroupRec?) {
        var gemini = AgyGroupRec(), claude = AgyGroupRec()
        var hasG = false, hasC = false
        for line in text.split(whereSeparator: \.isNewline) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 4, let rem = Double(cols[2].replacingOccurrences(of: "%", with: "")) else { continue }
            let group = cols[0].lowercased(), label = cols[1].lowercased()
            let w = WinRec(used: min(max(100 - rem, 0), 100), resets: parseISO(cols[3]))
            let isWeek = label.contains("week")
            guard isWeek || label.contains("five") || label.contains("5") else { continue }
            if group.contains("gemini") {
                hasG = true
                if isWeek { gemini.week = w } else { gemini.five = w }
            } else if group.contains("claude") || group.contains("gpt") {
                hasC = true
                if isWeek { claude.week = w } else { claude.five = w }
            }
        }
        return (hasG ? gemini : nil, hasC ? claude : nil)
    }
}

// MARK: optional quota file (see README "quotaFile")

enum QuotaFile {
    struct Result {
        var ts: Double?
        var claude: [String: ClaudeRec] = [:]
        var agy: [String: AgyRec] = [:]
    }

    static func read(_ path: String) -> Result? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Paths.expand(path))),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out = Result(ts: (json["ts"] as? NSNumber)?.doubleValue)

        func win(_ any: Any?, remaining: Bool) -> WinRec? {
            guard let d = any as? [String: Any] else { return nil }
            let key = remaining ? "remaining" : "pct"
            guard let v = (d[key] as? NSNumber)?.doubleValue else { return nil }
            return WinRec(used: remaining ? 100 - v : v, resets: (d["resets"] as? NSNumber)?.doubleValue)
        }
        func group(_ any: Any?) -> AgyGroupRec? {
            guard let d = any as? [String: Any] else { return nil }
            return AgyGroupRec(week: win(d["week"], remaining: true), five: win(d["five"], remaining: true))
        }
        for (k, v) in (json["claude"] as? [String: Any]) ?? [:] {
            guard let q = v as? [String: Any] else { continue }
            out.claude[k.lowercased()] = ClaudeRec(five: win(q["five_hour"], remaining: false), week: win(q["seven_day"], remaining: false),
                                                   fetchedAt: (q["ts"] as? NSNumber)?.doubleValue ?? out.ts, error: q["error"] as? String)
        }
        for (k, v) in (json["agy"] as? [String: Any]) ?? [:] {
            guard let q = v as? [String: Any] else { continue }
            out.agy[k.lowercased()] = AgyRec(gemini: group(q["gemini"]), claude: group(q["claude"]),
                                             fetchedAt: (q["ts"] as? NSNumber)?.doubleValue ?? out.ts,
                                             needsLogin: (q["needs_login"] as? Bool) ?? false, error: q["error"] as? String)
        }
        return out
    }
}

// MARK: helpers

func parseISO(_ s: String) -> Double? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d.timeIntervalSince1970 }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)?.timeIntervalSince1970
}
