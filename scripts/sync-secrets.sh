#!/usr/bin/env bash

################################################################################
# Vault Secrets Sync Script for Craftista GitOps
#
# This script populates Vault with secrets from environment variables or
# interactive prompts. It supports:
# - Application secrets (database credentials, API keys)
# - CI/CD secrets (DockerHub, SonarQube, GitHub)
# - Auto-generation of secure random values
#
# Usage:
#   ./sync-secrets.sh --environment <env> [options]
#
# Options:
#   --environment    Target environment (dev, staging, prod) [required]
#   --service        Specific service to sync (optional, syncs all if not specified)
#   --vault-addr     Vault server address [default: from VAULT_ADDR env]
#   --vault-token    Vault root token [default: from VAULT_TOKEN env]
#   --interactive    Prompt for secrets interactively
#   --from-file      Load secrets from file (JSON format)
#   --dry-run        Show what would be synced without actually syncing
#   --help           Show this help message
#
# Requirements:
#   - vault CLI installed
#   - VAULT_ADDR and VAULT_TOKEN environment variables set
#   - openssl for generating random secrets
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT=""
SERVICE=""
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
INTERACTIVE=false
FROM_FILE=""
DRY_RUN=false

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

    # Check openssl
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install openssl first."
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

    # Validate environment
    if [[ -z "${ENVIRONMENT}" ]]; then
        log_error "Environment is required. Use --environment flag."
        exit 1
    fi

    if [[ ! "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Invalid environment: ${ENVIRONMENT}. Must be dev, staging, or prod."
        exit 1
    fi

    log_success "All prerequisites met"
}

generate_random_secret() {
    local length="${1:-32}"
    openssl rand -base64 "${length}" | tr -d "=+/" | cut -c1-"${length}"
}

prompt_for_secret() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local secret_value

    if [[ -n "${default_value}" ]]; then
        read -rsp "${prompt_text} [default: ${default_value}]: " secret_value
    else
        read -rsp "${prompt_text}: " secret_value
    fi
    echo "" >&2

    if [[ -z "${secret_value}" && -n "${default_value}" ]]; then
        echo "${default_value}"
    else
        echo "${secret_value}"
    fi
}

sync_secret() {
    local path="$1"
    shift
    local -a key_values=("$@")

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would sync to ${path}: ${key_values[*]}"
        return 0
    fi

    log_info "Syncing secret to ${path}..."
    vault kv put "${path}" "${key_values[@]}"
    log_success "Secret synced: ${path}"
}

################################################################################
# Frontend Service Secrets
################################################################################

sync_frontend_secrets() {
    log_info "Syncing frontend service secrets for ${ENVIRONMENT}..."

    local session_secret
    local jwt_secret
    local api_key

    if [[ "${INTERACTIVE}" == "true" ]]; then
        session_secret=$(prompt_for_secret "Enter session secret" "$(generate_random_secret 32)")
        jwt_secret=$(prompt_for_secret "Enter JWT secret" "$(generate_random_secret 64)")
        api_key=$(prompt_for_secret "Enter API key" "$(generate_random_secret 32)")
    else
        session_secret="${FRONTEND_SESSION_SECRET:-$(generate_random_secret 32)}"
        jwt_secret="${FRONTEND_JWT_SECRET:-$(generate_random_secret 64)}"
        api_key="${FRONTEND_API_KEY:-$(generate_random_secret 32)}"
    fi

    sync_secret "secret/craftista/${ENVIRONMENT}/frontend/api-keys" \
        "session_secret=${session_secret}" \
        "jwt_secret=${jwt_secret}" \
        "api_key=${api_key}"

    sync_secret "secret/craftista/${ENVIRONMENT}/frontend/config" \
        "node_env=${ENVIRONMENT}" \
        "log_level=${FRONTEND_LOG_LEVEL:-info}" \
        "port=${FRONTEND_PORT:-3000}"
}

################################################################################
# Catalogue Service Secrets
################################################################################

sync_catalogue_secrets() {
    log_info "Syncing catalogue service secrets for ${ENVIRONMENT}..."

    local mongodb_uri
    local mongodb_username
    local mongodb_password
    local mongodb_database

    if [[ "${INTERACTIVE}" == "true" ]]; then
        mongodb_uri=$(prompt_for_secret "Enter MongoDB URI" "${CATALOGUE_MONGODB_URI:-}")
        mongodb_username=$(prompt_for_secret "Enter MongoDB username" "catalogue_user")
        mongodb_password=$(prompt_for_secret "Enter MongoDB password" "$(generate_random_secret 24)")
        mongodb_database=$(prompt_for_secret "Enter MongoDB database" "catalogue")
    else
        mongodb_uri="${CATALOGUE_MONGODB_URI:-mongodb://catalogue-mongodb:27017}"
        mongodb_username="${CATALOGUE_MONGODB_USERNAME:-catalogue_user}"
        mongodb_password="${CATALOGUE_MONGODB_PASSWORD:-$(generate_random_secret 24)}"
        mongodb_database="${CATALOGUE_MONGODB_DATABASE:-catalogue}"
    fi

    sync_secret "secret/craftista/${ENVIRONMENT}/catalogue/mongodb-credentials" \
        "username=${mongodb_username}" \
        "password=${mongodb_password}"

    sync_secret "secret/craftista/${ENVIRONMENT}/catalogue/mongodb-uri" \
        "uri=${mongodb_uri}" \
        "database=${mongodb_database}"

    sync_secret "secret/craftista/${ENVIRONMENT}/catalogue/config" \
        "flask_env=${ENVIRONMENT}" \
        "log_level=${CATALOGUE_LOG_LEVEL:-INFO}" \
        "data_source=mongodb"
}

################################################################################
# Voting Service Secrets
################################################################################

sync_voting_secrets() {
    log_info "Syncing voting service secrets for ${ENVIRONMENT}..."

    local postgres_uri
    local postgres_username
    local postgres_password
    local postgres_database

    if [[ "${INTERACTIVE}" == "true" ]]; then
        postgres_uri=$(prompt_for_secret "Enter PostgreSQL URI" "${VOTING_POSTGRES_URI:-}")
        postgres_username=$(prompt_for_secret "Enter PostgreSQL username" "voting_user")
        postgres_password=$(prompt_for_secret "Enter PostgreSQL password" "$(generate_random_secret 24)")
        postgres_database=$(prompt_for_secret "Enter PostgreSQL database" "voting")
    else
        postgres_uri="${VOTING_POSTGRES_URI:-postgresql://voting-postgres:5432}"
        postgres_username="${VOTING_POSTGRES_USERNAME:-voting_user}"
        postgres_password="${VOTING_POSTGRES_PASSWORD:-$(generate_random_secret 24)}"
        postgres_database="${VOTING_POSTGRES_DATABASE:-voting}"
    fi

    sync_secret "secret/craftista/${ENVIRONMENT}/voting/postgres-credentials" \
        "username=${postgres_username}" \
        "password=${postgres_password}"

    sync_secret "secret/craftista/${ENVIRONMENT}/voting/postgres-uri" \
        "uri=${postgres_uri}" \
        "database=${postgres_database}"

    sync_secret "secret/craftista/${ENVIRONMENT}/voting/config" \
        "spring_profiles_active=${ENVIRONMENT}" \
        "log_level=${VOTING_LOG_LEVEL:-INFO}"
}

################################################################################
# Recommendation Service Secrets
################################################################################

sync_recommendation_secrets() {
    log_info "Syncing recommendation service secrets for ${ENVIRONMENT}..."

    local redis_uri
    local redis_password

    if [[ "${INTERACTIVE}" == "true" ]]; then
        redis_uri=$(prompt_for_secret "Enter Redis URI" "${RECOMMENDATION_REDIS_URI:-}")
        redis_password=$(prompt_for_secret "Enter Redis password" "$(generate_random_secret 24)")
    else
        redis_uri="${RECOMMENDATION_REDIS_URI:-redis://recommendation-redis:6379}"
        redis_password="${RECOMMENDATION_REDIS_PASSWORD:-$(generate_random_secret 24)}"
    fi

    sync_secret "secret/craftista/${ENVIRONMENT}/recommendation/redis-credentials" \
        "password=${redis_password}"

    sync_secret "secret/craftista/${ENVIRONMENT}/recommendation/redis-uri" \
        "uri=${redis_uri}"

    sync_secret "secret/craftista/${ENVIRONMENT}/recommendation/config" \
        "environment=${ENVIRONMENT}" \
        "log_level=${RECOMMENDATION_LOG_LEVEL:-info}"
}

################################################################################
# Common Secrets
################################################################################

sync_common_secrets() {
    log_info "Syncing common secrets for ${ENVIRONMENT}..."

    local registry_username
    local registry_password

    if [[ "${INTERACTIVE}" == "true" ]]; then
        registry_username=$(prompt_for_secret "Enter Docker registry username" "${DOCKER_USERNAME:-}")
        registry_password=$(prompt_for_secret "Enter Docker registry password" "${DOCKER_PASSWORD:-}")
    else
        registry_username="${DOCKER_USERNAME:-}"
        registry_password="${DOCKER_PASSWORD:-}"
    fi

    if [[ -n "${registry_username}" && -n "${registry_password}" ]]; then
        sync_secret "secret/craftista/${ENVIRONMENT}/common/registry" \
            "username=${registry_username}" \
            "password=${registry_password}"
    else
        log_warning "Skipping registry credentials (not provided)"
    fi
}

################################################################################
# CI/CD Secrets
################################################################################

sync_cicd_secrets() {
    log_info "Syncing CI/CD secrets..."

    local dockerhub_username
    local dockerhub_password
    local sonarqube_token
    local gitops_deploy_key
    local slack_webhook_url

    if [[ "${INTERACTIVE}" == "true" ]]; then
        dockerhub_username=$(prompt_for_secret "Enter DockerHub username" "${DOCKERHUB_USERNAME:-}")
        dockerhub_password=$(prompt_for_secret "Enter DockerHub password" "${DOCKERHUB_PASSWORD:-}")
        sonarqube_token=$(prompt_for_secret "Enter SonarQube token" "${SONARQUBE_TOKEN:-}")
        gitops_deploy_key=$(prompt_for_secret "Enter GitOps deploy key" "${GITOPS_DEPLOY_KEY:-}")
        slack_webhook_url=$(prompt_for_secret "Enter Slack webhook URL" "${SLACK_WEBHOOK_URL:-}")
    else
        dockerhub_username="${DOCKERHUB_USERNAME:-}"
        dockerhub_password="${DOCKERHUB_PASSWORD:-}"
        sonarqube_token="${SONARQUBE_TOKEN:-}"
        gitops_deploy_key="${GITOPS_DEPLOY_KEY:-}"
        slack_webhook_url="${SLACK_WEBHOOK_URL:-}"
    fi

    if [[ -n "${dockerhub_username}" && -n "${dockerhub_password}" ]]; then
        sync_secret "secret/github-actions/dockerhub-credentials" \
            "username=${dockerhub_username}" \
            "password=${dockerhub_password}"
    else
        log_warning "Skipping DockerHub credentials (not provided)"
    fi

    if [[ -n "${sonarqube_token}" ]]; then
        sync_secret "secret/github-actions/sonarqube-token" \
            "token=${sonarqube_token}"
    else
        log_warning "Skipping SonarQube token (not provided)"
    fi

    if [[ -n "${gitops_deploy_key}" ]]; then
        sync_secret "secret/github-actions/gitops-deploy-key" \
            "private_key=${gitops_deploy_key}"
    else
        log_warning "Skipping GitOps deploy key (not provided)"
    fi

    if [[ -n "${slack_webhook_url}" ]]; then
        sync_secret "secret/github-actions/slack-webhook-url" \
            "url=${slack_webhook_url}"
    else
        log_warning "Skipping Slack webhook URL (not provided)"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --service)
                SERVICE="$2"
                shift 2
                ;;
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
            --interactive)
                INTERACTIVE=true
                shift
                ;;
            --from-file)
                FROM_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
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

    log_info "Starting secrets sync..."
    log_info "Environment: ${ENVIRONMENT}"
    log_info "Vault Address: ${VAULT_ADDR}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No secrets will be synced"
    fi

    # Check prerequisites
    check_prerequisites

    # Sync secrets based on service filter
    if [[ -z "${SERVICE}" || "${SERVICE}" == "frontend" ]]; then
        sync_frontend_secrets
    fi

    if [[ -z "${SERVICE}" || "${SERVICE}" == "catalogue" ]]; then
        sync_catalogue_secrets
    fi

    if [[ -z "${SERVICE}" || "${SERVICE}" == "voting" ]]; then
        sync_voting_secrets
    fi

    if [[ -z "${SERVICE}" || "${SERVICE}" == "recommendation" ]]; then
        sync_recommendation_secrets
    fi

    if [[ -z "${SERVICE}" ]]; then
        sync_common_secrets
    fi

    # Sync CI/CD secrets (only if no specific service is specified)
    if [[ -z "${SERVICE}" && "${ENVIRONMENT}" == "dev" ]]; then
        sync_cicd_secrets
    fi

    log_success "Secrets sync completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Verify secrets in Vault: vault kv list secret/craftista/${ENVIRONMENT}/"
    echo "2. Test secret access from a pod"
    echo "3. Update External Secrets or Vault Agent Injector configurations"
}

# Run main function
main "$@"
