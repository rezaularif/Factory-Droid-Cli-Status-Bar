#!/usr/bin/env node
// Merge status-bar hooks into ~/.factory/settings.json (never clobber other hooks).
// Copies scripts to ~/.factory/statusbar/ and pins a stable node path.

const fs = require("fs");
const path = require("path");
const {
  STATUS_DIR, SETTINGS_PATH, MARKER, locateNode, shellQuote, log, ensureDirs,
} = require(path.join(__dirname, "lib", "common.js"));

const updateDest = path.join(STATUS_DIR, "update.js");
const lifecycleDest = path.join(STATUS_DIR, "lifecycle.js");
const libDest = path.join(STATUS_DIR, "lib");

function copyTree() {
  ensureDirs();
  fs.mkdirSync(libDest, { recursive: true });
  fs.copyFileSync(path.join(__dirname, "update.js"), updateDest);
  fs.copyFileSync(path.join(__dirname, "lifecycle.js"), lifecycleDest);
  fs.copyFileSync(path.join(__dirname, "lib", "common.js"), path.join(libDest, "common.js"));
  for (const f of [updateDest, lifecycleDest, path.join(libDest, "common.js")]) {
    try { fs.chmodSync(f, 0o755); } catch {}
  }
}

function stripOurs(arr) {
  return (arr || [])
    .map((entry) => ({
      ...entry,
      hooks: (entry.hooks || []).filter((h) => !(h.command || "").includes(MARKER)),
    }))
    .filter((entry) => (entry.hooks || []).length > 0);
}

function main() {
  copyTree();
  const node = locateNode();
  const cmd = (script, evt) => `${shellQuote(node)} ${shellQuote(script)} ${evt}`;

  let settings = {};
  if (fs.existsSync(SETTINGS_PATH)) {
    settings = JSON.parse(fs.readFileSync(SETTINGS_PATH, "utf8"));
    const bak = SETTINGS_PATH + ".bak-statusbar";
    if (!fs.existsSync(bak)) fs.copyFileSync(SETTINGS_PATH, bak);
  }
  settings.hooks = settings.hooks || {};

  // Prepend our hooks so we run before other tools (e.g. Orca) and always see stdin.
  const add = (evt, command, matched = false) => {
    settings.hooks[evt] = stripOurs(settings.hooks[evt]);
    const entry = { hooks: [{ type: "command", command, timeout: 10 }] };
    if (matched) entry.matcher = "*";
    settings.hooks[evt] = [entry, ...(settings.hooks[evt] || [])];
  };

  add("UserPromptSubmit", cmd(updateDest, "prompt"));
  add("PreToolUse", cmd(updateDest, "pre"), true);
  add("PostToolUse", cmd(updateDest, "post"), true);
  add("Notification", cmd(updateDest, "notify"));
  // PermissionRequest is ignored by some Droid versions ("unknown hook event keys") —
  // keep it for versions that support it; harmless when ignored.
  add("PermissionRequest", cmd(updateDest, "permreq"), true);
  add("Stop", cmd(updateDest, "stop"));
  add("SubagentStop", cmd(updateDest, "stop"));
  add("SessionStart", cmd(lifecycleDest, "start"));
  add("SessionEnd", cmd(lifecycleDest, "end"));

  fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2) + "\n");
  console.log("Installed Droid status-bar hooks into", SETTINGS_PATH);
  console.log("Node:", node);
  console.log("Scripts:", updateDest, "and", lifecycleDest);
  log(`[install] hooks installed node=${node}`);
}

try {
  main();
} catch (e) {
  console.error("Install failed:", e.message || e);
  try { log(`[error] install: ${e.message || e}`); } catch {}
  process.exit(1);
}
