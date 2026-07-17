// Shared helpers for Droid Status Bar hooks.
// Loaded via require() from scripts copied into ~/.factory/statusbar/.

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const HOME = os.homedir();
const STATUS_DIR = path.join(HOME, ".factory", "statusbar");
const STATE_DIR = path.join(STATUS_DIR, "state.d");
const LOG_PATH = path.join(STATUS_DIR, "hooks.log");
const SETTINGS_PATH = path.join(HOME, ".factory", "settings.json");
const BUNDLE_ID = "com.local.droidstatusbar";
const APP_EXEC = "DroidStatusBar";
const MARKER = STATUS_DIR;

// Prefer stable symlinks over Homebrew Cellar paths (which break on node upgrades).
const NODE_CANDIDATES = [
  "/opt/homebrew/bin/node",
  "/usr/local/bin/node",
  "/usr/bin/node",
  path.join(HOME, ".volta", "bin", "node"),
  path.join(HOME, ".asdf", "shims", "node"),
];

const TOOL_LABELS = {
  Execute: "Running command",
  Bash: "Running command",
  Shell: "Running command",
  Edit: "Editing",
  MultiEdit: "Editing",
  ApplyPatch: "Editing",
  Create: "Writing",
  Write: "Writing",
  NotebookEdit: "Editing",
  Read: "Reading",
  LS: "Listing",
  Grep: "Searching",
  Glob: "Searching",
  ToolSearch: "Searching",
  WebSearch: "Searching web",
  FetchUrl: "Browsing web",
  WebFetch: "Browsing web",
  TodoWrite: "Planning",
  Task: "Delegating",
  Skill: "Using skill",
  AskUser: "Asking you",
  ExitSpecMode: "Exiting spec",
  getIdeDiagnostics: "Checking diagnostics",
  GenerateDroid: "Generating droid",
  StartMissionRun: "Starting mission",
  EndFeatureRun: "Wrapping up",
  DismissHandoffItems: "Dismissing handoff",
};

function ensureDirs() {
  fs.mkdirSync(STATE_DIR, { recursive: true });
}

function log(msg) {
  try {
    ensureDirs();
    fs.appendFileSync(LOG_PATH, `${new Date().toISOString()} ${msg}\n`);
  } catch {}
}

function debug(event, payload) {
  if (process.env.DROID_STATUSBAR_DEBUG !== "1") return;
  const tool = payload.tool_name || "-";
  const mode = payload.permission_mode || "-";
  const msg = JSON.stringify(payload.message || "").slice(0, 160);
  log(`[debug] [${event}] tool=${tool} mode=${mode} msg=${msg} keys=${Object.keys(payload).join(",")}`);
}

function safeId(s) {
  return String(s || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64) || "unknown";
}

function writeAtomic(file, obj) {
  ensureDirs();
  const tmp = `${file}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(obj), { mode: 0o600 });
  fs.renameSync(tmp, file);
  try { fs.chmodSync(file, 0o600); } catch {}
}

function readJson(file, fallback = null) {
  try {
    const value = JSON.parse(fs.readFileSync(file, "utf8"));
    // A truncated/empty state file can legitimately contain JSON `null` while
    // another hook is replacing it. Treat that the same as an unreadable file
    // so callers never dereference a null session object.
    return value == null ? fallback : value;
  } catch {
    return fallback;
  }
}

function readStdin(timeoutMs = 1000) {
  return new Promise((resolve) => {
    let raw = "";
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      resolve(raw);
    };
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (d) => { raw += d; });
    process.stdin.on("end", finish);
    process.stdin.on("error", finish);
    setTimeout(finish, timeoutMs);
  });
}

function parsePayload(raw) {
  try {
    return JSON.parse(raw || "{}");
  } catch (e) {
    log(`[warn] bad JSON stdin: ${String(e.message || e).slice(0, 120)}`);
    return {};
  }
}

function processComm(pid) {
  if (!pid || pid <= 1) return "";
  try {
    return cp.execFileSync("ps", ["-p", String(pid), "-o", "comm="], {
      encoding: "utf8",
      timeout: 500,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

function processPpid(pid) {
  if (!pid || pid <= 1) return 0;
  try {
    const out = cp.execFileSync("ps", ["-p", String(pid), "-o", "ppid="], {
      encoding: "utf8",
      timeout: 500,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return parseInt(out, 10) || 0;
  } catch {
    return 0;
  }
}

function pidAlive(pid) {
  if (!pid || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    // EPERM means the process exists but we can't signal it — treat as alive.
    return e && e.code === "EPERM";
  }
}

function isAgentProcessName(name) {
  if (!name) return false;
  // macOS `ps -o comm=` often returns a full path or "-/bin/zsh".
  const base = path.basename(name.replace(/^-/, "")).toLowerCase();
  if (base === "droid") return true;
  if (base === "factory" || base === "factory-desktop") return true;
  if (base.includes("factory-desktop")) return true;
  // Some builds report the helper under Electron's name.
  if (name.toLowerCase().includes("factory.app")) return true;
  return false;
}

// Walk parents until we find droid / Factory. Return 0 if unknown —
// NEVER fall back to a short-lived shell (sh/zsh) or the app will reap the
// session ~400ms later when that shell exits and the icon never animates.
function resolveSessionPid(startPid) {
  let pid = startPid > 0 ? startPid : process.ppid;
  const chain = [];
  const seen = new Set();
  for (let i = 0; i < 12 && pid > 1 && !seen.has(pid); i++) {
    seen.add(pid);
    const name = processComm(pid);
    chain.push(`${pid}:${path.basename((name || "?").replace(/^-/, ""))}`);
    if (isAgentProcessName(name)) {
      return { pid, chain };
    }
    pid = processPpid(pid);
  }
  return { pid: 0, chain };
}

function resolveSessionPidNumber(startPid) {
  return resolveSessionPid(startPid).pid;
}

function detectEntrypoint(prev = {}) {
  if (process.env.FACTORY_DESKTOP === "1" || process.env.DROID_SURFACE === "desktop") {
    return "factory-desktop";
  }
  // Terminal-launched sessions almost always set TERM_PROGRAM.
  if (process.env.TERM_PROGRAM) return "cli";

  let pid = process.ppid;
  const seen = new Set();
  for (let i = 0; i < 12 && pid > 1 && !seen.has(pid); i++) {
    seen.add(pid);
    const name = processComm(pid);
    if (isAgentProcessName(name)) {
      const base = path.basename((name || "").replace(/^-/, "")).toLowerCase();
      if (base === "droid") return "cli";
      return "factory-desktop";
    }
    pid = processPpid(pid);
  }

  if (prev.entrypoint) return prev.entrypoint;
  return "cli";
}

function toolLabel(toolName) {
  const t = toolName || "";
  if (!t) return "Using tool";
  if (t.includes("___") || t.startsWith("mcp__") || t.startsWith("mcp_")) {
    const server = t.split(/___|__/)[0].replace(/^mcp_?/i, "") || "MCP";
    return `Using ${server}`;
  }
  if (TOOL_LABELS[t]) return TOOL_LABELS[t];
  return "Using tool";
}

function clip(s, n = 48) {
  const t = String(s || "").replace(/\s+/g, " ").trim();
  if (!t) return "";
  return t.length > n ? t.slice(0, n - 1) + "…" : t;
}

function isGenericTitle(t) {
  const s = String(t || "").trim().toLowerCase();
  return !s || s === "new session" || s === "start new chat" || s === "list" || s === "hi" || s === "untitled";
}

/** Live activity text from a tool call (file, command, summary, …). */
function toolDetail(toolName, toolInput) {
  let input = toolInput;
  if (typeof input === "string") {
    try { input = JSON.parse(input); } catch { input = null; }
  }
  const base = toolLabel(toolName);
  if (!input || typeof input !== "object") return base;

  // Droid Execute often includes a human `summary`.
  if (input.summary) return clip(input.summary, 52);
  if (input.command) return clip(`Run ${input.command}`, 52);

  const file = input.file_path || input.path || input.filePath || input.target_file;
  if (file) {
    const name = path.basename(String(file));
    if (/edit|write|create|patch|multi/i.test(toolName || "")) return clip(`Editing ${name}`, 52);
    if (/read/i.test(toolName || "")) return clip(`Reading ${name}`, 52);
    return clip(`${base} ${name}`, 52);
  }

  const dir = input.directory_path || input.dir || input.cwd;
  if (dir) return clip(`Listing ${path.basename(String(dir)) || dir}`, 52);

  const q = input.pattern || input.regex || input.query || input.search || input.glob;
  if (q) return clip(`Search ${q}`, 52);

  if (input.url) return clip(`Fetch ${input.url}`, 52);
  if (Array.isArray(input.todos)) return "Planning";
  if (input.description) return clip(input.description, 52);

  return base;
}

/**
 * Resolve Droid's real session title from:
 *  1. previous state
 *  2. ~/.factory/sessions-index.json
 *  3. session_start line in the transcript jsonl
 */
function resolveSessionTitle(sessionId, transcriptPath, prev = {}) {
  prev = prev && typeof prev === "object" ? prev : {};
  if (prev.title && !isGenericTitle(prev.title)) return prev.title;

  const sid = String(sessionId || prev.sessionId || "");
  // sessions-index.json: { version, entries: [{ sessionId, title, ... }] }
  try {
    const indexPath = path.join(HOME, ".factory", "sessions-index.json");
    const idx = readJson(indexPath, null);
    const entries = (idx && idx.entries) || (Array.isArray(idx) ? idx : null);
    if (Array.isArray(entries) && sid) {
      const hit = entries.find((e) => e && (e.sessionId === sid || e.id === sid));
      if (hit && hit.title && !isGenericTitle(hit.title)) return String(hit.title);
      // Index may lag; still use generic title if that's all we have later.
      if (hit && hit.title) return String(hit.title);
    }
  } catch {}

  // Transcript: first session_start record has title.
  const tpath = transcriptPath || prev.transcript || "";
  if (tpath) {
    try {
      const fh = fs.openSync(tpath, "r");
      const buf = Buffer.alloc(Math.min(8192, fs.fstatSync(fh).size || 0));
      const n = fs.readSync(fh, buf, 0, buf.length, 0);
      fs.closeSync(fh);
      const text = buf.slice(0, n).toString("utf8");
      for (const line of text.split("\n")) {
        if (!line.includes("session_start") && !line.includes('"title"')) continue;
        try {
          const j = JSON.parse(line);
          if (j.type === "session_start" && j.title) return String(j.title);
          if (j.title && j.type !== "message") return String(j.title);
        } catch {}
      }
    } catch {}
  }

  if (prev.title) return prev.title;
  return "";
}

function locateNode() {
  for (const p of NODE_CANDIDATES) {
    try {
      if (fs.existsSync(p) && fs.statSync(p).isFile()) {
        // Resolve symlinks so we still get a real binary, but prefer the stable path string.
        return p;
      }
    } catch {}
  }
  // Avoid embedding a Cellar version path when possible.
  const exec = process.execPath;
  if (exec.includes("/Cellar/node/")) {
    const brew = "/opt/homebrew/bin/node";
    if (fs.existsSync(brew)) return brew;
    const intel = "/usr/local/bin/node";
    if (fs.existsSync(intel)) return intel;
  }
  return exec;
}

function appRunning() {
  try {
    cp.execFileSync("pgrep", ["-x", APP_EXEC], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

// Remove only dead or ancient session files — never a blind wipe of the whole directory.
function reapStaleStateFiles({ maxAgeSec = 3600 } = {}) {
  ensureDirs();
  const now = Math.floor(Date.now() / 1000);
  let removed = 0;
  for (const f of fs.readdirSync(STATE_DIR)) {
    if (!f.endsWith(".json")) continue;
    const full = path.join(STATE_DIR, f);
    try {
      const s = readJson(full, null);
      if (!s) {
        fs.rmSync(full, { force: true });
        removed++;
        continue;
      }
      const pid = Number(s.pid) || 0;
      const ts = Number(s.ts) || 0;
      const dead = pid > 0 ? !pidAlive(pid) : ts > 0 && now - ts > maxAgeSec;
      if (dead) {
        fs.rmSync(full, { force: true });
        removed++;
      }
    } catch {
      try { fs.rmSync(full, { force: true }); removed++; } catch {}
    }
  }
  return removed;
}

function statePathFor(sessionId) {
  return path.join(STATE_DIR, `${safeId(sessionId)}.json`);
}

function shellQuote(s) {
  // Safe for embedding absolute paths in settings.json command strings.
  return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

module.exports = {
  HOME,
  STATUS_DIR,
  STATE_DIR,
  LOG_PATH,
  SETTINGS_PATH,
  BUNDLE_ID,
  APP_EXEC,
  MARKER,
  TOOL_LABELS,
  ensureDirs,
  log,
  debug,
  safeId,
  writeAtomic,
  readJson,
  readStdin,
  parsePayload,
  processComm,
  pidAlive,
  resolveSessionPid,
  resolveSessionPidNumber,
  isAgentProcessName,
  detectEntrypoint,
  toolLabel,
  toolDetail,
  clip,
  isGenericTitle,
  resolveSessionTitle,
  locateNode,
  appRunning,
  reapStaleStateFiles,
  statePathFor,
  shellQuote,
};
