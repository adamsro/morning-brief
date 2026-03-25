# Morning Brief

A macOS menu bar app that delivers daily competitive intelligence briefs using Claude Code. Action-oriented — tells you what to *do* today, not just what happened. Uses your existing Claude Code subscription, no API keys needed.

## How It Works

1. App runs in your menu bar, checks your schedule daily
2. Fetches recent Reddit and Hacker News posts matching your keywords
3. Claude Code searches the web, analyzes findings, generates an actionable brief
4. Brief saves to `~/Documents/Morning Brief/` and posts to Discord
5. You get a macOS notification when it's ready
6. Click to open — read the brief, ask follow-up questions in the chat window

Session continuity: Claude remembers prior briefs within the week via `--resume`, so you only see new developments. Fresh session starts weekly.

## Quick Start

```bash
cd MorningBrief
swift build
./build-app.sh
open .build/MorningBrief.app
```

Or copy to `/Applications` for permanent use:
```bash
cp -R .build/MorningBrief.app /Applications/
```

## Requirements

- macOS 15.0+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI with an active subscription

## Features

- **Action-oriented briefs** — "Do Today" items with URLs and suggested angles, not passive reports
- **Reddit/HN monitoring** — twice-daily social monitoring with dedup, posts new mentions to Discord
- **Discord integration** — briefs and social mentions posted to configurable webhook channels
- **Session continuity** — Claude remembers what it told you this week, no repetition
- **Monday deep dives** — broader weekly scan on your configured reset day, deltas the rest of the week
- **Weekend skip** — no briefs on Saturday/Sunday
- **Configurable prompt** — edit the prompt in Settings to track anything
- **Follow-up chat** — ask questions about the brief in the app's chat window (streaming)
- **Signed .app bundle** — proper macOS app with notifications and launch-at-login

## Settings

Configure via the menu bar icon → Settings:

| Setting | Description |
|---------|-------------|
| Schedule hour | When to generate the daily brief |
| Weekly reset | Day to start a fresh Claude session (broader scan) |
| Discord webhooks | Webhook URLs for #morning-brief, #reddit-mentions, #hn-mentions |
| Notifications | macOS notifications when brief is ready |
| Launch at Login | Start automatically on boot |
| Social monitoring | Enable/disable Reddit & HN fetching |
| Prompt | Full prompt editor — customize what the brief covers |

## Discord Setup

Create webhooks in your Discord server (channel → Edit → Integrations → Webhooks) and paste the URLs in Settings:

| Channel | Purpose |
|---------|---------|
| `#morning-brief` | Daily brief posted here |
| `#reddit-mentions` | New Reddit posts matching your keywords |
| `#hn-mentions` | New Hacker News posts matching your keywords |

## Project Structure

```
morning-brief/
  MorningBrief/                     # macOS Swift app
    Package.swift
    build-app.sh                    # Build, sign, and package .app bundle
    Sources/
      App/                          # App entry, delegate, state
      Models/                       # Config, errors, messages, metadata
      Services/                     # Claude CLI, scheduling, social monitoring, Discord, storage
      Views/                        # Chat window, settings, markdown rendering
      Resources/DefaultPrompt.md    # Default prompt template
  morning-brief.sh                  # Original shell script version
  install.sh / uninstall.sh         # launchd setup for shell script version
```

## How the Brief Works

The prompt is designed around action items, not reports:

- **Do Today** — Reddit threads to reply to, outreach opportunities, content to create
- **What Changed** — one-liner per competitor with news, skip the rest
- **New Signals** — new competitors or market shifts
- **Content Opportunity** — one specific idea tied to a market signal
- **Quick Radar** — ongoing threads from prior briefs still worth watching

If nothing happened: "Quiet day. No action items." No padding.

## License

MIT

---

Made by [MimicScribe](https://mimicscribe.app)
