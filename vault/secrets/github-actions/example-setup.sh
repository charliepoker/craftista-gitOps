#!/bin/bash

# Example script showing how to set up GitHub Actions secrets in Vault
# This is a demonstration script - replace with your actual values

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}GitHub Actions Secrets Setup Example${NC}"
echo "This script demonstrates how to populate Vault with GitHub Actions secrets"
echo ""

# Check if we're in dry-run mode
DRY_RUN="${1:-false}"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo -e "${YELLOW}Running in DRY RUN mode - no secrets will be created${NC}"
    echo ""
fi

# Example environment variables (replace with your actual values)
export DOCKERHUB_USERNAME="your-dockerhub-username"
export DOCKERHUB_ACCESS_TOKEN="dckr_pat_your-access-token-here"
export SONARQUBE_TOKEN="squ_your-sonarqube-token-here"
export SONARQUBE_URL="https://sonarqube.example.com"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
export SLACK_CHANNEL="#ci-cd"

# SSH key files (generate these first)
export GITOPS_PRIVATE_KEY_FILE="./gitops-deploy-key"
export GITOPS_PUBLIC_KEY_FILE="./gitops-deploy-key.pub"

# Optional Nexus credentials
export NEXUS_USERNAME="nexus-user"
export NEXUS_PASSWORD="nexus-password"
export NEXUS_URL="https://nexus.example.com"

echo -e "${GREEN}Step 1: Generate SSH key pair for GitOps repository${NC}"
if [[ ! -f "$GITOPS_PRIVATE_KEY_FILE" ]]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t ed25519 -C "github-actions@craftista" -f gitops-deploy-key -N ""
    echo "✓ SSH key pair generated"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Add the following public key to your craftista-gitops repository as a deploy key:${NC}"
    cat gitops-deploy-key.pub
    echo ""
    read -p "Press Enter after adding the deploy key to GitHub..."
else
    echo "✓ SSH key pair already exists"
fi

echo ""
echo -e "${GREEN}Step 2: Set up Vault connection${NC}"
echo "Make sure VAULT_ADDR and VAULT_TOKEN are set:"
echo "  export VAULT_ADDR=\"https://your-vault-server.com\""
echo "  export VAULT_TOKEN=\"your-vault-token\""
echo ""

if [[ -z "${VAULT_ADDR:-}" || -z "${VAULT_TOKEN:-}" ]]; then
    echo -e "${YELLOW}Warning: VAULT_ADDR and VAULT_TOKEN must be set before running the setup script${NC}"
    echo ""
fi

echo -e "${GREEN}Step 3: Run the GitHub Actions secrets setup script${NC}"
echo ""

# Navigate to scripts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/../../scripts" && pwd)"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "Command to run (dry-run):"
    echo "  cd $SCRIPTS_DIR"
    echo "  ./setup-github-actions-secrets.sh --from-env --dry-run"
    echo ""
    echo "Or using the general sync script:"
    echo "  ./sync-secrets.sh --type github-actions --from-env --dry-run"
else
    echo "Commands to run:"
    echo ""
    echo "Option 1 - Using dedicated GitHub Actions script:"
    echo "  cd $SCRIPTS_DIR"
    echo "  ./setup-github-actions-secrets.sh --from-env"
    echo ""
    echo "Option 2 - Using general sync script:"
    echo "  ./sync-secrets.sh --type github-actions --from-env"
    echo ""
    echo "Option 3 - Interactive mode:"
    echo "  ./setup-github-actions-secrets.sh --interactive"
fi

echo ""
echo -e "${GREEN}Step 4: Verify secrets in Vault${NC}"
echo "After running the setup script, verify the secrets were created:"
echo ""
echo "  vault kv list secret/github-actions/"
echo "  vault kv get secret/github-actions/dockerhub-credentials"
echo "  vault kv get secret/github-actions/sonarqube-token"
echo "  vault kv get secret/github-actions/gitops-deploy-key"
echo "  vault kv get secret/github-actions/slack-webhook-url"
echo ""

echo -e "${GREEN}Step 5: Test GitHub Actions integration${NC}"
echo "Once secrets are in Vault, your GitHub Actions workflows can access them using:"
echo "- GitHub OIDC authentication with Vault"
echo "- The github-actions-policy for authorization"
echo ""

echo -e "${BLUE}Security Notes:${NC}"
echo "- Never commit actual secret values to Git"
echo "- Rotate secrets regularly (every 90 days recommended)"
echo "- Monitor secret access through Vault audit logs"
echo "- Use access tokens instead of passwords where possible"
echo ""

if [[ "$DRY_RUN" != "--dry-run" ]]; then
    echo -e "${YELLOW}Ready to proceed? Make sure you have:${NC}"
    echo "1. ✓ Set VAULT_ADDR and VAULT_TOKEN environment variables"
    echo "2. ✓ Added the public key to GitHub as a deploy key"
    echo "3. ✓ Obtained all required tokens and credentials"
    echo "4. ✓ Reviewed the secret values above"
    echo ""
    read -p "Press Enter to continue with the actual setup, or Ctrl+C to cancel..."
    
    echo ""
    echo "Running setup script..."
    cd "$SCRIPTS_DIR"
    ./setup-github-actions-secrets.sh --from-env
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"