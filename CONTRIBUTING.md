# Contributing

Thanks for helping! The project is small: a Swift package in `app/`, no dependencies.

- **Build:** `cd app && swift build` (or `./build.sh` for a signed `build/Usage.app`).
- **Try it without touching your real setup:**
  `USAGE_BAR_CONFIG=/tmp/cfg.json USAGE_BAR_CACHE=/tmp/cache app/.build/debug/Usage --check`
  prints what the app would show and quits. `--snapshot DIR` renders the UI to PNGs.
- **Be gentle with the Anthropic usage API.** It rate-limits per token. Do not add polling faster than the 5-minute floor, and avoid test loops that call it; use a `quotaFile` or the cache while iterating on UI.
- **Never log or store tokens.** Tokens are read from the keychain per request and sent only to `api.anthropic.com`.
- **UI:** `design/DESIGN-PROMPT.md` is the spec. Keep changes in `Views.swift` / `Theme.swift` / `MenuBarImage.swift` visual-only and update the screenshots in `design/` if the look changes.
- Open an issue before large changes. Keep PRs focused; explain what you tested.
