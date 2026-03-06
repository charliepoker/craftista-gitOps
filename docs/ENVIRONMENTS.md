# Environment Overview

## Summary

| Environment | Purpose | Replicas | Resources | Auto-Sync | Image Tag |
|-------------|---------|----------|-----------|-----------|-----------|
| **Dev** | Development & Testing | 1 | Low (50-200m CPU) | ✅ Yes | `dev-latest` |
| **Staging** | Pre-production Testing | 2 | Medium (100-400m CPU) | ✅ Yes | `dev-latest` |
| **Production** | Live Traffic | 2-3 | High (200-1000m CPU) | ✅ Yes | `prod-latest` |

## Dev Environment

**Namespace**: `craftista-dev`

**Purpose**: Rapid development and testing

**Configuration**:
- 1 replica per service
- Lower resource limits
- Debug logging enabled
- Fast iteration cycle

**Domains**:
- `*.home-lab.webdemoapp.com`

**Deployment**: Automatic on push to `develop` branch

## Staging Environment

**Namespace**: `craftista-staging`

**Purpose**: Pre-production validation

**Configuration**:
- 2 replicas per service (1 for voting)
- Medium resource limits
- Production-like setup
- Full canary deployment

**Domains**:
- `*.staging.webdemoapp.com`

**Deployment**: Automatic on push to `main` branch

## Production Environment

**Namespace**: `craftista-prod`

**Purpose**: Live user traffic

**Configuration**:
- 3 replicas (catalogue, frontend, recommendation)
- 2 replicas (voting)
- High resource limits
- Warning-level logging
- Full canary with pauses

**Domains**:
- `*.webdemoapp.com`

**Deployment**: Automatic on push to `main` branch with `prod-latest` tag

## Promotion Flow

```
Developer → Dev → Staging → Production
   ↓         ↓       ↓          ↓
 develop   main    main    prod-latest
```

### Typical Workflow

1. **Develop**: Push to `develop` branch
   - CI builds and pushes `dev-latest` image
   - ArgoCD syncs to dev environment
   - Test changes

2. **Staging**: Merge to `main` branch
   - CI builds and pushes `dev-latest` image
   - ArgoCD syncs to staging environment
   - QA testing

3. **Production**: Tag release
   - CI builds and pushes `prod-latest` image
   - ArgoCD syncs to production environment
   - Canary deployment with monitoring

## Resource Allocation

### Dev
```yaml
requests:
  cpu: 50m
  memory: 128Mi
limits:
  cpu: 200m
  memory: 256Mi
```

### Staging
```yaml
requests:
  cpu: 100m
  memory: 128Mi
limits:
  cpu: 400m
  memory: 512Mi
```

### Production
```yaml
requests:
  cpu: 200m
  memory: 256Mi
limits:
  cpu: 1000m
  memory: 512Mi
```

## Canary Strategy

All environments use the same canary strategy:

```
20% (2min) → 50% (2min) → 80% (1min) → 100%
```

**Differences**:
- **Dev**: Manual promotion recommended
- **Staging**: Can use auto-promotion
- **Production**: Manual promotion required

## Access

### Dev
```bash
kubectl config set-context --current --namespace=craftista-dev
kubectl get rollout
```

### Staging
```bash
kubectl config set-context --current --namespace=craftista-staging
kubectl get rollout
```

### Production
```bash
kubectl config set-context --current --namespace=craftista-prod
kubectl get rollout
```

## Monitoring

### Check All Environments
```bash
for env in dev staging prod; do
  echo "=== craftista-$env ==="
  kubectl get rollout -n craftista-$env
  echo ""
done
```

### Health Status
```bash
for env in dev staging prod; do
  echo "=== $env ==="
  for svc in catalogue frontend recommendation voting; do
    kubectl argo rollouts status $svc -n craftista-$env --timeout 2s 2>&1 | head -1
  done
  echo ""
done
```

## Configuration Differences

### Logging
- **Dev**: DEBUG
- **Staging**: INFO
- **Production**: WARNING

### Debug Mode
- **Dev**: Enabled
- **Staging**: Disabled
- **Production**: Disabled

### Database Connections
- **Dev**: `mongodb-dev`, `redis-dev`, `postgres-dev`
- **Staging**: `mongodb`, `redis`, `postgres`
- **Production**: `mongodb`, `redis`, `postgres`

## Best Practices

1. **Always test in dev first**
2. **Validate in staging before production**
3. **Use feature flags for risky changes**
4. **Monitor metrics during rollouts**
5. **Keep production stable - no experiments**

## Emergency Access

### Production Rollback
```bash
# Abort and rollback
kubectl argo rollouts abort <service> -n craftista-prod
kubectl argo rollouts undo <service> -n craftista-prod
```

### Disable Auto-Sync
```bash
# Temporarily disable for emergency fixes
kubectl patch application craftista-<service>-prod -n argocd \
  --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
```
