import Cocoa

enum Paths {
    static var statusDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".factory/statusbar")
    }
    static var stateDir: String {
        (statusDir as NSString).appendingPathComponent("state.d")
    }
    static var uiConfig: String {
        (statusDir as NSString).appendingPathComponent("uiconfig.json")
    }
}

enum SessionState {
    static let permission = "permission"
    static let thinking = "thinking"
    static let tool = "tool"
    static let idle = "idle"
    static let done = "done"
}

struct LiveActivity {
    var id: String
    var label: String
    var detail: String
    var tool: String
    var startedAt: Double
    var ts: Double

    init(json o: [String: Any]) {
        self.id = o["id"] as? String ?? ""
        self.label = o["label"] as? String ?? ""
        self.detail = o["detail"] as? String ?? ""
        self.tool = o["tool"] as? String ?? ""
        self.startedAt = (o["startedAt"] as? NSNumber)?.doubleValue ?? 0
        self.ts = (o["ts"] as? NSNumber)?.doubleValue ?? 0
    }

    var text: String {
        if !detail.isEmpty { return detail }
        if !label.isEmpty { return label }
        if !tool.isEmpty { return tool }
        return "Using tool"
    }
}

struct Session {
    var id: String
    var state: String
    var label: String
    /// Live activity: "Editing README.md", "Run git status", user prompt snippet, …
    var detail: String
    /// Real Droid session title from session_start / sessions-index.
    var title: String
    /// Original user/delegation prompt, when supplied by the lifecycle hook.
    var prompt: String
    var tool: String
    var project: String
    var transcript: String
    var cwd: String
    var entrypoint: String   // "cli" | "factory-desktop"
    var termProgram: String
    var pid: Int32
    var started: Bool
    var startedAt: Double
    var ts: Double
    var activities: [LiveActivity]
    var eff: String = ""
    var branch: String = ""
    var displayName: String = ""

    init(json o: [String: Any], id: String) {
        self.id = id
        self.state = o["state"] as? String ?? SessionState.idle
        self.label = o["label"] as? String ?? ""
        self.detail = o["detail"] as? String ?? ""
        self.title = o["title"] as? String ?? ""
        self.prompt = o["prompt"] as? String ?? ""
        self.tool = o["tool"] as? String ?? ""
        self.project = o["project"] as? String ?? ""
        self.transcript = o["transcript"] as? String ?? ""
        self.cwd = o["cwd"] as? String ?? ""
        self.entrypoint = o["entrypoint"] as? String ?? ""
        self.termProgram = o["term_program"] as? String ?? ""
        self.pid = Int32(truncatingIfNeeded: (o["pid"] as? NSNumber)?.intValue ?? 0)
        self.started = o["started"] as? Bool ?? false
        self.startedAt = (o["startedAt"] as? NSNumber)?.doubleValue ?? 0
        self.ts = (o["ts"] as? NSNumber)?.doubleValue ?? 0
        self.activities = (o["activities"] as? [[String: Any]] ?? []).map(LiveActivity.init)
    }

    var isWorking: Bool {
        eff == SessionState.thinking || eff == SessionState.tool
            || state == SessionState.thinking || state == SessionState.tool
    }

    /// Factory uses a separate Droid process for delegated work. Its prompt is
    /// marked explicitly, so the status bar can present it as part of the
    /// parent task instead of making one user task look duplicated.
    var isSubagent: Bool {
        let p = promptText.lowercased()
        return p.hasPrefix("# task tool invocation") || p.contains("subagent type:")
    }

    private var promptText: String {
        // The prompt is stored in `detail` by older hook payloads and in the
        // session title/label by some Factory versions. Keep this check local
        // to the model so filtering remains consistent across the UI.
        if !prompt.isEmpty { return prompt }
        if !detail.isEmpty { return detail }
        if !label.isEmpty { return label }
        return title
    }
}

enum Brand {
    static let accent = NSColor(srgbRed: 0xEF / 255.0, green: 0x6F / 255.0, blue: 0x2E / 255.0, alpha: 1) // #ef6f2e Droid orange
    static let amber = NSColor(srgbRed: 0.95, green: 0.73, blue: 0.18, alpha: 1)
    static let factoryBundleID = "com.electron.factory"
}

/// Soft / hard timeouts for stuck states (seconds since last hook write).
enum Timeouts {
    /// Soft: no hook activity → treat as idle for display (Esc often fires no Stop).
    static let softIdle: Double = 180
    /// Hard: force idle even if still "working".
    static let hardWorking: Double = 900
    /// Permission prompts can sit longer.
    static let hardPermission: Double = 7200
    static let launchGrace: TimeInterval = 2   // only while a turn is active
    static let idleQuit: TimeInterval = 1.2    // debounce before exit when idle
}

let thinkingWords: [String] = [
    "Accomplishing", "Actioning", "Actualizing", "Architecting", "Baking", "Beaming",
    "Bootstrapping", "Brewing", "Calculating", "Cascading", "Churning", "Droiding",
    "Coalescing", "Composing", "Computing", "Considering", "Contemplating", "Cooking",
    "Crafting", "Creating", "Crunching", "Cultivating", "Deliberating", "Doing",
    "Forging", "Generating", "Gitifying", "Harmonizing", "Hatching", "Ideating",
    "Imagining", "Inferring", "Manifesting", "Marinating", "Mulling", "Musing",
    "Noodling", "Orchestrating", "Percolating", "Pondering", "Processing", "Puzzling",
    "Reticulating", "Ruminating", "Simmering", "Sketching", "Spinning", "Synthesizing",
    "Thinking", "Tinkering", "Vibing", "Working", "Wrangling",
]
