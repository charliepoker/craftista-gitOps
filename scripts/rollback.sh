#!/usr/bin/env bash

################################################################################
# Rollback Script for Craftista GitOps
#
# This script rolls back a service to a previous Git commit or image tag by:
# - Reverting to a specific Git commit
# - Or updating to a specific previous image tag
# - Committing and pushing the rollback
# - Optionally waiting for ArgoCD to sync
#
# Usage:
#   ./rollback.sh --service <service> --environment <env> [options]
#
# Options:
#   --service        Service name (frontend, catalogue, voting, recommendation) [required]
#   --environment    Target environment (dev, staging, prod) [required]
#   --to-commit      Git commit SHA to rollback to
#   --to-tag         Image tag to rollback to
#   --steps          Number of commits to go back [default: 1]
#   --wait           Wait for ArgoCD to sync the change
#   --timeout        Timeout for ArgoCD sync in seconds [default: 300]
#   --dry-run        Show what would be changed without making changes
#   --help           Show this help message
#
# Requirements:
#   - git configured with push access to GitOps repository
#   - yq installed for YAML manipulation
#   - kubectl (optional, for ArgoCD sync monitoring)
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SERVICE=""
ENVIRONMENT=""
TO_COMMIT=""
TO_TAG=""
STEPS=1
WAIT_FOR_SYNC=false
SYNC_TIMEOUT=300
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

    # Check git
    if ! command -v git &> /dev/null; then
        log_error "git is not installed. Please install git first."
        exit 1
    fi

    # Check yq
    if ! command -v yq &> /dev/null; then
        log_error "yq is not installed. Please install yq first."
        log_info "Install with: brew install yq (macOS) or snap install yq (Linux)"
        exit 1
    fi

    # Validate service
    if [[ -z "${SERVICE}" ]]; then
        log_error "Service is required. Use --service flag."
        exit 1
    fi

    if [[ ! "${SERVICE}" =~ ^(frontend|catalogue|voting|recommendation)$ ]]; then
        log_error "Invalid service: ${SERVICE}. Must be frontend, catalogue, voting, or recommendation."
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

get_current_state() {
    log_info "Getting current state..."

    cd "${GITOPS_ROOT}"

    local overlay_path="kubernetes/overlays/${ENVIRONMENT}/${SERVICE}"
    local kustomization_file="${overlay_path}/kustomization.yaml"

    if [[ ! -f "${kustomization_file}" ]]; then
        log_error "Kustomization file not found: ${kustomization_file}"
        exit 1
    fi

    # Get current image tag
    local current_tag
    current_tag=$(yq eval '.images[0].newTag' "${kustomization_file}")

    # Get current commit
    local current_commit
    current_commit=$(git rev-parse HEAD)

    log_info "Current state:"
    log_info "  Commit: ${current_commit}"
    log_info "  Image Tag: ${current_tag}"

    echo "${current_tag}"
}

show_recent_deployments() {
    log_info "Recent deployments for ${SERVICE} in ${ENVIRONMENT}:"
    echo ""

    cd "${GITOPS_ROOT}"

    # Show last 10 commits affecting this service
    git log --oneline --max-count=10 \
        --grep="${SERVICE}" \
        --grep="${ENVIRONMENT}" \
        -- "kubernetes/overlays/${ENVIRONMENT}/${SERVICE}/" \
           "helm/charts/${SERVICE}/values-${ENVIRONMENT}.yaml" \
        || log_warning "No recent deployment history found"

    echo ""
}

determine_rollback_target() {
    log_info "Determining rollback target..."

    cd "${GITOPS_ROOT}"

    # If specific commit provided, use it
    if [[ -n "${TO_COMMIT}" ]]; then
        if git rev-parse "${TO_COMMIT}" &> /dev/null; then
            log_info "Rolling back to commit: ${TO_COMMIT}"
            echo "${TO_COMMIT}"
            return 0
        else
            log_error "Invalid commit: ${TO_COMMIT}"
            exit 1
        fi
    fi

    # If specific tag provided, we'll update to that tag
    if [[ -n "${TO_TAG}" ]]; then
        log_info "Rolling back to image tag: ${TO_TAG}"
        return 0
    fi

    # Otherwise, go back N steps in git history
    local target_commit
    target_commit=$(git log --oneline --max-count=$((STEPS + 1)) \
        --grep="${SERVICE}" \
        --grep="${ENVIRONMENT}" \
        -- "kubernetes/overlays/${ENVIRONMENT}/${SERVICE}/" \
           "helm/charts/${SERVICE}/values-${ENVIRONMENT}.yaml" \
        | tail -1 | awk '{print $1}')

    if [[ -z "${target_commit}" ]]; then
        log_error "Could not find commit to rollback to"
        log_info "Try specifying --to-commit or --to-tag explicitly"
        exit 1
    fi

    log_info "Rolling back ${STEPS} step(s) to commit: ${target_commit}"
    echo "${target_commit}"
}

rollback_to_commit() {
    local target_commit="$1"

    log_info "Rolling back to commit: ${target_commit}..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would rollback to commit: ${target_commit}"
        return 0
    fi

    cd "${GITOPS_ROOT}"

    # Get the files we need to restore
    local overlay_path="kubernetes/overlays/${ENVIRONMENT}/${SERVICE}"
    local helm_values="helm/charts/${SERVICE}/values-${ENVIRONMENT}.yaml"

    # Restore files from target commit
    log_info "Restoring files from commit ${target_commit}..."

    if git show "${target_commit}:${overlay_path}/kustomization.yaml" > /dev/null 2>&1; then
        git show "${target_commit}:${overlay_path}/kustomization.yaml" > "${overlay_path}/kustomization.yaml"
        log_success "Restored: ${overlay_path}/kustomization.yaml"
    fi

    if git show "${target_commit}:${helm_values}" > /dev/null 2>&1; then
        git show "${target_commit}:${helm_values}" > "${helm_values}"
        log_success "Restored: ${helm_values}"
    fi
}

rollback_to_tag() {
    local target_tag="$1"

    log_info "Rolling back to image tag: ${target_tag}..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would rollback to tag: ${target_tag}"
        return 0
    fi

    cd "${GITOPS_ROOT}"

    local overlay_path="kubernetes/overlays/${ENVIRONMENT}/${SERVICE}"
    local kustomization_file="${overlay_path}/kustomization.yaml"
    local helm_values="helm/charts/${SERVICE}/values-${ENVIRONMENT}.yaml"

    # Update kustomization
    if [[ -f "${kustomization_file}" ]]; then
        yq eval ".images[0].newTag = \"${target_tag}\"" -i "${kustomization_file}"
        log_success "Updated: ${kustomization_file}"
    fi

    # Update helm values
    if [[ -f "${helm_values}" ]]; then
        yq eval ".image.tag = \"${target_tag}\"" -i "${helm_values}"
        log_success "Updated: ${helm_values}"
    fi
}

request_confirmation() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would request confirmation"
        return 0
    fi

    echo ""
    echo "=========================================="
    echo "ROLLBACK CONFIRMATION REQUIRED"
    echo "=========================================="
    echo ""
    echo "Service:      ${SERVICE}"
    echo "Environment:  ${ENVIRONMENT}"

    if [[ -n "${TO_COMMIT}" ]]; then
        echo "Target:       Commit ${TO_COMMIT}"
    elif [[ -n "${TO_TAG}" ]]; then
        echo "Target:       Image tag ${TO_TAG}"
    else
        echo "Target:       ${STEPS} step(s) back"
    fi

    echo ""
    echo "This will rollback the service to a previous state."
    echo ""
    read -rp "Do you want to proceed with this rollback? (yes/no): " confirmation

    if [[ "${confirmation}" != "yes" ]]; then
        log_error "Rollback cancelled by user"
        exit 1
    fi

    log_success "Rollback confirmed"
}

commit_and_push_rollback() {
    log_info "Committing and pushing rollback..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would commit and push rollback"
        return 0
    fi

    cd "${GITOPS_ROOT}"

    # Check if there are changes
    if ! git diff --quiet; then
        log_info "Changes detected, committing..."

        # Configure git if needed
        if ! git config user.email &> /dev/null; then
            git config user.email "gitops-automation@craftista.com"
            git config user.name "GitOps Automation"
        fi

        # Stage changes
        git add "kubernetes/overlays/${ENVIRONMENT}/${SERVICE}/"
        git add "helm/charts/${SERVICE}/values-${ENVIRONMENT}.yaml" 2>/dev/null || true

        # Commit with descriptive message
        local commit_msg="Rollback ${SERVICE} in ${ENVIRONMENT}

Service: ${SERVICE}
Environment: ${ENVIRONMENT}"

        if [[ -n "${TO_COMMIT}" ]]; then
            commit_msg="${commit_msg}
Target Commit: ${TO_COMMIT}"
        elif [[ -n "${TO_TAG}" ]]; then
            commit_msg="${commit_msg}
Target Tag: ${TO_TAG}"
        else
            commit_msg="${commit_msg}
Steps Back: ${STEPS}"
        fi

        commit_msg="${commit_msg}
Performed by: ${USER:-automation}
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
"

        git commit -m "${commit_msg}"

        # Push changes
        log_info "Pushing rollback to remote..."
        if git push; then
            log_success "Rollback pushed successfully"
        else
            log_error "Failed to push rollback. Please check your git configuration and permissions."
            exit 1
        fi
    else
        log_info "No changes to commit"
    fi
}

wait_for_argocd_sync() {
    log_info "Waiting for ArgoCD to sync..."

    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl not available, cannot wait for ArgoCD sync"
        return 0
    fi

    local app_name="craftista-${SERVICE}-${ENVIRONMENT}"
    local elapsed=0

    log_info "Monitoring ArgoCD application: ${app_name}"

    while [[ ${elapsed} -lt ${SYNC_TIMEOUT} ]]; do
        # Check sync status
        local sync_status
        sync_status=$(kubectl get application "${app_name}" -n argocd \
            -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

        local health_status
        health_status=$(kubectl get application "${app_name}" -n argocd \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

        log_info "Sync: ${sync_status}, Health: ${health_status}"

        if [[ "${sync_status}" == "Synced" && "${health_status}" == "Healthy" ]]; then
            log_success "ArgoCD sync completed successfully"
            return 0
        fi

        sleep 10
        elapsed=$((elapsed + 10))
    done

    log_error "Timeout waiting for ArgoCD sync after ${SYNC_TIMEOUT} seconds"
    log_error "Please check ArgoCD UI for details"
    exit 1
}

################################################################################
# Main Execution
################################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --service)
                SERVICE="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --to-commit)
                TO_COMMIT="$2"
                shift 2
                ;;
            --to-tag)
                TO_TAG="$2"
                shift 2
                ;;
            --steps)
                STEPS="$2"
                shift 2
                ;;
            --wait)
                WAIT_FOR_SYNC=true
                shift
                ;;
            --timeout)
                SYNC_TIMEOUT="$2"
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

    log_info "Starting rollback procedure..."
    log_info "Service: ${SERVICE}"
    log_info "Environment: ${ENVIRONMENT}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi

    # Check prerequisites
    check_prerequisites

    # Show current state
    local current_tag
    current_tag=$(get_current_state)

    # Show recent deployments
    show_recent_deployments

    # Determine rollback target
    local target_commit
    if [[ -z "${TO_TAG}" ]]; then
        target_commit=$(determine_rollback_target)
    fi

    # Request confirmation
    request_confirmation

    # Perform rollback
    if [[ -n "${TO_TAG}" ]]; then
        rollback_to_tag "${TO_TAG}"
    else
        rollback_to_commit "${target_commit}"
    fi

    # Commit and push
    commit_and_push_rollback

    # Wait for sync if requested
    if [[ "${WAIT_FOR_SYNC}" == "true" ]]; then
        wait_for_argocd_sync
    fi

    log_success "Rollback completed successfully!"
    echo ""
    echo "=========================================="
    echo "ROLLBACK SUMMARY"
    echo "=========================================="
    echo "Service:      ${SERVICE}"
    echo "Environment:  ${ENVIRONMENT}"
    echo "Previous Tag: ${current_tag}"

    if [[ -n "${TO_TAG}" ]]; then
        echo "New Tag:      ${TO_TAG}"
    elif [[ -n "${TO_COMMIT}" ]]; then
        echo "Target:       Commit ${TO_COMMIT}"
    else
        echo "Steps Back:   ${STEPS}"
    fi

    echo "Timestamp:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "Next steps:"
    echo "1. Monitor ArgoCD for sync status"
    echo "2. Verify application health in ${ENVIRONMENT}"
    echo "3. Check application logs for errors"
    echo "4. Run smoke tests"
    echo "=========================================="
}

# Run main function
main "$@"
