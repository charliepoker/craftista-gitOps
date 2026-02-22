# Craftista Staging Environment

## Overview

The staging environment is a pre-production environment that mirrors production configuration with the following characteristics:

- **Namespace**: `craftista-staging`
- **Replicas**: 2 per service (vs 1 in dev)
- **Purpose**: Testing and validation before production deployment
- **Auto-sync**: Enabled via ArgoCD

## Architecture

### Services Deployed

1. **Frontend** - Node.js/Express web application
2. **Catalogue** - Python/Flask product catalog API
3. **Voting** - Java/Spring Boot voting service
4. **Recommendation** - Golang recommendation engine

### Dependencies

1. **MongoDB** - Catalogue database
2. **PostgreSQL** - Voting database  
3. **Redis** - Recommendation cache

## Directory Structure

```
kubernetes/overlays/homelab/staging/
├── namespace.yaml                    # Staging namespace definition
├── vault-ca.yaml                     # Vault CA certificate
├── kustomization.yaml                # Main kustomization file
├── deps/                             # Database dependencies
│   └── kustomization.yaml
├── catalogue/
│   ├── kustomization.yaml            # Image tags and patches
│   ├── deployment-patch.yaml         # Staging-specific deployment config
│   ├── configmap-patch.yaml          # Environment variables
│   ├── ingress-patch.yaml            # Ingress configuration
│   └── resources-patch.yaml          # Resource limits/requests
├── frontend/
│   └── ... (same structure)
├── voting/
│   └── ... (same structure)
└── recommendation/
    └── ... (same structure)
```

## Deployment

### Initial Deployment

Deploy the entire staging environment:

```bash
./deploy-staging.sh
```

This script will:
1. Create the `craftista-staging` namespace
2. Deploy database dependencies (MongoDB, PostgreSQL, Redis)
3. Apply ArgoCD applications for all services
4. Wait for sync and display status

### Manual Deployment

If you prefer manual deployment:

```bash
# 1. Create namespace
kubectl apply -f kubernetes/overlays/homelab/staging/namespace.yaml

# 2. Deploy dependencies
kubectl apply -f argocd/applications/clusters/homelab/staging/deps-app.yaml

# 3. Deploy services
kubectl apply -f argocd/applications/clusters/homelab/staging/catalogue-app.yaml
kubectl apply -f argocd/applications/clusters/homelab/staging/frontend-app.yaml
kubectl apply -f argocd/applications/clusters/homelab/staging/voting-app.yaml
kubectl apply -f argocd/applications/clusters/homelab/staging/recommendation-app.yaml
```

## Promotion from Dev

### Automated Promotion

Use the promotion script to copy current dev image tags to staging:

```bash
./promote-dev-to-staging.sh
```

This script will:
1. Show current dev image tags
2. Ask for confirmation
3. Update staging kustomization files
4. Show git diff
5. Commit and push changes (optional)
6. ArgoCD will auto-sync the changes

### Manual Promotion

1. Get current dev image tags:
```bash
grep -A 2 "images:" kubernetes/overlays/homelab/dev/catalogue/kustomization.yaml
```

2. Update staging kustomization:
```bash
# Edit kubernetes/overlays/homelab/staging/catalogue/kustomization.yaml
# Update the newTag value under images section
```

3. Commit and push:
```bash
git add kubernetes/overlays/homelab/staging/*/kustomization.yaml
git commit -m "chore: Promote services to staging"
git push origin main
```

4. ArgoCD will automatically sync within 3 minutes, or force sync:
```bash
kubectl patch application craftista-catalogue-staging -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

## Monitoring

### Check Application Status

```bash
# All staging applications
kubectl get applications -n argocd -l environment=staging

# Specific service
kubectl get application craftista-catalogue-staging -n argocd -o yaml
```

### Check Pod Status

```bash
# All pods in staging
kubectl get pods -n craftista-staging

# Watch pods
kubectl get pods -n craftista-staging -w

# Specific service
kubectl get pods -n craftista-staging -l app=catalogue
```

### View Logs

```bash
# Service logs
kubectl logs -n craftista-staging -l app=catalogue --tail=100 -f

# Database logs
kubectl logs -n craftista-staging -l app=mongodb --tail=50
```

### Check Ingress

```bash
kubectl get ingress -n craftista-staging
```

## Configuration

### Environment Variables

Each service has staging-specific configuration in `configmap-patch.yaml`:

**Catalogue**:
- `FLASK_ENV`: staging
- `FLASK_DEBUG`: False
- `DATA_SOURCE`: mongodb
- `LOG_LEVEL`: INFO

**Frontend**:
- `NODE_ENV`: staging
- `LOG_LEVEL`: info

**Voting**:
- `SPRING_PROFILES_ACTIVE`: staging
- `LOGGING_LEVEL_ROOT`: INFO

**Recommendation**:
- `GIN_MODE`: release
- `LOG_LEVEL`: info

### Resource Limits

Staging uses higher resource limits than dev (defined in `resources-patch.yaml`):

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### Replicas

All services run with 2 replicas in staging for high availability testing.

## Secrets Management

Secrets are managed via External Secrets Operator and HashiCorp Vault:

```bash
# Check external secrets
kubectl get externalsecrets -n craftista-staging

# Check if secrets are synced
kubectl get secrets -n craftista-staging
```

Vault paths for staging:
- `secret/craftista/staging/catalogue/*`
- `secret/craftista/staging/frontend/*`
- `secret/craftista/staging/voting/*`
- `secret/craftista/staging/recommendation/*`

## Troubleshooting

### Application Not Syncing

```bash
# Check sync status
kubectl get application craftista-catalogue-staging -n argocd -o jsonpath='{.status.sync.status}'

# Check for errors
kubectl get application craftista-catalogue-staging -n argocd -o jsonpath='{.status.conditions}'

# Force refresh
kubectl patch application craftista-catalogue-staging -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name> -n craftista-staging

# Check logs
kubectl logs <pod-name> -n craftista-staging

# Check resource constraints
kubectl top pods -n craftista-staging
```

### Database Connection Issues

```bash
# Check database pods
kubectl get pods -n craftista-staging -l app=mongodb
kubectl get pods -n craftista-staging -l app=postgres

# Check database logs
kubectl logs -n craftista-staging -l app=mongodb --tail=50

# Test connection from service pod
kubectl exec -it <service-pod> -n craftista-staging -- curl mongodb:27017
```

### Image Pull Errors

```bash
# Check image pull secrets
kubectl get secrets -n craftista-staging

# Verify image exists in registry
docker pull 8060633493/craftista-catalogue:<tag>
```

## Rollback

### Rollback to Previous Version

1. Find previous image tag from git history:
```bash
git log --oneline kubernetes/overlays/homelab/staging/catalogue/kustomization.yaml
```

2. Revert to previous commit:
```bash
git revert <commit-hash>
git push origin main
```

3. Or manually update image tag and commit.

### Emergency Rollback

```bash
# Scale down service
kubectl scale deployment catalogue -n craftista-staging --replicas=0

# Update image tag
# ... edit kustomization.yaml ...

# Scale back up
kubectl scale deployment catalogue -n craftista-staging --replicas=2
```

## Testing in Staging

### Smoke Tests

```bash
# Test frontend
curl https://staging.craftista.local

# Test catalogue API
curl https://staging.craftista.local/api/catalogue/products

# Test voting API
curl https://staging.craftista.local/api/voting/health

# Test recommendation API
curl https://staging.craftista.local/api/recommendation/health
```

### Load Testing

Use tools like k6, Apache Bench, or Locust to test staging before promoting to production.

## Next Steps

After successful staging validation:

1. Run integration tests
2. Perform manual QA testing
3. Run load/performance tests
4. Get stakeholder approval
5. Promote to production using `./promote-staging-to-prod.sh`

## Related Documentation

- [Development Environment](../dev/README.md)
- [Production Environment](../prod/README.md)
- [ArgoCD Documentation](../../../argocd/docs/)
- [Promotion Scripts](../../../scripts/)
