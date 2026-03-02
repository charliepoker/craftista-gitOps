# Craftista GitOps Repository

GitOps repository for Craftista microservices deployment using ArgoCD and Argo Rollouts.

## Architecture

- **4 Microservices**: catalogue, frontend, voting, recommendation
- **Deployment Strategy**: Canary deployments with Argo Rollouts
- **GitOps**: ArgoCD for automated sync and deployment
- **Environments**: Dev and Staging

## Quick Links

- [Canary Deployment Documentation](docs/CANARY_DEPLOYMENT.md)
- [Quick Start Guide](docs/QUICKSTART_CANARY.md)

## Current Status

### Dev Environment
- ✅ Catalogue: Healthy (Rollout with canary)
- ✅ Frontend: Healthy (Rollout with canary)
- ✅ Recommendation: Healthy (Rollout with canary)
- ✅ Voting: Healthy (Rollout with canary)

### Staging Environment
- ✅ Catalogue: Healthy (Rollout with canary)
- ✅ Frontend: Healthy (Rollout with canary)
- ✅ Recommendation: Healthy (Rollout with canary)
- ✅ Voting: Healthy (Rollout with canary)

## Canary Deployment Flow

```
Deploy → 20% traffic (2min) → 50% traffic (2min) → 80% traffic (1min) → 100%
```

## Repository Structure

```
.
├── argocd/
│   └── applications/          # ArgoCD Application manifests
├── kubernetes/
│   ├── base/                  # Base Kubernetes manifests
│   │   ├── catalogue/
│   │   ├── frontend/
│   │   ├── recommendation/
│   │   └── voting/
│   └── overlays/              # Environment-specific overlays
│       └── homelab/
│           ├── dev/
│           └── staging/
└── docs/                      # Documentation
    ├── CANARY_DEPLOYMENT.md
    └── QUICKSTART_CANARY.md
```

## Prerequisites

- Kubernetes cluster
- ArgoCD installed
- Argo Rollouts installed
- kubectl-argo-rollouts CLI plugin

## Quick Start

### Check Status
```bash
# Dev environment
kubectl get rollout -n craftista-dev

# Staging environment
kubectl get rollout -n craftista-staging
```

### Deploy New Version
```bash
# Update image tag in patches.yaml
# Commit and push - ArgoCD will sync automatically

# Or manually trigger
kubectl argo rollouts set image frontend \
  frontend=8060633493/craftista-frontend:new-tag \
  -n craftista-staging
```

### Monitor Deployment
```bash
kubectl argo rollouts get rollout frontend -n craftista-staging --watch
```

### Control Deployment
```bash
# Promote to next step
kubectl argo rollouts promote frontend -n craftista-staging

# Fully promote (skip pauses)
kubectl argo rollouts promote frontend -n craftista-staging --full

# Abort and rollback
kubectl argo rollouts abort frontend -n craftista-staging
```

## Key Features

- ✅ **Progressive Traffic Shifting**: 20% → 50% → 80% → 100%
- ✅ **Automated Pauses**: Built-in validation windows
- ✅ **Instant Rollback**: Abort and revert to stable version
- ✅ **GitOps Workflow**: All changes tracked in Git
- ✅ **ArgoCD Integration**: Automated sync and deployment
- ✅ **Multi-Environment**: Dev and Staging with different configs

## Service Endpoints

### Dev
- Frontend: https://frontend.home-lab.webdemoapp.com
- Catalogue: https://catalogue.home-lab.webdemoapp.com
- Voting: https://voting.home-lab.webdemoapp.com
- Recommendation: https://recommendation.home-lab.webdemoapp.com

### Staging
- Frontend: https://frontend.staging.webdemoapp.com
- Catalogue: https://catalogue.staging.webdemoapp.com
- Voting: https://voting.staging.webdemoapp.com
- Recommendation: https://recommendation.staging.webdemoapp.com

## Common Operations

### Health Check
```bash
# All services
for svc in catalogue frontend recommendation voting; do
  kubectl argo rollouts status $svc -n craftista-staging --timeout 2s
done

# ArgoCD apps
kubectl get application -n argocd -l environment=staging
```

### Rollback
```bash
# Undo to previous version
kubectl argo rollouts undo <service> -n <namespace>

# Undo to specific revision
kubectl argo rollouts undo <service> --to-revision=<n> -n <namespace>
```

### View History
```bash
kubectl argo rollouts history <service> -n <namespace>
```

## Troubleshooting

See [Canary Deployment Documentation](docs/CANARY_DEPLOYMENT.md#troubleshooting) for common issues and solutions.

## Contributing

1. Create feature branch
2. Make changes
3. Test in dev environment
4. Create PR for review
5. Merge to main (triggers staging deployment)

## License

MIT
