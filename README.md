<div align="center">
  <img src="assets/AppIcon.png" width="128" alt="Droid orange three-dot loader icon" />
  <h1>Droid Notch</h1>
  <p><strong>See what Droid is doing in your MacBook notch.</strong><br />A calm, glanceable activity surface for Factory and Droid CLI on macOS.</p>
  <p>
    <a href="https://github.com/rezaularif/Factory-Droid-Cli-Status-Bar/releases/latest"><img src="assets/download.png" width="230" alt="Download for macOS" /></a>
  </p>
  <p>
    <img src="https://img.shields.io/github/v/release/rezaularif/Factory-Droid-Cli-Status-Bar?label=latest%20release&color=ef6f2e" alt="Latest release" />
    <img src="https://img.shields.io/badge/macOS-12%2B-111111?logo=apple&logoColor=white" alt="macOS 12 or later" />
    <img src="https://img.shields.io/github/license/rezaularif/Factory-Droid-Cli-Status-Bar?color=111111" alt="MIT license" />
  </p>
</div>

The app icon uses the same Droid orange three-dot loader as the default activity animation.

## See it in action

<p align="center">
  <img src="assets/droid-status-bar-demo.gif" alt="Droid activity feedback on macOS" />
</p>

On a MacBook with a camera notch, Droid rests against the camera housing with the selected Droid animation in a small right-side ear. The cue shows that a task is active and invites you to hover; it then fades into the expanded task view. New work briefly peeks out, approval requests stay visible longer in amber, and hovering reveals the task title plus its current action. Long activity details scroll automatically. Macs without a notch use the original menu-bar indicator.

## At a glance

| You see | What it means |
| --- | --- |
| 🟠 Notch animation | Droid is actively thinking or using a tool |
| 📝 Live activity | The current action, such as reading a file or running tests |
| ⏱ Elapsed time | How long the current task has been running |
| 🟡 Permission prompt | Droid is waiting for you to approve something |
| 👥 One calm task row | Factory workers are grouped under their main task |

## How it works

```mermaid
flowchart LR
    A["You ask Factory to do something"] --> B["Droid works in the background"]
    B --> C["Droid Notch watches the session"]
    C --> D["The notch shows progress, tools, time, and permissions"]
```

Nothing new to learn: keep working in Factory as usual, and hover over the notch whenever you want reassurance that the task is moving. Click to open the running Factory or terminal task; right-click for sessions and options.

## Install in about 30 seconds

1. Click the **Download for macOS** button above, or download `DroidStatusBar.dmg` from the [latest release](https://github.com/rezaularif/Factory-Droid-Cli-Status-Bar/releases/latest).
2. Open the download and drag the **DroidStatusBar** app into your **Applications** folder.
3. Open the app once. It installs the Factory connection automatically.

On first launch, macOS may show an unidentified-developer warning because public notarization is not configured yet. Control-click the app, choose **Open**, and confirm once.

<details>
<summary>Technical architecture</summary>

```
hooks/
  lib/common.js     shared helpers (pid, entrypoint, labels, logging)
  update.js         prompt / tool / permission / stop → state files
  lifecycle.js      session start/end → launch app / cleanup
  install.js        merge hooks into ~/.factory/settings.json
  uninstall.js
  test.js           unit tests for helpers
Sources/
  main.swift            entrypoint
  Models.swift          Session, paths, timeouts
  SessionStore.swift    load / evaluate / reap sessions
  GitBranch.swift       branch from .git/HEAD
  MenuViews.swift       toggle + session row
  NotchOverlay.swift    notch detection + top-center activity surface
  StatusController.swift menu bar UI + icons
  *Frames.swift         animation assets (unchanged)
```

### Build from source

```bash
cd ~/droid-status-bar
./build.sh
cp -R build/DroidStatusBar.app /Applications/
open /Applications/DroidStatusBar.app   # installs hooks on first launch
```

Or hooks only:

```bash
node hooks/install.js
```

</details>

## Debug

```bash
DROID_STATUSBAR_DEBUG=1 droid
tail -f ~/.factory/statusbar/hooks.log
ls ~/.factory/statusbar/state.d/
node hooks/test.js
```

## Uninstall

```bash
node hooks/uninstall.js
# or
node /Applications/DroidStatusBar.app/Contents/Resources/uninstall.js
```

## Requirements

- macOS 12+
- A notched MacBook for the notch surface (other Macs use the menu-bar fallback)
- Droid / Factory CLI
- Node.js (stable path preferred: `/opt/homebrew/bin/node`)

## License

MIT — adapted from [claude-status-bar](https://github.com/m1ckc3s/claude-status-bar). Not affiliated with Factory or Anthropic.
