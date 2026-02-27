#!/bin/bash
set -e

echo "🚀 Deploying Craftista Staging Environment"
echo "=========================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check if we're connected to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"
echo

STAGING_APPS_DIR="argocd/applications/clusters/homelab/staging"

# Step 1: Create namespace if it doesn't exist
echo "📦 Step 1: Creating namespace..."
kubectl apply -f kubernetes/overlays/homelab/staging/namespace.yaml
echo

# Step 2: Deploy dependencies (MongoDB, PostgreSQL, Redis)
echo "🗄️  Step 2: Deploying dependencies..."
if [ ! -f "${STAGING_APPS_DIR}/deps-app.yaml" ]; then
    echo -e "${RED}❌ Missing ${STAGING_APPS_DIR}/deps-app.yaml (cannot deploy dependencies)${NC}"
    exit 1
fi
kubectl apply -f "${STAGING_APPS_DIR}/deps-app.yaml"
echo -e "${YELLOW}⏳ Waiting for dependencies to be ready (this may take a few minutes)...${NC}"
sleep 10
echo

# Step 3: Deploy ArgoCD applications for staging
echo "🎯 Step 3: Deploying ArgoCD applications..."

APPS=("bootstrap-app" "secrets-app" "catalogue-app" "frontend-app" "voting-app" "recommendation-app")

for app in "${APPS[@]}"; do
    echo "  📝 Applying $app..."
    kubectl apply -f "${STAGING_APPS_DIR}/$app.yaml"
done
echo

# Step 4: Wait for ArgoCD to sync
echo "⏳ Step 4: Waiting for ArgoCD to sync applications..."
sleep 15

# Step 5: Check application status
echo "📊 Step 5: Checking application status..."
echo
kubectl get applications -n argocd -l environment=staging -o wide
echo

# Step 6: Check pod status
echo "🔍 Step 6: Checking pod status in staging namespace..."
echo
kubectl get pods -n craftista-staging
echo

# Step 7: Display service endpoints
echo "🌐 Step 7: Service endpoints:"
echo
kubectl get ingress -n craftista-staging
echo

echo -e "${GREEN}✅ Staging deployment initiated!${NC}"
echo
echo "📝 Next steps:"
echo "  1. Monitor ArgoCD sync status: kubectl get applications -n argocd -l environment=staging"
echo "  2. Check pod health: kubectl get pods -n craftista-staging -w"
echo "  3. View logs: kubectl logs -n craftista-staging -l app=<service-name>"
echo "  4. Access ArgoCD UI to monitor deployment progress"
echo
echo "🔗 To promote from dev to staging, use: ./scripts/promote-to-staging.sh"
