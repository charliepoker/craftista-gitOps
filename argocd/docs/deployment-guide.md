# Craftista Deployment Guide

This guide provides step-by-step instructions for deploying the Craftista application using GitOps methodology. Follow these procedures to set up the complete CI/CD pipeline and deploy applications to your EKS cluster.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [ArgoCD Installation](#argocd-installation)
- [Vault Setup](#vault-setup)
- [External Secrets Configuration](#external-secrets-configuration)
- [Deploying Services](#deploying-services)
- [Environment Promotion](#environment-promotion)
- [Image Tag Updates](#image-tag-updates)
- [Monitoring and Verification](#monitoring-and-verification)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Infrastructure Requirements

Before starting the deployment, ensure the following infrastructure is provisioned via the [craftista-iac](https://github.com/charliepoker/Craftista-IaC.git) repository:

- ✅ EKS cluster (v1.24+) with worker nodes
- ✅ VPC with public and private subnets
- ✅ RDS PostgreSQL instance for voting service
- ✅ DocumentDB MongoDB cluster for catalogue service
- ✅ ElastiCache Redis cluster for recommendation service
- ✅ Application Load Balancer with SSL certificates
- ✅ Route53 DNS records for `webdemoapp.com`
- ✅ SonarQube EC2 instance (optional for CI/CD)
- ✅ Nexus Repository EC2 instance (optional for artifacts)

### Tool Requirements

Install and configure the following tools on your local machine:

```bash
# Kubernetes CLI
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm package manager
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd

# Vault CLI
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install vault

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### AWS Configuration

Configure AWS credentials and kubectl context:

```bash
# Configure AWS credentials
aws configure

# Update kubeconfig for EKS cluster
aws eks update-kubeconfig --region us-east-1 --name craftista-cluster

# Verify cluster access
kubectl get nodes
```

## Initial Setup

### 1. Clone Repository

```bash
git clone https://github.com/charliepoker/craftista-gitops.git
cd craftista-gitops
```

### 2. Verify Cluster Connectivity

```bash
# Check cluster status
kubectl cluster-info

# Verify worker nodes
kubectl get nodes -o wide

# Check available storage classes
kubectl get storageclass
```

### 3. Create Namespaces

```bash
# Create namespaces for all environments
kubectl apply -f kubernetes/overlays/dev/namespace.yaml
kubectl apply -f kubernetes/overlays/staging/namespace.yaml
kubectl apply -f kubernetes/overlays/prod/namespace.yaml

# Verify namespaces
kubectl get namespaces | grep craftista
```

## ArgoCD Installation

### 1. Install ArgoCD

Use the provided setup script:

```bash
# Make script executable
chmod +x scripts/setup-argocd.sh

# Run installation script
./scripts/setup-argocd.sh
```

Or install manually:

```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f argocd/install/argocd-install.yaml

# Apply custom configuration
kubectl apply -n argocd -f argocd/install/argocd-cm.yaml
kubectl apply -n argocd -f argocd/install/argocd-rbac-cm.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### 2. Access ArgoCD UI

```bash
# Port forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access UI at https://localhost:8080
# Username: admin
# Password: (from above command)
```

### 3. Configure ArgoCD CLI

```bash
# Login to ArgoCD
argocd login localhost:8080

# Change admin password
argocd account update-password
```

### 4. Create ArgoCD Projects

```bash
# Create projects for each environment
kubectl apply -f argocd/projects/craftista-dev.yaml
kubectl apply -f argocd/projects/craftista-staging.yaml
kubectl apply -f argocd/projects/craftista-prod.yaml

# Verify projects
argocd proj list
```

## Vault Setup

### 1. Install Vault

Use the provided setup script:

```bash
# Make script executable
chmod +x scripts/setup-vault.sh

# Run Vault setup
./scripts/setup-vault.sh
```

Or install manually using Helm:

```bash
# Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "server.ha.enabled=true" \
  --set "server.ha.replicas=3" \
  --set "server.ha.raft.enabled=true"

# Wait for Vault to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=300s
```

### 2. Initialize and Unseal Vault

```bash
# Initialize Vault (run once)
kubectl exec vault-0 -n vault -- vault operator init -key-shares=5 -key-threshold=3

# Save the unseal keys and root token securely
# Unseal Vault on each pod
kubectl exec vault-0 -n vault -- vault operator unseal <unseal-key-1>
kubectl exec vault-0 -n vault -- vault operator unseal <unseal-key-2>
kubectl exec vault-0 -n vault -- vault operator unseal <unseal-key-3>

# Repeat for other Vault pods if using HA setup
```

### 3. Configure Vault Authentication

```bash
# Make auth scripts executable
chmod +x vault/auth/kubernetes-auth.sh
chmod +x vault/auth/github-oidc-auth.sh

# Configure Kubernetes authentication
./vault/auth/kubernetes-auth.sh

# Configure GitHub OIDC (optional)
./vault/auth/github-oidc-auth.sh
```

### 4. Apply Vault Policies

```bash
# Apply all Vault policies
kubectl exec vault-0 -n vault -- vault policy write frontend-policy - < vault/policies/frontend-policy.hcl
kubectl exec vault-0 -n vault -- vault policy write catalogue-policy - < vault/policies/catalogue-policy.hcl
kubectl exec vault-0 -n vault -- vault policy write voting-policy - < vault/policies/voting-policy.hcl
kubectl exec vault-0 -n vault -- vault policy write recommendation-policy - < vault/policies/recommendation-policy.hcl
kubectl exec vault-0 -n vault -- vault policy write github-actions-policy - < vault/policies/github-actions-policy.hcl
```

### 5. Populate Vault with Secrets

```bash
# Make secrets script executable
chmod +x scripts/sync-secrets.sh

# Set environment variables for secrets
export MONGODB_URI="mongodb://username:password@docdb-cluster.cluster-xxx.us-east-1.docdb.amazonaws.com:27017/catalogue?ssl=true"
export POSTGRES_URI="postgresql://username:password@rds-instance.xxx.us-east-1.rds.amazonaws.com:5432/voting"
export REDIS_URI="redis://elasticache-cluster.xxx.cache.amazonaws.com:6379"
export DOCKERHUB_USERNAME="your-dockerhub-username"
export DOCKERHUB_PASSWORD="your-dockerhub-password"
export SONARQUBE_TOKEN="your-sonarqube-token"

# Sync secrets to Vault
./scripts/sync-secrets.sh
```

## External Secrets Configuration

### 1. Install External Secrets Operator

```bash
# Add External Secrets Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace

# Wait for operator to be ready
kubectl wait --for=condition=available --timeout=300s deployment/external-secrets -n external-secrets-system
```

### 2. Configure Secret Stores

```bash
# Apply cluster-wide secret store
kubectl apply -f external-secrets/cluster-secret-store.yaml

# Apply namespace-specific secret stores
kubectl apply -f external-secrets/secret-store.yaml
```

### 3. Create External Secrets

```bash
# Apply external secrets for all services
kubectl apply -f external-secrets/external-secrets/frontend-secrets.yaml
kubectl apply -f external-secrets/external-secrets/catalogue-secrets.yaml
kubectl apply -f external-secrets/external-secrets/voting-secrets.yaml
kubectl apply -f external-secrets/external-secrets/recommendation-secrets.yaml

# Verify secrets are created
kubectl get secrets -n craftista-dev | grep craftista
kubectl get secrets -n craftista-staging | grep craftista
kubectl get secrets -n craftista-prod | grep craftista
```

## Deploying Services

### 1. Deploy to Development Environment

```bash
# Apply RBAC configurations
kubectl apply -f kubernetes/common/rbac/

# Apply network policies
kubectl apply -f kubernetes/common/network-policies/

# Create ArgoCD applications for dev
kubectl apply -f argocd/applications/dev/

# Verify applications are created
argocd app list

# Sync applications
argocd app sync craftista-frontend-dev
argocd app sync craftista-catalogue-dev
argocd app sync craftista-voting-dev
argocd app sync craftista-recommendation-dev
```

### 2. Monitor Deployment Progress

```bash
# Watch ArgoCD applications
argocd app get craftista-frontend-dev --refresh

# Monitor pod status
kubectl get pods -n craftista-dev -w

# Check application logs
kubectl logs -f deployment/frontend -n craftista-dev
```

### 3. Deploy to Staging Environment

```bash
# Create ArgoCD applications for staging
kubectl apply -f argocd/applications/staging/

# Sync applications (automatic if configured)
argocd app sync craftista-frontend-staging
argocd app sync craftista-catalogue-staging
argocd app sync craftista-voting-staging
argocd app sync craftista-recommendation-staging
```

### 4. Deploy to Production Environment

```bash
# Create ArgoCD applications for production (manual sync)
kubectl apply -f argocd/applications/prod/

# Manual sync required for production
argocd app sync craftista-frontend-prod --dry-run
argocd app sync craftista-frontend-prod

# Repeat for other services after verification
```

## Environment Promotion

### Automated Promotion (CI/CD Pipeline)

The CI/CD pipeline automatically promotes images through environments based on Git branches:

1. **Development**: Triggered by pushes to `develop` branch
2. **Staging**: Triggered by pushes to `staging` branch
3. **Production**: Triggered by pushes to `main` branch (with manual approval)

### Manual Promotion

Use the provided scripts for manual promotion:

```bash
# Promote from dev to staging
./scripts/promote-to-staging.sh frontend v1.2.3

# Promote from staging to production (requires approval)
./scripts/promote-to-prod.sh frontend v1.2.3
```

### Promotion Process

1. **Image Verification**: Ensure image exists in registry and passes security scans
2. **Configuration Update**: Update image tag in target environment overlay
3. **Git Commit**: Commit changes with descriptive message
4. **ArgoCD Sync**: ArgoCD detects changes and syncs to cluster
5. **Health Check**: Verify deployment health and rollback if needed

## Image Tag Updates

### Automatic Updates (CI/CD)

Image tags are automatically updated by the CI/CD pipeline in the [craftista](https://github.com/charliepoker/craftista.git) repository:

```yaml
# Example GitHub Actions workflow step
- name: Update GitOps Repository
  run: |
    git clone https://github.com/charliepoker/craftista-gitops.git
    cd craftista-gitops

    # Update image tag in appropriate overlay
    sed -i "s|image: .*/craftista-frontend:.*|image: 8060633493/craftista-frontend:${GITHUB_SHA}|" \
      kubernetes/overlays/${ENVIRONMENT}/frontend/kustomization.yaml

    # Commit and push changes
    git add .
    git commit -m "Update frontend image to ${GITHUB_SHA}"
    git push origin main
```

### Manual Image Updates

For manual updates, modify the appropriate overlay files:

```bash
# Update dev environment
vim kubernetes/overlays/dev/frontend/kustomization.yaml

# Update the image tag
images:
  - name: 8060633493/craftista-frontend
    newTag: "v1.2.3"

# Commit changes
git add kubernetes/overlays/dev/frontend/kustomization.yaml
git commit -m "Update frontend to v1.2.3 in dev"
git push origin main
```

### Using Helm Charts

For Helm-based deployments, update values files:

```bash
# Update image tag in values file
vim helm/charts/frontend/values-dev.yaml

# Modify image tag
image:
  tag: "v1.2.3"

# Commit changes
git add helm/charts/frontend/values-dev.yaml
git commit -m "Update frontend Helm chart to v1.2.3"
git push origin main
```

## Monitoring and Verification

### Health Checks

```bash
# Check ArgoCD application health
argocd app get craftista-frontend-dev

# Check pod health
kubectl get pods -n craftista-dev
kubectl describe pod <pod-name> -n craftista-dev

# Check service endpoints
kubectl get endpoints -n craftista-dev

# Test service connectivity
kubectl port-forward svc/frontend 3000:3000 -n craftista-dev
curl http://localhost:3000/health
```

### Application Access

Verify applications are accessible through ingress:

```bash
# Check ingress status
kubectl get ingress -n craftista-dev

# Test external access (replace with your domain)
curl -k https://frontend.dev.webdemoapp.com/health
curl -k https://catalogue.dev.webdemoapp.com/health
curl -k https://voting.dev.webdemoapp.com/health
curl -k https://recommendation.dev.webdemoapp.com/health
```

### Logs and Debugging

```bash
# View application logs
kubectl logs -f deployment/frontend -n craftista-dev

# View ArgoCD logs
kubectl logs -f deployment/argocd-application-controller -n argocd

# View Vault logs
kubectl logs -f vault-0 -n vault

# View External Secrets Operator logs
kubectl logs -f deployment/external-secrets -n external-secrets-system
```

## Troubleshooting

### Common Issues and Solutions

#### ArgoCD Application Stuck in Progressing State

```bash
# Check application events
kubectl describe application craftista-frontend-dev -n argocd

# Force refresh and sync
argocd app get craftista-frontend-dev --refresh
argocd app sync craftista-frontend-dev --force

# Check for resource conflicts
kubectl get events -n craftista-dev --sort-by='.lastTimestamp'
```

#### Secrets Not Available

```bash
# Check External Secrets status
kubectl get externalsecrets -n craftista-dev
kubectl describe externalsecret frontend-secrets -n craftista-dev

# Verify Vault connectivity
kubectl exec -it vault-0 -n vault -- vault status

# Check secret store configuration
kubectl get secretstore -n craftista-dev
kubectl describe secretstore vault-backend -n craftista-dev
```

#### Pod Startup Issues

```bash
# Check pod events
kubectl describe pod <pod-name> -n craftista-dev

# Check resource constraints
kubectl top pods -n craftista-dev
kubectl describe nodes

# Verify image pull
kubectl get events -n craftista-dev | grep "Failed to pull image"
```

#### Network Connectivity Issues

```bash
# Check network policies
kubectl get networkpolicies -n craftista-dev
kubectl describe networkpolicy <policy-name> -n craftista-dev

# Test pod-to-pod connectivity
kubectl exec -it <frontend-pod> -n craftista-dev -- curl http://catalogue:5000/health

# Check service DNS resolution
kubectl exec -it <frontend-pod> -n craftista-dev -- nslookup catalogue.craftista-dev.svc.cluster.local
```

### Rollback Procedures

If deployment issues occur, use the rollback procedures:

```bash
# Rollback using ArgoCD
argocd app rollback craftista-frontend-dev <revision-id>

# Or use the rollback script
./scripts/rollback.sh frontend dev <git-commit-hash>

# Verify rollback success
kubectl get pods -n craftista-dev
argocd app get craftista-frontend-dev
```

### Getting Help

For additional support:

1. Check the [troubleshooting runbook](runbooks/troubleshooting.md)
2. Review [ArgoCD documentation](https://argo-cd.readthedocs.io/)
3. Consult [Vault documentation](https://www.vaultproject.io/docs)
4. Create an issue in this repository with detailed error information

## Next Steps

After successful deployment:

1. Set up monitoring and alerting
2. Configure backup procedures
3. Implement disaster recovery plans
4. Set up log aggregation
5. Configure performance monitoring
6. Review and update security policies

For ongoing operations, refer to the [operational runbooks](runbooks/) for detailed procedures.
