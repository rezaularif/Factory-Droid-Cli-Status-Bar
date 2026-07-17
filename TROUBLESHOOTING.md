# Troubleshooting

## Icon never appears

```bash
rg statusbar ~/.factory/settings.json
node ~/droid-status-bar/hooks/install.js
# start a *new* droid session
```

Confirm Node is a stable path (not a deleted Cellar version):

```bash
rg 'node ' ~/.factory/settings.json | head
```

## Frozen spinner / amber dot

Esc often skips `Stop`. The app now soft-idles after **3 minutes** without hook activity, and detects Droid transcript lines like `Request interrupted by user`.

```bash
tail -f ~/.factory/statusbar/hooks.log
```

## Orca hooks

Install only strips commands containing `~/.factory/statusbar`. Orca entries stay.

## Build

```bash
xcode-select --install
cd ~/droid-status-bar && ./build.sh
```
