#!/usr/bin/env bash

################################################################################
# Vault Setup Script for Craftista GitOps
#
# This script configures HashiCorp Vault with:
# - Vault policies for each microservice
# - Kubernetes authentication method
# - GitHub OIDC authentication method
# - Secret paths and structure
#
# Usage:
#   ./setup-vault.sh [--vault-addr <addr>] [--vault-token <token>]
#
# Options:
#   --vault-addr     Vault server address [default: from VAULT_ADDR env]
#   --vault-token    Vault root token [default: from VAULT_TOKEN env]
#   --github-org     GitHub organization [default: charliepoker]
#   --github-repo    GitHub repository [default: craftista]
#   --help           Show this help message
#
# Requirements:
#   - vault CLI installed
#   - kubectl configured with cluster access
#   - Vault server running and unsealed
#   - VAULT_ADDR and VAULT_TOKEN environment variables set
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
GITHUB_ORG="${GITHUB_ORG:-charliepoker}"
GITHUB_REPO="${GITHUB_REPO:-craftista}"
VAULT_NAMESPACE="vault"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

show_help() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //g'
    exit 0
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check vault CLI
    if ! command -v vault &> /dev/null; then
        log_error "vault CLI is not installed. Please install vault first."
        exit 1
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi

    # Check VAULT_TOKEN
    if [[ -z "${VAULT_TOKEN}" ]]; then
        log_error "VAULT_TOKEN environment variable is not set."
        exit 1
    fi

    # Test Vault connectivity
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault at ${VAULT_ADDR}. Please check VAULT_ADDR."
        exit 1
    fi

    log_success "All prerequisites met"
}

################################################################################
# Vault Policy Configuration
################################################################################

apply_vault_policies() {
    log_info "Applying Vault policies..."

    local policies_dir="${GITOPS_ROOT}/vault/policies"

    if [[ ! -d "${policies_dir}" ]]; then
        log_error "Policies directory not found: ${policies_dir}"
        exit 1
    fi

    # Apply each policy file
    for policy_file in "${policies_dir}"/*.hcl; do
        if [[ -f "${policy_file}" ]]; then
            local policy_name
            policy_name=$(basename "${policy_file}" .hcl)

            log_info "Applying policy: ${policy_name}"
            vault policy write "${policy_name}" "${policy_file}"
            log_success "Policy applied: ${policy_name}"
        fi
    done

    log_success "All Vault policies applied"
}

################################################################################
# Kubernetes Authentication
################################################################################

configure_kubernetes_auth() {
    log_info "Configuring Kubernetes authentication..."

    # Enable Kubernetes auth method if not already enabled
    if ! vault auth list | grep -q "kubernetes/"; then
        log_info "Enabling Kubernetes auth method..."
        vault auth enable kubernetes
    else
        log_info "Kubernetes auth method already enabled"
    fi

    # Get Kubernetes cluster information
    local k8s_host
    k8s_host=$(kubectl config view --raw --minify --flatten \
        -o jsonpath='{.clusters[0].cluster.server}')

    local k8s_ca_cert
    k8s_ca_cert=$(kubectl config view --raw --minify --flatten \
        -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

    # Get service account token
    local sa_token
    if kubectl get sa vault -n "${VAULT_NAMESPACE}" &> /dev/null; then
        sa_token=$(kubectl get secret -n "${VAULT_NAMESPACE}" \
            $(kubectl get sa vault -n "${VAULT_NAMESPACE}" \
            -o jsonpath='{.secrets[0].name}') \
            -o jsonpath='{.data.token}' | base64 -d)
    else
        log_warning "Vault service account not found. Using default token."
        sa_token=$(kubectl get secret -n default \
            $(kubectl get sa default -n default \
            -o jsonpath='{.secrets[0].name}') \
            -o jsonpath='{.data.token}' | base64 -d)
    fi

    # Configure Kubernetes auth
    log_info "Configuring Kubernetes auth backend..."
    vault write auth/kubernetes/config \
        kubernetes_host="${k8s_host}" \
        kubernetes_ca_cert="${k8s_ca_cert}" \
        token_reviewer_jwt="${sa_token}"

    log_success "Kubernetes auth configured"

    # Create roles for each service
    create_kubernetes_roles
}

create_kubernetes_roles() {
    log_info "Creating Kubernetes auth roles..."

    local services=("frontend" "catalogue" "voting" "recommendation")
    local environments=("dev" "staging" "prod")

    for service in "${services[@]}"; do
        log_info "Creating role for ${service}..."

        # Create role that allows access from all environments
        vault write "auth/kubernetes/role/${service}" \
            bound_service_account_names="${service}" \
            bound_service_account_namespaces="craftista-dev,craftista-staging,craftista-prod" \
            policies="${service}-policy" \
            ttl=24h

        log_success "Role created: ${service}"
    done

    log_success "All Kubernetes auth roles created"
}

################################################################################
# GitHub OIDC Authentication
################################################################################

configure_github_oidc_auth() {
    log_info "Configuring GitHub OIDC authentication..."

    # Enable JWT auth method if not already enabled
    if ! vault auth list | grep -q "jwt/"; then
        log_info "Enabling JWT auth method..."
        vault auth enable jwt
    else
        log_info "JWT auth method already enabled"
    fi

    # Configure JWT auth for GitHub OIDC
    log_info "Configuring JWT auth backend..."
    vault write auth/jwt/config \
        bound_issuer="https://token.actions.githubusercontent.com" \
        oidc_discovery_url="https://token.actions.githubusercontent.com"

    log_success "GitHub OIDC auth configured"

    # Create roles for GitHub Actions
    create_github_roles
}

create_github_roles() {
    log_info "Creating GitHub OIDC roles..."

    # General GitHub Actions role
    log_info "Creating github-actions role..."
    vault write auth/jwt/role/github-actions \
        role_type="jwt" \
        bound_audiences="https://github.com/${GITHUB_ORG}" \
        bound_claims_type="string" \
        bound_claims="repository=${GITHUB_ORG}/${GITHUB_REPO}" \
        user_claim="actor" \
        policies="github-actions-policy" \
        ttl=1h

    # Branch-specific roles
    for branch in "main" "develop" "staging"; do
        log_info "Creating github-actions-${branch} role..."
        vault write "auth/jwt/role/github-actions-${branch}" \
            role_type="jwt" \
            bound_audiences="https://github.com/${GITHUB_ORG}" \
            bound_claims_type="string" \
            bound_claims="repository=${GITHUB_ORG}/${GITHUB_REPO},ref=refs/heads/${branch}" \
            user_claim="actor" \
            policies="github-actions-policy" \
            ttl=1h
    done

    log_success "All GitHub OIDC roles created"
}

################################################################################
# Secret Path Initialization
################################################################################

initialize_secret_paths() {
    log_info "Initializing secret paths..."

    # Enable KV v2 secrets engine if not already enabled
    if ! vault secrets list | grep -q "secret/"; then
        log_info "Enabling KV v2 secrets engine..."
        vault secrets enable -path=secret kv-v2
    else
        log_info "KV v2 secrets engine already enabled"
    fi

    local services=("frontend" "catalogue" "voting" "recommendation")
    local environments=("dev" "staging" "prod")

    # Create placeholder secrets for each service and environment
    for env in "${environments[@]}"; do
        for service in "${services[@]}"; do
            log_info "Creating placeholder secret for ${service} in ${env}..."

            # Create a placeholder secret (will be populated by sync-secrets.sh)
            vault kv put "secret/craftista/${env}/${service}/config" \
                placeholder="true" \
                environment="${env}" \
                service="${service}" \
                created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                || log_warning "Failed to create placeholder for ${service}/${env}"
        done
    done

    # Create common secrets path
    for env in "${environments[@]}"; do
        log_info "Creating common secrets for ${env}..."
        vault kv put "secret/craftista/${env}/common/config" \
            placeholder="true" \
            environment="${env}" \
            created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            || log_warning "Failed to create common secrets for ${env}"
    done

    # Create GitHub Actions secrets path
    log_info "Creating GitHub Actions secrets path..."
    vault kv put "secret/github-actions/config" \
        placeholder="true" \
        created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        || log_warning "Failed to create GitHub Actions secrets"

    log_success "Secret paths initialized"
}

################################################################################
# Verification
################################################################################

verify_configuration() {
    log_info "Verifying Vault configuration..."

    # Check policies
    log_info "Checking policies..."
    local policies=("frontend-policy" "catalogue-policy" "voting-policy" "recommendation-policy" "github-actions-policy")
    for policy in "${policies[@]}"; do
        if vault policy read "${policy}" &> /dev/null; then
            log_success "Policy exists: ${policy}"
        else
            log_error "Policy missing: ${policy}"
        fi
    done

    # Check auth methods
    log_info "Checking auth methods..."
    if vault auth list | grep -q "kubernetes/"; then
        log_success "Kubernetes auth enabled"
    else
        log_error "Kubernetes auth not enabled"
    fi

    if vault auth list | grep -q "jwt/"; then
        log_success "JWT auth enabled"
    else
        log_error "JWT auth not enabled"
    fi

    # Check secrets engine
    log_info "Checking secrets engine..."
    if vault secrets list | grep -q "secret/"; then
        log_success "KV v2 secrets engine enabled"
    else
        log_error "KV v2 secrets engine not enabled"
    fi

    log_success "Verification complete"
}

################################################################################
# Main Execution
################################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vault-addr)
                VAULT_ADDR="$2"
                export VAULT_ADDR
                shift 2
                ;;
            --vault-token)
                VAULT_TOKEN="$2"
                export VAULT_TOKEN
                shift 2
                ;;
            --github-org)
                GITHUB_ORG="$2"
                shift 2
                ;;
            --github-repo)
                GITHUB_REPO="$2"
                shift 2
                ;;
            --help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done

    log_info "Starting Vault setup..."
    log_info "Vault Address: ${VAULT_ADDR}"
    log_info "GitHub Org: ${GITHUB_ORG}"
    log_info "GitHub Repo: ${GITHUB_REPO}"

    # Check prerequisites
    check_prerequisites

    # Apply configurations
    apply_vault_policies
    configure_kubernetes_auth
    configure_github_oidc_auth
    initialize_secret_paths

    # Verify configuration
    verify_configuration

    log_success "Vault setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Run ./sync-secrets.sh to populate secrets from environment variables"
    echo "2. Test authentication from a pod using Vault Agent Injector"
    echo "3. Test GitHub Actions authentication in a workflow"
    echo "4. Review audit logs to ensure proper access control"
}

# Run main function
main "$@"
