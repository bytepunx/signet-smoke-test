#!/usr/bin/env bash
# Live demo of the actual thing this whole harness exists to prove: change a
# secret, sync it, and watch one echo pod detect the change, acquire the
# restart lock, exit, get restarted by Kubernetes, and re-print the new
# value — the full WatchBundle -> debounce -> AcquireLock -> exit -> fresh
# GetServiceBundle cycle, for real, driven by a real signet instance.
#
# Usage: scripts/update-secret-and-watch.sh <language>   (default: go)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd kubectl
require_cmd signet
require_cmd git

LANG_ARG="${1:-go}"
NEW_VALUE="hello-from-signet-${LANG_ARG}-updated-$(date +%s)"

TOKEN="$(admin_token)"

log "updating secrets/smoke-${LANG_ARG}/echo/greeting.yaml to a new value"
(
  cd "$REPO_ROOT"
  signet secret set "smoke-${LANG_ARG}/echo/greeting" \
    --value "$NEW_VALUE" \
    --secrets-root secrets/ \
    --sops-config .sops.yaml \
    --token "$TOKEN"
  git add "secrets/smoke-${LANG_ARG}/echo/greeting.yaml"
  git commit -m "smoke-test: update smoke-${LANG_ARG}/echo greeting"
  git push
)

REPO_ID="$(cat "$REPO_ROOT/.smoke-repo-id" 2>/dev/null || true)"
[[ -n "$REPO_ID" ]] || die "no .smoke-repo-id found — run scripts/provision.sh first"

log "signet repo sync --id $REPO_ID"
signet repo sync --id "$REPO_ID" --token "$TOKEN"

log "watching smoke-${LANG_ARG}/echo logs for the new value (up to 2 minutes)..."
deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
  if kubectl logs -n "smoke-${LANG_ARG}" deployment/echo --tail=-1 2>/dev/null \
      | grep -q "$NEW_VALUE"; then
    log "confirmed: smoke-${LANG_ARG}/echo picked up the new value after a real restart cycle."
    exit 0
  fi
  sleep 3
done

die "timed out waiting for smoke-${LANG_ARG}/echo to pick up the new value — check 'kubectl logs -n smoke-${LANG_ARG} deployment/echo' and 'kubectl get pods -n smoke-${LANG_ARG}' by hand"
