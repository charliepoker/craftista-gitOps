# Craftista Staging Environment - Quick Start Guide

## ✅ What's Been Configured

Your staging environment is now fully configured with:

- ✅ **Namespace**: `craftista-staging`
- ✅ **Services**: catalogue, frontend, voting, recommendation (2 replicas each)
- ✅ **Dependencies**: MongoDB, PostgreSQL, Redis
- ✅ **ArgoCD Apps**: All services configured with auto-sync
- ✅ **Image Tags**: Set from current dev deployment
- ✅ **Secrets**: External Secrets configured for Vault integration
- ✅ **Ingress**: Configured for staging domain

## 🚀 Deploy Staging Environment

### Option 1: Automated Deployment (Recommended)

```bash
cd ~/Documents/craftista-gitOps
./deploy-staging.sh
```

### Option 2: Manual Deployment

```bash
# Apply all ArgoCD applications for staging
kubectl apply -f argocd/applications/clusters/homelab/staging/

# Monitor deployment
kubectl get applications -n argocd -l environment=staging -w
```

## 📊 Current Image Tags

All services are configured with these image tags (from dev):

- **catalogue**: `develop-a911a8cb2698b5817d6395cab388bc271d1b9693`
- **frontend**: `develop-a911a8cb2698b5817d6395cab388bc271d1b9693`
- **voting**: `develop-a911a8cb2698b5817d6395cab388bc271d1b9693`
- **recommendation**: `develop-589912414e58cdd4a124215c362c24d391953dd0`

## 🔄 Promote from Dev to Staging

When you want to promote new versions from dev:

```bash
cd ~/Documents/craftista-gitOps
./promote-dev-to-staging.sh
```

This will:
1. Show current dev image tags
2. Ask for confirmation
3. Update staging kustomization files
4. Commit and push changes
5. ArgoCD auto-syncs within 3 minutes

## 📝 Verify Deployment

```bash
# Check ArgoCD applications
kubectl get applications -n argocd -l environment=staging

# Check pods
kubectl get pods -n craftista-staging

# Check services
kubectl get svc -n craftista-staging

# Check ingress
kubectl get ingress -n craftista-staging
```

## 🔍 Monitor Status

```bash
# Watch pods come up
kubectl get pods -n craftista-staging -w

# View logs for a service
kubectl logs -n craftista-staging -l app=catalogue -f

# Check ArgoCD sync status
kubectl get application craftista-catalogue-staging -n argocd -o jsonpath='{.status.sync.status}'
```

## 🌐 Access Staging

Once deployed, access your staging environment:

- **Frontend**: https://staging.craftista.local
- **Catalogue API**: https://staging.craftista.local/api/catalogue
- **Voting API**: https://staging.craftista.local/api/voting
- **Recommendation API**: https://staging.craftista.local/api/recommendation

## 🔧 Common Commands

```bash
# Force ArgoCD sync
kubectl patch application craftista-catalogue-staging -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Scale a service
kubectl scale deployment catalogue -n craftista-staging --replicas=3

# Restart a service
kubectl rollout restart deployment catalogue -n craftista-staging

# Check resource usage
kubectl top pods -n craftista-staging
```

## 📚 Documentation

- Full staging docs: `kubernetes/overlays/homelab/staging/README.md`
- ArgoCD docs: `argocd/docs/`
- Troubleshooting: `argocd/docs/runbooks/troubleshooting.md`

## 🆘 Troubleshooting

### Pods not starting?
```bash
kubectl describe pod <pod-name> -n craftista-staging
kubectl logs <pod-name> -n craftista-staging
```

### ArgoCD not syncing?
```bash
kubectl get application <app-name> -n argocd -o yaml | grep -A 10 status
```

### Database connection issues?
```bash
kubectl get pods -n craftista-staging -l app=mongodb
kubectl logs -n craftista-staging -l app=mongodb
```

## 🎯 Next Steps

1. Deploy staging: `./deploy-staging.sh`
2. Verify all pods are running
3. Test application functionality
4. Set up CI/CD to auto-promote to staging
5. Configure monitoring and alerting

## 📞 Need Help?

- Check the full README: `kubernetes/overlays/homelab/staging/README.md`
- Review ArgoCD docs: `argocd/docs/`
- Check runbooks: `argocd/docs/runbooks/`
