#!/usr/bin/env bash

################################################################################
# Promote to Production Script for Craftista GitOps
#
# This script promotes a Docker image from staging to production with:
# - Manual approval requirement
# - Image verification in DockerHub
# - Staging validation checks
# - Production overlay updates
# - Rollback capability
#
# Usage:
#   ./promote-to-prod.sh --service <service> --tag <tag> [options]
#
# Options:
#   --service        Service name (frontend, catalogue, voting, recommendation) [required]
#   --tag            Image tag to promote [required]
#   --skip-approval  Skip manual approval prompt (use with caution!)
#   --wait           Wait for ArgoCD to sync the change
#   --timeout        Timeout for ArgoCD sync in seconds [default: 600]
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
IMAGE_TAG=""
SKIP_APPROVAL=false
WAIT_FOR_SYNC=false
SYNC_TIMEOUT=600
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

verify_staging_deployment() {
    log_info "Verifying staging deployment..."

    local staging_overlay="${GITOPS_ROOT}/kubernetes/overlays/staging/${SERVICE}"
    local kustomization_file="${staging_overlay}/kustomization.yaml"

    if [[ ! -f "${kustomization_file}" ]]; then
        log_error "Staging kustomization file not found: ${kustomization_file}"
        exit 1
    fi

    # Check if staging is using the same tag
    local staging_tag
    staging_tag=$(yq eval '.images[0].newTag' "${kustomization_file}")

    if [[ "${staging_tag}" != "${IMAGE_TAG}" ]]; then
        log_error "Staging is not using the requested tag!"
        log_error "Staging tag: ${staging_tag}"
        log_error "Requested tag: ${IMAGE_TAG}"
        log_error "Please ensure the image has been deployed and validated in staging first."
        exit 1
    fi

    log_success "Staging is using tag: ${IMAGE_TAG}"

    # Check ArgoCD application health if kubectl is available
    if command -v kubectl &> /dev/null; then
        local app_name="craftista-${SERVICE}-staging"
        local health_status
        health_status=$(kubectl get application "${app_name}" -n argocd \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

        if [[ "${health_status}" == "Healthy" ]]; then
            log_success "Staging application is healthy"
        else
            log_warning "Staging application health: ${health_status}"
            log_warning "Consider verifying staging health before promoting to production"
        fi
    fi
}

request_approval() {
    if [[ "${SKIP_APPROVAL}" == "true" ]]; then
        log_warning "Skipping approval (--skip-approval flag used)"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would request approval"
        return 0
    fi

    echo ""
    echo "=========================================="
    echo "PRODUCTION DEPLOYMENT APPROVAL REQUIRED"
    echo "=========================================="
    echo ""
    echo "Service:    ${SERVICE}"
    echo "Image Tag:  ${IMAGE_TAG}"
    echo "Target:     PRODUCTION"
    echo ""
    echo "This will deploy to the production environment."
    echo "Please ensure:"
    echo "  ✓ Image has been tested in staging"
    echo "  ✓ All smoke tests have passed"
    echo "  ✓ Stakeholders have been notified"
    echo "  ✓ Rollback plan is ready"
    echo ""
    read -rp "Do you approve this production deployment? (yes/no): " approval

    if [[ "${approval}" != "yes" ]]; then
        log_error "Deployment not approved. Exiting."
        exit 1
    fi

    log_success "Deployment approved"
}

update_production_overlay() {
    log_info "Updating production overlay..."

    local prod_overlay="${GITOPS_ROOT}/kubernetes/overlays/prod/${SERVICE}"
    local kustomization_file="${prod_overlay}/kustomization.yaml"

    if [[ ! -f "${kustomization_file}" ]]; then
        log_error "Production kustomization file not found: ${kustomization_file}"
        exit 1
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would update ${kustomization_file} with tag: ${IMAGE_TAG}"
        return 0
    fi

    # Get current tag for comparison and rollback
    local current_tag
    current_tag=$(yq eval '.images[0].newTag' "${kustomization_file}")

    if [[ "${current_tag}" == "${IMAGE_TAG}" ]]; then
        log_warning "Production is already using tag: ${IMAGE_TAG}"
        log_info "No changes needed"
        return 0
    fi

    log_info "Updating image tag from ${current_tag} to ${IMAGE_TAG}..."
    log_info "Previous tag saved for rollback: ${current_tag}"

    # Save previous tag for potential rollback
    echo "${current_tag}" > "${GITOPS_ROOT}/.last-prod-tag-${SERVICE}"

    # Update the image tag
    yq eval ".images[0].newTag = \"${IMAGE_TAG}\"" -i "${kustomization_file}"

    log_success "Production overlay updated"
}

update_helm_values() {
    log_info "Updating Helm values for production..."

    local helm_values="${GITOPS_ROOT}/helm/charts/${SERVICE}/values-prod.yaml"

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
        git add kubernetes/overlays/prod/"${SERVICE}"/kustomization.yaml
        git add helm/charts/"${SERVICE}"/values-prod.yaml 2>/dev/null || true

        # Commit with descriptive message
        local commit_msg="Promote ${SERVICE} to production: ${IMAGE_TAG}

Promoted from staging environment
Service: ${SERVICE}
Image Tag: ${IMAGE_TAG}
Approved by: ${USER:-automation}
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)

This is a production deployment. Rollback available via:
./rollback.sh --service ${SERVICE}
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

    local app_name="craftista-${SERVICE}-prod"
    local elapsed=0

    log_info "Monitoring ArgoCD application: ${app_name}"
    log_warning "Note: Production apps may require manual sync in ArgoCD"

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

        if [[ "${sync_status}" == "OutOfSync" ]]; then
            log_warning "Application is OutOfSync. Manual sync may be required in ArgoCD UI."
        fi

        sleep 15
        elapsed=$((elapsed + 15))
    done

    log_error "Timeout waiting for ArgoCD sync after ${SYNC_TIMEOUT} seconds"
    log_error "Please check ArgoCD UI and manually sync if needed"
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
            --skip-approval)
                SKIP_APPROVAL=true
                shift
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

    log_info "Starting promotion to PRODUCTION..."
    log_info "Service: ${SERVICE}"
    log_info "Image Tag: ${IMAGE_TAG}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi

    # Check prerequisites
    check_prerequisites

    # Verify image exists
    verify_image_exists

    # Verify staging deployment
    verify_staging_deployment

    # Request approval
    request_approval

    # Update configurations
    update_production_overlay
    update_helm_values

    # Commit and push
    commit_and_push_changes

    # Wait for sync if requested
    if [[ "${WAIT_FOR_SYNC}" == "true" ]]; then
        wait_for_argocd_sync
    fi

    log_success "Promotion to production completed successfully!"
    echo ""
    echo "=========================================="
    echo "PRODUCTION DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "Service:      ${SERVICE}"
    echo "Image Tag:    ${IMAGE_TAG}"
    echo "Environment:  PRODUCTION"
    echo "Timestamp:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "Next steps:"
    echo "1. Monitor ArgoCD for sync status (may require manual sync)"
    echo "2. Verify application health in production"
    echo "3. Run smoke tests against production"
    echo "4. Monitor logs and metrics"
    echo "5. If issues occur, rollback with: ./rollback.sh --service ${SERVICE}"
    echo ""
    echo "Rollback information saved to: .last-prod-tag-${SERVICE}"
    echo "=========================================="
}

# Run main function
main "$@"
