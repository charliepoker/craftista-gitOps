# 🚀 Production-Ready GitOps Setup

## ✅ What's Implemented

### 1. Three Environments
- **Dev**: Development and testing (`craftista-dev`)
- **Staging**: Pre-production validation (`craftista-staging`)
- **Production**: Live traffic (`craftista-prod`)

### 2. Argo Rollouts (All Environments)
- ✅ Canary deployment strategy
- ✅ Progressive traffic shifting (20% → 50% → 80% → 100%)
- ✅ Automated pauses for validation
- ✅ Instant rollback capability
- ✅ Rollout history tracking

### 3. ArgoCD GitOps
- ✅ Automated sync from Git
- ✅ Self-healing enabled
- ✅ Bootstrap apps for each environment
- ✅ Application-of-applications pattern

### 4. Production Configuration
- ✅ High availability (3 replicas for critical services)
- ✅ Production resource limits (200m-1000m CPU, 256Mi-512Mi RAM)
- ✅ Proper logging levels (WARNING in prod)
- ✅ SSL/TLS with cert-manager
- ✅ Service mesh ready

### 5. All 4 Microservices
- ✅ Catalogue (Python/Flask + MongoDB)
- ✅ Frontend (Node.js/React)
- ✅ Recommendation (Go + Redis)
- ✅ Voting (Java/Spring Boot + PostgreSQL)

## 📁 Repository Structure

```
craftista-gitOps/
├── argocd/
│   └── applications/
│       └── clusters/homelab/
│           ├── dev/          # Dev ArgoCD apps
│           ├── staging/      # Staging ArgoCD apps
│           └── prod/         # Production ArgoCD apps
│               ├── bootstrap-app.yaml
│               ├── catalogue-app.yaml
│               ├── frontend-app.yaml
│               ├── recommendation-app.yaml
│               └── voting-app.yaml
├── kubernetes/
│   ├── base/                 # Base manifests (Rollouts)
│   │   ├── catalogue/
│   │   ├── frontend/
│   │   ├── recommendation/
│   │   └── voting/
│   └── overlays/homelab/
│       ├── dev/              # Dev overlays
│       ├── staging/          # Staging overlays
│       └── prod/             # Production overlays
│           ├── catalogue/
│           ├── frontend/
│           ├── recommendation/
│           └── voting/
└── docs/
    ├── CANARY_DEPLOYMENT.md
    ├── QUICKSTART_CANARY.md
    ├── PRODUCTION_SETUP.md
    └── ENVIRONMENTS.md
```

## 🚀 Quick Start

### Deploy to Production

1. **Apply bootstrap app**:
   ```bash
   kubectl apply -f argocd/applications/clusters/homelab/prod/bootstrap-app.yaml
   ```

2. **Verify deployment**:
   ```bash
   kubectl get application -n argocd -l environment=production
   kubectl get rollout -n craftista-prod
   ```

3. **Monitor rollouts**:
   ```bash
   kubectl argo rollouts get rollout frontend -n craftista-prod --watch
   ```

### Deploy New Version

1. **Update image tag** in `kubernetes/overlays/homelab/prod/{service}/patches.yaml`
2. **Commit and push** to Git
3. **ArgoCD automatically syncs** and triggers canary deployment
4. **Monitor and promote** as needed

## 📊 Environment Comparison

| Feature | Dev | Staging | Production |
|---------|-----|---------|------------|
| Replicas | 1 | 2 | 2-3 |
| CPU Limits | 200m | 400m | 1000m |
| Memory Limits | 256Mi | 512Mi | 512Mi |
| Auto-Sync | ✅ | ✅ | ✅ |
| Canary | ✅ | ✅ | ✅ |
| Image Tag | dev-latest | dev-latest | prod-latest |

## 🔄 GitOps Workflow

```
┌─────────────┐
│   Develop   │
│   (branch)  │
└──────┬──────┘
       │ push
       ↓
┌─────────────┐      ┌─────────────┐
│     CI      │─────→│  Dev Env    │
│   Pipeline  │      │ (automated) │
└──────┬──────┘      └─────────────┘
       │ merge to main
       ↓
┌─────────────┐      ┌─────────────┐
│     CI      │─────→│ Staging Env │
│   Pipeline  │      │ (automated) │
└──────┬──────┘      └─────────────┘
       │ tag release
       ↓
┌─────────────┐      ┌─────────────┐
│     CI      │─────→│  Prod Env   │
│   Pipeline  │      │  (canary)   │
└─────────────┘      └─────────────┘
```

## 🎯 Canary Deployment Flow

```
1. Deploy Canary Pods
   ↓
2. Route 20% Traffic → Pause 2min
   ↓
3. Route 50% Traffic → Pause 2min
   ↓
4. Route 80% Traffic → Pause 1min
   ↓
5. Route 100% Traffic (Full Promotion)
```

## 📝 Key Commands

### Check Status
```bash
# All environments
for env in dev staging prod; do
  kubectl get rollout -n craftista-$env
done

# Production health
for svc in catalogue frontend recommendation voting; do
  kubectl argo rollouts status $svc -n craftista-prod --timeout 2s
done
```

### Control Deployments
```bash
# Promote canary
kubectl argo rollouts promote <service> -n craftista-prod

# Abort and rollback
kubectl argo rollouts abort <service> -n craftista-prod
kubectl argo rollouts undo <service> -n craftista-prod
```

### Monitor
```bash
# Watch rollout
kubectl argo rollouts get rollout <service> -n craftista-prod --watch

# View history
kubectl argo rollouts history <service> -n craftista-prod
```

## 🔒 Production Safety

### Built-in Safeguards
- ✅ Canary deployment with pauses
- ✅ Automated health checks
- ✅ Instant rollback capability
- ✅ GitOps audit trail
- ✅ Resource limits prevent overload

### Best Practices
1. Always test in dev → staging → production
2. Monitor metrics during canary phases
3. Use manual promotion in production
4. Keep rollout history for quick rollback
5. Document all production changes

## 📚 Documentation

- **[Canary Deployment Guide](docs/CANARY_DEPLOYMENT.md)** - Complete configuration reference
- **[Quick Start](docs/QUICKSTART_CANARY.md)** - Common operations
- **[Production Setup](docs/PRODUCTION_SETUP.md)** - Production deployment guide
- **[Environments](docs/ENVIRONMENTS.md)** - Environment comparison

## 🎓 What You've Learned

This setup demonstrates:
- ✅ **GitOps**: Infrastructure as code with Git as source of truth
- ✅ **Progressive Delivery**: Safe deployments with canary strategy
- ✅ **High Availability**: Multiple replicas with proper resource limits
- ✅ **Observability**: Rollout tracking and history
- ✅ **Automation**: ArgoCD automated sync and self-healing
- ✅ **Production-Grade**: Enterprise patterns and best practices

## 🚀 Next Steps

### Immediate
1. Deploy to production using bootstrap app
2. Test canary deployment flow
3. Practice rollback procedures

### Future Enhancements
1. Add Prometheus metrics for automated analysis
2. Implement automated rollback on error thresholds
3. Add smoke tests between canary steps
4. Set up Slack/PagerDuty notifications
5. Implement blue-green deployment option
6. Add chaos engineering tests

## 🎉 You're Production Ready!

Your GitOps setup now includes:
- ✅ Three fully configured environments
- ✅ Canary deployments for safe releases
- ✅ Automated GitOps workflow
- ✅ Production-grade configuration
- ✅ Complete documentation

**Ready to deploy to production!** 🚀
