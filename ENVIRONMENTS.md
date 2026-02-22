# Craftista Environments Comparison

## Environment Overview

| Environment | Namespace | Purpose | Replicas | Auto-Sync |
|-------------|-----------|---------|----------|-----------|
| **Dev** | craftista-dev | Active development | 1 | ✅ Enabled |
| **Staging** | craftista-staging | Pre-production testing | 2 | ✅ Enabled |
| **Prod** | craftista-prod | Production | 3 | ✅ Enabled |

## Configuration Differences

### Resource Allocation

| Service | Dev CPU/Memory | Staging CPU/Memory | Prod CPU/Memory |
|---------|----------------|--------------------|--------------------|
| Catalogue | 100m / 128Mi | 200m / 256Mi | 500m / 512Mi |
| Frontend | 100m / 128Mi | 200m / 256Mi | 500m / 512Mi |
| Voting | 100m / 128Mi | 200m / 256Mi | 500m / 512Mi |
| Recommendation | 100m / 128Mi | 200m / 256Mi | 500m / 512Mi |

### Environment Variables

| Variable | Dev | Staging | Prod |
|----------|-----|---------|------|
| LOG_LEVEL | DEBUG | INFO | WARN |
| FLASK_DEBUG | True | False | False |
| NODE_ENV | development | staging | production |
| GIN_MODE | debug | release | release |

### Database Configuration

| Database | Dev | Staging | Prod |
|----------|-----|---------|------|
| MongoDB | Single instance | Single instance | Replica Set (3) |
| PostgreSQL | Single instance | Single instance | HA Cluster |
| Redis | Single instance | Single instance | Sentinel (3) |

## Deployment Workflow

```
┌─────────────┐
│   Dev       │  ← Continuous deployment from 'develop' branch
│  (1 replica)│
└──────┬──────┘
       │
       │ Promote (manual/automated)
       ↓
┌─────────────┐
│  Staging    │  ← Testing and validation
│ (2 replicas)│
└──────┬──────┘
       │
       │ Promote (manual approval required)
       ↓
┌─────────────┐
│  Production │  ← Live environment
│ (3 replicas)│
└─────────────┘
```

## Promotion Process

### Dev → Staging

**Automated**:
```bash
./promote-dev-to-staging.sh
```

**Manual**:
1. Get dev image tags
2. Update staging kustomization files
3. Commit and push
4. ArgoCD auto-syncs

### Staging → Production

**Manual** (requires approval):
```bash
./scripts/promote-to-prod.sh
```

**Process**:
1. Validate staging deployment
2. Run integration tests
3. Get stakeholder approval
4. Update prod kustomization files
5. Create release tag
6. Deploy to production

## Access URLs

| Environment | Frontend | Catalogue API | Voting API | Recommendation API |
|-------------|----------|---------------|------------|-------------------|
| **Dev** | dev.craftista.local | dev.craftista.local/api/catalogue | dev.craftista.local/api/voting | dev.craftista.local/api/recommendation |
| **Staging** | staging.craftista.local | staging.craftista.local/api/catalogue | staging.craftista.local/api/voting | staging.craftista.local/api/recommendation |
| **Prod** | craftista.com | api.craftista.com/catalogue | api.craftista.com/voting | api.craftista.com/recommendation |

## Monitoring & Observability

| Aspect | Dev | Staging | Prod |
|--------|-----|---------|------|
| Metrics | Basic | Full | Full + Alerts |
| Logging | Console | Aggregated | Aggregated + Retention |
| Tracing | Disabled | Enabled | Enabled |
| Alerts | None | Basic | Comprehensive |
| Uptime SLA | None | None | 99.9% |

## Security

| Feature | Dev | Staging | Prod |
|---------|-----|---------|------|
| TLS/SSL | Self-signed | Let's Encrypt | Commercial Cert |
| Network Policies | Basic | Enforced | Enforced |
| Pod Security | Permissive | Restricted | Restricted |
| Secrets Rotation | Manual | Manual | Automated |
| Vulnerability Scanning | Weekly | Daily | Daily |

## Backup & DR

| Aspect | Dev | Staging | Prod |
|--------|-----|---------|------|
| Database Backups | None | Daily | Hourly |
| Backup Retention | N/A | 7 days | 30 days |
| Disaster Recovery | None | Manual | Automated |
| RTO | N/A | 4 hours | 1 hour |
| RPO | N/A | 24 hours | 1 hour |

## Cost Optimization

| Environment | Estimated Monthly Cost | Scaling Strategy |
|-------------|----------------------|------------------|
| Dev | $50-100 | Fixed (1 replica) |
| Staging | $150-250 | Fixed (2 replicas) |
| Prod | $500-1000 | HPA (3-10 replicas) |

## Testing Strategy

### Dev Environment
- Unit tests
- Integration tests
- Developer smoke tests
- Rapid iteration

### Staging Environment
- Full integration tests
- End-to-end tests
- Performance tests
- Security scans
- UAT (User Acceptance Testing)
- Load testing

### Production Environment
- Smoke tests post-deployment
- Synthetic monitoring
- Real user monitoring
- Canary deployments
- Blue/green deployments

## Current Status

### ✅ Dev Environment
- Status: **Deployed and Running**
- Services: 4/4 healthy
- Last Updated: Current
- Image Tags: Latest from develop branch

### ✅ Staging Environment
- Status: **Configured, Ready to Deploy**
- Services: 0/4 (not yet deployed)
- Configuration: Complete
- Image Tags: Promoted from dev

### ⏳ Production Environment
- Status: **Configured, Awaiting Deployment**
- Services: TBD
- Configuration: Complete
- Image Tags: TBD

## Quick Commands

### Check All Environments
```bash
# Dev
kubectl get pods -n craftista-dev
kubectl get applications -n argocd -l environment=dev

# Staging
kubectl get pods -n craftista-staging
kubectl get applications -n argocd -l environment=staging

# Prod
kubectl get pods -n craftista-prod
kubectl get applications -n argocd -l environment=prod
```

### Compare Image Tags
```bash
for env in dev staging prod; do
  echo "=== $env ==="
  grep "newTag:" kubernetes/overlays/homelab/$env/catalogue/kustomization.yaml
done
```

## Best Practices

1. **Always test in dev first**
2. **Promote to staging for validation**
3. **Run full test suite in staging**
4. **Get approval before prod deployment**
5. **Use feature flags for risky changes**
6. **Monitor closely after deployment**
7. **Have rollback plan ready**
8. **Document all changes**

## Related Documentation

- [Dev Environment](kubernetes/overlays/homelab/dev/README.md)
- [Staging Environment](kubernetes/overlays/homelab/staging/README.md)
- [Production Environment](kubernetes/overlays/homelab/prod/README.md)
- [Deployment Guide](DEPLOYMENT_GUIDE.md)
- [ArgoCD Documentation](argocd/docs/)
