#!/bin/bash
# gstack SessionStart hook — makes gstack's skills invocable in Claude Code on the web.
#
# Why this exists: `.claude/skills/` is git-ignored, so the per-skill symlinks that
# `./setup` normally creates cannot be committed. A fresh cloud container therefore
# clones the repo WITHOUT any registered skills. This hook rebuilds the binary and
# recreates the symlinks on every web/mobile session boot so `/qa`, `/ship`,
# `/review`, etc. show up as slash commands.
#
# Runs only in remote (Claude Code on the web) sessions. Idempotent.
set -uo pipefail

# Local sessions already have skills installed via ./setup — nothing to do.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

REPO="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO" || exit 0
LOG="$REPO/.claude/hooks/session-start.log"

{
  echo "=== gstack session-start hook: $(date -u) ==="

  # 1. Install JS deps (cached in the container after first run).
  if command -v bun >/dev/null 2>&1; then
    bun install || echo "warn: bun install failed (skills still usable, binary may be stale)"

    # 2. Build the browse/design binaries + regenerate skill docs.
    #    Non-fatal: prompt-only skills work without the binary.
    bun run build || echo "warn: bun run build failed (browse-dependent skills may not work)"

    # 3. Best-effort: install Playwright Chromium so /browse and /qa can drive a browser.
    bunx playwright install chromium >/dev/null 2>&1 || echo "warn: chromium install skipped (network policy?)"
  else
    echo "warn: bun not found — cannot build binary"
  fi

  # 4. Register skills. Mirror gstack's proven layout:
  #    .claude/skills/gstack -> repo root, then each skill -> gstack/<name>.
  mkdir -p "$REPO/.claude/skills"
  ln -snf "$REPO" "$REPO/.claude/skills/gstack"
  linked=0
  for d in "$REPO"/*/; do
    name="$(basename "$d")"
    [ "$name" = "node_modules" ] && continue
    if [ -f "$d/SKILL.md" ]; then
      ln -snf "gstack/$name" "$REPO/.claude/skills/$name"
      linked=$((linked + 1))
    fi
  done
  echo "registered $linked gstack skills into .claude/skills/"
  echo "=== done ==="
} >>"$LOG" 2>&1

# Surface a concise line into the session context.
echo "gstack skills registered into .claude/skills/ (see .claude/hooks/session-start.log)"
exit 0
