#!/usr/bin/env bash

################################################################################
# ArgoCD Setup Script for Craftista GitOps
#
# This script installs and configures ArgoCD in an EKS cluster with:
# - High availability deployment
# - RBAC configuration
# - Project and application setup
# - Ingress configuration
#
# Usage:
#   ./setup-argocd.sh [--environment <env>] [--domain <domain>]
#
# Options:
#   --environment    Target environment (dev, staging, prod) [default: dev]
#   --domain         Base domain for ingress [default: webdemoapp.com]
#   --skip-install   Skip ArgoCD installation (only configure)
#   --help           Show this help message
#
# Requirements:
#   - kubectl configured with EKS cluster access
#   - helm 3.x installed
#   - Valid kubeconfig for target cluster
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="${ENVIRONMENT:-dev}"
DOMAIN="${DOMAIN:-webdemoapp.com}"
SKIP_INSTALL=false
ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="5.51.6"

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

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install helm 3.x first."
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi

    log_success "All prerequisites met"
}

################################################################################
# ArgoCD Installation
################################################################################

install_argocd() {
    log_info "Installing ArgoCD version ${ARGOCD_VERSION}..."

    # Create namespace
    if ! kubectl get namespace "${ARGOCD_NAMESPACE}" &> /dev/null; then
        log_info "Creating namespace ${ARGOCD_NAMESPACE}..."
        kubectl create namespace "${ARGOCD_NAMESPACE}"
    else
        log_info "Namespace ${ARGOCD_NAMESPACE} already exists"
    fi

    # Add ArgoCD Helm repository
    log_info "Adding ArgoCD Helm repository..."
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update

    # Install or upgrade ArgoCD
    log_info "Installing/upgrading ArgoCD..."
    helm upgrade --install argocd argo/argo-cd \
        --namespace "${ARGOCD_NAMESPACE}" \
        --version "${ARGOCD_VERSION}" \
        --set server.service.type=LoadBalancer \
        --set server.extraArgs[0]="--insecure" \
        --set configs.params."server\.insecure"=true \
        --wait \
        --timeout 10m

    log_success "ArgoCD installed successfully"
}

wait_for_argocd() {
    log_info "Waiting for ArgoCD to be ready..."

    # Wait for deployments
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server \
        deployment/argocd-repo-server \
        deployment/argocd-applicationset-controller \
        -n "${ARGOCD_NAMESPACE}"

    log_success "ArgoCD is ready"
}

get_argocd_password() {
    log_info "Retrieving ArgoCD admin password..."

    # Get initial admin password
    ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" | base64 -d)

    log_success "ArgoCD admin password retrieved"
    echo ""
    echo "=========================================="
    echo "ArgoCD Admin Credentials:"
    echo "Username: admin"
    echo "Password: ${ARGOCD_PASSWORD}"
    echo "=========================================="
    echo ""
}

configure_argocd_ingress() {
    log_info "Configuring ArgoCD ingress..."

    local ingress_host
    case "${ENVIRONMENT}" in
        dev)
            ingress_host="argocd.dev.${DOMAIN}"
            ;;
        staging)
            ingress_host="argocd.staging.${DOMAIN}"
            ;;
        prod)
            ingress_host="argocd.${DOMAIN}"
            ;;
        *)
            log_error "Invalid environment: ${ENVIRONMENT}"
            exit 1
            ;;
    esac

    log_info "Creating ingress for ${ingress_host}..."

    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: ${ARGOCD_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  rules:
  - host: ${ingress_host}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
  tls:
  - hosts:
    - ${ingress_host}
    secretName: argocd-server-tls
EOF

    log_success "Ingress configured for ${ingress_host}"
}

################################################################################
# ArgoCD Configuration
################################################################################

apply_argocd_projects() {
    log_info "Applying ArgoCD projects..."

    local project_file="${GITOPS_ROOT}/argocd/projects/craftista-${ENVIRONMENT}.yaml"

    if [[ -f "${project_file}" ]]; then
        kubectl apply -f "${project_file}"
        log_success "Applied project: craftista-${ENVIRONMENT}"
    else
        log_warning "Project file not found: ${project_file}"
    fi
}

apply_argocd_applications() {
    log_info "Applying ArgoCD applications for ${ENVIRONMENT} environment..."

    local apps_dir="${GITOPS_ROOT}/argocd/applications/${ENVIRONMENT}"

    if [[ -d "${apps_dir}" ]]; then
        kubectl apply -f "${apps_dir}/"
        log_success "Applied applications from ${apps_dir}"
    else
        log_warning "Applications directory not found: ${apps_dir}"
    fi
}

configure_argocd_rbac() {
    log_info "Configuring ArgoCD RBAC..."

    local rbac_file="${GITOPS_ROOT}/argocd/install/argocd-rbac-cm.yaml"

    if [[ -f "${rbac_file}" ]]; then
        kubectl apply -f "${rbac_file}"
        log_success "RBAC configuration applied"
    else
        log_warning "RBAC configuration file not found: ${rbac_file}"
    fi
}

configure_argocd_cm() {
    log_info "Configuring ArgoCD ConfigMap..."

    local cm_file="${GITOPS_ROOT}/argocd/install/argocd-cm.yaml"

    if [[ -f "${cm_file}" ]]; then
        kubectl apply -f "${cm_file}"
        log_success "ConfigMap applied"
    else
        log_warning "ConfigMap file not found: ${cm_file}"
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
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --skip-install)
                SKIP_INSTALL=true
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

    log_info "Starting ArgoCD setup for ${ENVIRONMENT} environment..."
    log_info "Domain: ${DOMAIN}"

    # Check prerequisites
    check_prerequisites

    # Install ArgoCD if not skipped
    if [[ "${SKIP_INSTALL}" == "false" ]]; then
        install_argocd
        wait_for_argocd
        get_argocd_password
    else
        log_info "Skipping ArgoCD installation"
    fi

    # Configure ArgoCD
    configure_argocd_cm
    configure_argocd_rbac
    configure_argocd_ingress

    # Apply projects and applications
    apply_argocd_projects
    apply_argocd_applications

    log_success "ArgoCD setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Access ArgoCD UI at: https://argocd.${ENVIRONMENT}.${DOMAIN}"
    echo "2. Login with username 'admin' and the password shown above"
    echo "3. Verify that all applications are syncing correctly"
    echo "4. Configure GitHub webhook for automatic sync (optional)"
}

# Run main function
main "$@"
