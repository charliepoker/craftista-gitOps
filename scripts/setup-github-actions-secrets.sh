#!/bin/bash

# setup-github-actions-secrets.sh
# Script to populate GitHub Actions CI/CD secrets in HashiCorp Vault
# 
# This script reads secret values from environment variables or prompts
# and stores them in Vault at the appropriate paths for GitHub Actions workflows.
#
# Usage:
#   ./setup-github-actions-secrets.sh [options]
#
# Options:
#   --vault-addr URL     Vault server address (default: $VAULT_ADDR)
#   --vault-token TOKEN  Vault authentication token (default: $VAULT_TOKEN)
#   --interactive        Prompt for all secret values interactively
#   --from-env           Read secret values from environment variables
#   --dry-run            Show what would be done without making changes
#   --help               Show this help message
#
# Environment Variables (when using --from-env):
#   DOCKERHUB_USERNAME          DockerHub username
#   DOCKERHUB_ACCESS_TOKEN      DockerHub access token
#   SONARQUBE_TOKEN            SonarQube authentication token
#   SONARQUBE_URL              SonarQube server URL
#   GITOPS_PRIVATE_KEY_FILE    Path to GitOps deploy private key file
#   GITOPS_PUBLIC_KEY_FILE     Path to GitOps deploy public key file
#   SLACK_WEBHOOK_URL          Slack webhook URL for notifications
#   SLACK_CHANNEL              Slack channel for notifications
#   NEXUS_USERNAME             Nexus repository username (optional)
#   NEXUS_PASSWORD             Nexus repository password (optional)
#   NEXUS_URL                  Nexus server URL (optional)

set -euo pipefail

# Default values
VAULT_ADDR="${VAULT_ADDR:-}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
INTERACTIVE=false
FROM_ENV=false
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_BASE_PATH="secret/data/github-actions"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
GitHub Actions Secrets Setup Script

This script populates HashiCorp Vault with secrets required for GitHub Actions CI/CD workflows.

Usage: $0 [options]

Options:
    --vault-addr URL     Vault server address (default: \$VAULT_ADDR)
    --vault-token TOKEN  Vault authentication token (default: \$VAULT_TOKEN)
    --interactive        Prompt for all secret values interactively
    --from-env           Read secret values from environment variables
    --dry-run            Show what would be done without making changes
    --help               Show this help message

Environment Variables (when using --from-env):
    DOCKERHUB_USERNAME          DockerHub username
    DOCKERHUB_ACCESS_TOKEN      DockerHub access token
    SONARQUBE_TOKEN            SonarQube authentication token
    SONARQUBE_URL              SonarQube server URL
    GITOPS_PRIVATE_KEY_FILE    Path to GitOps deploy private key file
    GITOPS_PUBLIC_KEY_FILE     Path to GitOps deploy public key file
    SLACK_WEBHOOK_URL          Slack webhook URL for notifications
    SLACK_CHANNEL              Slack channel for notifications
    NEXUS_USERNAME             Nexus repository username (optional)
    NEXUS_PASSWORD             Nexus repository password (optional)
    NEXUS_URL                  Nexus server URL (optional)

Examples:
    # Interactive mode
    $0 --interactive

    # From environment variables
    export DOCKERHUB_USERNAME="myuser"
    export DOCKERHUB_ACCESS_TOKEN="dckr_pat_..."
    $0 --from-env

    # Dry run to see what would be done
    $0 --from-env --dry-run

Prerequisites:
    - Vault CLI installed and in PATH
    - Vault server accessible and unsealed
    - Valid Vault token with write permissions to secret/data/github-actions/*
    - GitHub Actions policy applied in Vault

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vault-addr)
            VAULT_ADDR="$2"
            shift 2
            ;;
        --vault-token)
            VAULT_TOKEN="$2"
            shift 2
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --from-env)
            FROM_ENV=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if vault CLI is installed
    if ! command -v vault &> /dev/null; then
        log_error "Vault CLI is not installed or not in PATH"
        log_error "Please install Vault CLI: https://www.vaultproject.io/downloads"
        exit 1
    fi
    
    # Check Vault address
    if [[ -z "$VAULT_ADDR" ]]; then
        log_error "VAULT_ADDR is not set"
        log_error "Please set VAULT_ADDR environment variable or use --vault-addr option"
        exit 1
    fi
    
    # Check Vault token
    if [[ -z "$VAULT_TOKEN" ]]; then
        log_error "VAULT_TOKEN is not set"
        log_error "Please set VAULT_TOKEN environment variable or use --vault-token option"
        exit 1
    fi
    
    # Test Vault connectivity
    if ! vault auth -method=token token="$VAULT_TOKEN" &> /dev/null; then
        log_error "Cannot authenticate with Vault"
        log_error "Please check VAULT_ADDR and VAULT_TOKEN"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Prompt for secret value
prompt_secret() {
    local prompt="$1"
    local var_name="$2"
    local is_multiline="${3:-false}"
    
    if [[ "$is_multiline" == "true" ]]; then
        echo -n "$prompt (press Ctrl+D when done): "
        local value
        value=$(cat)
        echo
    else
        echo -n "$prompt: "
        read -s value
        echo
    fi
    
    if [[ -z "$value" ]]; then
        log_warning "Empty value provided for $var_name"
        return 1
    fi
    
    eval "$var_name=\"\$value\""
    return 0
}

# Read secret from file
read_file_content() {
    local file_path="$1"
    
    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        return 1
    fi
    
    cat "$file_path"
}

# Write secret to Vault
write_vault_secret() {
    local path="$1"
    shift
    local key_value_pairs=("$@")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would write to $path:"
        for pair in "${key_value_pairs[@]}"; do
            local key="${pair%%=*}"
            echo "  $key=***"
        done
        return 0
    fi
    
    local vault_cmd="vault kv put $path"
    for pair in "${key_value_pairs[@]}"; do
        vault_cmd="$vault_cmd $pair"
    done
    
    if eval "$vault_cmd" &> /dev/null; then
        log_success "Successfully wrote secret to $path"
        return 0
    else
        log_error "Failed to write secret to $path"
        return 1
    fi
}

# Setup DockerHub credentials
setup_dockerhub_credentials() {
    log_info "Setting up DockerHub credentials..."
    
    local username password
    
    if [[ "$FROM_ENV" == "true" ]]; then
        username="${DOCKERHUB_USERNAME:-}"
        password="${DOCKERHUB_ACCESS_TOKEN:-}"
        
        if [[ -z "$username" || -z "$password" ]]; then
            log_error "DOCKERHUB_USERNAME and DOCKERHUB_ACCESS_TOKEN must be set when using --from-env"
            return 1
        fi
    elif [[ "$INTERACTIVE" == "true" ]]; then
        prompt_secret "DockerHub username" username || return 1
        prompt_secret "DockerHub access token" password || return 1
    else
        log_error "Must use either --interactive or --from-env mode"
        return 1
    fi
    
    write_vault_secret "$SECRETS_BASE_PATH/dockerhub-credentials" \
        "username=$username" \
        "password=$password" \
        "registry=docker.io"
}

# Setup SonarQube token
setup_sonarqube_token() {
    log_info "Setting up SonarQube token..."
    
    local token url
    
    if [[ "$FROM_ENV" == "true" ]]; then
        token="${SONARQUBE_TOKEN:-}"
        url="${SONARQUBE_URL:-}"
        
        if [[ -z "$token" || -z "$url" ]]; then
            log_error "SONARQUBE_TOKEN and SONARQUBE_URL must be set when using --from-env"
            return 1
        fi
    elif [[ "$INTERACTIVE" == "true" ]]; then
        prompt_secret "SonarQube authentication token" token || return 1
        prompt_secret "SonarQube server URL" url || return 1
    else
        log_error "Must use either --interactive or --from-env mode"
        return 1
    fi
    
    write_vault_secret "$SECRETS_BASE_PATH/sonarqube-token" \
        "token=$token" \
        "url=$url" \
        "organization=craftista"
}

# Setup GitOps deploy key
setup_gitops_deploy_key() {
    log_info "Setting up GitOps deploy key..."
    
    local private_key public_key
    
    if [[ "$FROM_ENV" == "true" ]]; then
        local private_key_file="${GITOPS_PRIVATE_KEY_FILE:-}"
        local public_key_file="${GITOPS_PUBLIC_KEY_FILE:-}"
        
        if [[ -z "$private_key_file" || -z "$public_key_file" ]]; then
            log_error "GITOPS_PRIVATE_KEY_FILE and GITOPS_PUBLIC_KEY_FILE must be set when using --from-env"
            return 1
        fi
        
        private_key=$(read_file_content "$private_key_file") || return 1
        public_key=$(read_file_content "$public_key_file") || return 1
    elif [[ "$INTERACTIVE" == "true" ]]; then
        echo "Please paste the private key content (press Ctrl+D when done):"
        private_key=$(cat)
        
        prompt_secret "GitOps deploy public key" public_key || return 1
    else
        log_error "Must use either --interactive or --from-env mode"
        return 1
    fi
    
    write_vault_secret "$SECRETS_BASE_PATH/gitops-deploy-key" \
        "private_key=$private_key" \
        "public_key=$public_key" \
        "repository=charliepoker/craftista-gitops"
}

# Setup Slack webhook
setup_slack_webhook() {
    log_info "Setting up Slack webhook..."
    
    local webhook_url channel
    
    if [[ "$FROM_ENV" == "true" ]]; then
        webhook_url="${SLACK_WEBHOOK_URL:-}"
        channel="${SLACK_CHANNEL:-#ci-cd}"
        
        if [[ -z "$webhook_url" ]]; then
            log_error "SLACK_WEBHOOK_URL must be set when using --from-env"
            return 1
        fi
    elif [[ "$INTERACTIVE" == "true" ]]; then
        prompt_secret "Slack webhook URL" webhook_url || return 1
        prompt_secret "Slack channel (default: #ci-cd)" channel
        channel="${channel:-#ci-cd}"
    else
        log_error "Must use either --interactive or --from-env mode"
        return 1
    fi
    
    write_vault_secret "$SECRETS_BASE_PATH/slack-webhook-url" \
        "webhook_url=$webhook_url" \
        "channel=$channel" \
        "username=GitHub Actions"
}

# Setup Nexus credentials (optional)
setup_nexus_credentials() {
    log_info "Setting up Nexus credentials (optional)..."
    
    local username password url
    
    if [[ "$FROM_ENV" == "true" ]]; then
        username="${NEXUS_USERNAME:-}"
        password="${NEXUS_PASSWORD:-}"
        url="${NEXUS_URL:-}"
        
        if [[ -z "$username" && -z "$password" && -z "$url" ]]; then
            log_info "Nexus credentials not provided, skipping..."
            return 0
        fi
        
        if [[ -z "$username" || -z "$password" || -z "$url" ]]; then
            log_error "All Nexus credentials (NEXUS_USERNAME, NEXUS_PASSWORD, NEXUS_URL) must be set if any are provided"
            return 1
        fi
    elif [[ "$INTERACTIVE" == "true" ]]; then
        echo "Nexus credentials are optional. Press Enter to skip or provide values:"
        prompt_secret "Nexus username (optional)" username
        
        if [[ -n "$username" ]]; then
            prompt_secret "Nexus password" password || return 1
            prompt_secret "Nexus server URL" url || return 1
        else
            log_info "Skipping Nexus credentials setup"
            return 0
        fi
    else
        log_error "Must use either --interactive or --from-env mode"
        return 1
    fi
    
    write_vault_secret "$SECRETS_BASE_PATH/nexus-credentials" \
        "username=$username" \
        "password=$password" \
        "url=$url"
}

# Verify secrets were written correctly
verify_secrets() {
    log_info "Verifying secrets were written correctly..."
    
    local paths=(
        "$SECRETS_BASE_PATH/dockerhub-credentials"
        "$SECRETS_BASE_PATH/sonarqube-token"
        "$SECRETS_BASE_PATH/gitops-deploy-key"
        "$SECRETS_BASE_PATH/slack-webhook-url"
    )
    
    # Add Nexus path if it exists
    if vault kv get "$SECRETS_BASE_PATH/nexus-credentials" &> /dev/null; then
        paths+=("$SECRETS_BASE_PATH/nexus-credentials")
    fi
    
    local failed=false
    for path in "${paths[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would verify $path"
        elif vault kv get "$path" &> /dev/null; then
            log_success "Verified: $path"
        else
            log_error "Failed to verify: $path"
            failed=true
        fi
    done
    
    if [[ "$failed" == "true" ]]; then
        return 1
    fi
    
    return 0
}

# Main function
main() {
    log_info "Starting GitHub Actions secrets setup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Validate mode selection
    if [[ "$INTERACTIVE" == "false" && "$FROM_ENV" == "false" ]]; then
        log_error "Must specify either --interactive or --from-env mode"
        show_help
        exit 1
    fi
    
    if [[ "$INTERACTIVE" == "true" && "$FROM_ENV" == "true" ]]; then
        log_error "Cannot use both --interactive and --from-env modes"
        show_help
        exit 1
    fi
    
    # Setup secrets
    local failed=false
    
    setup_dockerhub_credentials || failed=true
    setup_sonarqube_token || failed=true
    setup_gitops_deploy_key || failed=true
    setup_slack_webhook || failed=true
    setup_nexus_credentials || failed=true
    
    if [[ "$failed" == "true" ]]; then
        log_error "Some secrets failed to setup"
        exit 1
    fi
    
    # Verify secrets
    verify_secrets || {
        log_error "Secret verification failed"
        exit 1
    }
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed successfully"
        log_info "Run without --dry-run to actually create the secrets"
    else
        log_success "All GitHub Actions secrets have been successfully configured in Vault"
        log_info "Secrets are available at: $SECRETS_BASE_PATH/*"
        log_info "GitHub Actions workflows can now access these secrets using the github-actions-policy"
    fi
}

# Run main function
main "$@"