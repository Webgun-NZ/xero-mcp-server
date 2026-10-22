#!/usr/bin/env bash
# =============================================================================
# Repo-local setup for the Codex review bridge
# Run from the project root after installing the project bundle
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(pwd)"
GITIGNORE="$PROJECT_ROOT/.gitignore"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Repo-local Codex Review Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: run this inside a git repository."
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: Claude CLI not found."
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: Codex CLI not found."
  exit 1
fi

mkdir -p "$PROJECT_ROOT/.reviews" "$PROJECT_ROOT/docs" "$PROJECT_ROOT/prompts" "$PROJECT_ROOT/scripts"
chmod +x "$PROJECT_ROOT/scripts/codex-review.sh"

if [ ! -f "$GITIGNORE" ]; then
  touch "$GITIGNORE"
fi

for entry in \
  ".reviews/" \
  ".env.local" \
  "node_modules/" \
  "dist/" \
  "build/" \
  "coverage/" \
  "*.log"; do
  if ! grep -qxF "$entry" "$GITIGNORE"; then
    printf '%s\n' "$entry" >> "$GITIGNORE"
  fi
done

echo "✓ Repo-local review bridge prepared"
echo ""
echo "Next steps:"
echo "1. Customize CLAUDE.md, AGENTS.md, and docs/PROJECT-ARCHITECTURE.md"
echo "2. Smoke test with: ./scripts/codex-review.sh diff"
echo "3. If you want a commit gate, add a pre-commit hook that runs:"
echo "   ./scripts/codex-review.sh diff --staged-only"
echo ""
