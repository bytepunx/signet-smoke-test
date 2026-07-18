#!/usr/bin/env bash
# Provisions signet itself for the smoke test: admin RBAC, SOPS age key,
# the six secrets/config pairs, the GitHub deploy key + repo registration,
# an initial sync, and the shared-secret policy. Idempotent — safe to
# re-run against an already-provisioned cluster.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd kubectl
require_cmd signet
require_cmd gh
require_cmd git
require_cmd ssh-keygen

REPO_SLUG="bytepunx/signet-smoke-test"
REPO_GIT_URL="git@github.com:${REPO_SLUG}.git"
DEPLOY_KEY_TITLE="smoke-test-readonly"
DEPLOY_KEY_DIR="$REPO_ROOT/.secrets"
DEPLOY_KEY_PATH="$DEPLOY_KEY_DIR/deploy_key"

cd "$REPO_ROOT"

log "applying admin RBAC fix"
kubectl apply -f manifests/admin-rbac.yaml

log "starting admin port-forward"
# The Service intentionally does not expose 8444 (admin is loopback-only by
# design — see deploy/helm/signet/templates/service.yaml's own comment).
# Forward to the Deployment directly instead, which reaches the container
# port regardless of what the Service exposes.
kubectl port-forward -n "$SIGNET_NAMESPACE" deploy/signet 8444:8444 >/tmp/signet-smoke-portforward.log 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do
  nc -z localhost 8444 2>/dev/null && break
  sleep 0.5
done

signet config set server localhost:8444
TOKEN="$(admin_token)"

log "signet status"
signet status --token "$TOKEN"

log "ensuring a SOPS age key exists"
if ! signet sops-key get --token "$TOKEN" >/dev/null 2>&1; then
  log "no active key — rotating to create the first one"
  signet sops-key rotate --token "$TOKEN"
fi
signet sops-key update-config --file .sops.yaml --secrets-path secrets/ --token "$TOKEN"

log "authoring secrets"
for lang in "${LANGUAGES[@]}"; do
  signet secret set "smoke-${lang}/echo/greeting" \
    --value "hello-from-signet-${lang}" \
    --secrets-root secrets/ \
    --sops-config .sops.yaml \
    --token "$TOKEN"
done
signet secret set "smoke-shared/common/greeting" \
  --value "hello-from-signet-shared" \
  --secrets-root secrets/ \
  --sops-config .sops.yaml \
  --token "$TOKEN"

log "authoring plain config files (config/<namespace>/<service>.yaml)"
mkdir -p config
for lang in "${LANGUAGES[@]}"; do
  mkdir -p "config/smoke-${lang}"
  cat > "config/smoke-${lang}/echo.yaml" <<EOF
language: ${lang}
message: hello from signet config
EOF
done
mkdir -p config/smoke-shared
cat > config/smoke-shared/common.yaml <<'EOF'
message: hello from shared signet config
EOF

log "ensuring a read-only deploy key exists on $REPO_SLUG"
mkdir -p "$DEPLOY_KEY_DIR"
if [[ ! -f "$DEPLOY_KEY_PATH" ]]; then
  ssh-keygen -t ed25519 -N '' -C "$DEPLOY_KEY_TITLE" -f "$DEPLOY_KEY_PATH" >/dev/null
fi
if ! gh repo deploy-key list --repo "$REPO_SLUG" | grep -q "$DEPLOY_KEY_TITLE"; then
  gh repo deploy-key add "${DEPLOY_KEY_PATH}.pub" --repo "$REPO_SLUG" --title "$DEPLOY_KEY_TITLE"
fi

log "committing and pushing secrets/config/.sops.yaml"
git add secrets/ config/ .sops.yaml
if ! git diff --cached --quiet; then
  git commit -m "smoke-test: provision secrets and config"
  git push
else
  log "nothing to commit (already up to date)"
fi

log "registering the repository with signet (or reusing an existing registration)"
REPO_ID="$(signet repo list --token "$TOKEN" | grep "$REPO_SLUG" | awk '{print $1}' || true)"
if [[ -z "$REPO_ID" ]]; then
  REPO_ID="$(signet repo add \
    --name smoke-test \
    --repo-url "$REPO_GIT_URL" \
    --branch main \
    --secrets-path secrets/ \
    --config-path config/ \
    --deploy-key "$DEPLOY_KEY_PATH" \
    --token "$TOKEN" \
    | grep -i '^ID' | awk '{print $NF}')"
  [[ -n "$REPO_ID" ]] || die "could not parse repo ID from 'signet repo add' output"
fi
echo "$REPO_ID" > "$REPO_ROOT/.smoke-repo-id"
log "repo ID: $REPO_ID"

log "triggering an explicit sync"
signet repo sync --id "$REPO_ID" --token "$TOKEN"

log "provisioning complete. Run scripts/deploy-echo.sh next."
