#!/usr/bin/env bash
# Checks each echo pod's logs for the ECHO_BUNDLE: line and confirms it
# contains the expected per-language secret/config values authored by
# provision.sh. Matches by substring, not full JSON parsing — the five
# client libraries don't all format ECHO_BUNDLE identically (e.g. numeric
# vs. string config values, key ordering), so this stays robust to that
# instead of requiring one canonical shape across languages.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd kubectl

fail=0

check() {
  local lang="$1" expect="$2"
  local logs
  logs="$(kubectl logs -n "smoke-${lang}" deployment/echo --tail=-1 2>/dev/null || true)"
  if [[ -z "$logs" ]]; then
    echo "FAIL  smoke-${lang}: no logs (pod not running yet?)"
    fail=1
    return
  fi
  if ! grep -q "ECHO_BUNDLE:" <<<"$logs"; then
    echo "FAIL  smoke-${lang}: no ECHO_BUNDLE: line in logs yet"
    fail=1
    return
  fi
  if ! grep "ECHO_BUNDLE:" <<<"$logs" | grep -q -- "$expect"; then
    echo "FAIL  smoke-${lang}: ECHO_BUNDLE present but missing expected value: $expect"
    echo "        actual: $(grep 'ECHO_BUNDLE:' <<<"$logs" | tail -1)"
    fail=1
    return
  fi
  echo "OK    smoke-${lang}: found expected value ($expect)"
}

for lang in "${LANGUAGES[@]}"; do
  check "$lang" "hello-from-signet-${lang}"
  check "$lang" "hello-from-signet-shared"
done

if [[ "$fail" -ne 0 ]]; then
  die "one or more languages failed verification (see FAIL lines above)"
fi
log "all five languages verified: per-language secret + shared secret both present."
