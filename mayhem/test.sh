#!/usr/bin/env bash
#
# mayhem/test.sh — behavioral oracle for tldr-c-client (golden-output render tests).
#
# Upstream ships no unit-test suite (its CI just builds and smoke-runs the binary), but the
# renderer (`tldr -r <page>`) is a deterministic, offline parse-and-render path — so the oracle
# renders committed sample pages with the NORMAL-flags build produced by mayhem/build.sh
# (out-test/tldr) and diffs the output against committed golden files. Asserts real output
# (golden diffs), not exit status; also asserts the error path rejects a missing page.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/out-test/tldr"
if [ ! -x "$BIN" ]; then
  echo "FATAL: $BIN missing — mayhem/build.sh must build the test binary" >&2
  emit_ctrf "golden-render" 0 1
  exit $?
fi

passed=0; failed=0

# Golden render tests: output must match the committed golden byte-for-byte.
for page in "$SRC"/mayhem/tests/*.md; do
  name="$(basename "$page" .md)"
  golden="$SRC/mayhem/tests/$name.golden"
  "$BIN" -r "$page" > "/tmp/render-$name.out" 2>/dev/null
  if [ -f "$golden" ] && diff -u "$golden" "/tmp/render-$name.out" >/dev/null; then
    echo "PASS render $name"; passed=$((passed+1))
  else
    echo "FAIL render $name (output differs from golden)"; failed=$((failed+1))
    [ -f "$golden" ] && diff -u "$golden" "/tmp/render-$name.out" | head -20
  fi
done

emit_ctrf "golden-render" "$passed" "$failed"
