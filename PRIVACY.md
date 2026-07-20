# Privacy

Droid Notch is fully local:

- Hook scripts write session state only under `~/.factory/statusbar/`.
- The menu bar app reads that directory and never uploads status data.
- No network calls are made in the default build (update checks are disabled until a public release feed exists).

Hook stdin may briefly contain tool names and paths; these stay on disk only in the per-session JSON files you control.
