#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Promote Craftista from Dev to Staging${NC}"
echo "=========================================="
echo

# Services to promote
SERVICES=("catalogue" "frontend" "voting" "recommendation")

# Function to get current image tag from dev
get_dev_image_tag() {
    local service=$1
    local tag=$(grep -A 2 "images:" "kubernetes/overlays/homelab/dev/$service/kustomization.yaml" | grep "newTag:" | tail -1 | awk '{print $2}')
    echo "$tag"
}

# Function to update staging image tag
update_staging_image_tag() {
    local service=$1
    local new_tag=$2
    local kustomization_file="kubernetes/overlays/homelab/staging/$service/kustomization.yaml"
    
    # Check if images section exists
    if grep -q "images:" "$kustomization_file"; then
        # Update existing tag
        sed -i.bak "/name: 8060633493\/craftista-$service/,/newTag:/ s/newTag:.*/newTag: $new_tag/" "$kustomization_file"
        rm -f "${kustomization_file}.bak"
    else
        echo -e "${RED}❌ No images section found in $kustomization_file${NC}"
        return 1
    fi
}

echo "📋 Current image tags in Dev:"
echo "------------------------------"
for service in "${SERVICES[@]}"; do
    dev_tag=$(get_dev_image_tag "$service")
    echo -e "  ${service}: ${YELLOW}${dev_tag}${NC}"
done
echo

# Ask for confirmation
read -p "Do you want to promote these versions to staging? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ Promotion cancelled${NC}"
    exit 1
fi

echo
echo "🔄 Promoting services to staging..."
echo

# Promote each service
for service in "${SERVICES[@]}"; do
    echo -e "${BLUE}📦 Promoting $service...${NC}"
    
    dev_tag=$(get_dev_image_tag "$service")
    
    if [ -z "$dev_tag" ]; then
        echo -e "${RED}❌ Could not find dev tag for $service${NC}"
        continue
    fi
    
    update_staging_image_tag "$service" "$dev_tag"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $service promoted: $dev_tag${NC}"
    else
        echo -e "${RED}❌ Failed to promote $service${NC}"
    fi
    echo
done

# Show git diff
echo "📝 Changes to be committed:"
echo "----------------------------"
git diff kubernetes/overlays/homelab/staging/*/kustomization.yaml
echo

# Ask if user wants to commit
read -p "Commit and push these changes? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo
    echo "💾 Committing changes..."
    
    git add kubernetes/overlays/homelab/staging/*/kustomization.yaml
    
    # Create commit message with all promoted services
    commit_msg="chore: Promote services from dev to staging

Promoted services:
"
    for service in "${SERVICES[@]}"; do
        dev_tag=$(get_dev_image_tag "$service")
        commit_msg+="- $service: $dev_tag
"
    done
    
    git commit -m "$commit_msg"
    
    echo "📤 Pushing to remote..."
    git push origin main
    
    echo
    echo -e "${GREEN}✅ Promotion complete!${NC}"
    echo
    echo "📊 ArgoCD will automatically sync the changes to staging."
    echo "   Monitor progress: kubectl get applications -n argocd -l environment=staging"
    echo
else
    echo -e "${YELLOW}⚠️  Changes not committed. You can review and commit manually.${NC}"
fi
