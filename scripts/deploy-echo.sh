#!/usr/bin/env bash
# Deploys the echo workloads (see lib.sh's LANGUAGES for which languages are
# currently active). Requires provision.sh to have already run (secrets/
# config synced, so there's something for them to actually fetch).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd kubectl

for lang in "${LANGUAGES[@]}"; do
  log "applying manifests/echo-${lang}.yaml"
  kubectl apply -f "$REPO_ROOT/manifests/echo-${lang}.yaml"
done

log "waiting for all echo Deployments to report Available..."
for lang in "${LANGUAGES[@]}"; do
  kubectl wait --for=condition=Available "deployment/echo" \
    -n "smoke-${lang}" --timeout=120s
done

log "all ${#LANGUAGES[@]} echo Deployments are up. Run scripts/verify.sh to check their output."
