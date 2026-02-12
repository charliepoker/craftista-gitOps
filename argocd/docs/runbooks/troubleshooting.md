# Troubleshooting Guide

This guide provides solutions for common issues encountered in the Craftista GitOps environment. Use this as your first reference when diagnosing problems with deployments, applications, or infrastructure.

## Table of Contents

- [Quick Diagnostic Commands](#quick-diagnostic-commands)
- [ArgoCD Issues](#argocd-issues)
- [Application Deployment Issues](#application-deployment-issues)
- [Secrets and Vault Issues](#secrets-and-vault-issues)
- [Network and Connectivity Issues](#network-and-connectivity-issues)
- [Database Connection Issues](#database-connection-issues)
- [Performance Issues](#performance-issues)
- [CI/CD Pipeline Issues](#cicd-pipeline-issues)
- [Monitoring and Logging](#monitoring-and-logging)
- [Emergency Procedures](#emergency-procedures)

## Quick Diagnostic Commands

### System Health Check

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes -o wide

# Check all pods across environments
kubectl get pods --all-namespaces | grep craftista

# Check ArgoCD applications
argocd app list

# Check Vault status
kubectl exec vault-0 -n vault -- vault status

# Check External Secrets Operator
kubectl get externalsecrets --all-namespaces
```

### Resource Usage

```bash
# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces | grep craftista

# Check storage usage
kubectl get pv
kubectl get pvc --all-namespaces

# Check events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20
```

## ArgoCD Issues

### Application Stuck in "Progressing" State

**Symptoms**: ArgoCD application shows "Progressing" for extended period

**Diagnosis**:

```bash
# Check application status
argocd app get craftista-frontend-prod

# Check application events
kubectl describe application craftista-frontend-prod -n argocd

# Check controller logs
kubectl logs -f deployment/argocd-application-controller -n argocd
```

**Solutions**:

1. **Force Refresh and Sync**:

   ```bash
   argocd app get craftista-frontend-prod --refresh
   argocd app sync craftista-frontend-prod --force
   ```

2. **Check Resource Conflicts**:

   ```bash
   # Look for resource conflicts
   kubectl get events -n craftista-prod --sort-by='.lastTimestamp'

   # Check for stuck resources
   kubectl get all -n craftista-prod | grep -E "(Pending|Error|CrashLoopBackOff)"
   ```

3. **Reset Application State**:
   ```bash
   # Delete and recreate application (last resort)
   argocd app delete craftista-frontend-prod --cascade=false
   kubectl apply -f argocd/applications/prod/frontend-app.yaml
   ```

### ArgoCD Sync Failures

**Symptoms**: Applications fail to sync with errors

**Common Errors and Solutions**:

1. **"Resource not found" Error**:

   ```bash
   # Check if namespace exists
   kubectl get namespace craftista-prod

   # Create namespace if missing
   kubectl create namespace craftista-prod
   ```

2. **"Insufficient permissions" Error**:

   ```bash
   # Check ArgoCD service account permissions
   kubectl get clusterrolebinding | grep argocd

   # Check specific permissions
   kubectl auth can-i create deployments --as=system:serviceaccount:argocd:argocd-application-controller -n craftista-prod
   ```

3. **"Invalid manifest" Error**:

   ```bash
   # Validate Kubernetes manifests
   kubectl apply --dry-run=client -f kubernetes/overlays/prod/frontend/

   # Check Kustomize build
   kubectl kustomize kubernetes/overlays/prod/frontend/
   ```

### ArgoCD Server Not Accessible

**Symptoms**: Cannot access ArgoCD UI or CLI fails to connect

**Solutions**:

1. **Check ArgoCD Server Status**:

   ```bash
   kubectl get pods -n argocd | grep argocd-server
   kubectl logs -f deployment/argocd-server -n argocd
   ```

2. **Port Forward for Local Access**:

   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```

3. **Check Ingress Configuration**:
   ```bash
   kubectl get ingress -n argocd
   kubectl describe ingress argocd-server-ingress -n argocd
   ```

## Application Deployment Issues

### Pods Stuck in Pending State

**Symptoms**: Pods remain in "Pending" status

**Diagnosis**:

```bash
# Check pod details
kubectl describe pod <pod-name> -n craftista-prod

# Check node resources
kubectl describe nodes
kubectl top nodes
```

**Common Causes and Solutions**:

1. **Insufficient Resources**:

   ```bash
   # Check resource requests vs available
   kubectl describe nodes | grep -A 5 "Allocated resources"

   # Reduce resource requests temporarily
   kubectl patch deployment frontend -n craftista-prod -p '{"spec":{"template":{"spec":{"containers":[{"name":"frontend","resources":{"requests":{"cpu":"50m","memory":"64Mi"}}}]}}}}'
   ```

2. **Node Selector Issues**:

   ```bash
   # Check node labels
   kubectl get nodes --show-labels

   # Remove node selector if problematic
   kubectl patch deployment frontend -n craftista-prod -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
   ```

3. **PVC Issues**:
   ```bash
   # Check persistent volume claims
   kubectl get pvc -n craftista-prod
   kubectl describe pvc <pvc-name> -n craftista-prod
   ```

### Pods in CrashLoopBackOff

**Symptoms**: Pods continuously restart

**Diagnosis**:

```bash
# Check pod logs
kubectl logs <pod-name> -n craftista-prod --previous

# Check pod events
kubectl describe pod <pod-name> -n craftista-prod

# Check liveness/readiness probes
kubectl get pod <pod-name> -n craftista-prod -o yaml | grep -A 10 "livenessProbe\|readinessProbe"
```

**Solutions**:

1. **Application Startup Issues**:

   ```bash
   # Increase startup time
   kubectl patch deployment frontend -n craftista-prod -p '{"spec":{"template":{"spec":{"containers":[{"name":"frontend","livenessProbe":{"initialDelaySeconds":60}}]}}}}'

   # Check environment variables
   kubectl exec <pod-name> -n craftista-prod -- env | grep -E "(DATABASE|REDIS|MONGO)"
   ```

2. **Resource Limits**:

   ```bash
   # Increase memory limits
   kubectl patch deployment frontend -n craftista-prod -p '{"spec":{"template":{"spec":{"containers":[{"name":"frontend","resources":{"limits":{"memory":"512Mi"}}}]}}}}'
   ```

3. **Configuration Issues**:

   ```bash
   # Check ConfigMaps and Secrets
   kubectl get configmap -n craftista-prod
   kubectl get secrets -n craftista-prod

   # Verify secret data
   kubectl get secret frontend-secrets -n craftista-prod -o yaml
   ```

### Image Pull Errors

**Symptoms**: "ImagePullBackOff" or "ErrImagePull" status

**Solutions**:

1. **Check Image Exists**:

   ```bash
   # Verify image in registry
   docker pull 8060633493/craftista-frontend:latest

   # Check image tag in deployment
   kubectl get deployment frontend -n craftista-prod -o yaml | grep image:
   ```

2. **Registry Authentication**:

   ```bash
   # Check image pull secrets
   kubectl get secrets -n craftista-prod | grep docker

   # Create image pull secret if missing
   kubectl create secret docker-registry dockerhub-secret \
     --docker-server=docker.io \
     --docker-username=$DOCKERHUB_USERNAME \
     --docker-password=$DOCKERHUB_PASSWORD \
     -n craftista-prod
   ```

## Secrets and Vault Issues

### External Secrets Not Syncing

**Symptoms**: Kubernetes secrets not created from Vault

**Diagnosis**:

```bash
# Check External Secrets status
kubectl get externalsecrets -n craftista-prod
kubectl describe externalsecret frontend-secrets -n craftista-prod

# Check External Secrets Operator logs
kubectl logs -f deployment/external-secrets -n external-secrets-system
```

**Solutions**:

1. **Vault Connectivity**:

   ```bash
   # Test Vault connection from cluster
   kubectl run vault-test --rm -it --image=vault:latest -- vault status -address=http://vault.vault:8200

   # Check Vault service
   kubectl get svc -n vault
   ```

2. **Authentication Issues**:

   ```bash
   # Check Kubernetes auth configuration
   kubectl exec vault-0 -n vault -- vault auth list

   # Test service account token
   kubectl exec vault-0 -n vault -- vault write auth/kubernetes/login role=frontend jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
   ```

3. **Secret Path Issues**:

   ```bash
   # Verify secret exists in Vault
   kubectl exec vault-0 -n vault -- vault kv get secret/craftista/prod/frontend/config

   # Check secret store configuration
   kubectl get secretstore -n craftista-prod -o yaml
   ```

### Vault Sealed or Unavailable

**Symptoms**: Vault returns "sealed" status or is unreachable

**Solutions**:

1. **Unseal Vault**:

   ```bash
   # Check Vault status
   kubectl exec vault-0 -n vault -- vault status

   # Unseal Vault (requires unseal keys)
   kubectl exec vault-0 -n vault -- vault operator unseal <unseal-key-1>
   kubectl exec vault-0 -n vault -- vault operator unseal <unseal-key-2>
   kubectl exec vault-0 -n vault -- vault operator unseal <unseal-key-3>
   ```

2. **Vault Pod Issues**:

   ```bash
   # Check Vault pods
   kubectl get pods -n vault
   kubectl logs -f vault-0 -n vault

   # Restart Vault if needed
   kubectl delete pod vault-0 -n vault
   ```

## Network and Connectivity Issues

### Service-to-Service Communication Failures

**Symptoms**: Services cannot communicate with each other

**Diagnosis**:

```bash
# Test internal connectivity
kubectl exec -it deployment/frontend -n craftista-prod -- curl http://catalogue:5000/health

# Check service endpoints
kubectl get endpoints -n craftista-prod

# Check network policies
kubectl get networkpolicies -n craftista-prod
```

**Solutions**:

1. **DNS Resolution Issues**:

   ```bash
   # Test DNS resolution
   kubectl exec -it deployment/frontend -n craftista-prod -- nslookup catalogue.craftista-prod.svc.cluster.local

   # Check CoreDNS
   kubectl get pods -n kube-system | grep coredns
   kubectl logs -f deployment/coredns -n kube-system
   ```

2. **Network Policy Blocking**:

   ```bash
   # Temporarily disable network policies for testing
   kubectl delete networkpolicy --all -n craftista-prod

   # Check specific policy
   kubectl describe networkpolicy frontend-policy -n craftista-prod
   ```

3. **Service Configuration**:

   ```bash
   # Check service configuration
   kubectl get svc catalogue -n craftista-prod -o yaml

   # Verify service selector matches pod labels
   kubectl get pods -n craftista-prod --show-labels | grep catalogue
   ```

### Ingress Not Working

**Symptoms**: External access to applications fails

**Solutions**:

1. **Check Ingress Controller**:

   ```bash
   # Check ingress controller pods
   kubectl get pods -n ingress-nginx
   kubectl logs -f deployment/ingress-nginx-controller -n ingress-nginx
   ```

2. **Verify Ingress Configuration**:

   ```bash
   # Check ingress resources
   kubectl get ingress -n craftista-prod
   kubectl describe ingress frontend-ingress -n craftista-prod

   # Test ingress controller directly
   kubectl port-forward svc/ingress-nginx-controller 8080:80 -n ingress-nginx
   ```

3. **DNS and SSL Issues**:

   ```bash
   # Check DNS resolution
   nslookup webdemoapp.com

   # Check SSL certificates
   kubectl get certificates -n craftista-prod
   kubectl describe certificate frontend-tls -n craftista-prod
   ```

## Database Connection Issues

### MongoDB Connection Failures (Catalogue Service)

**Symptoms**: Catalogue service cannot connect to MongoDB

**Solutions**:

1. **Check Connection String**:

   ```bash
   # Verify MongoDB URI in secret
   kubectl get secret catalogue-secrets -n craftista-prod -o jsonpath='{.data.mongodb-uri}' | base64 -d

   # Test connection from pod
   kubectl exec -it deployment/catalogue -n craftista-prod -- python -c "
   import pymongo
   import os
   client = pymongo.MongoClient(os.environ['MONGODB_URI'])
   print(client.admin.command('ping'))
   "
   ```

2. **DocumentDB Connectivity**:

   ```bash
   # Check DocumentDB cluster status (from AWS CLI)
   aws docdb describe-db-clusters --db-cluster-identifier craftista-docdb-prod

   # Test network connectivity
   kubectl run mongodb-test --rm -it --image=mongo:4.4 -- mongo --host <docdb-endpoint> --port 27017 --ssl --sslAllowInvalidCertificates
   ```

### PostgreSQL Connection Failures (Voting Service)

**Symptoms**: Voting service cannot connect to PostgreSQL

**Solutions**:

1. **Check Connection Parameters**:

   ```bash
   # Verify PostgreSQL URI
   kubectl get secret voting-secrets -n craftista-prod -o jsonpath='{.data.postgres-uri}' | base64 -d

   # Test connection
   kubectl exec -it deployment/voting -n craftista-prod -- psql $POSTGRES_URI -c "SELECT 1;"
   ```

2. **RDS Connectivity**:

   ```bash
   # Check RDS instance status
   aws rds describe-db-instances --db-instance-identifier craftista-rds-prod

   # Test network connectivity
   kubectl run postgres-test --rm -it --image=postgres:13 -- psql -h <rds-endpoint> -U <username> -d voting
   ```

### Redis Connection Failures (Recommendation Service)

**Symptoms**: Recommendation service cannot connect to Redis

**Solutions**:

1. **Check Redis Configuration**:

   ```bash
   # Verify Redis URI
   kubectl get secret recommendation-secrets -n craftista-prod -o jsonpath='{.data.redis-uri}' | base64 -d

   # Test Redis connection
   kubectl exec -it deployment/recommendation -n craftista-prod -- redis-cli -u $REDIS_URI ping
   ```

2. **ElastiCache Connectivity**:

   ```bash
   # Check ElastiCache cluster status
   aws elasticache describe-cache-clusters --cache-cluster-id craftista-redis-prod

   # Test connectivity
   kubectl run redis-test --rm -it --image=redis:6 -- redis-cli -h <elasticache-endpoint> -p 6379 ping
   ```

## Performance Issues

### High Response Times

**Symptoms**: Application responses are slow

**Diagnosis**:

```bash
# Check response times
curl -w "@curl-format.txt" -o /dev/null -s https://webdemoapp.com/

# Check resource usage
kubectl top pods -n craftista-prod
kubectl top nodes

# Check application metrics
kubectl exec -it deployment/frontend -n craftista-prod -- curl http://localhost:3000/metrics
```

**Solutions**:

1. **Scale Up Resources**:

   ```bash
   # Increase CPU/memory limits
   kubectl patch deployment frontend -n craftista-prod -p '{"spec":{"template":{"spec":{"containers":[{"name":"frontend","resources":{"limits":{"cpu":"500m","memory":"512Mi"}}}]}}}}'

   # Scale up replicas
   kubectl scale deployment frontend --replicas=5 -n craftista-prod
   ```

2. **Enable Horizontal Pod Autoscaling**:

   ```bash
   # Create HPA
   kubectl autoscale deployment frontend --cpu-percent=70 --min=2 --max=10 -n craftista-prod

   # Check HPA status
   kubectl get hpa -n craftista-prod
   ```

### Database Performance Issues

**Solutions**:

1. **Check Database Metrics**:

   ```bash
   # MongoDB performance
   kubectl exec -it deployment/catalogue -n craftista-prod -- python -c "
   import pymongo
   client = pymongo.MongoClient('$MONGODB_URI')
   stats = client.catalogue.command('dbStats')
   print('Database stats:', stats)
   "

   # PostgreSQL performance
   kubectl exec -it deployment/voting -n craftista-prod -- psql $POSTGRES_URI -c "
   SELECT query, calls, total_time, mean_time
   FROM pg_stat_statements
   ORDER BY total_time DESC LIMIT 10;
   "
   ```

2. **Optimize Database Connections**:

   ```bash
   # Check connection pool settings
   kubectl get configmap catalogue-config -n craftista-prod -o yaml

   # Update connection pool size
   kubectl patch configmap catalogue-config -n craftista-prod -p '{"data":{"MAX_POOL_SIZE":"20"}}'
   ```

## CI/CD Pipeline Issues

### GitHub Actions Failures

**Symptoms**: CI/CD pipelines fail to complete

**Common Issues**:

1. **Docker Build Failures**:

   ```bash
   # Check Dockerfile syntax
   docker build -t test-image ./frontend/

   # Check base image availability
   docker pull node:16-alpine
   ```

2. **Security Scan Failures**:

   ```bash
   # Check SonarQube connectivity
   curl -u $SONARQUBE_TOKEN: https://sonarqube.webdemoapp.com/api/system/status

   # Check Trivy scan results
   trivy image 8060633493/craftista-frontend:latest
   ```

3. **GitOps Update Failures**:

   ```bash
   # Check deploy key permissions
   ssh -T git@github.com -i ~/.ssh/gitops_deploy_key

   # Verify Vault authentication
   vault auth -method=github token=$GITHUB_TOKEN
   ```

### Image Tag Update Issues

**Symptoms**: New images not deployed despite successful CI

**Solutions**:

1. **Check Image Tag Updates**:

   ```bash
   # Verify image tag in GitOps repo
   git log --oneline -5 kubernetes/overlays/prod/frontend/

   # Check current image in deployment
   kubectl get deployment frontend -n craftista-prod -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

2. **Force ArgoCD Sync**:
   ```bash
   # Force refresh and sync
   argocd app get craftista-frontend-prod --refresh
   argocd app sync craftista-frontend-prod --force
   ```

## Monitoring and Logging

### Log Collection

```bash
# Collect logs from all services
for service in frontend catalogue voting recommendation; do
  echo "=== $service logs ==="
  kubectl logs deployment/$service -n craftista-prod --tail=100
done

# Collect ArgoCD logs
kubectl logs deployment/argocd-application-controller -n argocd --tail=100

# Collect Vault logs
kubectl logs vault-0 -n vault --tail=100

# Collect ingress controller logs
kubectl logs deployment/ingress-nginx-controller -n ingress-nginx --tail=100
```

### System Events

```bash
# Get recent events across all namespaces
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -50

# Get events for specific namespace
kubectl get events -n craftista-prod --sort-by='.lastTimestamp'

# Watch events in real-time
kubectl get events -n craftista-prod --watch
```

## Emergency Procedures

### Complete System Failure

1. **Immediate Assessment**:

   ```bash
   # Check cluster health
   kubectl get nodes
   kubectl get pods --all-namespaces | grep -v Running

   # Check critical services
   kubectl get pods -n kube-system
   kubectl get pods -n argocd
   kubectl get pods -n vault
   ```

2. **Emergency Rollback**:

   ```bash
   # Rollback all services to last known good state
   for service in frontend catalogue voting recommendation; do
     ./scripts/rollback.sh $service prod emergency
   done
   ```

3. **Activate Maintenance Mode**:

   ```bash
   # Deploy maintenance page
   kubectl apply -f emergency/maintenance-mode.yaml

   # Update DNS to point to maintenance page
   # (This would be done through your DNS provider)
   ```

### Data Loss Prevention

```bash
# Emergency database backups
kubectl exec deployment/voting -n craftista-prod -- pg_dump $POSTGRES_URI > emergency-backup-$(date +%Y%m%d-%H%M).sql

kubectl exec deployment/catalogue -n craftista-prod -- mongodump --uri="$MONGODB_URI" --archive > emergency-backup-$(date +%Y%m%d-%H%M).archive

# Copy backups to safe location
aws s3 cp emergency-backup-*.sql s3://craftista-emergency-backups/
aws s3 cp emergency-backup-*.archive s3://craftista-emergency-backups/
```

## Getting Help

### Escalation Path

1. **Level 1**: Check this troubleshooting guide
2. **Level 2**: Check component-specific documentation
3. **Level 3**: Contact on-call engineer
4. **Level 4**: Engage vendor support (AWS, HashiCorp, etc.)

### Useful Resources

- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug-application-cluster/)
- [ArgoCD Troubleshooting](https://argo-cd.readthedocs.io/en/stable/operator-manual/troubleshooting/)
- [Vault Troubleshooting](https://www.vaultproject.io/docs/troubleshooting)
- [AWS EKS Troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)

### Emergency Contacts

- **On-Call Engineer**: [Contact information]
- **Platform Team**: [Contact information]
- **Database Team**: [Contact information]
- **Security Team**: [Contact information]
- **AWS Support**: [Support case URL]

Remember: When troubleshooting, always start with the basics (connectivity, resources, logs) before diving into complex scenarios. Document your findings and solutions to improve this guide for future incidents.
