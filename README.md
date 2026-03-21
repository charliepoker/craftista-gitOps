# Craftista GitOps Repository

GitOps configuration repository for the [Craftista](https://github.com/charliepoker/craftista) microservices application. This repo is the single source of truth for all Kubernetes deployments, managed by ArgoCD.

## Quick Start

```bash
# 1. Install ArgoCD project
kubectl apply -f argocd/projects/craftista-homelab.yaml

# 2. Deploy dev dependencies (MongoDB, PostgreSQL, Redis)
kubectl apply -f argocd/applications/clusters/homelab/dev/deps-app.yaml

# 3. Deploy dev services
for app in catalogue frontend voting recommendation; do
  kubectl apply -f argocd/applications/clusters/homelab/dev/${app}-app.yaml
done

# 4. Watch deployment
kubectl get pods -n craftista-dev -w
```

## Architecture

| Service | Language | Port | Database | Image |
|---|---|---|---|---|
| Frontend | Node.js | 3000 | — | `8060633493/craftista-frontend` |
| Catalogue | Python/Flask | 5000 | MongoDB | `8060633493/craftista-catalogue` |
| Recommendation | Go/Gin | 8080 | Redis | `8060633493/craftista-recommendation` |
| Voting | Java/Spring Boot | 8080 | PostgreSQL | `8060633493/craftista-voting` |

## Environments

| Environment | Namespace | Replicas | Domain |
|---|---|---|---|
| Dev | `craftista-dev` | 1 | `*.home-lab.webdemoapp.com` |
| Staging | `craftista-staging` | 2 | `*.staging.webdemoapp.com` |
| Production | `craftista-prod` | 3 | `*.webdemoapp.com` |

## Deployment Flow

```
Code push → GitHub Actions CI → Docker Hub → Update this repo → ArgoCD sync → Argo Rollouts canary
```

## Documentation

| Document | Description |
|---|---|
| [Deployment Guide](docs/DEPLOYMENT_GUIDE.md) | Step-by-step guide for deploying to dev, staging, and production |
| [GitOps Framework](docs/GITOPS_FRAMEWORK.md) | Complete guide to GitOps patterns and tools used |
| [EKS Migration Guide](docs/EKS_MIGRATION_GUIDE.md) | Guide for migrating from homelab to AWS EKS |
| [Runbook](docs/RUNBOOK.md) | Operational runbook for day-to-day management |
| [Incident Response](docs/INCIDENT_RESPONSE.md) | Incident response playbooks and templates |
| [Architecture Decisions](docs/ARCHITECTURE_DECISION_RECORDS.md) | ADRs documenting key design choices |
| [Environments](docs/ENVIRONMENTS.md) | Environment configuration details |
| [Production Setup](docs/PRODUCTION_SETUP.md) | Production-specific setup instructions |

## Repository Structure

```
├── argocd/                    # ArgoCD applications and projects
│   ├── applications/clusters/ # Per-cluster, per-env ArgoCD apps
│   ├── install/               # ArgoCD installation manifests
│   └── projects/              # AppProject definitions
├── kubernetes/
│   ├── base/                  # Base Kustomize manifests
│   ├── overlays/              # Environment-specific patches
│   └── common/                # Network policies, RBAC
├── helm/charts/               # Helm charts (alternative packaging)
├── external-secrets/          # External Secrets Operator configs
├── vault/                     # Vault policies and auth
├── scripts/                   # Operational scripts
└── docs/                      # Documentation
```

## Tools Used

- **ArgoCD** — GitOps continuous delivery
- **Argo Rollouts** — Canary deployments with NGINX traffic splitting
- **Kustomize** — Base/overlay configuration management
- **Helm** — Alternative chart-based packaging
- **HashiCorp Vault** — Secrets management
- **External Secrets Operator** — Vault-to-Kubernetes secret sync
- **cert-manager** — Automated TLS certificate management
- **NGINX Ingress** — Ingress controller with canary support
