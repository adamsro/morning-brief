# Morning Brief

A macOS utility that runs AI prompts on a schedule and delivers daily reports. Uses your existing Claude Code subscription — no API keys or credits needed.

Built for indie developers and small teams who want automated competitive intelligence without enterprise pricing.

## How It Works

1. A macOS `launchd` agent triggers daily at 9 AM
2. If your Mac was asleep, it catches up on the next wake
3. Claude Code runs your prompt with web search enabled
4. A markdown report lands in `reports/`
5. You get a macOS notification when it's ready

## Quick Start

```bash
# Clone
git clone https://github.com/mimicscribe/morning-brief.git
cd morning-brief

# Configure
cp config.example.sh config.sh
# Edit config.sh with your product and competitor details

# Install (sets up daily 9 AM schedule)
./install.sh

# Or run manually
./morning-brief.sh
```

## Requirements

- macOS 15.0+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI with an active subscription

## Configuration

Edit `config.sh`:

| Variable | Description |
|----------|-------------|
| `BACKEND` | AI backend — `claude` (more coming) |
| `PRODUCT_NAME` | Your product name |
| `PRODUCT_DESCRIPTION` | What your product does |
| `COMPETITORS` | Comma-separated competitor list |
| `FOCUS_AREAS` | What to track |
| `PROMPT_FILE` | Path to prompt template |
| `ONCE_PER_DAY` | Skip if already ran today |
| `NOTIFY` | macOS notifications |
| `OPEN_AFTER` | Auto-open report when done |

## Custom Prompts

Create your own prompt templates in `prompts/`. Templates support these variables:

- `{{DATE}}` — today's date
- `{{PRODUCT_NAME}}` — from config
- `{{PRODUCT_DESCRIPTION}}` — from config
- `{{COMPETITORS}}` — from config
- `{{FOCUS_AREAS}}` — from config

## CLI Options

```
morning-brief [OPTIONS]

  -f, --force       Run even if already ran today
  -p, --prompt      Path to prompt template
  -b, --backend     AI backend (claude)
  -c, --config      Path to config file
  -h, --help        Show help
```

## Manage Schedule

```bash
# Install (daily at 9 AM)
./install.sh

# Uninstall
./uninstall.sh

# Check status
launchctl list | grep morning-brief
```

## Project Structure

```
morning-brief/
  morning-brief.sh          # Main runner
  config.sh                 # Your config (gitignored)
  config.example.sh         # Example config
  install.sh                # Set up launchd schedule
  uninstall.sh              # Remove schedule
  prompts/                  # Prompt templates
    competitor-analysis.md   # Default competitor analysis prompt
  reports/                  # Generated reports (gitignored)
```

## License

MIT

---

Made by [MimicScribe](https://mimicscribe.app)
