#!/bin/bash
# Script to configure GitHub OIDC authentication method in Vault
# This enables GitHub Actions workflows to authenticate with Vault using OIDC

set -e

# Configuration variables
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
GITHUB_ORG="${GITHUB_ORG:-charliepoker}"
GITHUB_REPO="${GITHUB_REPO:-craftista}"
OIDC_DISCOVERY_URL="https://token.actions.githubusercontent.com"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Configuring GitHub OIDC Authentication in Vault ===${NC}"

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

# Enable JWT auth method if not already enabled
echo -e "${YELLOW}Enabling JWT auth method...${NC}"
if vault auth list | grep -q "jwt/"; then
  echo -e "${YELLOW}JWT auth method already enabled${NC}"
else
  vault auth enable jwt
  echo -e "${GREEN}✓ JWT auth method enabled${NC}"
fi

# Configure JWT auth method for GitHub OIDC
echo -e "${YELLOW}Configuring JWT auth method for GitHub OIDC...${NC}"
vault write auth/jwt/config \
  oidc_discovery_url="$OIDC_DISCOVERY_URL" \
  bound_issuer="https://token.actions.githubusercontent.com" \
  default_role="github-actions"

echo -e "${GREEN}✓ JWT auth method configured for GitHub OIDC${NC}"

# Create role for GitHub Actions
echo -e "${YELLOW}Creating Vault role for GitHub Actions...${NC}"
vault write auth/jwt/role/github-actions \
  role_type="jwt" \
  bound_audiences="https://github.com/$GITHUB_ORG" \
  bound_subject="repo:$GITHUB_ORG/$GITHUB_REPO:*" \
  user_claim="actor" \
  policies="github-actions-policy" \
  ttl=1h

echo -e "${GREEN}✓ Created role for GitHub Actions${NC}"

# Create additional role for specific branches (optional)
echo -e "${YELLOW}Creating role for main branch deployments...${NC}"
vault write auth/jwt/role/github-actions-main \
  role_type="jwt" \
  bound_audiences="https://github.com/$GITHUB_ORG" \
  bound_subject="repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main" \
  bound_claims='{"ref":"refs/heads/main"}' \
  user_claim="actor" \
  policies="github-actions-policy" \
  ttl=1h

echo -e "${GREEN}✓ Created role for main branch${NC}"

# Create role for develop branch
echo -e "${YELLOW}Creating role for develop branch deployments...${NC}"
vault write auth/jwt/role/github-actions-develop \
  role_type="jwt" \
  bound_audiences="https://github.com/$GITHUB_ORG" \
  bound_subject="repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/develop" \
  bound_claims='{"ref":"refs/heads/develop"}' \
  user_claim="actor" \
  policies="github-actions-policy" \
  ttl=1h

echo -e "${GREEN}✓ Created role for develop branch${NC}"

# Create role for staging branch
echo -e "${YELLOW}Creating role for staging branch deployments...${NC}"
vault write auth/jwt/role/github-actions-staging \
  role_type="jwt" \
  bound_audiences="https://github.com/$GITHUB_ORG" \
  bound_subject="repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/staging" \
  bound_claims='{"ref":"refs/heads/staging"}' \
  user_claim="actor" \
  policies="github-actions-policy" \
  ttl=1h

echo -e "${GREEN}✓ Created role for staging branch${NC}"

# Verify configuration
echo -e "${YELLOW}Verifying JWT auth configuration...${NC}"
vault read auth/jwt/config

echo -e "${GREEN}=== GitHub OIDC Authentication Configuration Complete ===${NC}"
echo ""
echo "Configuration Summary:"
echo "  Organization: $GITHUB_ORG"
echo "  Repository: $GITHUB_REPO"
echo "  OIDC Discovery URL: $OIDC_DISCOVERY_URL"
echo ""
echo "Next steps:"
echo "1. Apply github-actions-policy using: vault policy write github-actions-policy vault/policies/github-actions-policy.hcl"
echo "2. Configure GitHub Actions workflows to use OIDC authentication"
echo "3. Add the following to your GitHub Actions workflow:"
echo ""
echo "    - name: Import Secrets from Vault"
echo "      uses: hashicorp/vault-action@v2"
echo "      with:"
echo "        url: $VAULT_ADDR"
echo "        method: jwt"
echo "        role: github-actions"
echo "        secrets: |"
echo "          secret/data/github-actions/dockerhub-credentials username | DOCKER_USERNAME ;"
echo "          secret/data/github-actions/dockerhub-credentials password | DOCKER_PASSWORD"
echo ""
echo "4. Ensure GitHub Actions has permissions to request OIDC tokens:"
echo "   Add 'id-token: write' to workflow permissions"
