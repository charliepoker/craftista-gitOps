# Quick Start - Canary Deployments

## Prerequisites

- Argo Rollouts installed in cluster
- kubectl-argo-rollouts CLI plugin installed
- ArgoCD managing applications

## Verify Installation

```bash
# Check Argo Rollouts controller
kubectl get pods -n argo-rollouts

# Check CLI version
kubectl argo rollouts version

# Check all services
kubectl get rollout -n craftista-staging
kubectl get rollout -n craftista-dev
```

## Deploy New Version

### Option 1: Via GitOps (Recommended)

1. Update image tag in `kubernetes/overlays/homelab/{env}/{service}/patches.yaml`:
   ```yaml
   - op: replace
     path: /spec/template/spec/containers/0/image
     value: 8060633493/craftista-frontend:new-tag
   ```

2. Commit and push:
   ```bash
   git add .
   git commit -m "feat: update frontend to new-tag"
   git push
   ```

3. ArgoCD will automatically sync and trigger canary deployment

### Option 2: Manual (Testing)

```bash
# Update image directly
kubectl argo rollouts set image frontend \
  frontend=8060633493/craftista-frontend:new-tag \
  -n craftista-staging
```

## Monitor Deployment

```bash
# Watch rollout progress
kubectl argo rollouts get rollout frontend -n craftista-staging --watch

# Check status
kubectl argo rollouts status frontend -n craftista-staging
```

## Control Deployment

### Promote (advance to next step)
```bash
kubectl argo rollouts promote frontend -n craftista-staging
```

### Fully Promote (skip all pauses)
```bash
kubectl argo rollouts promote frontend -n craftista-staging --full
```

### Abort (rollback)
```bash
kubectl argo rollouts abort frontend -n craftista-staging
```

## Canary Flow

```
┌─────────────────────────────────────────────────────────┐
│ 1. Deploy Canary Pods                                   │
│    - New version pods created                           │
│    - Old version pods remain                            │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ 2. Route 20% Traffic to Canary                          │
│    - NGINX Ingress splits traffic                       │
│    - Pause 2 minutes                                    │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ 3. Route 50% Traffic to Canary                          │
│    - Monitor metrics/errors                             │
│    - Pause 2 minutes                                    │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ 4. Route 80% Traffic to Canary                          │
│    - Final validation                                   │
│    - Pause 1 minute                                     │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ 5. Full Promotion (100%)                                │
│    - All traffic to new version                         │
│    - Old pods scaled down                               │
└─────────────────────────────────────────────────────────┘
```

## Common Commands

```bash
# List all rollouts
kubectl get rollout -n craftista-staging

# Get detailed rollout info
kubectl argo rollouts get rollout <service> -n <namespace>

# View rollout history
kubectl argo rollouts history <service> -n <namespace>

# Restart rollout
kubectl argo rollouts restart <service> -n <namespace>

# Undo to previous version
kubectl argo rollouts undo <service> -n <namespace>

# Check pods
kubectl get pods -n <namespace> -l app=<service>
```

## Troubleshooting

### Rollout stuck at 0%
- Check if canary pods are running: `kubectl get pods -n <namespace>`
- Check rollout events: `kubectl describe rollout <service> -n <namespace>`

### Image pull errors
- Verify image exists: Check Docker Hub
- Check image pull secrets: `kubectl get secret dockerhub-pull-secret -n <namespace>`

### Service selector issues
- Verify service selector matches pod labels
- Check `service-selector-patch.yaml` is applied

### Ingress not routing traffic
- Verify ingress backend service name
- Check ingress annotations for canary configuration

## Health Checks

```bash
# All services status
for svc in catalogue frontend recommendation voting; do
  echo "$svc: $(kubectl argo rollouts status $svc -n craftista-staging --timeout 2s 2>&1 | head -1)"
done

# Pod health
kubectl get pods -n craftista-staging -l 'app in (catalogue,frontend,recommendation,craftista-voting)'

# ArgoCD sync status
kubectl get application -n argocd -l environment=staging
```

## Emergency Rollback

```bash
# Abort current rollout
kubectl argo rollouts abort <service> -n <namespace>

# Undo to previous version
kubectl argo rollouts undo <service> -n <namespace>

# Or manually set old image
kubectl argo rollouts set image <service> \
  <container>=<old-image> \
  -n <namespace>
```

## Best Practices

1. **Always test in dev first** before deploying to staging
2. **Monitor logs** during canary phases
3. **Use --full flag** only when confident (skips validation pauses)
4. **Keep rollout history** for easy rollback
5. **Document changes** in commit messages for audit trail

## Next Steps

- Set up Prometheus metrics for automated analysis
- Configure Slack notifications for deployment events
- Implement automated rollback based on error rates
- Add smoke tests between canary steps
