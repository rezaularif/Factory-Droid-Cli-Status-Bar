#!/usr/bin/env node
// Minimal unit tests for hook helpers. Run: node hooks/test.js

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { toolLabel, toolDetail, resolveSessionTitle, safeId, shellQuote, locateNode, clip } = require("./lib/common.js");

let failed = 0;
function test(name, fn) {
  try {
    fn();
    console.log("  ok ", name);
  } catch (e) {
    failed++;
    console.error("  FAIL", name, e.message);
  }
}

console.log("toolLabel");
test("Execute", () => assert.strictEqual(toolLabel("Execute"), "Running command"));
test("Edit", () => assert.strictEqual(toolLabel("Edit"), "Editing"));
test("MCP triple", () => assert.strictEqual(toolLabel("Paper___write_html"), "Using Paper"));
test("unknown", () => assert.strictEqual(toolLabel("SomethingWeird"), "Using tool"));

console.log("toolDetail");
test("Execute summary", () => assert.strictEqual(
  toolDetail("Execute", { summary: "Check git status", command: "git status" }),
  "Check git status"));
test("Read file", () => assert.ok(toolDetail("Read", { file_path: "/Users/a/README.md" }).includes("README.md")));
test("Edit file", () => assert.ok(toolDetail("Edit", { file_path: "/tmp/x.swift" }).includes("Editing")));
test("clip", () => assert.strictEqual(clip("abcdefghij", 6), "abcde…"));
test("null previous state is safe", () => assert.strictEqual(
  resolveSessionTitle("missing-session", "", null), ""));

console.log("safeId");
test("strips bad chars", () => assert.strictEqual(safeId("../a b!"), "..ab"));
test("empty → unknown", () => assert.strictEqual(safeId(""), "unknown"));

console.log("shellQuote");
test("quotes path", () => assert.strictEqual(shellQuote("/opt/homebrew/bin/node"), "'/opt/homebrew/bin/node'"));
test("escapes single quote", () => assert.ok(shellQuote("a'b").includes("\\'")));

console.log("locateNode");
test("returns a path", () => {
  const n = locateNode();
  assert.ok(n && n.length > 0);
  assert.ok(!n.includes("/Cellar/node/") || fs.existsSync(n), "node path should exist or be non-cellar");
});

// install merge: strip marker, keep other hooks
console.log("install merge logic");
test("stripOurs keeps orca", () => {
  const MARKER = path.join(os.homedir(), ".factory", "statusbar");
  const stripOurs = (arr) =>
    (arr || [])
      .map((entry) => ({
        ...entry,
        hooks: (entry.hooks || []).filter((h) => !(h.command || "").includes(MARKER)),
      }))
      .filter((entry) => (entry.hooks || []).length > 0);

  const input = [
    { hooks: [{ type: "command", command: "if [ -x '/Users/x/.orca/agent-hooks/droid-hook.sh' ]; then sh; fi" }] },
    { hooks: [{ type: "command", command: `node ${MARKER}/update.js prompt` }] },
  ];
  const out = stripOurs(input);
  assert.strictEqual(out.length, 1);
  assert.ok(out[0].hooks[0].command.includes("orca"));
});

if (failed) {
  console.error(`\n${failed} failed`);
  process.exit(1);
}
console.log("\nall passed");
