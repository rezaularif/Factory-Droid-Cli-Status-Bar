#!/usr/bin/env node
// Remove only our status-bar hooks from ~/.factory/settings.json.

const fs = require("fs");
const path = require("path");
const cp = require("child_process");
const { SETTINGS_PATH, MARKER, APP_EXEC, log } = require(path.join(__dirname, "lib", "common.js"));

try { cp.execFileSync("pkill", ["-x", APP_EXEC], { stdio: "ignore" }); } catch {}

if (!fs.existsSync(SETTINGS_PATH)) {
  console.log("No settings.json; nothing to do.");
  process.exit(0);
}

const settings = JSON.parse(fs.readFileSync(SETTINGS_PATH, "utf8"));
for (const evt of Object.keys(settings.hooks || {})) {
  settings.hooks[evt] = (settings.hooks[evt] || [])
    .map((e) => ({
      ...e,
      hooks: (e.hooks || []).filter((h) => !(h.command || "").includes(MARKER)),
    }))
    .filter((e) => (e.hooks || []).length > 0);
  if (settings.hooks[evt].length === 0) delete settings.hooks[evt];
}
fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2) + "\n");
console.log("Removed Droid status-bar hooks from", SETTINGS_PATH);
log("[uninstall] hooks removed");
