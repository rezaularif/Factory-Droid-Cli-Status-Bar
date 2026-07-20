# Changelog

## 0.4.1

- Added the selected animated Droid indicator to a compact right-side notch ear while work is active.
- Faded the indicator seamlessly into the expanded task view on hover.
- Kept the physical camera-housing position unchanged so the cue reads as part of the notch.

## 0.4.0

- Redesigned the expanded notch as a structured two-line live activity with task title, current action, and optional elapsed time.
- Added brief automatic peeks for new tasks and longer amber approval alerts.
- Added a short hover-exit grace period to prevent edge flicker.
- Kept long activity details readable with an overflow-only marquee while task titles remain stable.

## 0.3.1

- Matched the resting overlay exactly to the detected camera-housing width and depth.
- Added a compact hover expansion with smooth, looping marquee text for long tasks.
- Replaced the notch spinner with a calmer activity pulse in the expanded view.
- Made left-click open the active Factory or terminal task; right-click opens options.

## 0.3.0

- Added a notch-native activity surface that grows from the MacBook camera housing.
- Moved live activity, animations, timers, and permission feedback out of the menu bar on notched Macs.
- Kept the sessions and options menu accessible by clicking the notch surface.
- Added automatic menu-bar fallback for Macs and displays without a usable notch.

## 0.2.7

- Replaced the old Claude-derived app icon with a Droid orange three-dot loader icon.
- Updated the README hero graphic to use the new Droid visual identity.

## 0.2.6

- Added live parallel-tool activity tracking with automatic cycling in the menu bar.
- Improved status text, session freshness, permission labels, and activity details.
- Collapsed Factory parent sessions and delegated Explorer workers into one top-level session row.
- Fixed lifecycle handling for null/empty state and stale session records.

## 0.2.4

- Default **three-dot** loader (#ef6f2e); menu-bar text hard-capped
- **Removed Claude-port animation assets**: SparkFrames, LogoFrame (Claude spark), CrabFrames/CrabRender
- Animation menu is Droid-only: Three dots, Braille, Dots 10, Block, Breathe, Orbit, Droid Logo

## 0.2.3

Real session activity (not placeholders):

- Resolve Droid session **title** from `sessions-index.json` / transcript `session_start`
- Live **detail** from tools: file paths, commands, Execute `summary`, search queries
- Menu bar text: `Session title · Reading README.md` while working
- Dropdown session rows use the real title
- “Playful words” off by default (optional toggle)

## 0.2.2

Droid CLI animations:

- Extracted spinner catalog from the `droid` binary (`dots`, `dots10`, `dots2`, `breathe`, `orbit`, …)
- Extracted 44-frame FullScreenAnimation logo (`Rai`) as `assets/droid-logo-frames.json`
- Menu **Animation** styles: Dots (CLI default), Dots 10 (stream), Block, Breathe, Orbit, Droid Logo, Spark, Crab
- Default style is now **Dots (CLI)** — the same braille spinner family as Droid TUI

## 0.2.1

- Fix zombie menu bar item (controller retain)
- Quit when idle; relaunch on prompt

## 0.2.0

Rewrite / reliability pass:

- Shared hook library (`hooks/lib/common.js`)
- macOS parent-walk for session PID + Factory vs CLI entrypoint
- Stable Node path (prefer brew symlink over Cellar)
- Safer SessionStart cleanup (reap dead only, no full wipe)
- Soft idle timeout (3m) + Droid interrupt transcript markers
- `SubagentStop` wired; better MCP tool labels
- Structured always-on error log (`hooks.log`)
- Swift split: Models, SessionStore, GitBranch, MenuViews, StatusController
- Removed dead GitHub update-check
- Hook unit tests (`node hooks/test.js`)

## 0.1.0

Initial Droid port from claude-status-bar.
