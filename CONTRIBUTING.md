# Contributing

## Build

```bash
./build.sh
```

## Tests

```bash
node hooks/test.js
```

## Structure

Keep it small: hooks own I/O and state files; Swift owns display. Prefer fixing `hooks/lib/common.js` for PID/entrypoint/tool labels before touching the app.

Animation assets in `*Frames.swift` can stay as-is; branding polish is optional.
