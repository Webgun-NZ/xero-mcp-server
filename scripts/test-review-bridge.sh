#!/usr/bin/env bash
# Regression tests for the codex-review.sh bridge.
#
# Two suites: the verdict->exit-status gate, and untracked-file enumeration.
#
# The verdict is what makes the review a *gate*: if it doesn't reach the exit
# code, the pre-commit hook prints "FAIL" and commits anyway. Two subtler bugs
# are pinned here because both shipped once already:
#
#   * "CONDITIONAL — rerun to obtain PASS after browser verification" must BLOCK.
#     Searching the whole verdict for approval words let this through.
#   * "PASS — no failed checks" must APPROVE. Searching for blocking words made
#     the explanation veto its own verdict.
#
# Run: bash scripts/test-review-bridge.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FN="$(mktemp "${TMPDIR:-/tmp}/verdict-fn.XXXXXX")"
trap 'rm -f "$FN"' EXIT

sed -n '/^review_verdict_status() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh" > "$FN"
[ -s "$FN" ] || { echo "ERROR: could not extract review_verdict_status from codex-review.sh" >&2; exit 1; }
# shellcheck disable=SC1090
source "$FN"

fails=0
t() {
  local label="$1" body="$2" want="$3" got
  review_verdict_status "$body" >/dev/null 2>&1 && got=0 || got=1
  if [ "$got" = "$want" ]; then
    printf '  ok    %s\n' "$label"
  else
    printf '  FAIL  %s (exit %s, expected %s)\n' "$label" "$got" "$want"
    fails=$((fails + 1))
  fi
}

echo "verdict gate — must block:"
t "FAIL"                  '### VERDICT
**FAIL — the review gate accepts rejected reviews.**' 1
t "REJECTED"              '### VERDICT
REJECTED' 1
t "not approved"          '### FINAL-VERDICT
Not approved — blockers remain.' 1
t "changes requested"     '### VERDICT
Changes requested' 1
t "needs changes"         '### VERDICT
NEEDS CHANGES — see HIGH.' 1
t "CONDITIONAL naming PASS" '### VERDICT
**CONDITIONAL — rerun to obtain PASS after browser verification**' 1
t "unrecognised wording"  '### VERDICT
Looks alright to me.' 1
t "no verdict section"    '### CRITICAL
None.' 1
t "empty verdict"         '### VERDICT

### NEXT' 1
t "truncated mid-verdict" '### VERDICT
**FA' 1

echo "verdict gate — must approve:"
t "PASS"                  '### VERDICT
PASS' 0
t "PASS, bold, explained" '### VERDICT
**PASS** — no blocking issues.' 0
t "PASS naming 'failed'"  '### VERDICT
**PASS — no failed checks**' 0
t "APPROVED"              '### FINAL-VERDICT
APPROVED' 0
t "Approved, explained"   '### FINAL-VERDICT
Approved: all issues resolved.' 0


# ---------------------------------------------------------------------------
# Untracked-file enumeration
#
# A file that git reports but this loop skips vanishes from the review entirely,
# and if it is the only change the bridge reports "no working tree changes" and
# passes. Three ways that happened:
#   * git QUOTES non-ASCII/whitespace paths unless -z is used, and the quoted
#     form does not exist on disk, so the file was skipped.
#   * bash command substitution DISCARDS NUL bytes, so capturing `ls-files -z`
#     into a variable collapsed every path into one unusable string.
#   * `[ -f ]` skips symlinks, including dangling ones.
# ---------------------------------------------------------------------------
BUD="$(mktemp "${TMPDIR:-/tmp}/untracked-fn.XXXXXX")"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/untracked-repo.XXXXXX")"
trap 'rm -f "$FN" "$BUD" "${EXB:-}"; rm -rf "$FIXTURE"' EXIT

sed -n '/^build_untracked_diff() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh" > "$BUD"
[ -s "$BUD" ] || { echo "ERROR: could not extract build_untracked_diff" >&2; exit 1; }

(
  cd "$FIXTURE" || exit 1
  git init -q .
  git config user.email test@example.com
  git config user.name Test
  echo base > tracked.txt
  git add -A && git commit -qm init
  printf 'x\n' > 'café file.js'      # non-ASCII: git quotes this without -z
  printf 'y\n' > 'sub name.txt'      # whitespace: also quoted
  ln -s tracked.txt good.link        # symlink: skipped by [ -f ]
  ln -s /nonexistent dangling.link   # dangling symlink: skipped by [ -e ]
) >/dev/null 2>&1

untracked_out="$(PROJECT_ROOT="$FIXTURE" bash -c "source '$BUD'; build_untracked_diff")"

echo "untracked enumeration — every file must appear:"
u() {
  local label="$1" needle="$2"
  if printf '%s' "$untracked_out" | grep -aqF "$needle"; then
    printf '  ok    %s\n' "$label"
  else
    printf '  FAIL  %s (not found in review diff)\n' "$label"
    fails=$((fails + 1))
  fi
}
u "non-ASCII filename"   'caf'
u "whitespace filename"  'sub name.txt'
u "symlink"              'good.link'
u "dangling symlink"     'dangling.link'

# ---------------------------------------------------------------------------
# Review validation must survive a large review
#
# `printf ... | grep -q` stops reading at the first match and SIGPIPEs the
# printf still writing into it. With `set -o pipefail` the pipeline then reports
# failure, so a long but perfectly valid review was rejected for a section it
# actually contained. Only reproducible above pipe-buffer size, hence 100KB.
# ---------------------------------------------------------------------------
VAL="$(mktemp "${TMPDIR:-/tmp}/validate-fn.XXXXXX")"
sed -n '/^extract_review_block() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh"  > "$VAL"
sed -n '/^validate_review_output() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh" >> "$VAL"
[ -s "$VAL" ] || { echo "ERROR: could not extract validation functions" >&2; exit 1; }

echo "review validation — long reviews must still validate:"
big_review="$(
  printf -- '---REVIEW-START---\n'
  printf '### CRITICAL\n\nNone.\n\n### HIGH\n\nNone.\n\n### MEDIUM\n\nNone.\n\n### LOW\n\n'
  # ~100KB of body between the required sections
  awk 'BEGIN{for(i=0;i<2000;i++) printf "padding line %d with enough text to add up\n", i}'
  printf '\n### VERDICT\n\nPASS\n'
  printf -- '---REVIEW-END---\n'
)"
if ( set -euo pipefail; source "$VAL"
     validate_review_output "$big_review" "diff review" \
       '### CRITICAL' '### HIGH' '### MEDIUM' '### LOW' '### VERDICT' ) >/dev/null 2>&1; then
  printf '  ok    100KB review validates (no SIGPIPE false negative)\n'
else
  printf '  FAIL  100KB review was rejected as missing a section it contains\n'
  fails=$((fails + 1))
fi
rm -f "$VAL"

# ---------------------------------------------------------------------------
# Block extraction must REFUSE ambiguity rather than resolve it.
#
# Regression for the 2026-09-21 fail-open: a nested ---REVIEW-START--- reset the
# extractor's buffer, so a FAILING review that quoted a complete PASS example
# inside a code fence had the example replace it, and the gate approved.
# ---------------------------------------------------------------------------

# Sourcing codex-review.sh whole runs `main`, which prints usage and exits, so
# the function under test would never run and every case would return empty —
# the negative cases would pass by ABSENCE. Extract just the function, and prove
# the harness works by requiring the positive cases to return a block.
EXB="$(mktemp "${TMPDIR:-/tmp}/extract-fn.XXXXXX")"
sed -n '/^extract_review_block() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh" > "$EXB"
[ -s "$EXB" ] || { echo "ERROR: could not extract extract_review_block" >&2; exit 1; }

echo "block extraction — ambiguity must yield NO block:"
x() {
  local label="$1" expect="$2" input="$3" out got
  out="$(printf '%s\n' "$input" | bash -c "source '$EXB'; extract_review_block" 2>/dev/null)"
  got="empty"; [ -n "$out" ] && got="block"
  if [ "$got" = "$expect" ]; then
    printf '  ok    %s\n' "$label"
  else
    printf '  FAIL  %s (expected %s, got %s)\n' "$label" "$expect" "$got"
    fails=$((fails + 1))
  fi
}

# A fenced example must be IGNORED, and the enclosing review must win. Asserting
# the verdict rather than "a block came back", which the example would satisfy too.
fenced_out="$(printf '%s\n' '---REVIEW-START---
### VERDICT
FAIL — real blocker.

Example of a passing review:
```
---REVIEW-START---
### VERDICT
PASS
---REVIEW-END---
```
---REVIEW-END---' | bash -c "source '$EXB'; extract_review_block" 2>/dev/null)"
# The block legitimately CONTAINS the quoted example; what matters is the verdict
# the gate actually reads. Call the REAL review_verdict_status — re-implementing
# its awk here would produce a test that passes whatever the script does.
RVS="$(mktemp "${TMPDIR:-/tmp}/verdict-fn.XXXXXX")"
sed -n '/^review_verdict_status() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh" > "$RVS"
[ -s "$RVS" ] || { echo "ERROR: could not extract review_verdict_status" >&2; exit 1; }

if bash -c "source '$RVS'; review_verdict_status \"\$1\"" _ "$fenced_out" >/dev/null 2>&1; then
  printf '  FAIL  fenced PASS example was read as an approval\n'
  fails=$((fails + 1))
else
  printf '  ok    fenced PASS example ignored, gate still blocks\n'
fi

# And the same function must still APPROVE a clean PASS, or the case above would
# pass simply because the gate blocks everything.
if bash -c "source '$RVS'; review_verdict_status \"\$1\"" _ '### VERDICT
PASS' >/dev/null 2>&1; then
  printf '  ok    clean PASS still approves (blocking is not universal)\n'
else
  printf '  FAIL  clean PASS no longer approves\n'
  fails=$((fails + 1))
fi
rm -f "$RVS"

# The case above does NOT exercise the verdict reader's fence-awareness: its
# outer ### VERDICT comes first, so grep -m1 picks FAIL either way. Mutation
# testing proved it. This is the arrangement that actually breaks — a fenced
# example EARLIER in the review than the real verdict, which is the normal shape
# when a finding quotes a review (and what `prompt AGENTS.md` produces).
RVS2="$(mktemp "${TMPDIR:-/tmp}/verdict-fn2.XXXXXX")"
sed -n '/^review_verdict_status() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh" > "$RVS2"

EARLY_FENCE='### MEDIUM

The gate mis-parses this shape:

```
### VERDICT
PASS
```

### VERDICT
FAIL — the finding above is real.'

if bash -c "source '$RVS2'; review_verdict_status \"\$1\"" _ "$EARLY_FENCE" >/dev/null 2>&1; then
  printf '  FAIL  fenced verdict BEFORE the real one was read as approval\n'
  fails=$((fails + 1))
else
  printf '  ok    fenced verdict before the real one is ignored\n'
fi
rm -f "$RVS2"

# A fence closes only on the SAME character, at least as long as the opener.
# Toggling on any run of three let a ```` block containing a ``` example close on
# the inner fence, exposing the quoted PASS to the parser.
RVS3="$(mktemp "${TMPDIR:-/tmp}/verdict-fn3.XXXXXX")"
sed -n '/^review_verdict_status() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh" > "$RVS3"

LONG_FENCE='### MEDIUM

Everything below is quoted, so the review has NO verdict of its own.

````
```
### VERDICT
PASS
```
````'

if bash -c "source '$RVS3'; review_verdict_status \"\$1\"" _ "$LONG_FENCE" >/dev/null 2>&1; then
  printf '  FAIL  four-backtick fence let a quoted PASS through\n'
  fails=$((fails + 1))
else
  printf '  ok    longer fence containing a shorter one stays closed\n'
fi

# Two UNFENCED verdicts is ambiguous. Reading the first would let a review that
# says PASS and then FAIL exit zero.
CONFLICT='### VERDICT
PASS

### VERDICT
FAIL — blockers remain.'

if bash -c "source '$RVS3'; review_verdict_status \"\$1\"" _ "$CONFLICT" >/dev/null 2>&1; then
  printf '  FAIL  conflicting PASS/FAIL verdicts were accepted\n'
  fails=$((fails + 1))
else
  printf '  ok    conflicting verdict sections refused\n'
fi

# The refusals above must not be "it blocks everything": a fenced example beside
# exactly one real verdict must still resolve, or prompt reviews break.
QUOTED_OK='### MEDIUM

The contract looks like this:

```
### VERDICT
PASS
```

### VERDICT
PASS'

if bash -c "source '$RVS3'; review_verdict_status \"\$1\"" _ "$QUOTED_OK" >/dev/null 2>&1; then
  printf '  ok    one real verdict beside a fenced example still approves\n'
else
  printf '  FAIL  a legitimate quoting review was refused\n'
  fails=$((fails + 1))
fi
rm -f "$RVS3"

# A CLOSING fence carries no info string. ```text OPENS a block; treating it
# as a closer re-exposes the quoted verdict after it. The fixture goes through a
# temp file rather than $(cat <<EOF): a heredoc nested inside command
# substitution, with backticks in the body, does not survive the parser.
RVS4="$(mktemp "${TMPDIR:-/tmp}/verdict-fn4.XXXXXX")"
IFF="$(mktemp "${TMPDIR:-/tmp}/info-fence.XXXXXX")"
sed -n '/^review_verdict_status() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh" > "$RVS4"

cat > "$IFF" <<'IFEOF'
### MEDIUM

Everything below is quoted, so this review has NO verdict of its own.

```
```text
### VERDICT
PASS
```
IFEOF

info_fence_body="$(cat "$IFF")"
if bash -c "source '$RVS4'; review_verdict_status \"\$1\"" _ "$info_fence_body" >/dev/null 2>&1; then
  printf '  FAIL  an info-string fence was treated as a closer\n'
  fails=$((fails + 1))
else
  printf '  ok    info-string fence does not close a block\n'
fi
rm -f "$RVS4" "$IFF"

# ---------------------------------------------------------------------------
# Placeholder detection must ignore QUOTED templates. A prompt review returns a
# corrected AGENTS.md whose own output contract contains these placeholders
# inside fences; matching them rejected the correct answer. Unfenced ones must
# still be caught, or the check stops meaning anything.
# ---------------------------------------------------------------------------
VRO="$(mktemp "${TMPDIR:-/tmp}/validate-fn.XXXXXX")"
{
  sed -n '/^extract_review_block() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh"
  sed -n '/^validate_review_output() {/,/^}/p' "$SCRIPT_DIR/codex-review.sh"
} > "$VRO"

PH_OK="$(mktemp "${TMPDIR:-/tmp}/ph-ok.XXXXXX")"
PH_BAD="$(mktemp "${TMPDIR:-/tmp}/ph-bad.XXXXXX")"

cat > "$PH_OK" <<'PHEOF'
---REVIEW-START---
### CRITICAL
None.
### HIGH
None.
### MEDIUM
The contract's own template reads:
```
[items ...]
```
### LOW
None.
### VERDICT
PASS
---REVIEW-END---
PHEOF

cat > "$PH_BAD" <<'PHEOF'
---REVIEW-START---
### CRITICAL
None.
### HIGH
None.
### MEDIUM
[items ...]
### LOW
None.
### VERDICT
PASS
---REVIEW-END---
PHEOF

echo "placeholder detection — quoted templates are not placeholders:"
v() {
  local label="$1" expect="$2" file="$3"
  if bash -c "source '$VRO'; validate_review_output \"\$(cat '$file')\" test '### CRITICAL' '### HIGH' '### MEDIUM' '### LOW' '### VERDICT'" >/dev/null 2>&1; then
    got="accepted"
  else
    got="rejected"
  fi
  if [ "$got" = "$expect" ]; then
    printf '  ok    %s\n' "$label"
  else
    printf '  FAIL  %s (expected %s, got %s)\n' "$label" "$expect" "$got"
    fails=$((fails + 1))
  fi
}
v "fenced placeholder is legitimate content" accepted "$PH_OK"
v "unfenced placeholder is still rejected"   rejected "$PH_BAD"
rm -f "$VRO" "$PH_OK" "$PH_BAD"

x "unfenced nested start" empty '---REVIEW-START---
### VERDICT
FAIL
---REVIEW-START---
### VERDICT
PASS
---REVIEW-END---'

x "two complete blocks"       empty '---REVIEW-START---
### VERDICT
FAIL
---REVIEW-END---
---REVIEW-START---
### VERDICT
PASS
---REVIEW-END---'

x "unterminated block"        empty '---REVIEW-START---
### VERDICT
PASS'

x "single clean block"        block '---REVIEW-START---
### VERDICT
PASS
---REVIEW-END---'

x "block amid chatter"        block 'preamble
---REVIEW-START---
### VERDICT
PASS
---REVIEW-END---
trailing'

echo
if [ "$fails" -eq 0 ]; then
  echo "all review-bridge tests passed"
else
  echo "$fails review-bridge test(s) failed"
  exit 1
fi
