#!/usr/bin/env bash
# =============================================================================
# codex-review.sh — Generic Claude CLI ↔ Codex CLI review bridge
# Authoritative per-project review path. Customize repo docs, not this contract.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REVIEW_LOG_DIR="$PROJECT_ROOT/.reviews"
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
AGENTS_MD="$PROJECT_ROOT/AGENTS.md"
DOCS_DIR="$PROJECT_ROOT/docs"

TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
CODEX_TIMEOUT_SECONDS="${CODEX_TIMEOUT_SECONDS:-600}"
MAX_CONTEXT_LINES=120
MAX_DOC_LINES=800
MAX_DIFF_LINES=5000
MAX_REVIEW_LOG_LINES=200
VALIDATED_REVIEW_OUTPUT=""

mkdir -p "$REVIEW_LOG_DIR"

check_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    echo "ERROR: codex CLI not found." >&2
    exit 1
  fi
}

truncate_lines() {
  local limit="$1"
  sed -n "1,${limit}p"
}

repo_file_list() {
  if command -v rg >/dev/null 2>&1; then
    (cd "$PROJECT_ROOT" && rg --files \
      -g '!node_modules' \
      -g '!.git' \
      -g '!.reviews' \
      -g '!dist' \
      -g '!build' \
      -g '!coverage')
  else
    (cd "$PROJECT_ROOT" && find . -type f \
      -not -path './.git/*' \
      -not -path './node_modules/*' \
      -not -path './.reviews/*' \
      -not -path './dist/*' \
      -not -path './build/*' \
      -not -path './coverage/*')
  fi
}

read_preview() {
  local filepath="$1"
  local limit="${2:-0}"

  [ -f "$filepath" ] || return 1

  if [ "$limit" -gt 0 ]; then
    sed -n "1,${limit}p" "$filepath"
  else
    cat "$filepath"
  fi
}

build_context() {
  local context=""

  context+="## Repository Files"$'\n'
  context+="$(repo_file_list | truncate_lines "$MAX_CONTEXT_LINES")"$'\n\n'

  if [ -f "$CLAUDE_MD" ]; then
    context+="## CLAUDE.md"$'\n'
    context+="$(truncate_lines "$MAX_DOC_LINES" < "$CLAUDE_MD")"$'\n\n'
  fi

  if [ -f "$AGENTS_MD" ]; then
    context+="## AGENTS.md"$'\n'
    context+="$(truncate_lines "$MAX_DOC_LINES" < "$AGENTS_MD")"$'\n\n'
  fi

  if [ -d "$DOCS_DIR" ]; then
    local doc
    for doc in "$DOCS_DIR"/*.md; do
      [ -f "$doc" ] || continue
      context+="## $(basename "$doc")"$'\n'
      context+="$(truncate_lines "$MAX_DOC_LINES" < "$doc")"$'\n\n'
    done
  fi

  printf '%s' "$context"
}

build_untracked_diff() {
  local output=""
  local file

  # A failure here must not read as "no untracked files". An empty diff sends
  # review_diff down its "no working tree changes" PASS branch, so a broken git
  # invocation would come back as a clean review.
  #
  # -z is required, not cosmetic: without it git QUOTES paths containing non-ASCII
  # characters or whitespace ("src/café.js"), and the quoted form doesn't exist on
  # disk, so those files were silently skipped. A change consisting only of such
  # files reviewed as clean.
  #
  # The listing goes via a temp file, not a variable: bash command substitution
  # DISCARDS NUL bytes, so `listing="$(git ls-files -z)"` silently collapses every
  # path into one unusable string and the loop finds nothing at all.
  local list_file err_file
  list_file="$(mktemp "${TMPDIR:-/tmp}/codex-untracked.XXXXXX")"
  err_file="$(mktemp "${TMPDIR:-/tmp}/codex-untracked-err.XXXXXX")"
  if ! git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -z \
      >"$list_file" 2>"$err_file"; then
    printf 'ERROR: could not enumerate untracked files: %s\n' "$(cat "$err_file")" >&2
    rm -f "$list_file" "$err_file"
    return 1
  fi
  rm -f "$err_file"

  while IFS= read -r -d '' file; do
    [ -n "$file" ] || continue
    # -e alone misses dangling symlinks; both tests together keep every real
    # entry, symlinks included, so nothing drops out of the review unseen.
    { [ -e "$PROJECT_ROOT/$file" ] || [ -L "$PROJECT_ROOT/$file" ]; } || continue
    # git diff --no-index exits 1 when files differ, which is the normal case
    # here, so only a status above 1 is a real error.
    local file_diff="" status=0
    file_diff="$(git -C "$PROJECT_ROOT" diff --no-index -- /dev/null "$PROJECT_ROOT/$file" 2>&1)" || status=$?
    if [ "$status" -gt 1 ]; then
      # Surface it in the diff rather than aborting or dropping it. An
      # undiffable file (dangling symlink, unreadable mode) must still be
      # visible to the reviewer instead of vanishing into a clean review.
      output+="## Untracked file could not be diffed: $file"$'\n'"$file_diff"$'\n'
      continue
    fi
    output+="$file_diff"$'\n'
  done < "$list_file"
  rm -f "$list_file"

  printf '%s' "$output"
}

build_review_diff() {
  local scope="${1:-working-tree}"
  local include_untracked="${2:-true}"
  local staged=""
  local unstaged=""
  local untracked=""
  local diff=""

  # Never swallow a git failure: an empty diff is indistinguishable from a clean
  # tree, and a clean tree is reported as PASS.
  if ! staged="$(git -C "$PROJECT_ROOT" diff --cached 2>&1)"; then
    printf 'ERROR: could not read staged changes: %s\n' "$staged" >&2
    return 1
  fi
  if ! unstaged="$(git -C "$PROJECT_ROOT" diff 2>&1)"; then
    printf 'ERROR: could not read unstaged changes: %s\n' "$unstaged" >&2
    return 1
  fi

  if [ "$scope" = "staged-only" ]; then
    [ -n "$staged" ] && diff+=$'## Staged changes\n'"$staged"$'\n\n'
  else
    [ -n "$staged" ] && diff+=$'## Staged changes\n'"$staged"$'\n\n'
    [ -n "$unstaged" ] && diff+=$'## Unstaged changes\n'"$unstaged"$'\n\n'
  fi

  if [ "$include_untracked" = "true" ]; then
    untracked="$(build_untracked_diff)" || return 1
    [ -n "$untracked" ] && diff+=$'## Untracked files\n'"$untracked"$'\n'
  fi

  printf '%s' "$diff"
}

run_codex() {
  local prompt="$1"
  local output_file
  local stderr_file
  local result=""
  local status=0

  output_file="$(mktemp "${TMPDIR:-/tmp}/codex-review-output.XXXXXX")"
  stderr_file="$(mktemp "${TMPDIR:-/tmp}/codex-review-stderr.XXXXXX")"

  # Run codex from PROJECT_ROOT, not the caller's directory. The diff is always
  # collected from PROJECT_ROOT, so invoking the bridge from inside another repo
  # would otherwise hand codex this project's diff alongside a different repo's
  # working tree and instructions.
  if printf '%s' "$prompt" \
    | ( cd "$PROJECT_ROOT" \
        && perl -e 'my $timeout = shift; alarm $timeout; exec @ARGV or die $!;' \
          "$CODEX_TIMEOUT_SECONDS" \
          codex exec --color never --output-last-message "$output_file" - ) \
      >"$stderr_file" 2>&1; then
    if [ -s "$output_file" ]; then
      result="$(cat "$output_file")"
    else
      result="$(cat "$stderr_file")"
      status=1
    fi
  else
    status=$?
    if [ -s "$stderr_file" ]; then
      result="$(cat "$stderr_file")"
    elif [ -s "$output_file" ]; then
      result="$(cat "$output_file")"
    else
      result="ERROR: codex exec failed with exit code $status."
    fi
  fi

  rm -f "$output_file" "$stderr_file"
  printf '%s' "$result"
  return "$status"
}

extract_review_block() {
  # Fail-closed extractor. Emits a block ONLY when the output contains exactly
  # one complete, unambiguous review. Anything else prints nothing on stdout,
  # which the caller's emptiness check turns into a blocking error.
  #
  # The previous version reset its buffer on a nested ---REVIEW-START---, so a
  # FAILING review that quoted a complete PASS example inside a code fence had
  # the example REPLACE it, and the gate read the quote's verdict as the answer.
  # It also silently took the last of several blocks. Ambiguity is now refused
  # rather than resolved, because guessing here fails open.
  awk '
    {
      line = $0
      sub(/\r$/, "", line)
      mk = ""
      probe = line
      sub(/^[ \t]+/, "", probe)
      if (match(probe, /^(`+|~+)/)) {
        cand = substr(probe, 1, RLENGTH)
        if (length(cand) >= 3) { mk = cand }
      }
    }
    mk != "" {
      ch = substr(mk, 1, 1)
      ln = length(mk)
      rest = probe
      sub(/^(`+|~+)/, "", rest)
      if (!fence) { fence = 1; fch = ch; flen = ln }
      # A CLOSING fence carries no info string. ```text opens a block, it does
      # not close one, and treating it as a closer re-exposes quoted content.
      else if (ch == fch && ln >= flen && rest ~ /^[ \t]*$/) { fence = 0 }
      if (capture) { block = block line ORS }
      next
    }
    !fence && line == "---REVIEW-START---" {
      if (capture) {
        print "ERROR: nested ---REVIEW-START--- outside a code fence; refusing to guess which is the real review." > "/dev/stderr"
        ambiguous = 1
      }
      capture = 1
      block = line ORS
      next
    }
    capture {
      block = block line ORS
    }
    !fence && line == "---REVIEW-END---" && capture {
      blocks++
      last_block = block
      capture = 0
      block = ""
    }
    END {
      if (ambiguous) { exit 0 }
      if (capture) {
        print "ERROR: unterminated review block (no ---REVIEW-END---); output was truncated." > "/dev/stderr"
        exit 0
      }
      if (blocks > 1) {
        print "ERROR: " blocks " complete review blocks found; refusing to pick one." > "/dev/stderr"
        exit 0
      }
      if (blocks == 0) { exit 0 }
      printf "%s", last_block
    }
  '
}

validate_review_output() {
  local result="$1"
  local mode="$2"
  shift 2
  local review_block
  local required

  VALIDATED_REVIEW_OUTPUT=""
  review_block="$(printf '%s\n' "$result" | extract_review_block)"

  [ -n "$review_block" ] || {
    echo "ERROR: codex $mode output missing valid review markers." >&2
    return 1
  }

  # Strip fenced content BEFORE checking for required sections. Searching the
  # whole block let a review whose severity headings existed only inside a quoted
  # example satisfy the contract while carrying no findings sections at all.
  local unfenced_block
  unfenced_block="$(printf '%s\n' "$review_block" | awk '
    {
      line = $0
      sub(/\r$/, "", line)
      mk = ""
      probe = line
      sub(/^[ \t]+/, "", probe)
      if (match(probe, /^(`+|~+)/)) {
        cand = substr(probe, 1, RLENGTH)
        if (length(cand) >= 3) { mk = cand }
      }
    }
    mk != "" {
      ch = substr(mk, 1, 1)
      ln = length(mk)
      rest = probe
      sub(/^(`+|~+)/, "", rest)
      if (!fence) { fence = 1; fch = ch; flen = ln }
      else if (ch == fch && ln >= flen && rest ~ /^[ \t]*$/) { fence = 0 }
      next
    }
    !fence { print line }
  ')"

  for required in "$@"; do
    # Anchored at line start, against the unfenced text only. Here-string rather
    # than a pipe: `grep -q` stops at the first match, sending SIGPIPE back to a
    # `printf` still writing, and under `set -o pipefail` that rejected a long but
    # perfectly valid review for a section it actually contained.
    if ! grep -qE -- "^${required}[[:space:]]*$" <<< "$unfenced_block"; then
      echo "ERROR: codex $mode output missing required section: $required" >&2
      return 1
    fi
  done

  # Against the UNFENCED text, not the whole block. A legitimate prompt review
  # returns a corrected AGENTS.md whose own output templates contain these
  # placeholders inside code fences; matching those rejected the correct answer.
  if grep -Eq '^\[(items.*|unified diff.*|PASS \| FAIL.*|confirmed fixes.*|remaining blockers.*|numbered list.*|complete corrected version.*)\]$' <<< "$unfenced_block"; then
    echo "ERROR: codex $mode output still contains template placeholder text." >&2
    return 1
  fi

  VALIDATED_REVIEW_OUTPUT="$review_block"
}

save_and_print() {
  local log_file="$1"
  local content="$2"
  printf '%s\n' "$content" > "$log_file"
  printf '%s\n' "$content"
}

# Turn the review's verdict into an exit status.
#
# Without this the bridge prints "FAIL" and still returns 0, so the pre-commit
# hook this script documents would wave rejected changes straight through — the
# gate would print its objection and open the door anyway.
#
# Fail-closed by design: a missing, empty or unrecognised verdict blocks. A
# reviewer that dies mid-sentence must not read as approval.
review_verdict_status() {
  local verdict
  # A verdict section inside a code fence is a quoted example (the reviewer
  # contract itself contains one) and must not answer for the review quoting it.
  # More than ONE unfenced verdict section is ambiguous and is refused outright:
  # reading the first would let "PASS ... ### VERDICT FAIL" exit zero.
  local verdict_count
  verdict_count="$(printf '%s\n' "$1" | awk '
    {
      line = $0
      sub(/\r$/, "", line)
      mk = ""
      probe = line
      sub(/^[ \t]+/, "", probe)
      if (match(probe, /^(`+|~+)/)) {
        cand = substr(probe, 1, RLENGTH)
        if (length(cand) >= 3) { mk = cand }
      }
    }
    mk != "" {
      ch = substr(mk, 1, 1)
      ln = length(mk)
      rest = probe
      sub(/^(`+|~+)/, "", rest)
      if (!fence) { fence = 1; fch = ch; flen = ln }
      # A CLOSING fence carries no info string. ```text opens a block, it does
      # not close one, and treating it as a closer re-exposes quoted content.
      else if (ch == fch && ln >= flen && rest ~ /^[ \t]*$/) { fence = 0 }
      next
    }
    fence { next }
    /^### (FINAL-)?VERDICT[ \t]*$/ { n++ }
    END { print n + 0 }
  ')"
  if [ "${verdict_count:-0}" -ne 1 ]; then
    printf 'ERROR: review carries %s unfenced verdict sections; treating as blocking.\n' \
      "${verdict_count:-0}" >&2
    return 1
  fi

  verdict="$(printf '%s\n' "$1" \
    | awk '
    {
      line = $0
      sub(/\r$/, "", line)
      mk = ""
      probe = line
      sub(/^[ \t]+/, "", probe)
      if (match(probe, /^(`+|~+)/)) {
        cand = substr(probe, 1, RLENGTH)
        if (length(cand) >= 3) { mk = cand }
      }
    }
    mk != "" {
      ch = substr(mk, 1, 1)
      ln = length(mk)
      rest = probe
      sub(/^(`+|~+)/, "", rest)
      if (!fence) { fence = 1; fch = ch; flen = ln }
      # A CLOSING fence carries no info string. ```text opens a block, it does
      # not close one, and treating it as a closer re-exposes quoted content.
      else if (ch == fch && ln >= flen && rest ~ /^[ \t]*$/) { fence = 0 }
      next
    }
    fence { next }
    /^### (FINAL-)?VERDICT[ \t]*$/ { f=1; next }
    /^### / { f=0 }
    f' \
    | tr -d '*_`' | tr '[:lower:]' '[:upper:]')"

  if ! grep -q '[A-Z]' <<< "$verdict"; then
    printf 'ERROR: review output carries no verdict; treating as blocking.\n' >&2
    return 1
  fi

  # Only the LEADING token decides. Searching the whole verdict for keywords is
  # wrong in both directions: "CONDITIONAL — rerun to obtain PASS after browser
  # verification" would read as approval, and "PASS — no failed checks" would
  # read as a failure because the explanation mentions "failed".
  local token
  token="$(grep -m1 '[A-Z]' <<< "$verdict" \
    | sed -e 's/—.*$//' -e 's/–.*$//' -e 's/ - .*$//' -e 's/:.*$//' -e 's/\..*$//' -e 's/(.*$//' \
    | tr -s '[:space:]' ' ' \
    | sed -e 's/^ *//' -e 's/ *$//')"

  # Fail-closed allowlist: an explicit leading PASS/APPROVED and nothing else.
  # Any other verdict — FAIL, REJECTED, CONDITIONAL, NEEDS CHANGES, or wording
  # nobody anticipated — blocks.
  case "$token" in
    PASS|PASSED|APPROVE|APPROVED|ACCEPT|ACCEPTED) return 0 ;;
  esac

  printf 'ERROR: verdict %s is not an approval; treating as blocking.\n' \
    "$(printf '%s' "${token:-<empty>}" | cut -c1-80)" >&2
  return 1
}

review_diff() {
  local scope="${1:-working-tree}"
  local include_untracked="${2:-true}"
  local log_file="$REVIEW_LOG_DIR/diff_${TIMESTAMP}.md"
  local diff

  diff="$(build_review_diff "$scope" "$include_untracked")"

  if [ -z "$diff" ]; then
    save_and_print "$log_file" "$(cat <<'EOF'
---REVIEW-START---
## Diff Review

### CRITICAL
None

### HIGH
None

### MEDIUM
None

### LOW
None

### PROMPT-FIXES
None

### SUGGESTED-DIFF
None

### VERDICT
PASS — no working tree changes to review
---REVIEW-END---
EOF
)"
    return 0
  fi

  local prompt
  prompt="$(cat <<EOF
You are the independent reviewer for this repository.

$(build_context)

## Changes
\`\`\`diff
$(printf '%s' "$diff" | truncate_lines "$MAX_DIFF_LINES")
\`\`\`

Use the review contract defined in AGENTS.md.

---REVIEW-START---
## Diff Review

### CRITICAL
[items with filename:line or 'None']

### HIGH
[items or 'None']

### MEDIUM
[items or 'None']

### LOW
[items or 'None']

### PROMPT-FIXES
[instruction or prompt corrections, or 'None']

### SUGGESTED-DIFF
[unified diff or 'None']

### VERDICT
[PASS | FAIL | CONDITIONAL — with blockers listed]
---REVIEW-END---
EOF
)"

  local result
  result="$(run_codex "$prompt")" || {
    save_and_print "$log_file" "$result"
    return 1
  }

  validate_review_output "$result" "diff review" '### CRITICAL' '### HIGH' '### MEDIUM' '### LOW' '### VERDICT' || {
    save_and_print "$log_file" "$result"
    return 1
  }

  save_and_print "$log_file" "$VALIDATED_REVIEW_OUTPUT"
  review_verdict_status "$VALIDATED_REVIEW_OUTPUT"
}

review_file() {
  local filepath="$1"
  local abs="$PROJECT_ROOT/$filepath"
  local log_file="$REVIEW_LOG_DIR/file_$(basename "$filepath")_${TIMESTAMP}.md"

  [ -f "$abs" ] || {
    echo "ERROR: file not found: $filepath" >&2
    exit 1
  }

  local prompt
  prompt="$(cat <<EOF
You are the independent reviewer for this repository.

File: $filepath

\`\`\`
$(read_preview "$abs")
\`\`\`

$(build_context)

Use the review contract defined in AGENTS.md.

---REVIEW-START---
## File Review: $filepath

### CRITICAL
[items with filename:line or 'None']

### HIGH
[items or 'None']

### MEDIUM
[items or 'None']

### LOW
[items or 'None']

### PROMPT-FIXES
[instruction or prompt corrections, or 'None']

### SUGGESTED-DIFF
[unified diff or 'None']

### VERDICT
[PASS | FAIL | CONDITIONAL — with blockers listed]
---REVIEW-END---
EOF
)"

  local result
  result="$(run_codex "$prompt")" || {
    save_and_print "$log_file" "$result"
    return 1
  }

  validate_review_output "$result" "file review" '### CRITICAL' '### HIGH' '### MEDIUM' '### LOW' '### VERDICT' || {
    save_and_print "$log_file" "$result"
    return 1
  }

  save_and_print "$log_file" "$VALIDATED_REVIEW_OUTPUT"
  review_verdict_status "$VALIDATED_REVIEW_OUTPUT"
}

review_prompt_file() {
  local filepath="$1"
  local abs="$PROJECT_ROOT/$filepath"
  local log_file="$REVIEW_LOG_DIR/prompt_$(basename "$filepath")_${TIMESTAMP}.md"

  [ -f "$abs" ] || {
    echo "ERROR: file not found: $filepath" >&2
    exit 1
  }

  local prompt
  prompt="$(cat <<EOF
You are reviewing a prompt or instruction file for this repository.

File: $filepath

\`\`\`
$(read_preview "$abs")
\`\`\`

$(build_context)

---REVIEW-START---
## Prompt Review: $filepath

### ISSUES
[numbered list or 'None']

### REVISED-PROMPT
[complete corrected version or 'No changes needed']

### CHANGES-MADE
[what changed and why]
---REVIEW-END---
EOF
)"

  local result
  result="$(run_codex "$prompt")" || {
    save_and_print "$log_file" "$result"
    return 1
  }

  validate_review_output "$result" "prompt review" '### ISSUES' '### REVISED-PROMPT' '### CHANGES-MADE' || {
    save_and_print "$log_file" "$result"
    return 1
  }

  save_and_print "$log_file" "$VALIDATED_REVIEW_OUTPUT"
}

review_phase() {
  local label="$1"
  local log_file="$REVIEW_LOG_DIR/phase_${label}_${TIMESTAMP}.md"
  local diff
  diff="$(build_review_diff "working-tree" "true")"
  [ -n "$diff" ] || diff="No current working tree changes."

  local prompt
  prompt="$(cat <<EOF
You are performing a milestone or phase review for this repository.

Phase or milestone label: $label

$(build_context)

## Current Changes
\`\`\`diff
$(printf '%s' "$diff" | truncate_lines "$MAX_DIFF_LINES")
\`\`\`

Use the project contract in AGENTS.md and the project architecture docs.

---REVIEW-START---
## Phase Review: $label

### CRITICAL
[items with filename:line or 'None']

### HIGH
[items or 'None']

### MEDIUM
[items or 'None']

### LOW
[items or 'None']

### PROMPT-FIXES
[instruction or prompt corrections, or 'None']

### SUGGESTED-DIFF
[unified diff or 'None']

### VERDICT
[PASS | FAIL | CONDITIONAL — with blockers listed]
---REVIEW-END---
EOF
)"

  local result
  result="$(run_codex "$prompt")" || {
    save_and_print "$log_file" "$result"
    return 1
  }

  validate_review_output "$result" "phase review" '### CRITICAL' '### HIGH' '### MEDIUM' '### LOW' '### VERDICT' || {
    save_and_print "$log_file" "$result"
    return 1
  }

  save_and_print "$log_file" "$VALIDATED_REVIEW_OUTPUT"
  review_verdict_status "$VALIDATED_REVIEW_OUTPUT"
}

approve_phase() {
  local label="$1"
  local log_file="$REVIEW_LOG_DIR/approval_${label}_${TIMESTAMP}.md"
  local current_diff
  local prior_reviews=""
  local f

  current_diff="$(build_review_diff "working-tree" "true")"
  [ -n "$current_diff" ] || current_diff="No current unreviewed diff captured."

  for f in "$REVIEW_LOG_DIR"/*.md; do
    [ -f "$f" ] || continue
    prior_reviews+="## $(basename "$f")"$'\n'
    prior_reviews+="$(sed -n "1,${MAX_REVIEW_LOG_LINES}p" "$f")"$'\n\n'
  done

  local prompt
  prompt="$(cat <<EOF
You are performing final approval for this repository.

Approval label: $label

$(build_context)

## Prior Reviews
$prior_reviews

## Current Diff Snapshot
\`\`\`diff
$(printf '%s' "$current_diff" | truncate_lines "$MAX_DIFF_LINES")
\`\`\`

Verify that critical and high issues are resolved and that the current working tree is safe.

---REVIEW-START---
## Final Approval: $label

### RESOLVED-ISSUES
[confirmed fixes or 'None']

### UNRESOLVED-ISSUES
[remaining blockers or 'None']

### FINAL-VERDICT
[APPROVED | REJECTED — with blockers]
---REVIEW-END---
EOF
)"

  local result
  result="$(run_codex "$prompt")" || {
    save_and_print "$log_file" "$result"
    return 1
  }

  validate_review_output "$result" "final approval" '### RESOLVED-ISSUES' '### UNRESOLVED-ISSUES' '### FINAL-VERDICT' || {
    save_and_print "$log_file" "$result"
    return 1
  }

  save_and_print "$log_file" "$VALIDATED_REVIEW_OUTPUT"
  review_verdict_status "$VALIDATED_REVIEW_OUTPUT"
}

usage() {
  cat <<'EOF'
Usage: ./scripts/codex-review.sh <command> [args]

Commands:
  diff [--staged-only|--tracked-only]   Review current changes
  file <path>                           Review a specific file
  prompt <path>                         Review a prompt or instruction file
  phase <label>                         Review a milestone or phase label
  approve <label>                       Final approval for a milestone or phase
EOF
}

main() {
  check_codex

  [ $# -gt 0 ] || {
    usage
    exit 1
  }

  case "$1" in
    diff)
      case "${2:-}" in
        --staged-only) review_diff "staged-only" "false" ;;
        --tracked-only) review_diff "working-tree" "false" ;;
        *) review_diff "working-tree" "true" ;;
      esac
      ;;
    file)
      [ $# -ge 2 ] || { usage; exit 1; }
      review_file "$2"
      ;;
    prompt)
      [ $# -ge 2 ] || { usage; exit 1; }
      review_prompt_file "$2"
      ;;
    phase)
      [ $# -ge 2 ] || { usage; exit 1; }
      review_phase "$2"
      ;;
    approve)
      [ $# -ge 2 ] || { usage; exit 1; }
      approve_phase "$2"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
