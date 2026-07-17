#!/usr/bin/env node
// SessionStart / SessionEnd for Droid.
// Usage: node lifecycle.js <start|end>
//
// SessionStart only records an idle session file — it does NOT keep the menu bar
// open. The app is launched from update.js on real activity (prompt / tool / permission).

const fs = require("fs");
const path = require("path");
const {
  readStdin, parsePayload, log, writeAtomic, readJson, safeId, statePathFor,
  resolveSessionPid, detectEntrypoint, resolveSessionTitle, reapStaleStateFiles,
  ensureDirs,
} = require(path.join(__dirname, "lib", "common.js"));

const event = process.argv[2];

(async () => {
  const raw = await readStdin();
  const j = parsePayload(raw);
  const id = safeId(j.session_id || j.sessionId);
  const cwd = j.cwd || "";
  const statePath = statePathFor(id);
  const resolved = resolveSessionPid(process.ppid);

  if (event === "start") {
    try {
      const n = reapStaleStateFiles({ maxAgeSec: 3600 });
      if (n > 0) log(`[lifecycle] reaped ${n} stale session file(s)`);
    } catch (e) {
      log(`[warn] reap failed: ${e.message || e}`);
    }

    try {
      ensureDirs();
      const prev = readJson(statePath, {}) || {};
      const active = prev.started &&
        (prev.state === "thinking" || prev.state === "tool" || prev.state === "permission");
      const transcript = j.transcript_path || (prev && prev.transcript) || "";
      const title = resolveSessionTitle(j.session_id || j.sessionId || id, transcript, prev);

      if (active) {
        // Race: a prompt/tool already wrote activity — keep it, don't reset to idle.
        const merged = {
          ...prev,
          title: title || prev.title || "",
          cwd: cwd || prev.cwd,
          project: cwd ? path.basename(cwd) : prev.project,
          transcript,
          pid: resolved.pid || prev.pid || 0,
          entrypoint: detectEntrypoint(prev),
          term_program: process.env.TERM_PROGRAM || prev.term_program || "",
          ts: Math.floor(Date.now() / 1000),
        };
        writeAtomic(statePath, merged);
        log(`[lifecycle] start keep-active sid=${id} state=${prev.state} title=${title}`);
      } else {
        // Idle only — do not seed fake "thinking" (that pinned the icon for the whole
        // open session). Real work comes from UserPromptSubmit / PreToolUse.
        const now = Math.floor(Date.now() / 1000);
        writeAtomic(statePath, {
          state: "idle",
          label: "",
          detail: "",
          title: title || "",
          prompt: "",
          tool: "",
          project: cwd ? path.basename(cwd) : "",
          cwd,
          sessionId: j.session_id || j.sessionId || id,
          transcript,
          entrypoint: detectEntrypoint({}),
          term_program: process.env.TERM_PROGRAM || "",
          pid: resolved.pid || 0,
          started: false,
          startedAt: 0,
          ts: now,
          activities: [],
        });
        log(`[lifecycle] start idle sid=${id} title=${title || "-"} pid=${resolved.pid}`);
      }
    } catch (e) {
      log(`[error] SessionStart write failed: ${e.message || e}`);
    }
    // Deliberately do NOT open the menu-bar app here. update.js launches on activity.
  } else if (event === "end") {
    try {
      fs.rmSync(statePath, { force: true });
      log(`[lifecycle] end sid=${id}`);
    } catch (e) {
      log(`[warn] SessionEnd rm failed: ${e.message || e}`);
    }
  } else {
    log(`[warn] lifecycle unknown event '${event}'`);
  }
})().catch((e) => {
  log(`[error] lifecycle.js: ${e.message || e}`);
}).finally(() => process.exit(0));
