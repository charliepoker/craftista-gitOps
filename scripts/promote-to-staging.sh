#!/usr/bin/env bash

################################################################################
# Promote to Staging Script for Craftista GitOps
#
# This script promotes a Docker image from dev to staging by:
# - Verifying the image exists in DockerHub
# - Updating the staging overlay with the new image tag
# - Committing and pushing changes to the GitOps repository
# - Optionally waiting for ArgoCD to sync
#
# Usage:
#   ./promote-to-staging.sh --service <service> --tag <tag> [options]
#
# Options:
#   --service        Service name (frontend, catalogue, voting, recommendation) [required]
#   --tag            Image tag to promote [required]
#   --wait           Wait for ArgoCD to sync the change
#   --timeout        Timeout for ArgoCD sync in seconds [default: 300]
#   --dry-run        Show what would be changed without making changes
#   --help           Show this help message
#
# Requirements:
#   - git configured with push access to GitOps repository
#   - yq installed for YAML manipulation
#   - docker CLI (optional, for image verification)
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
IMAGE_TAG=""
WAIT_FOR_SYNC=false
SYNC_TIMEOUT=300
DRY_RUN=false
DOCKER_REGISTRY="8060633493"

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

    # Validate image tag
    if [[ -z "${IMAGE_TAG}" ]]; then
        log_error "Image tag is required. Use --tag flag."
        exit 1
    fi

    log_success "All prerequisites met"
}

verify_image_exists() {
    log_info "Verifying image exists in DockerHub..."

    local image_name="${DOCKER_REGISTRY}/craftista-${SERVICE}:${IMAGE_TAG}"

    # Try to pull image manifest (doesn't download layers)
    if command -v docker &> /dev/null; then
        if docker manifest inspect "${image_name}" &> /dev/null; then
            log_success "Image verified: ${image_name}"
            return 0
        else
            log_error "Image not found: ${image_name}"
            log_error "Please ensure the image has been built and pushed to DockerHub"
            exit 1
        fi
    else
        log_warning "Docker CLI not available, skipping image verification"
        log_warning "Assuming image exists: ${image_name}"
    fi
}

get_current_dev_tag() {
    log_info "Getting current dev image tag..."

    local dev_overlay="${GITOPS_ROOT}/kubernetes/overlays/dev/${SERVICE}"
    local kustomization_file="${dev_overlay}/kustomization.yaml"

    if [[ ! -f "${kustomization_file}" ]]; then
        log_error "Dev kustomization file not found: ${kustomization_file}"
        exit 1
    fi

    # Extract current image tag from kustomization
    local current_tag
    current_tag=$(yq eval '.images[0].newTag' "${kustomization_file}")

    if [[ -z "${current_tag}" || "${current_tag}" == "null" ]]; then
        log_warning "Could not determine current dev tag"
        return 1
    fi

    log_info "Current dev tag: ${current_tag}"
    echo "${current_tag}"
}

update_staging_overlay() {
    log_info "Updating staging overlay..."

    local staging_overlay="${GITOPS_ROOT}/kubernetes/overlays/staging/${SERVICE}"
    local kustomization_file="${staging_overlay}/kustomization.yaml"

    if [[ ! -f "${kustomization_file}" ]]; then
        log_error "Staging kustomization file not found: ${kustomization_file}"
        exit 1
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would update ${kustomization_file} with tag: ${IMAGE_TAG}"
        return 0
    fi

    # Get current tag for comparison
    local current_tag
    current_tag=$(yq eval '.images[0].newTag' "${kustomization_file}")

    if [[ "${current_tag}" == "${IMAGE_TAG}" ]]; then
        log_warning "Staging is already using tag: ${IMAGE_TAG}"
        log_info "No changes needed"
        return 0
    fi

    log_info "Updating image tag from ${current_tag} to ${IMAGE_TAG}..."

    # Update the image tag
    yq eval ".images[0].newTag = \"${IMAGE_TAG}\"" -i "${kustomization_file}"

    log_success "Staging overlay updated"
}

update_helm_values() {
    log_info "Updating Helm values for staging..."

    local helm_values="${GITOPS_ROOT}/helm/charts/${SERVICE}/values-staging.yaml"

    if [[ ! -f "${helm_values}" ]]; then
        log_warning "Helm values file not found: ${helm_values}"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would update ${helm_values} with tag: ${IMAGE_TAG}"
        return 0
    fi

    # Get current tag
    local current_tag
    current_tag=$(yq eval '.image.tag' "${helm_values}")

    if [[ "${current_tag}" == "${IMAGE_TAG}" ]]; then
        log_info "Helm values already using tag: ${IMAGE_TAG}"
        return 0
    fi

    log_info "Updating Helm image tag from ${current_tag} to ${IMAGE_TAG}..."

    # Update the image tag
    yq eval ".image.tag = \"${IMAGE_TAG}\"" -i "${helm_values}"

    log_success "Helm values updated"
}

commit_and_push_changes() {
    log_info "Committing and pushing changes..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would commit and push changes"
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
        git add kubernetes/overlays/staging/"${SERVICE}"/kustomization.yaml
        git add helm/charts/"${SERVICE}"/values-staging.yaml 2>/dev/null || true

        # Commit with descriptive message
        local commit_msg="Promote ${SERVICE} to staging: ${IMAGE_TAG}

Promoted from dev environment
Service: ${SERVICE}
Image Tag: ${IMAGE_TAG}
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
"
        git commit -m "${commit_msg}"

        # Push changes
        log_info "Pushing changes to remote..."
        if git push; then
            log_success "Changes pushed successfully"
        else
            log_error "Failed to push changes. Please check your git configuration and permissions."
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

    local app_name="craftista-${SERVICE}-staging"
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
            --tag)
                IMAGE_TAG="$2"
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

    log_info "Starting promotion to staging..."
    log_info "Service: ${SERVICE}"
    log_info "Image Tag: ${IMAGE_TAG}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi

    # Check prerequisites
    check_prerequisites

    # Verify image exists
    verify_image_exists

    # Update configurations
    update_staging_overlay
    update_helm_values

    # Commit and push
    commit_and_push_changes

    # Wait for sync if requested
    if [[ "${WAIT_FOR_SYNC}" == "true" ]]; then
        wait_for_argocd_sync
    fi

    log_success "Promotion to staging completed successfully!"
    echo ""
    echo "Summary:"
    echo "  Service: ${SERVICE}"
    echo "  Image Tag: ${IMAGE_TAG}"
    echo "  Environment: staging"
    echo ""
    echo "Next steps:"
    echo "1. Monitor ArgoCD for sync status"
    echo "2. Verify application health in staging"
    echo "3. Run smoke tests against staging environment"
    echo "4. If successful, promote to production using ./promote-to-prod.sh"
}

# Run main function
main "$@"
