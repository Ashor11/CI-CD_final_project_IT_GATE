#!/usr/bin/env bash
# Bootstrap Vault for ashour-chat: KV v2, Kubernetes auth, policy, role, and seed secrets.
# Prereqs: Vault running and unsealed. Set VAULT_ADDR and VAULT_TOKEN (e.g. root token from dev mode or init).
# Run from host with vault CLI: kubectl port-forward -n vault svc/vault 8200:8200, then:
#   export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=<root-or-unseal-token>
#   ./vault/bootstrap.sh
# Or exec into pod: kubectl exec -n vault vault-0 -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$ROOT_TOKEN ./vault/bundle-of-commands'
# This script is idempotent; safe to run multiple times.

set -e

# KV v2 at path "secret" (dev mode already has it)
vault secrets enable -path=secret kv-v2 2>/dev/null || true

# Kubernetes auth
vault auth enable kubernetes 2>/dev/null || true

# Configure Kubernetes auth (token reviewer for validating service account JWTs).
# From outside the cluster: set VAULT_KUBE_CA_CERT and VAULT_KUBE_REVIEWER_JWT (see README).
KUBE_HOST="${KUBE_HOST:-https://kubernetes.default.svc:443}"
if [ -n "${VAULT_KUBE_CA_CERT}" ] && [ -n "${VAULT_KUBE_REVIEWER_JWT}" ]; then
  vault write auth/kubernetes/config \
    kubernetes_host="${KUBE_HOST}" \
    kubernetes_ca_cert="${VAULT_KUBE_CA_CERT}" \
    token_reviewer_jwt="${VAULT_KUBE_REVIEWER_JWT}"
else
  vault write auth/kubernetes/config \
    kubernetes_host="${KUBE_HOST}" \
    disable_local_ca_jwt=false
fi

# Policy: allow read of secret/data/ashour-chat
vault policy write ashour-chat-read - <<'POLICY'
path "secret/data/ashour-chat" {
  capabilities = ["read"]
}
POLICY

# Role: bound to namespace ashour-chat and service account used by ESO
# External Secrets Operator uses a service account in the app namespace; create one if needed.
APP_NS="${VAULT_APP_NAMESPACE:-ashour-chat}"
SA_NAME="${VAULT_ESA_SERVICE_ACCOUNT:-default}"
vault write auth/kubernetes/role/ashour-chat-eso \
  bound_service_account_names="${SA_NAME}" \
  bound_service_account_namespaces="${APP_NS}" \
  audience="vault" \
  policies=ashour-chat-read \
  ttl=1h

# Seed secret/ashour-chat (override with env or use placeholders)
vault kv put secret/ashour-chat \
  redisPassword="${VAULT_secret_redisPassword:-buzzboard-redis-secret}" \
  mysqlRootPassword="${VAULT_secret_mysqlRootPassword:-buzzboard-mysql-root}" \
  mysqlUser="${VAULT_secret_mysqlUser:-buzzboard}" \
  mysqlPassword="${VAULT_secret_mysqlPassword:-buzzboard-mysql-secret}" \
  jwtSecret="${VAULT_secret_jwtSecret:-buzzboard-jwt-secret-change-in-production}"

echo "Bootstrap done. Path secret/ashour-chat is ready; role ashour-chat-eso for SA ${SA_NAME} in ${APP_NS}."
