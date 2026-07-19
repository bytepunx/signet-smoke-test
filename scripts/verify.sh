#!/usr/bin/env bash
# Checks each echo pod's logs for the ECHO_BUNDLE: line and confirms it
# contains the expected per-language secret/config values authored by
# provision.sh. Matches by substring, not full JSON parsing — the
# client libraries don't all format ECHO_BUNDLE identically (e.g. numeric
# vs. string config values, key ordering), so this stays robust to that
# instead of requiring one canonical shape across languages.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd kubectl

fail=0

check() {
  local lang="$1" marker="$2" expect="$3"
  local logs
  logs="$(kubectl logs -n "smoke-${lang}" deployment/echo --tail=-1 2>/dev/null || true)"
  if [[ -z "$logs" ]]; then
    echo "FAIL  smoke-${lang}: no logs (pod not running yet?)"
    fail=1
    return
  fi
  if ! grep -q "${marker}:" <<<"$logs"; then
    echo "FAIL  smoke-${lang}: no ${marker}: line in logs yet"
    fail=1
    return
  fi
  if ! grep "${marker}:" <<<"$logs" | grep -q -- "$expect"; then
    echo "FAIL  smoke-${lang}: ${marker} present but missing expected value: $expect"
    echo "        actual: $(grep "${marker}:" <<<"$logs" | tail -1)"
    fail=1
    return
  fi
  echo "OK    smoke-${lang}: found expected value ($expect) in ${marker}"
}

for lang in "${LANGUAGES[@]}"; do
  check "$lang" "ECHO_BUNDLE" "hello-from-signet-${lang}"
  # The shared secret is fetched via a separate GetServiceBundle call,
  # printed on its own ECHO_SHARED_BUNDLE: line (see each echo service's
  # SIGNET_SHARED_NAMESPACE/SIGNET_SHARED_SERVICE handling) — it does NOT
  # appear inside ECHO_BUNDLE:, since both scopes use the secret name
  # "greeting" and merging them would silently drop one.
  check "$lang" "ECHO_SHARED_BUNDLE" "hello-from-signet-shared"
done

if [[ "$fail" -ne 0 ]]; then
  die "one or more languages failed verification (see FAIL lines above)"
fi
log "all ${#LANGUAGES[@]} languages verified: per-language secret + shared secret both present."
