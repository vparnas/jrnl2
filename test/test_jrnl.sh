#!/usr/bin/env bash
# test_jrnl.sh — minimal test suite for jrnl2
# Usage: ./test_jrnl.sh [path/to/jrnl]
# Defaults to looking for 'jrnl' on PATH.

set -uo pipefail

JRNL="${1:-jrnl}"

# ── colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'

# ── test state ────────────────────────────────────────────────────────────────
PASS=0; FAIL=0; SKIP=0
FAILURES=()

# ── scaffolding ───────────────────────────────────────────────────────────────
TMPDIR_ROOT="$(mktemp -d)"
JOURNAL_FILE="$TMPDIR_ROOT/test-journal.txt"
CFG_FILE="$TMPDIR_ROOT/jrnl2.rc"

cat >"$CFG_FILE" <<EOF
DEFAULT_JRNL="testjournal"
TIMEFORMAT="%Y-%m-%d %H:%M"
RECORD_START_PAT="[0-9]{4}-[0-9]{2}-[0-9]{2}\s[0-9]{2}:[0-9]{2}"
TAC_RECORD_START_PAT="[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\s[0-9][0-9]:[0-9][0-9]"
EDITOR="true"
declare -A JOURNALS=(
    ['testjournal']="$JOURNAL_FILE"
)
EOF

export JRNL2_CFG="$CFG_FILE"

cleanup() {
    rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

reset_journal() {
    # Wipe the journal file between tests that need a clean slate
    : >"$JOURNAL_FILE"
}

# ── assertion helpers ─────────────────────────────────────────────────────────

# pass <description>
_pass() { echo -e "  ${GREEN}✓${RESET} $1"; PASS=$((PASS + 1)); }

# fail <description> [detail]
_fail() {
    echo -e "  ${RED}✗${RESET} $1"
    [[ -n "${2:-}" ]] && echo -e "      ${YELLOW}→ $2${RESET}"
    FAIL=$((FAIL + 1))
    FAILURES+=("$1")
}

# assert_exit_ok <description> <cmd…>
assert_exit_ok() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then _pass "$desc"
    else _fail "$desc" "command exited non-zero: $*"; fi
}

# assert_exit_fail <description> <cmd…>
assert_exit_fail() {
    local desc="$1"; shift
    if ! "$@" >/dev/null 2>&1; then _pass "$desc"
    else _fail "$desc" "expected non-zero exit from: $*"; fi
}

# assert_file_contains <description> <pattern> <file>
assert_file_contains() {
    local desc="$1" pattern="$2" file="$3"
    if grep -qE "$pattern" "$file" 2>/dev/null; then _pass "$desc"
    else _fail "$desc" "pattern not found: $pattern"; fi
}

# assert_file_not_contains <description> <pattern> <file>
assert_file_not_contains() {
    local desc="$1" pattern="$2" file="$3"
    if ! grep -qE "$pattern" "$file" 2>/dev/null; then _pass "$desc"
    else _fail "$desc" "pattern unexpectedly found: $pattern"; fi
}

# assert_output_contains <description> <pattern> <cmd…>
assert_output_contains() {
    local desc="$1" pattern="$2"; shift 2
    local out
    out="$("$@" 2>&1)"
    if echo "$out" | grep -qE "$pattern"; then _pass "$desc"
    else _fail "$desc" "pattern '$pattern' not found in output"; fi
}

# assert_output_not_contains <description> <pattern> <cmd…>
assert_output_not_contains() {
    local desc="$1" pattern="$2"; shift 2
    local out
    out="$("$@" 2>&1)"
    if ! echo "$out" | grep -qE "$pattern"; then _pass "$desc"
    else _fail "$desc" "pattern '$pattern' unexpectedly found in output"; fi
}

# assert_line_count <description> <expected_n> <cmd…>
assert_line_count() {
    local desc="$1" expected="$2"; shift 2
    local out count
    out="$("$@" 2>&1)"
    # Count non-empty lines (entry headers) in short mode
    count="$(echo "$out" | grep -cE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"
    if [[ "$count" -eq "$expected" ]]; then _pass "$desc"
    else _fail "$desc" "expected $expected date-lines, got $count"; fi
}

# ── test runner ───────────────────────────────────────────────────────────────
run_test() {
    local name="$1"
    echo -e "\n${YELLOW}[$name]${RESET}"
    "test_$name"
}

# ── guard: is the binary available? ──────────────────────────────────────────
if ! command -v "$JRNL" &>/dev/null; then
    echo -e "${RED}ERROR:${RESET} '$JRNL' not found. Pass the path as the first argument."
    echo "  Example: $0 ./jrnl"
    exit 1
fi

# ═════════════════════════════════════════════════════════════════════════════
# T E S T S
# ═════════════════════════════════════════════════════════════════════════════

# ── 1. Adding a plain entry ───────────────────────────────────────────────────
test_add_plain_entry() {
    reset_journal
    assert_exit_ok \
        "plain entry exits 0" \
        "$JRNL" "Hello world, this is a test entry"
    assert_file_contains \
        "entry text written to journal file" \
        "Hello world" "$JOURNAL_FILE"
    assert_file_contains \
        "entry has a timestamp" \
        "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}" "$JOURNAL_FILE"
}

# ── 2. Adding an entry via stdin ──────────────────────────────────────────────
test_add_via_stdin() {
    reset_journal
    echo "Piped entry from stdin" | assert_exit_ok \
        "stdin entry exits 0" \
        "$JRNL"
    assert_file_contains \
        "stdin entry written to file" \
        "Piped entry from stdin" "$JOURNAL_FILE"
}

# ── 3. Tags are stored and searchable ────────────────────────────────────────
test_tags() {
    reset_journal
    "$JRNL" "Working on @projectalpha today" >/dev/null
    "$JRNL" "Unrelated entry with no tags"   >/dev/null

    assert_file_contains \
        "tag written to journal file" \
        "@projectalpha" "$JOURNAL_FILE"

    assert_output_contains \
        "tag search returns the tagged entry" \
        "@projectalpha" \
        "$JRNL" -s "@projectalpha" --short

    assert_output_not_contains \
        "tag search omits untagged entry" \
        "Unrelated entry" \
        "$JRNL" -s "@projectalpha" --short
}

# ── 4. --tags lists tags with counts ─────────────────────────────────────────
test_tag_listing() {
    reset_journal
    "$JRNL" "First  @alpha entry"  >/dev/null
    "$JRNL" "Second @alpha entry"  >/dev/null
    "$JRNL" "Single @beta entry"   >/dev/null

    assert_output_contains \
        "--tags shows @alpha" \
        "@alpha" \
        "$JRNL" --tags

    assert_output_contains \
        "--tags shows @beta" \
        "@beta" \
        "$JRNL" --tags

    # @alpha appears twice — the count should be 2
    local out
    out="$("$JRNL" --tags)"
    if echo "$out" | grep -qE "2\s+@alpha|@alpha\s+2"; then
        _pass "@alpha count is 2"
    else
        _fail "@alpha count is 2" "output was: $out"
    fi
}

# ── 5. -n limits the number of returned entries ───────────────────────────────
test_max_entries() {
    reset_journal
    for i in 1 2 3 4 5; do
        "$JRNL" "Entry number $i" >/dev/null
    done

    assert_line_count \
        "-n 3 returns exactly 3 entries" \
        3 \
        "$JRNL" -n 3 --short
}

# ── 6. Text search (conjunctive) ──────────────────────────────────────────────
test_text_search() {
    reset_journal
    "$JRNL" "Meeting with Alice about budget"     >/dev/null
    "$JRNL" "Lunch with Bob"                       >/dev/null
    "$JRNL" "Follow-up meeting about the proposal" >/dev/null

    # Both "meeting" entries should appear
    assert_line_count \
        "search for 'meeting' returns 2 entries" \
        2 \
        "$JRNL" -s "meeting" --short

    # Only one entry matches both "meeting" and "budget"
    assert_line_count \
        "conjunctive search 'meeting' + 'budget' returns 1 entry" \
        1 \
        "$JRNL" -s "meeting" -s "budget" --short
}

# ── 7. --short shows headers only (no body text) ─────────────────────────────
test_short_mode() {
    reset_journal
    "$JRNL" "$(printf 'Header line\nThis is body text that should be hidden')" >/dev/null

    assert_output_not_contains \
        "--short hides body text" \
        "body text" \
        "$JRNL" --short
}

# ── 8. Multiple entries accumulate (nothing gets overwritten) ─────────────────
test_accumulation() {
    reset_journal
    "$JRNL" "First accumulated entry"  >/dev/null
    "$JRNL" "Second accumulated entry" >/dev/null
    "$JRNL" "Third accumulated entry"  >/dev/null

    assert_file_contains "first entry still present"  "First accumulated"  "$JOURNAL_FILE"
    assert_file_contains "second entry still present" "Second accumulated" "$JOURNAL_FILE"
    assert_file_contains "third entry still present"  "Third accumulated"  "$JOURNAL_FILE"
}

# ── 9. Case-insensitive search is the default ─────────────────────────────────
test_case_insensitive_search() {
    reset_journal
    "$JRNL" "Meeting with the BOARD" >/dev/null

    assert_line_count \
        "lowercase search finds uppercase content by default" \
        1 \
        "$JRNL" -s "board" --short
}

# ── 10. -R reverses output order ─────────────────────────────────────────────
test_reverse_order() {
    reset_journal
    "$JRNL" "Alpha entry" >/dev/null
    sleep 1               # ensure distinct timestamps (1-second resolution)
    "$JRNL" "Omega entry" >/dev/null

    local normal reversed
    normal="$("$JRNL" --short)"
    reversed="$("$JRNL" --short -R)"

    if [[ "$normal" != "$reversed" ]]; then
        _pass "-R produces different ordering"
    else
        _fail "-R produces different ordering" "normal and reversed output are identical"
    fi

    # In reversed output, Omega should come before Alpha
    local first_line
    first_line="$(echo "$reversed" | head -1)"
    if echo "$first_line" | grep -q "Omega"; then
        _pass "reversed output starts with the last-written entry"
    else
        _fail "reversed output starts with the last-written entry" "first line: $first_line"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# R U N   A L L
# ═════════════════════════════════════════════════════════════════════════════
echo -e "\n${YELLOW}jrnl2 test suite${RESET}  (binary: $JRNL)\n"
echo "────────────────────────────────────────"

for t in \
    add_plain_entry \
    add_via_stdin \
    tags \
    tag_listing \
    max_entries \
    text_search \
    short_mode \
    accumulation \
    case_insensitive_search \
    reverse_order
do
    run_test "$t"
done

echo -e "\n────────────────────────────────────────"
echo -e "Results: ${GREEN}$PASS passed${RESET}  ${RED}$FAIL failed${RESET}  ${YELLOW}$SKIP skipped${RESET}"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo -e "\n${RED}Failed tests:${RESET}"
    for f in "${FAILURES[@]}"; do echo "  • $f"; done
    exit 1
fi

echo -e "\n${GREEN}All tests passed.${RESET}"
exit 0
