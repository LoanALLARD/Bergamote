#!/usr/bin/env bash
# Runs a command. If it fails, repeats the telling lines of its output as an error annotation,
# so the cause shows on the run summary without opening the full log.
#
#   .github/scripts/run.sh cargo test --manifest-path core/Cargo.toml
log="$(mktemp)"
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  {
    grep -iE "error|failed|panicked|\[FAIL\]|✘|échec" "$log" | head -n 25
    echo "--- last lines ---"
    tail -n 25 "$log"
  } | cut -c1-400 | sed -e 's/%/%25/g' | awk '{ printf "%s%%0A", $0 }' > "$log.message"
  echo "::error title=Failed: $1 $2::$(cat "$log.message")"
fi
exit "$status"
