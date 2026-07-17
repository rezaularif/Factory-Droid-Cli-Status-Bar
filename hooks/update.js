#!/usr/bin/env node
// Map a Droid hook event → ~/.factory/statusbar/state.d/<session_id>.json
// Usage: node update.js <prompt|pre|post|notify|permreq|stop>
//
// Writes real session titles + live activity (tool/command/file), not placeholder verbs.

const path = require("path");
const cp = require("child_process");
const {
  readStdin, parsePayload, debug, log, writeAtomic, readJson,
  statePathFor, resolveSessionPid, detectEntrypoint, toolLabel, toolDetail,
  clip, resolveSessionTitle, BUNDLE_ID,
} = require(path.join(__dirname, "lib", "common.js"));

function launchApp() {
  try {
    cp.spawn("open", ["-g", "-b", BUNDLE_ID], { stdio: "ignore", detached: true }).unref();
  } catch (e) {
    log(`[warn] open app failed: ${e.message || e}`);
  }
}

function explicitActivityId(p) {
  const nested = p.tool_use || p.tool_call || p.toolUse || p.toolCall;
  const raw = p.tool_call_id || p.tool_use_id || p.toolCallId || p.toolUseId
    || p.call_id || p.callId || (nested && nested.id) || "";
  return raw ? String(raw) : "";
}

function activityFrom(p, ts) {
  const tool = p.tool_name || "";
  const input = p.tool_input ?? p.toolInput ?? p.input;
  const detail = toolDetail(tool, input);
  return {
    // A fallback id keeps duplicate parallel calls distinct. PostToolUse can
    // still match it by tool/detail when Droid does not provide an id.
    id: explicitActivityId(p) || `${tool}|${detail}|${Date.now()}|${process.pid}`,
    label: detail || toolLabel(tool),
    detail,
    tool,
    startedAt: ts,
    ts,
  };
}

function lastIndexWhere(items, predicate) {
  for (let i = items.length - 1; i >= 0; i--) {
    if (predicate(items[i])) return i;
  }
  return -1;
}

function removeActivity(activities, p) {
  if (!activities.length) return;
  const tool = p.tool_name || "";
  const detail = toolDetail(tool, p.tool_input ?? p.toolInput ?? p.input);
  const id = explicitActivityId(p);
  let index = id ? lastIndexWhere(activities, (a) => a.id === id) : -1;
  if (index < 0 && tool) {
    index = lastIndexWhere(activities, (a) => a.tool === tool &&
      (!detail || a.detail === detail || a.label === detail));
  }
  if (index < 0 && tool) index = lastIndexWhere(activities, (a) => a.tool === tool);
  if (index < 0) index = activities.length - 1;
  activities.splice(index, 1);
}

const event = process.argv[2] || "";

(async () => {
  const raw = await readStdin();
  const p = parsePayload(raw);
  debug(event, p);

  const sid = p.session_id || p.sessionId || "";
  const statePath = statePathFor(sid);
  const prev = readJson(statePath, {}) || {};
  const project = p.cwd ? path.basename(p.cwd) : prev.project || "";
  const cwd = p.cwd || prev.cwd || "";
  const transcript = p.transcript_path || prev.transcript || "";
  const title = resolveSessionTitle(sid, transcript, prev);
  const ts = Math.floor(Date.now() / 1000);
  let state = "idle";
  let label = "";
  let detail = prev.detail || "";
  let prompt = prev.prompt || "";
  let startedAt = prev.startedAt || 0;
  let tool = p.tool_name || "";
  let activities = Array.isArray(prev.activities)
    ? prev.activities.filter((a) => a && typeof a === "object")
    : [];

  switch (event) {
    case "prompt": {
      state = "thinking";
      prompt = clip(p.prompt || p.message || "", 80);
      // Show the user prompt while streaming, not a random verb.
      detail = prompt ? clip(prompt, 48) : "Streaming…";
      label = "Streaming…";
      startedAt = ts;
      tool = "";
      activities = [];
      break;
    }
    case "pre": {
      state = "tool";
      const activity = activityFrom(p, ts);
      const activityId = explicitActivityId(p);
      if (activityId) {
        const existing = activities.findIndex((a) => a.id === activityId);
        if (existing >= 0) activities[existing] = activity;
        else activities.push(activity);
      } else {
        activities.push(activity);
      }
      detail = activity.detail;
      label = activity.label;
      tool = activity.tool;
      if (!startedAt) startedAt = ts;
      break;
    }
    case "post": {
      removeActivity(activities, p);
      const current = activities[activities.length - 1];
      if (current) {
        // Another parallel tool is still active, so remain in tool state and
        // let the menu-bar UI cycle through the remaining activities.
        state = "tool";
        detail = current.detail;
        label = current.label;
        tool = current.tool;
      } else {
        state = "thinking";
        // Model is streaming again after the final tool. Prefer the last
        // concrete tool detail so the bar doesn't jump to a placeholder.
        label = "Streaming…";
        if (prev.detail && prev.state === "tool") {
          detail = prev.detail;
        } else if (prompt) {
          detail = clip(prompt, 48);
        } else {
          detail = "Streaming…";
        }
        tool = p.tool_name || prev.tool || "";
      }
      if (!startedAt) startedAt = ts;
      break;
    }
    case "notify": {
      const m = String(p.message || "").toLowerCase();
      const type = String(p.notification_type || "").toLowerCase();
      const isPerm =
        type === "permission_prompt" ||
        type.includes("permission") ||
        m.includes("permission") ||
        m.includes("awaiting approval") ||
        (m.includes("approve") && m.includes("tool"));
      if (!isPerm) {
        log(`[update] notify ignored (not permission) sid=${sid || "?"} type=${type}`);
        return;
      }
      state = "permission";
      label = "Awaiting permission";
      detail = clip(p.message || "Awaiting permission", 52);
      startedAt = 0;
      break;
    }
    case "permreq":
      state = "permission";
      label = "Awaiting permission";
      detail = toolDetail(p.tool_name, p.tool_input ?? p.toolInput) || "Awaiting permission";
      tool = p.tool_name || prev.tool || "";
      startedAt = 0;
      break;
    case "stop":
      state = "done";
      label = "Done";
      detail = title || "Done";
      tool = "";
      activities = [];
      startedAt = 0;
      break;
    default:
      log(`[warn] unknown event '${event}'`);
      return;
  }

  const resolved = resolveSessionPid(process.ppid);
  let pid = resolved.pid;
  if (!pid && prev.pid && Number(prev.pid) > 0) pid = Number(prev.pid);

  const out = {
    state,
    label,
    detail,
    title,
    prompt,
    tool,
    project,
    cwd,
    sessionId: sid,
    transcript,
    entrypoint: detectEntrypoint(prev),
    term_program: process.env.TERM_PROGRAM || prev.term_program || "",
    pid,
    started: true,
    startedAt,
    ts,
    activities,
  };

  try {
    writeAtomic(statePath, out);
    log(`[update] ${event} sid=${sid || "?"} state=${state} active=${activities.length} title=${clip(title, 40)} detail=${clip(detail, 60)} pid=${pid}`);
    if (state === "thinking" || state === "tool" || state === "permission") {
      launchApp();
    }
  } catch (e) {
    log(`[error] write state failed: ${e.message || e}`);
  }
})().catch((e) => {
  log(`[error] update.js: ${e.message || e}`);
  process.exit(0);
});
