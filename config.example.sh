# morning-brief configuration
# Copy this file to config.sh and customize it.

# --- AI Backend ---
# Supported: "claude" (uses Claude Code CLI + your subscription)
BACKEND="claude"

# --- Your Product ---
PRODUCT_NAME="Your Product"
PRODUCT_DESCRIPTION="Brief description of what your product does and who it's for."

# --- Competitors ---
# Comma-separated list of competitor products/companies to track
COMPETITORS="Competitor A, Competitor B, Competitor C"

# --- Focus Areas ---
# What aspects of the market to focus on
FOCUS_AREAS="pricing changes, new feature releases, new market entrants, product positioning"

# --- Prompt ---
# Path to the prompt template (supports {{VARIABLES}} from above)
PROMPT_FILE="prompts/competitor-analysis.md"

# --- Output ---
# Prefix for report filenames (e.g., "report" -> "report-2026-03-22.md")
REPORT_PREFIX="report"

# --- Behavior ---
# Only run once per day (skips if already ran today)
ONCE_PER_DAY="true"

# Send macOS notifications
NOTIFY="true"

# Open the report automatically when done
OPEN_AFTER="true"
