import Foundation

/// Loads per-session JSON from disk, computes effective state, reaps dead sessions.
final class SessionStore {
    private(set) var sessions: [String: Session] = [:]
    private var fileMTimes: [String: Date] = [:]
    var prevState: [String: String] = [:]
    var sessionWord: [String: String] = [:]

    /// Default hide-idle age for menu rows (display only). 0 = never.
    var hideIdleAfter: TimeInterval {
        UserDefaults.standard.object(forKey: "hideIdleAfter") as? Double ?? 900
    }

    func stateFileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: Paths.stateDir)) ?? [])
            .filter { $0.hasSuffix(".json") }
    }

    func sessionCount() -> Int { stateFileNames().count }

    func reload() {
        let fm = FileManager.default
        let files = stateFileNames()
        let present = Set(files)
        for key in Array(fileMTimes.keys) where !present.contains(key) {
            fileMTimes[key] = nil
            sessions[(key as NSString).deletingPathExtension] = nil
        }
        for f in files {
            let full = (Paths.stateDir as NSString).appendingPathComponent(f)
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let m = attrs[.modificationDate] as? Date else { continue }
            if fileMTimes[f] == m { continue }
            fileMTimes[f] = m
            guard let data = fm.contents(atPath: full),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let id = (f as NSString).deletingPathExtension
            var s = Session(json: o, id: id)
            GitBranch.invalidateNonGit(s.cwd)
            s.branch = GitBranch.branch(for: s.cwd)
            sessions[id] = s
        }
    }

    /// Refresh branches (e.g. on menu open after a checkout).
    func refreshBranches() {
        for (id, s) in sessions where !s.cwd.isEmpty {
            GitBranch.invalidateNonGit(s.cwd)
            var u = s
            u.branch = GitBranch.branch(for: u.cwd)
            sessions[id] = u
        }
    }

    static func pidAlive(_ pid: Int32) -> Bool {
        if pid <= 0 { return false }
        // Capture errno immediately; other syscalls can clobber it.
        let rc = kill(pid, 0)
        if rc == 0 { return true }
        return errno == EPERM
    }

    /// Compute effective state: hard/soft timeouts + Droid transcript interrupt markers.
    func effectiveState(_ s: Session, now: Double) -> String {
        let active = s.state == SessionState.thinking
            || s.state == SessionState.tool
            || s.state == SessionState.permission
        if active {
            let hard: Double = s.state == SessionState.permission
                ? Timeouts.hardPermission : Timeouts.hardWorking
            if now - s.ts > hard { return SessionState.idle }
            // Soft timeout for thinking/tool (not permission): Esc often skips Stop.
            if s.state != SessionState.permission, now - s.ts > Timeouts.softIdle {
                return SessionState.idle
            }
            if transcriptLooksInterrupted(s.transcript) {
                return SessionState.idle
            }
            return s.state
        }
        return s.state == SessionState.done ? SessionState.idle : s.state
    }

    /// Droid writes nested messages; interrupt text is often:
    /// `"text":"Request interrupted by user"` / `"Request cancelled by user"`.
    private func transcriptLooksInterrupted(_ path: String) -> Bool {
        guard !path.isEmpty, let chunk = tailText(path, bytes: 12_288) else { return false }
        let lower = chunk.lowercased()
        if lower.contains("request interrupted by user") { return true }
        if lower.contains("request cancelled by user") { return true }
        if lower.contains("interrupted by user") { return true }
        return false
    }

    private func tailText(_ path: String, bytes: UInt64) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        try? fh.seek(toOffset: size > bytes ? size - bytes : 0)
        guard let data = try? fh.readToEnd(), let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    static func priority(of eff: String) -> Int {
        switch eff {
        case SessionState.permission: return 2
        case SessionState.thinking, SessionState.tool: return 1
        default: return 0
        }
    }

    private func isActive(_ s: Session) -> Bool {
        s.eff == SessionState.permission || s.eff == SessionState.thinking || s.eff == SessionState.tool
    }

    /// A delegated Factory worker is a real session, but it should not occupy
    /// a second top-level row while its active parent is already represented.
    /// Matching the working directory is deliberately stricter than matching
    /// only the project name, since the same project name can be open twice.
    private func isSuppressedSubagent(_ s: Session) -> Bool {
        guard s.isSubagent, !s.cwd.isEmpty else { return false }
        return sessions.values.contains { parent in
            parent.id != s.id
                && !parent.isSubagent
                && parent.cwd == s.cwd
                && isActive(parent)
        }
    }

    /// Recompute eff, reap dead pids, fix display names. Returns the lead session if any.
    @discardableResult
    func evaluate(now: Double = Date().timeIntervalSince1970) -> Session? {
        for id in Array(sessions.keys) {
            guard var s = sessions[id] else { continue }
            s.eff = effectiveState(s, now: now)
            // Reap rules:
            //  - pid>0 and dead: only after a short grace so a wrong/ephemeral parent
            //    (or a slow process table update) doesn't delete a just-written thinking state.
            //  - pid==0: age-based only (hooks couldn't resolve droid/Factory).
            let dead: Bool
            if s.pid > 0 {
                let gone = !Self.pidAlive(s.pid)
                let grace: Double = 15 // seconds since last hook write
                dead = gone && (now - s.ts > grace)
            } else {
                let ageLimit = max(hideIdleAfter > 0 ? hideIdleAfter : 3600, 600)
                dead = now - s.ts > ageLimit
            }
            if dead {
                try? FileManager.default.removeItem(
                    atPath: (Paths.stateDir as NSString).appendingPathComponent(id + ".json"))
                sessions[id] = nil
                fileMTimes[id + ".json"] = nil
                prevState[id] = nil
                sessionWord[id] = nil
                continue
            }
            sessions[id] = s
            updateThinkingWord(s)
            prevState[s.id] = s.state
        }
        for id in Array(prevState.keys) where sessions[id] == nil {
            prevState[id] = nil
            sessionWord[id] = nil
        }

        // Disambiguate same project name from different parent folders.
        var cwdsByProject: [String: Set<String>] = [:]
        for s in sessions.values where !s.project.isEmpty && !s.cwd.isEmpty {
            cwdsByProject[s.project, default: []].insert(s.cwd)
        }
        for id in Array(sessions.keys) {
            guard var s = sessions[id] else { continue }
            if !s.cwd.isEmpty, (cwdsByProject[s.project]?.count ?? 0) > 1 {
                let parent = (((s.cwd as NSString).deletingLastPathComponent) as NSString).lastPathComponent
                s.displayName = parent.isEmpty ? s.project : parent + "/" + s.project
            } else {
                s.displayName = s.project
            }
            sessions[id] = s
        }

        let candidates = sessions.values.filter { !isSuppressedSubagent($0) }
        return candidates.max { a, b in
            let pa = Self.priority(of: a.eff), pb = Self.priority(of: b.eff)
            return pa == pb ? a.ts < b.ts : pa < pb
        }
    }

    func updateThinkingWord(_ s: Session) {
        let prev = prevState[s.id] ?? ""
        guard s.state == SessionState.thinking, prev != SessionState.thinking else { return }
        var w = thinkingWords.randomElement() ?? "Thinking"
        if thinkingWords.count > 1 {
            while w == sessionWord[s.id] { w = thinkingWords.randomElement() ?? w }
        }
        sessionWord[s.id] = w
    }

    /// What the model is doing right now (tool / stream / permission) — real text from hooks.
    func activityLabel(_ s: Session, useThinkingWords: Bool) -> String {
        // Prefer concrete detail from the hook (file path, command, prompt snippet).
        if !s.detail.isEmpty {
            // Optional playful words only when detail is a generic streaming placeholder.
            if useThinkingWords, s.state == SessionState.thinking,
               s.detail == "Streaming…" || s.detail.hasPrefix("After "),
               let w = sessionWord[s.id], !w.isEmpty {
                return w + "…"
            }
            return s.detail
        }
        if useThinkingWords, s.state == SessionState.thinking,
           let w = sessionWord[s.id], !w.isEmpty {
            return w + "…"
        }
        if !s.label.isEmpty { return s.label }
        switch s.state {
        case SessionState.tool: return s.tool.isEmpty ? "Using tool" : s.tool
        case SessionState.permission: return "Awaiting permission"
        case SessionState.thinking: return "Streaming…"
        case SessionState.done: return "Done"
        default: return "Idle"
        }
    }

    /// Active tool calls, ordered by the hook arrival order. Parallel Droid
    /// tools are intentionally kept separate so the UI can cycle through them.
    func activityLabels(_ s: Session, useThinkingWords: Bool) -> [String] {
        let live = s.activities.map { $0.text }.filter { !$0.isEmpty }
        if !live.isEmpty { return live }
        let fallback = activityLabel(s, useThinkingWords: useThinkingWords)
        return fallback.isEmpty ? [] : [fallback]
    }

    /// Session display name: Droid title → qualified project folder → project → short id.
    func sessionName(_ s: Session) -> String {
        let t = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty,
           t.lowercased() != "new session",
           t.lowercased() != "start new chat" {
            return t
        }
        if !s.displayName.isEmpty { return s.displayName }
        if !s.project.isEmpty { return s.project }
        if !s.id.isEmpty { return String(s.id.prefix(8)) }
        return "session"
    }

    /// Hard cap so the menu-bar item doesn’t shove neighboring icons.
    /// Full text remains in tooltips / dropdown.
    static let menuBarMaxChars = 18

    private func truncatedBar(_ s: String, max: Int = menuBarMaxChars) -> String {
        guard max > 1, s.count > max else { return s }
        return String(s.prefix(max - 1)) + "…"
    }

    /// Menu-bar text: short activity first; optional short title. Always hard-capped.
    func statusBarText(_ s: Session, useThinkingWords: Bool, activityOverride: String? = nil) -> String {
        let name = sessionName(s)
        let activity = activityOverride ?? activityLabel(s, useThinkingWords: useThinkingWords)
        let working = s.eff == SessionState.thinking
            || s.eff == SessionState.tool
            || s.eff == SessionState.permission
            || s.state == SessionState.thinking
            || s.state == SessionState.tool
            || s.state == SessionState.permission

        if !working {
            return truncatedBar(name)
        }
        if activity.isEmpty { return truncatedBar(name) }
        if name.isEmpty || name == activity { return truncatedBar(activity) }

        // Prefer live activity; only prepend title when both fit under the cap.
        let combined = "\(name) · \(activity)"
        if combined.count <= Self.menuBarMaxChars { return combined }
        if activity.count <= Self.menuBarMaxChars { return truncatedBar(activity) }
        return truncatedBar(activity)
    }

    /// Sessions visible in the dropdown (filters + idle hide).
    func visibleSessions(now: Double) -> [Session] {
        let allOrdered = sessions.values
            .filter { !isSuppressedSubagent($0) }
            .sorted { $0.ts > $1.ts }
        let ordered = allOrdered.filter { s in
            let eff = s.eff.isEmpty ? effectiveState(s, now: now) : s.eff
            let resting = !(eff == SessionState.permission
                || eff == SessionState.thinking
                || eff == SessionState.tool)
            let gated = s.entrypoint == "factory-desktop"
            return !gated || s.started || !resting
        }
        var visible = ordered.filter { s in
            let eff = s.eff.isEmpty ? effectiveState(s, now: now) : s.eff
            let resting = !(eff == SessionState.permission
                || eff == SessionState.thinking
                || eff == SessionState.tool)
            return !(hideIdleAfter > 0 && resting && now - s.ts > hideIdleAfter)
        }
        if visible.isEmpty, let lead = ordered.first { visible = [lead] }
        return visible
    }
}
