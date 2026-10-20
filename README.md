# Usage

A small macOS menu bar app that shows the **5-hour and weekly limits of all your AI accounts** in one place —
Claude (MAIN + SECOND) and agy / Gemini (agy, agy2, agy3, agy4) — so you never have to run `/usage` in each tool.

- **Menu bar:** two concentric gradient rings + one number — outer ring = MAIN 5-hour, inner ring = MAIN weekly, number = MAIN 5-hour %. Each ring is coloured by its own level
  (neutral < 70 · amber 70–85 · orange 85–95 · red ≥ 95). A small orange dot means an agy account needs login or the data is stale.
- **Popover:** Claude cards (MAIN, SECOND), agy rows with mini usage bars (click a row or **Details** to open a full details window), an alert strip when a Claude limit is ≥ 85%,
  and a `…` menu (refresh, agy on/off + sign in, start Claude session, token report, launch at login, quit).
- Light and dark mode, everything shown as **% used**. Design spec: [`design/`](design).

![popover](design/popover-dark.png) ![popover dark](design/details-dark.png)

![menu bar](design/menubar-dark.png)

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools (`xcode-select --install`) — provides `swift`
- The `~/.claude-control` toolkit with the `quota` command. The app only **reads** what it writes:
  - `ctl.py quota` refreshes `~/.claude-control/state/quota.json`
    (Claude: Anthropic usage API using the token Claude Code keeps in the keychain · agy: `agy -p "/quota"` per account)
  - controls call `~/.claude-control/bin/ai` (`agy on|off|login`, `main`)

Check it works before installing:

```bash
python3 ~/.claude-control/bin/ctl.py quota        # prints 5h / weekly for every account
```

## Install

```bash
git clone https://github.com/thexayotbe/usage-bar.git
cd usage-bar
./install.sh
```

`install.sh` builds the app, copies it to `~/Applications/Usage.app` and launches it. The ring appears in the menu bar
(there is no Dock icon). First launch only: macOS may ask to let Usage control **Terminal** (used by *Sign in…*,
*Start Claude session* and *Token report*) — allow it.

Start it automatically: click **… → Launch at login**.

## Build only

```bash
./build.sh            # → build/Usage.app (ad-hoc signed)
open build/Usage.app
```

If macOS refuses to open the app ("unidentified developer"), run `xattr -dr com.apple.quarantine ~/Applications/Usage.app`
or right-click → Open once.

## How it works

| Piece | What it does |
|---|---|
| Menu bar ring | Reads `quota.json` every 10 s; runs `ctl.py quota` every 5 min and whenever you open the popover and the data is old. |
| Claude cards | `claude.<account>.five_hour` / `seven_day` → `{pct, resets}` (% used). |
| Agy rows | `agy.<name>.gemini|claude.week|five` → `{remaining, resets}`; shown as `100 − remaining` (% used). |
| Agy on/off, sign in | `ai agy on|off <name>`, `ai agy login <name>` (opens Terminal). |
| Windows that already reset | Shown as 0%. |

`quota.json` shape:

```json
{
  "ts": 1792496000,
  "claude": { "main": { "five_hour": {"pct": 59, "resets": 1792510000}, "seven_day": {"pct": 27, "resets": 1792922400} } },
  "agy":    { "agy":  { "gemini": { "week": {"remaining": 96, "resets": 1792800000}, "five": {"remaining": 100, "resets": 1792510000} },
                        "claude": { "week": {"remaining": 98, "resets": 1793000000}, "five": {"remaining": 100, "resets": 1792510000} } } }
}
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Ring shows `–` and the dot is orange | No data yet — run `python3 ~/.claude-control/bin/ctl.py quota` and check for errors. |
| A Claude card says *no token / token expired* | Open a Claude Code session on that account once; it refreshes the keychain token. |
| agy row says *Needs login* | Click **Sign in** (opens Terminal), finish the Google sign-in, type `/quit`. |
| *Launch at login* does nothing | Run the app from `~/Applications` (use `./install.sh`), not from `build/`. |

## Develop

```bash
cd app && swift build -c release
.build/release/Usage --snapshot /tmp/usage   # renders popover + menu bar states to PNG, then quits
.build/release/Usage --show [--details]      # opens the popover (and the details window) at launch
```

## Uninstall

```bash
pkill -x Usage; rm -rf ~/Applications/Usage.app
```
