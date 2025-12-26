#!/bin/bash
# Configure Kubernetes authentication method in Vault
# Works both locally and in-cluster

set -euo pipefail

########################
# Configuration
########################
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
K8S_HOST="${K8S_HOST:-https://kubernetes.default.svc}"
K8S_NAMESPACE="${K8S_NAMESPACE:-vault}"
TOKEN_REVIEWER_SA="${TOKEN_REVIEWER_SA:-vault-token-reviewer}"
TOKEN_REVIEWER_JWT="${TOKEN_REVIEWER_JWT:-}"

K8S_CA_CERT="${K8S_CA_CERT:-/var/run/secrets/kubernetes.io/serviceaccount/ca.crt}"

########################
# Colors
########################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

########################
# Helpers
########################
die() {
  echo -e "${RED}ERROR:${NC} $1"
  exit 1
}

info() {
  echo -e "${YELLOW}$1${NC}"
}

ok() {
  echo -e "${GREEN}✓ $1${NC}"
}

########################
# Preconditions
########################
command -v vault >/dev/null || die "vault CLI not found"
command -v kubectl >/dev/null || die "kubectl not found"

[ -z "$VAULT_TOKEN" ] && die "VAULT_TOKEN must be set (use root token for bootstrap)"

export VAULT_ADDR VAULT_TOKEN

########################
# Connectivity check
########################
info "Checking Vault connectivity..."
vault status >/dev/null || die "Cannot connect to Vault at $VAULT_ADDR"
ok "Vault is accessible"

########################
# Enable auth method
########################
info "Enabling Kubernetes auth method..."
if vault auth list | grep -q '^kubernetes/'; then
  ok "Kubernetes auth already enabled"
else
  vault auth enable kubernetes
  ok "Kubernetes auth enabled"
fi

########################
# Ensure Token Reviewer SA
########################
info "Ensuring token reviewer ServiceAccount exists..."

kubectl get sa "$TOKEN_REVIEWER_SA" -n "$K8S_NAMESPACE" >/dev/null 2>&1 || \
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $TOKEN_REVIEWER_SA
  namespace: $K8S_NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $TOKEN_REVIEWER_SA-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: $TOKEN_REVIEWER_SA
  namespace: $K8S_NAMESPACE
EOF

ok "Token reviewer ServiceAccount ready"

########################
# Retrieve JWT
########################
if [ -z "$TOKEN_REVIEWER_JWT" ]; then
  info "Retrieving token reviewer JWT..."
  
  # Try kubectl create token first (Kubernetes ≥1.24)
  if TOKEN_REVIEWER_JWT=$(kubectl create token "$TOKEN_REVIEWER_SA" -n "$K8S_NAMESPACE" 2>/dev/null); then
    ok "Token reviewer JWT acquired via create token"
  elif [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]; then
    TOKEN_REVIEWER_JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    ok "Token reviewer JWT acquired from service account"
  else
    die "Unable to retrieve TOKEN_REVIEWER_JWT"
  fi
fi

[ -z "$TOKEN_REVIEWER_JWT" ] && die "TOKEN_REVIEWER_JWT is empty"
ok "Token reviewer JWT acquired"

########################
# Configure auth
########################
info "Configuring Kubernetes auth in Vault..."

# Get CA certificate - try in-cluster path first, then kubectl
if [ -f "$K8S_CA_CERT" ]; then
  vault write auth/kubernetes/config \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert=@"$K8S_CA_CERT" \
    disable_local_ca_jwt=false
else
  # Running locally - get CA from kubectl
  K8S_CA_CERT_DATA=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)
  vault write auth/kubernetes/config \
    token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
    kubernetes_host="$(kubectl config view --minify -o jsonpath='{.clusters[].cluster.server}')" \
    kubernetes_ca_cert="$K8S_CA_CERT_DATA" \
    disable_local_ca_jwt=false
fi

ok "Kubernetes auth configured"

########################
# Roles
########################
info "Creating Vault roles..."

create_role() {
  local name=$1
  local policy=$2

  vault write auth/kubernetes/role/$name \
    bound_service_account_names=$name \
    bound_service_account_namespaces=craftista-dev,craftista-staging,craftista-prod \
    policies=$policy \
    ttl=24h

  ok "Role created: $name"
}

create_role frontend frontend-policy
create_role catalogue catalogue-policy
create_role voting voting-policy
create_role recommendation recommendation-policy

########################
# Verify
########################
info "Verifying configuration..."
vault read auth/kubernetes/config >/dev/null
ok "Kubernetes auth verified"

echo -e "${GREEN}=== Kubernetes Authentication Configuration Complete ===${NC}"