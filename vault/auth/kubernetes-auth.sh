#!/bin/bash
# Script to configure Kubernetes authentication method in Vault
# This enables Kubernetes service accounts to authenticate with Vault

set -e

# Configuration variables
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
K8S_HOST="${K8S_HOST:-https://kubernetes.default.svc}"
K8S_CA_CERT="${K8S_CA_CERT:-/var/run/secrets/kubernetes.io/serviceaccount/ca.crt}"
TOKEN_REVIEWER_JWT="${TOKEN_REVIEWER_JWT:-}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Configuring Kubernetes Authentication in Vault ===${NC}"

# Check if Vault token is set
if [ -z "$VAULT_TOKEN" ]; then
  echo -e "${RED}Error: VAULT_TOKEN environment variable is not set${NC}"
  echo "Please set VAULT_TOKEN with a token that has admin privileges"
  exit 1
fi

# Export Vault address for CLI commands
export VAULT_ADDR

# Check Vault connectivity
echo -e "${YELLOW}Checking Vault connectivity...${NC}"
if ! vault status > /dev/null 2>&1; then
  echo -e "${RED}Error: Cannot connect to Vault at $VAULT_ADDR${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Vault is accessible${NC}"

# Enable Kubernetes auth method if not already enabled
echo -e "${YELLOW}Enabling Kubernetes auth method...${NC}"
if vault auth list | grep -q "kubernetes/"; then
  echo -e "${YELLOW}Kubernetes auth method already enabled${NC}"
else
  vault auth enable kubernetes
  echo -e "${GREEN}✓ Kubernetes auth method enabled${NC}"
fi

# Get the token reviewer JWT if not provided
if [ -z "$TOKEN_REVIEWER_JWT" ]; then
  echo -e "${YELLOW}Retrieving service account token...${NC}"
  # Try to get token from mounted service account
  if [ -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]; then
    TOKEN_REVIEWER_JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  else
    echo -e "${RED}Error: TOKEN_REVIEWER_JWT not provided and cannot read from service account${NC}"
    echo "Please provide TOKEN_REVIEWER_JWT environment variable"
    exit 1
  fi
fi

# Configure Kubernetes auth method
echo -e "${YELLOW}Configuring Kubernetes auth method...${NC}"
vault write auth/kubernetes/config \
  token_reviewer_jwt="$TOKEN_REVIEWER_JWT" \
  kubernetes_host="$K8S_HOST" \
  kubernetes_ca_cert=@"$K8S_CA_CERT" \
  disable_local_ca_jwt=false

echo -e "${GREEN}✓ Kubernetes auth method configured${NC}"

# Create roles for each microservice
echo -e "${YELLOW}Creating Vault roles for microservices...${NC}"

# Frontend role
vault write auth/kubernetes/role/frontend \
  bound_service_account_names=frontend \
  bound_service_account_namespaces=craftista-dev,craftista-staging,craftista-prod \
  policies=frontend-policy \
  ttl=24h

echo -e "${GREEN}✓ Created role for frontend service${NC}"

# Catalogue role
vault write auth/kubernetes/role/catalogue \
  bound_service_account_names=catalogue \
  bound_service_account_namespaces=craftista-dev,craftista-staging,craftista-prod \
  policies=catalogue-policy \
  ttl=24h

echo -e "${GREEN}✓ Created role for catalogue service${NC}"

# Voting role
vault write auth/kubernetes/role/voting \
  bound_service_account_names=voting \
  bound_service_account_namespaces=craftista-dev,craftista-staging,craftista-prod \
  policies=voting-policy \
  ttl=24h

echo -e "${GREEN}✓ Created role for voting service${NC}"

# Recommendation role
vault write auth/kubernetes/role/recommendation \
  bound_service_account_names=recommendation \
  bound_service_account_namespaces=craftista-dev,craftista-staging,craftista-prod \
  policies=recommendation-policy \
  ttl=24h

echo -e "${GREEN}✓ Created role for recommendation service${NC}"

# Verify configuration
echo -e "${YELLOW}Verifying Kubernetes auth configuration...${NC}"
vault read auth/kubernetes/config

echo -e "${GREEN}=== Kubernetes Authentication Configuration Complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. Apply Vault policies using: vault policy write <policy-name> <policy-file>"
echo "2. Ensure service accounts exist in Kubernetes namespaces"
echo "3. Configure pods with Vault annotations for secret injection"
