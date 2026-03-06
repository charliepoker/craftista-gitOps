# Production Environment Setup

## Overview

Production environment with enterprise-grade configuration:
- **Argo Rollouts** with canary deployment strategy
- **ArgoCD** for GitOps automation
- **High availability** with multiple replicas
- **Production resource limits** for stability
- **Automated sync** with self-healing

## Configuration

### Replicas
- **Catalogue**: 3 replicas
- **Frontend**: 3 replicas
- **Recommendation**: 3 replicas
- **Voting**: 2 replicas

### Resources (per pod)
```yaml
requests:
  cpu: 200m
  memory: 256Mi
limits:
  cpu: 1000m
  memory: 512Mi
```

### Image Tags
All services use `prod-latest` tag:
- `8060633493/craftista-catalogue:prod-latest`
- `8060633493/craftista-frontend:prod-latest`
- `8060633493/craftista-recommendation:prod-latest`
- `8060633493/craftista-voting:prod-latest`

### Domains
- Frontend: `https://frontend.webdemoapp.com`
- Catalogue: `https://catalogue.webdemoapp.com`
- Voting: `https://voting.webdemoapp.com`
- Recommendation: `https://recommendation.webdemoapp.com`

## Deployment

### Initial Setup

1. **Apply ArgoCD bootstrap app**:
   ```bash
   kubectl apply -f argocd/applications/clusters/homelab/prod/bootstrap-app.yaml
   ```

2. **Verify ArgoCD apps created**:
   ```bash
   kubectl get application -n argocd -l environment=production
   ```

3. **Wait for sync**:
   ```bash
   watch kubectl get application -n argocd -l environment=production
   ```

### Manual Deployment (if needed)

```bash
# Create namespace
kubectl create namespace craftista-prod

# Apply each service
for svc in catalogue frontend recommendation voting; do
  kubectl apply -k kubernetes/overlays/homelab/prod/$svc
done
```

## GitOps Workflow

### Deploying New Version

1. **Update image tag** in `kubernetes/overlays/homelab/prod/{service}/patches.yaml`:
   ```yaml
   - op: replace
     path: /spec/template/spec/containers/0/image
     value: 8060633493/craftista-frontend:v1.2.3
   ```

2. **Commit and push**:
   ```bash
   git add .
   git commit -m "feat: deploy frontend v1.2.3 to production"
   git push
   ```

3. **ArgoCD automatically**:
   - Detects change
   - Syncs to cluster
   - Triggers canary deployment

4. **Monitor rollout**:
   ```bash
   kubectl argo rollouts get rollout frontend -n craftista-prod --watch
   ```

### Canary Progression

```
Deploy → 20% (2min) → 50% (2min) → 80% (1min) → 100%
```

At each pause, you can:
- **Promote**: `kubectl argo rollouts promote <service> -n craftista-prod`
- **Abort**: `kubectl argo rollouts abort <service> -n craftista-prod`

## Monitoring

### Check All Services
```bash
# Rollout status
kubectl get rollout -n craftista-prod

# Pod status
kubectl get pods -n craftista-prod

# ArgoCD sync status
kubectl get application -n argocd -l environment=production
```

### Individual Service
```bash
# Detailed rollout info
kubectl argo rollouts get rollout <service> -n craftista-prod

# Rollout history
kubectl argo rollouts history <service> -n craftista-prod

# Pod logs
kubectl logs -n craftista-prod -l app=<service> --tail=100
```

### Health Checks
```bash
# All services health
for svc in catalogue frontend recommendation voting; do
  echo "$svc: $(kubectl argo rollouts status $svc -n craftista-prod --timeout 2s 2>&1 | head -1)"
done
```

## Rollback

### Abort Current Deployment
```bash
kubectl argo rollouts abort <service> -n craftista-prod
```

### Undo to Previous Version
```bash
kubectl argo rollouts undo <service> -n craftista-prod
```

### Undo to Specific Revision
```bash
# View history
kubectl argo rollouts history <service> -n craftista-prod

# Rollback
kubectl argo rollouts undo <service> --to-revision=<n> -n craftista-prod
```

## Troubleshooting

### ArgoCD App Out of Sync
```bash
# Manual sync
argocd app sync craftista-<service>-prod

# Or via kubectl
kubectl patch application craftista-<service>-prod -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### Rollout Stuck
```bash
# Check rollout status
kubectl describe rollout <service> -n craftista-prod

# Check pods
kubectl get pods -n craftista-prod -l app=<service>

# Check events
kubectl get events -n craftista-prod --sort-by='.lastTimestamp'
```

### Image Pull Errors
```bash
# Verify image exists
docker manifest inspect 8060633493/craftista-<service>:prod-latest

# Check pull secrets
kubectl get secret dockerhub-pull-secret -n craftista-prod
```

### Service Not Accessible
```bash
# Check ingress
kubectl get ingress -n craftista-prod

# Check services
kubectl get svc -n craftista-prod

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

## Production Best Practices

### Before Deploying

1. ✅ Test in dev environment
2. ✅ Test in staging environment
3. ✅ Review changes in PR
4. ✅ Ensure CI/CD pipeline passed
5. ✅ Check monitoring/alerts are working

### During Deployment

1. 🔍 Monitor rollout progress
2. 🔍 Watch application logs
3. 🔍 Check error rates/metrics
4. 🔍 Verify health checks passing
5. ⏸️ Use pauses to validate each step

### After Deployment

1. ✅ Verify all pods healthy
2. ✅ Test critical user flows
3. ✅ Check monitoring dashboards
4. ✅ Review logs for errors
5. 📝 Document any issues

## Emergency Procedures

### Complete Rollback
```bash
# 1. Abort current rollout
kubectl argo rollouts abort <service> -n craftista-prod

# 2. Undo to previous version
kubectl argo rollouts undo <service> -n craftista-prod

# 3. Verify rollback
kubectl argo rollouts status <service> -n craftista-prod
```

### Scale Down Service
```bash
kubectl argo rollouts scale <service> --replicas=0 -n craftista-prod
```

### Disable ArgoCD Auto-Sync
```bash
kubectl patch application craftista-<service>-prod -n argocd \
  --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

## Maintenance

### Update Resource Limits
Edit `kubernetes/overlays/homelab/prod/{service}/patches.yaml`:
```yaml
- op: replace
  path: /spec/template/spec/containers/0/resources/limits/cpu
  value: 2000m
```

### Scale Replicas
Edit `kubernetes/overlays/homelab/prod/{service}/rollout-patch.yaml`:
```yaml
spec:
  replicas: 5
```

### Update Configuration
Edit `kubernetes/overlays/homelab/prod/{service}/configmap-patch.yaml`

Then commit and push - ArgoCD will sync automatically.

## Metrics & Observability

### Key Metrics to Monitor
- Pod CPU/Memory usage
- Request latency (p50, p95, p99)
- Error rate
- Rollout success rate
- Time to deploy

### Recommended Tools
- **Prometheus**: Metrics collection
- **Grafana**: Dashboards
- **Loki**: Log aggregation
- **AlertManager**: Alerting
- **Jaeger**: Distributed tracing

## Next Steps

1. 🔄 Set up Prometheus metrics
2. 🔄 Configure automated rollback on errors
3. 🔄 Add smoke tests between canary steps
4. 🔄 Implement blue-green deployment option
5. 🔄 Set up Slack/PagerDuty notifications
