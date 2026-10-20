Design a macOS menu bar app called "Usage" that shows my AI usage limits at a glance. It must feel native to macOS (Sonoma/Sequoia style popover), calm, clean and beautiful — not a dashboard, not overcomplicated. Design light and dark mode.

## What it shows
I use 6 AI accounts. Each has limits that reset on a timer.

**Claude (2 accounts):** MAIN (primary) and SECOND (reserve). Each has two limits:
- 5-hour window: % used + reset in "3h 20m"
- Weekly window: % used + reset day/time e.g. "Sun 15:00"

**Agy / Gemini (4 accounts: agy, agy2, agy3, agy4):** each has two model groups, "Gemini" and "Claude & GPT", and each group has a weekly and a 5-hour limit. Show them as % USED (so every bar means the same thing as Claude's). Each account also has a state: ok / needs login / off.

Example data:
- MAIN: 5h 59% (resets in 3h 20m), week 27% (Sun 15:00)
- SECOND: 5h 93% (resets in 1h 10m), week 74% (Thu 04:00), reserve account
- agy: Gemini wk 4% / 5h 0%, Claude&GPT wk 2% / 5h 0%
- agy2: Gemini wk 1% / 5h 0%, Claude&GPT wk 3% / 5h 0%
- agy3: ok, almost unused
- agy4: needs login

## 1. Menu bar item (VERY minimal)
Just a small icon + ONE number. No long text, no multiple accounts, no statuses.
- Small ring/gauge glyph (template image style) + the single most important number: MAIN's 5-hour % (e.g. "59%").
- The ring color shifts with severity: neutral <70, amber 70-85, orange 85-95, red >=95 — based on the worst limit across Claude accounts.
- Show the variants: normal, warning, critical, and "needs attention" (a tiny dot).

## 2. Popover (opens on click, ~340pt wide)
Order, top to bottom:
1. Header: "Usage" + tiny "updated 12s ago" + a refresh icon button.
2. Claude section: two compact account cards (MAIN, SECOND). Each card: name + small label (primary / reserve), two thin progress bars (5h, week) with % and reset time right-aligned. Bars use the severity colors. Keep reserve visually quieter.
3. Agy section: four compact rows, one per account, collapsed by default: name, a tiny dual indicator (Gemini / Claude&GPT used %), state dot. Click a row to expand into its 4 limits. "Needs login" row shows a small "Sign in" button.
4. One optional alert strip only when something matters (e.g. "SECOND 5h at 93% — resets 17:50"). Hidden otherwise.
5. Footer: a single "…" menu button with: Refresh now, Agy accounts (on/off, sign in), Start Claude session, Token report, Launch at login, Quit.

## Style
- Native macOS feel: vibrancy/translucent material background, SF Pro, SF Symbols, 12-14pt radius, generous spacing, 4/8pt grid.
- Quiet by default: mostly neutral grays; color ONLY for severity. One accent color.
- Thin rounded progress bars (4-6pt), tabular numerals for percentages.
- No charts, no graphs, no history, no tabs. Everything visible without scrolling (agy collapsed).
- Keep it calm and glanceable — I should understand my state in 2 seconds.

## Deliverables
Menu bar item states, popover (light + dark), expanded agy row, needs-login row, alert state, the "…" menu. Also give exact colors, spacing and font sizes so a developer can implement it in SwiftUI/AppKit.
