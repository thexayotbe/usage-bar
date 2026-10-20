# usage-bar

A minimal macOS menu bar app that shows the 5-hour and weekly limits of all my AI accounts
(Claude MAIN/SECOND + agy 1–4) in one glance, so I never have to run `/usage` in each tool.

## How it works
- `ctl.py quota` (lives in `~/.claude-control/bin`) refreshes live limits into `~/.claude-control/state/quota.json`
  - Claude: Anthropic OAuth usage API, token read from the macOS keychain
  - agy: `agy -p "/quota"` per account
- The app only reads `quota.json` and calls the existing `ai` commands for controls.

## Layout
- `design/` — design prompt and exported designs
- `app/` — Swift menu bar app (coming)
