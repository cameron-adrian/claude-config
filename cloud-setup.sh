#!/bin/bash
# Cloud environment setup script for Claude Code on the web.
#
# ---------------------------------------------------------------------------
# THIS FILE IS NOT RUN FROM THE REPO. Paste its contents into the Setup script
# field of your cloud environment at claude.ai/code. It lives here so it is
# reviewable and versioned rather than existing only inside a web form.
# ---------------------------------------------------------------------------
#
# What it is for: user-level configuration does not travel to cloud sessions.
# The docs are explicit -- "Your user ~/.claude/CLAUDE.md ... Available in cloud
# sessions: No" and "User-level settings stay on your machine." So a cloud
# session starts with none of the house rules, which is why cloud sessions have
# behaved differently from local ones.
#
# A setup script runs as root on the session VM before Claude Code launches,
# which makes it the documented place to put a file in the VM's home directory.
# This one fetches CLAUDE.md from the config repo and installs it as the user
# memory file, so a cloud session loads the same rules a local one does.
#
# The hooks and commands arrive separately, as the `house` plugin, either via
# the account-level plugin sync or the repo's own .claude/settings.json.
#
# Constraints this script is written around:
#   * It must exit 0 or the session fails to start. Every step is || true.
#   * It must finish well under five minutes or the environment cache cannot
#     build. This is one small HTTP GET.
#   * github.com is on the default Trusted allowlist, so no extra config.

set -u

RAW="https://raw.githubusercontent.com/cameron-adrian/claude-config/main/CLAUDE.md"

# Claude Code runs as the session user, not as root, so the file has to land in
# that user's home rather than root's. /home/user is the standard layout; fall
# back to $HOME if it ever is not.
TARGET_HOME="/home/user"
[ -d "$TARGET_HOME" ] || TARGET_HOME="$HOME"

mkdir -p "$TARGET_HOME/.claude" || true

if curl -fsSL --max-time 30 "$RAW" -o "$TARGET_HOME/.claude/CLAUDE.md" 2>/dev/null; then
  # Only chown when running as root and the user exists; harmless otherwise.
  if [ "$(id -u)" = "0" ] && id user >/dev/null 2>&1; then
    chown -R user:user "$TARGET_HOME/.claude" || true
  fi
  echo "house: installed CLAUDE.md into $TARGET_HOME/.claude/"
else
  # A failed fetch must not stop the session. It only means this session runs
  # without the house rules, which is exactly where things were before.
  echo "house: could not fetch CLAUDE.md; continuing without it" >&2
fi

exit 0
