# Canary Deployment - Final Configuration

## Overview

All 4 microservices (catalogue, frontend, voting, recommendation) now use Argo Rollouts with canary deployment strategy in both dev and staging environments.

## Status

### Dev Environment
- ✅ **Catalogue**: Healthy (1 replica, Rollout with canary)
- ✅ **Frontend**: Healthy (1 replica, Rollout with canary)
- ✅ **Recommendation**: Healthy (1 replica, Rollout with canary)
- ✅ **Voting**: Healthy (1 replica, Rollout with canary)

### Staging Environment
- ✅ **Catalogue**: Healthy (2 replicas, Rollout with canary)
- ✅ **Frontend**: Healthy (2 replicas, Rollout with canary)
- ✅ **Recommendation**: Healthy (2 replicas, Rollout with canary)
- ✅ **Voting**: Healthy (1 replica, Rollout with canary)

## Canary Strategy

### Traffic Progression
```yaml
steps:
  - setWeight: 20    # Route 20% traffic to canary
  - pause: 2m        # Wait 2 minutes
  - setWeight: 50    # Route 50% traffic to canary
  - pause: 2m        # Wait 2 minutes
  - setWeight: 80    # Route 80% traffic to canary
  - pause: 1m        # Wait 1 minute
  - setWeight: 100   # Full promotion
```

### Infrastructure per Service
- **Stable Service**: Serves production traffic (e.g., `frontend`)
- **Canary Service**: Serves canary traffic (e.g., `frontend-canary`)
- **Rollout Resource**: Manages progressive deployment
- **NGINX Ingress**: Automatically splits traffic based on weights

## File Structure

```
kubernetes/
├── base/SERVICE/
│   ├── rollout.yaml          # Argo Rollout resource
│   ├── service.yaml          # Stable service
│   ├── service-canary.yaml   # Canary service
│   ├── configmap.yaml
│   ├── ingress.yaml
│   └── kustomization.yaml
│
└── overlays/homelab/{dev|staging}/SERVICE/
    ├── rollout-patch.yaml           # Sets replicas
    ├── patches.yaml                 # JSON6902: image, resources, labels
    ├── service-selector-patch.yaml  # Fixes service selector
    ├── configmap-patch.yaml         # Environment-specific config
    ├── ingress-patch.yaml           # Domain configuration
    └── kustomization.yaml
```

## Key Configurations

### Service Name Mappings
- **catalogue**: service=`catalogue`, rollout=`catalogue`
- **frontend**: service=`frontend`, rollout=`frontend`
- **voting**: service=`craftista-voting`, rollout=`voting`
- **recommendation**: service=`recco`, rollout=`recommendation`

### Image Tags
**Dev:**
- catalogue: `8060633493/craftista-catalogue:dev-latest`
- frontend: `8060633493/craftista-frontend:dev-latest`
- recommendation: `8060633493/craftista-recommendation:dev-latest`
- voting: `8060633493/craftista-voting:develop-b6103ceb8f51ee5f2a16d4f169abc4309b1e5466`

**Staging:**
- All services: `8060633493/craftista-SERVICE:dev-latest`

### Probe Settings
**Dev (slow startup):**
- Voting: `initialDelaySeconds: 240` (app takes ~195s to start)
- Catalogue: `initialDelaySeconds: 120`
- Recommendation: `initialDelaySeconds: 120`
- Frontend: Default (30s)

**Staging:**
- All services: Default probe settings

### Environment-Specific Fixes

**Dev:**
- MongoDB service: `mongodb-dev.craftista-dev.svc.cluster.local`
- Redis service: `redis-dev.craftista-dev.svc.cluster.local`
- PostgreSQL service: `postgres-dev.craftista-dev.svc.cluster.local`

**Staging:**
- MongoDB service: `mongodb.craftista-staging.svc.cluster.local`
- Redis service: `redis.craftista-staging.svc.cluster.local`
- PostgreSQL service: `postgres.craftista-staging.svc.cluster.local`

## Common Operations

### Check Rollout Status
```bash
# Single service
kubectl argo rollouts get rollout <service> -n <namespace>

# All services
kubectl get rollout -n <namespace>
```

### Promote Canary
```bash
# Advance to next step
kubectl argo rollouts promote <service> -n <namespace>

# Skip all steps and fully promote
kubectl argo rollouts promote <service> -n <namespace> --full
```

### Abort Rollout
```bash
kubectl argo rollouts abort <service> -n <namespace>
```

### Restart Rollout
```bash
kubectl argo rollouts restart <service> -n <namespace>
```

### Retry Failed Rollout
```bash
kubectl argo rollouts retry rollout <service> -n <namespace>
```

### Watch Rollout Progress
```bash
kubectl argo rollouts get rollout <service> -n <namespace> --watch
```

## ArgoCD Integration

All services are managed by ArgoCD with automated sync:

```bash
# Check ArgoCD app status
kubectl get application -n argocd -l environment=staging

# Sync manually
argocd app sync craftista-<service>-staging
```

## Troubleshooting

### Issue: Service selector mismatch
**Symptom**: `Service has unmatch label "environment" in rollout`

**Solution**: Use JSON patch to override service selector:
```yaml
# service-selector-patch.yaml
- op: replace
  path: /spec/selector
  value:
    app: <service-name>
```

### Issue: Ingress backend not found
**Symptom**: `ingress has no rules using service X backend`

**Solution**: Ensure ingress points to correct service name in `ingress-patch.yaml`

### Issue: Image pull errors
**Symptom**: `ImagePullBackOff` or `ErrImagePull`

**Solution**: 
- Verify image tag exists in Docker Hub
- Use `dev-latest` for dev environment (ARM64 compatible)
- Use specific commit hashes if needed

### Issue: Pod crashes on startup
**Symptom**: `CrashLoopBackOff` with timeout errors

**Solution**: Increase probe delays in `patches.yaml`:
```yaml
- op: replace
  path: /spec/template/spec/containers/0/livenessProbe/initialDelaySeconds
  value: 120
```

### Issue: Database connection failures
**Symptom**: "Waiting for MongoDB/Redis/PostgreSQL..."

**Solution**: Verify service names in secrets and configmaps match actual service names

## Testing Canary Deployment

1. **Trigger deployment** by updating image tag in patches.yaml
2. **Watch progression**:
   ```bash
   kubectl argo rollouts get rollout frontend -n craftista-staging --watch
   ```
3. **Verify traffic split**: Check pod logs to see traffic distribution
4. **Promote or abort** based on metrics/health

## Rollback

```bash
# Undo to previous revision
kubectl argo rollouts undo <service> -n <namespace>

# Undo to specific revision
kubectl argo rollouts undo <service> -n <namespace> --to-revision=<revision>
```

## Metrics & Monitoring

Monitor rollout health:
```bash
# Get rollout status
kubectl argo rollouts status <service> -n <namespace>

# View rollout history
kubectl argo rollouts history <service> -n <namespace>

# Check pod distribution
kubectl get pods -n <namespace> -l app=<service> -o wide
```

## Next Steps

1. ✅ All services converted to Rollouts with canary
2. ✅ ArgoCD managing all deployments
3. 🔄 Add Prometheus metrics for automated promotion/rollback
4. 🔄 Implement analysis templates for health checks
5. 🔄 Add Slack/email notifications for deployment events

## References

- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [Canary Deployment Patterns](https://argoproj.github.io/argo-rollouts/features/canary/)
- [NGINX Ingress Traffic Splitting](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/#canary)
