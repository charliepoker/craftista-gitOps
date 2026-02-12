# Disaster Recovery Procedure

This runbook provides comprehensive procedures for disaster recovery in the Craftista GitOps environment. Use these procedures to restore services after catastrophic failures, data loss, or infrastructure destruction.

## Table of Contents

- [Overview](#overview)
- [Disaster Scenarios](#disaster-scenarios)
- [Recovery Time Objectives](#recovery-time-objectives)
- [Backup Systems](#backup-systems)
- [Infrastructure Recovery](#infrastructure-recovery)
- [Data Recovery](#data-recovery)
- [Application Recovery](#application-recovery)
- [GitOps Repository Recovery](#gitops-repository-recovery)
- [Secrets Recovery](#secrets-recovery)
- [Verification and Testing](#verification-and-testing)
- [Communication Plan](#communication-plan)
- [Post-Recovery Tasks](#post-recovery-tasks)

## Overview

The Craftista disaster recovery plan is designed to restore full system functionality within defined Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO). The plan covers multiple disaster scenarios and provides step-by-step recovery procedures.

### Key Principles

1. **Infrastructure as Code**: All infrastructure can be recreated from Terraform code
2. **GitOps**: All configurations are version-controlled and can be restored from Git
3. **Automated Backups**: Regular automated backups of all critical data
4. **Multi-Region**: Critical components have cross-region backup capabilities
5. **Documentation**: All procedures are documented and regularly tested

### Recovery Priorities

1. **Critical**: Core application functionality (RTO: 1 hour)
2. **High**: Full feature set (RTO: 4 hours)
3. **Medium**: Non-essential features (RTO: 24 hours)
4. **Low**: Historical data and analytics (RTO: 72 hours)

## Disaster Scenarios

### Scenario 1: Complete AWS Region Failure

**Impact**: Total loss of primary AWS region
**Probability**: Low
**RTO**: 4 hours
**RPO**: 1 hour

### Scenario 2: EKS Cluster Destruction

**Impact**: Loss of Kubernetes cluster and all workloads
**Probability**: Medium
**RTO**: 2 hours
**RPO**: 15 minutes

### Scenario 3: Database Corruption/Loss

**Impact**: Loss of application data
**Probability**: Medium
**RTO**: 1 hour
**RPO**: 15 minutes

### Scenario 4: GitOps Repository Loss

**Impact**: Loss of deployment configurations
**Probability**: Low
**RTO**: 30 minutes
**RPO**: Real-time (Git distributed)

### Scenario 5: Vault Cluster Failure

**Impact**: Loss of secrets management
**Probability**: Medium
**RTO**: 1 hour
**RPO**: Real-time (Vault replication)

### Scenario 6: Complete Infrastructure Loss

**Impact**: Total system destruction
**Probability**: Very Low
**RTO**: 8 hours
**RPO**: 4 hours

## Recovery Time Objectives

| Component        | RTO        | RPO        | Backup Frequency |
| ---------------- | ---------- | ---------- | ---------------- |
| EKS Cluster      | 2 hours    | N/A        | N/A (IaC)        |
| PostgreSQL       | 1 hour     | 15 minutes | Every 15 minutes |
| MongoDB          | 1 hour     | 15 minutes | Every 15 minutes |
| Redis            | 30 minutes | 1 hour     | Hourly           |
| Vault            | 1 hour     | Real-time  | Continuous       |
| GitOps Repo      | 30 minutes | Real-time  | Continuous       |
| Container Images | 30 minutes | N/A        | Immutable        |

## Backup Systems

### Database Backups

#### PostgreSQL (RDS)

```bash
# Automated backups (configured in Terraform)
# - Point-in-time recovery enabled
# - 7-day backup retention
# - Cross-region backup replication

# Manual backup creation
aws rds create-db-snapshot \
  --db-instance-identifier craftista-rds-prod \
  --db-snapshot-identifier craftista-manual-$(date +%Y%m%d-%H%M)

# List available backups
aws rds describe-db-snapshots \
  --db-instance-identifier craftista-rds-prod \
  --snapshot-type manual
```

#### MongoDB (DocumentDB)

```bash
# Automated backups (configured in Terraform)
# - Continuous backup enabled
# - 7-day backup retention
# - Cross-region backup replication

# Manual backup creation
aws docdb create-db-cluster-snapshot \
  --db-cluster-identifier craftista-docdb-prod \
  --db-cluster-snapshot-identifier craftista-manual-$(date +%Y%m%d-%H%M)

# List available backups
aws docdb describe-db-cluster-snapshots \
  --db-cluster-identifier craftista-docdb-prod \
  --snapshot-type manual
```

#### Redis (ElastiCache)

```bash
# Automated backups (configured in Terraform)
# - Daily backup enabled
# - 5-day backup retention

# Manual backup creation
aws elasticache create-snapshot \
  --cache-cluster-id craftista-redis-prod \
  --snapshot-name craftista-manual-$(date +%Y%m%d-%H%M)

# List available backups
aws elasticache describe-snapshots \
  --cache-cluster-id craftista-redis-prod
```

### Application Data Backups

```bash
# Create application-level backups
kubectl create job backup-job-$(date +%Y%m%d-%H%M) \
  --from=cronjob/database-backup -n craftista-prod

# Verify backup completion
kubectl get jobs -n craftista-prod | grep backup

# Export backup to S3
kubectl exec job/backup-job-$(date +%Y%m%d-%H%M) -n craftista-prod -- \
  aws s3 cp /backup/data.tar.gz s3://craftista-disaster-recovery/$(date +%Y%m%d)/
```

### Configuration Backups

```bash
# Backup Kubernetes configurations
kubectl get all --all-namespaces -o yaml > k8s-backup-$(date +%Y%m%d).yaml
aws s3 cp k8s-backup-$(date +%Y%m%d).yaml s3://craftista-disaster-recovery/configs/

# Backup Vault data
kubectl exec vault-0 -n vault -- vault operator raft snapshot save /tmp/vault-snapshot-$(date +%Y%m%d).snap
kubectl cp vault-0:/tmp/vault-snapshot-$(date +%Y%m%d).snap ./vault-snapshot-$(date +%Y%m%d).snap -n vault
aws s3 cp vault-snapshot-$(date +%Y%m%d).snap s3://craftista-disaster-recovery/vault/

# Backup ArgoCD configurations
kubectl get applications -n argocd -o yaml > argocd-apps-$(date +%Y%m%d).yaml
aws s3 cp argocd-apps-$(date +%Y%m%d).yaml s3://craftista-disaster-recovery/argocd/
```

## Infrastructure Recovery

### Complete Infrastructure Recreation

1. **Prepare Recovery Environment**:

   ```bash
   # Clone infrastructure repository
   git clone https://github.com/charliepoker/Craftista-IaC.git
   cd Craftista-IaC

   # Switch to disaster recovery branch if needed
   git checkout disaster-recovery

   # Initialize Terraform
   terraform init
   ```

2. **Restore Terraform State** (if lost):

   ```bash
   # Import existing resources if state is lost
   terraform import aws_vpc.main vpc-xxxxxxxxx
   terraform import aws_eks_cluster.main craftista-cluster

   # Or restore from S3 backup
   aws s3 cp s3://craftista-terraform-state/prod/terraform.tfstate ./terraform.tfstate
   ```

3. **Deploy Infrastructure**:

   ```bash
   # Plan infrastructure deployment
   terraform plan -var-file=environments/prod/terraform.tfvars

   # Apply infrastructure
   terraform apply -var-file=environments/prod/terraform.tfvars -auto-approve

   # Verify infrastructure
   aws eks describe-cluster --name craftista-cluster
   ```

### EKS Cluster Recovery

1. **Recreate EKS Cluster**:

   ```bash
   # If cluster exists but is corrupted, delete first
   terraform destroy -target=aws_eks_cluster.main -auto-approve

   # Recreate cluster
   terraform apply -target=aws_eks_cluster.main -auto-approve

   # Update kubeconfig
   aws eks update-kubeconfig --region us-west-2 --name craftista-cluster
   ```

2. **Restore Cluster Add-ons**:

   ```bash
   # Install essential add-ons
   kubectl apply -f https://raw.githubusercontent.com/aws/aws-load-balancer-controller/v2.4.4/docs/install/iam_policy.json

   # Install ingress controller
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace

   # Install cert-manager
   helm repo add jetstack https://charts.jetstack.io
   helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true
   ```

### Network Recovery

1. **Verify Network Configuration**:

   ```bash
   # Check VPC and subnets
   aws ec2 describe-vpcs --filters "Name=tag:Name,Values=craftista-vpc"
   aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxxxxxx"

   # Check security groups
   aws ec2 describe-security-groups --filters "Name=vpc-id,Values=vpc-xxxxxxxxx"

   # Check route tables
   aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxxxxxxxx"
   ```

2. **Restore DNS Configuration**:

   ```bash
   # Verify Route53 hosted zone
   aws route53 list-hosted-zones-by-name --dns-name webdemoapp.com

   # Restore DNS records if needed
   aws route53 change-resource-record-sets --hosted-zone-id Z1234567890 --change-batch file://dns-records.json
   ```

## Data Recovery

### PostgreSQL Recovery

1. **Point-in-Time Recovery**:

   ```bash
   # Restore from point-in-time
   aws rds restore-db-instance-to-point-in-time \
     --source-db-instance-identifier craftista-rds-prod \
     --target-db-instance-identifier craftista-rds-recovery \
     --restore-time 2024-01-15T14:30:00Z \
     --subnet-group-name craftista-db-subnet-group \
     --vpc-security-group-ids sg-xxxxxxxxx
   ```

2. **Restore from Snapshot**:

   ```bash
   # List available snapshots
   aws rds describe-db-snapshots --db-instance-identifier craftista-rds-prod

   # Restore from specific snapshot
   aws rds restore-db-instance-from-db-snapshot \
     --db-instance-identifier craftista-rds-recovery \
     --db-snapshot-identifier craftista-manual-20240115-1430 \
     --subnet-group-name craftista-db-subnet-group \
     --vpc-security-group-ids sg-xxxxxxxxx
   ```

3. **Update Application Configuration**:

   ```bash
   # Update Vault with new database endpoint
   kubectl exec vault-0 -n vault -- vault kv put secret/craftista/prod/voting/postgres \
     uri="postgresql://username:password@craftista-rds-recovery.xxx.us-west-2.rds.amazonaws.com:5432/voting"

   # Restart applications
   kubectl rollout restart deployment/voting -n craftista-prod
   ```

### MongoDB Recovery

1. **Restore from Snapshot**:

   ```bash
   # Restore DocumentDB cluster from snapshot
   aws docdb restore-db-cluster-from-snapshot \
     --db-cluster-identifier craftista-docdb-recovery \
     --snapshot-identifier craftista-manual-20240115-1430 \
     --subnet-group-name craftista-docdb-subnet-group \
     --vpc-security-group-ids sg-xxxxxxxxx

   # Create cluster instances
   aws docdb create-db-instance \
     --db-instance-identifier craftista-docdb-recovery-1 \
     --db-instance-class db.t3.medium \
     --db-cluster-identifier craftista-docdb-recovery
   ```

2. **Manual Data Recovery**:
   ```bash
   # If automated recovery fails, restore from manual backup
   kubectl run mongodb-restore --rm -it --image=mongo:4.4 -- mongorestore \
     --uri="mongodb://username:password@craftista-docdb-recovery.cluster-xxx.us-west-2.docdb.amazonaws.com:27017/catalogue?ssl=true" \
     --archive=/backup/catalogue-backup.archive
   ```

### Redis Recovery

1. **Restore from Snapshot**:

   ```bash
   # Create new Redis cluster from snapshot
   aws elasticache create-cache-cluster \
     --cache-cluster-id craftista-redis-recovery \
     --snapshot-name craftista-manual-20240115-1430 \
     --cache-node-type cache.t3.micro \
     --subnet-group-name craftista-redis-subnet-group \
     --security-group-ids sg-xxxxxxxxx
   ```

2. **Warm Cache Recovery**:
   ```bash
   # Redis data is typically cache, so warm up from primary data sources
   kubectl exec -it deployment/recommendation -n craftista-prod -- \
     curl -X POST http://localhost:8080/admin/cache/warm
   ```

## Application Recovery

### Container Image Recovery

1. **Verify Image Availability**:

   ```bash
   # Check if images are available in DockerHub
   docker pull 8060633493/craftista-frontend:latest
   docker pull 8060633493/craftista-catalogue:latest
   docker pull 8060633493/craftista-voting:latest
   docker pull 8060633493/craftista-recommendation:latest
   ```

2. **Rebuild Images if Necessary**:

   ```bash
   # If images are lost, rebuild from source
   git clone https://github.com/charliepoker/craftista.git
   cd craftista

   # Build and push images
   docker build -t 8060633493/craftista-frontend:recovery ./frontend/
   docker push 8060633493/craftista-frontend:recovery

   # Update GitOps repo with recovery tags
   sed -i 's/:latest/:recovery/g' kubernetes/overlays/prod/*/kustomization.yaml
   ```

### Namespace and RBAC Recovery

1. **Recreate Namespaces**:

   ```bash
   # Create namespaces
   kubectl create namespace craftista-dev
   kubectl create namespace craftista-staging
   kubectl create namespace craftista-prod
   kubectl create namespace argocd
   kubectl create namespace vault
   kubectl create namespace external-secrets-system
   ```

2. **Restore RBAC Configuration**:

   ```bash
   # Apply RBAC configurations
   kubectl apply -f kubernetes/common/rbac/

   # Verify service accounts
   kubectl get serviceaccounts --all-namespaces | grep craftista
   ```

### Network Policies Recovery

```bash
# Apply network policies
kubectl apply -f kubernetes/common/network-policies/

# Verify network policies
kubectl get networkpolicies --all-namespaces
```

## GitOps Repository Recovery

### Repository Restoration

1. **Clone from Backup**:

   ```bash
   # If primary repository is lost, clone from backup
   git clone https://github.com/charliepoker/craftista-gitops-backup.git craftista-gitops
   cd craftista-gitops

   # Create new primary repository
   git remote add origin https://github.com/charliepoker/craftista-gitops.git
   git push -u origin main
   ```

2. **Restore from Local Backup**:

   ```bash
   # If Git repository is completely lost, restore from local backup
   aws s3 cp s3://craftista-disaster-recovery/git/craftista-gitops-backup.tar.gz ./
   tar -xzf craftista-gitops-backup.tar.gz
   cd craftista-gitops

   # Initialize new repository
   git init
   git add .
   git commit -m "Disaster recovery restore"
   git remote add origin https://github.com/charliepoker/craftista-gitops.git
   git push -u origin main
   ```

### Configuration Validation

```bash
# Validate Kubernetes manifests
kubectl apply --dry-run=client -f kubernetes/overlays/prod/frontend/

# Validate Helm charts
helm lint helm/charts/frontend/

# Validate ArgoCD applications
kubectl apply --dry-run=client -f argocd/applications/prod/
```

## Secrets Recovery

### Vault Recovery

1. **Restore Vault Cluster**:

   ```bash
   # Install Vault using Helm
   helm repo add hashicorp https://helm.releases.hashicorp.com
   helm install vault hashicorp/vault \
     --namespace vault \
     --create-namespace \
     --set "server.ha.enabled=true" \
     --set "server.ha.replicas=3" \
     --set "server.ha.raft.enabled=true"
   ```

2. **Initialize and Unseal Vault**:

   ```bash
   # Initialize Vault (if completely new)
   kubectl exec vault-0 -n vault -- vault operator init -key-shares=5 -key-threshold=3

   # Or restore from snapshot
   kubectl cp vault-snapshot-20240115.snap vault-0:/tmp/vault-snapshot.snap -n vault
   kubectl exec vault-0 -n vault -- vault operator raft snapshot restore /tmp/vault-snapshot.snap

   # Unseal Vault
   kubectl exec vault-0 -n vault -- vault operator unseal <unseal-key-1>
   kubectl exec vault-0 -n vault -- vault operator unseal <unseal-key-2>
   kubectl exec vault-0 -n vault -- vault operator unseal <unseal-key-3>
   ```

3. **Restore Vault Policies and Auth**:

   ```bash
   # Apply Vault policies
   kubectl exec vault-0 -n vault -- vault policy write frontend-policy - < vault/policies/frontend-policy.hcl
   kubectl exec vault-0 -n vault -- vault policy write catalogue-policy - < vault/policies/catalogue-policy.hcl
   kubectl exec vault-0 -n vault -- vault policy write voting-policy - < vault/policies/voting-policy.hcl
   kubectl exec vault-0 -n vault -- vault policy write recommendation-policy - < vault/policies/recommendation-policy.hcl

   # Configure authentication
   ./vault/auth/kubernetes-auth.sh
   ./vault/auth/github-oidc-auth.sh
   ```

### External Secrets Recovery

1. **Install External Secrets Operator**:

   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets \
     --namespace external-secrets-system \
     --create-namespace
   ```

2. **Restore Secret Stores and External Secrets**:

   ```bash
   # Apply secret stores
   kubectl apply -f external-secrets/cluster-secret-store.yaml
   kubectl apply -f external-secrets/secret-store.yaml

   # Apply external secrets
   kubectl apply -f external-secrets/external-secrets/

   # Verify secrets are created
   kubectl get secrets --all-namespaces | grep craftista
   ```

### Manual Secret Recovery

If Vault is completely lost and cannot be restored:

```bash
# Manually create critical secrets from backup
kubectl create secret generic frontend-secrets \
  --from-literal=session-secret="$(cat backup/frontend-session-secret)" \
  --from-literal=api-key="$(cat backup/frontend-api-key)" \
  -n craftista-prod

kubectl create secret generic catalogue-secrets \
  --from-literal=mongodb-uri="$(cat backup/catalogue-mongodb-uri)" \
  -n craftista-prod

kubectl create secret generic voting-secrets \
  --from-literal=postgres-uri="$(cat backup/voting-postgres-uri)" \
  -n craftista-prod

kubectl create secret generic recommendation-secrets \
  --from-literal=redis-uri="$(cat backup/recommendation-redis-uri)" \
  -n craftista-prod
```

## ArgoCD Recovery

### ArgoCD Installation

1. **Install ArgoCD**:

   ```bash
   # Create ArgoCD namespace
   kubectl create namespace argocd

   # Install ArgoCD
   kubectl apply -n argocd -f argocd/install/argocd-install.yaml

   # Apply custom configuration
   kubectl apply -n argocd -f argocd/install/argocd-cm.yaml
   kubectl apply -n argocd -f argocd/install/argocd-rbac-cm.yaml

   # Wait for ArgoCD to be ready
   kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
   ```

2. **Restore ArgoCD Applications**:

   ```bash
   # Create ArgoCD projects
   kubectl apply -f argocd/projects/

   # Create ArgoCD applications
   kubectl apply -f argocd/applications/dev/
   kubectl apply -f argocd/applications/staging/
   kubectl apply -f argocd/applications/prod/

   # Verify applications
   argocd app list
   ```

3. **Sync Applications**:

   ```bash
   # Sync all applications
   argocd app sync --all

   # Or sync individually
   argocd app sync craftista-frontend-prod
   argocd app sync craftista-catalogue-prod
   argocd app sync craftista-voting-prod
   argocd app sync craftista-recommendation-prod
   ```

## Verification and Testing

### System Health Verification

1. **Infrastructure Verification**:

   ```bash
   # Check cluster status
   kubectl cluster-info
   kubectl get nodes -o wide

   # Check storage classes
   kubectl get storageclass

   # Check ingress controller
   kubectl get pods -n ingress-nginx
   ```

2. **Database Connectivity**:

   ```bash
   # Test PostgreSQL
   kubectl run postgres-test --rm -it --image=postgres:13 -- psql \
     "postgresql://username:password@craftista-rds-recovery.xxx.us-west-2.rds.amazonaws.com:5432/voting" \
     -c "SELECT COUNT(*) FROM votes;"

   # Test MongoDB
   kubectl run mongodb-test --rm -it --image=mongo:4.4 -- mongo \
     "mongodb://username:password@craftista-docdb-recovery.cluster-xxx.us-west-2.docdb.amazonaws.com:27017/catalogue?ssl=true" \
     --eval "db.products.count()"

   # Test Redis
   kubectl run redis-test --rm -it --image=redis:6 -- redis-cli \
     -h craftista-redis-recovery.xxx.cache.amazonaws.com -p 6379 ping
   ```

3. **Application Health**:

   ```bash
   # Check all pods
   kubectl get pods --all-namespaces | grep craftista

   # Test health endpoints
   curl -k https://webdemoapp.com/health
   curl -k https://catalogue.webdemoapp.com/health
   curl -k https://voting.webdemoapp.com/health
   curl -k https://recommendation.webdemoapp.com/health
   ```

### Functional Testing

1. **End-to-End Testing**:

   ```bash
   # Test complete user flow
   curl -X GET https://webdemoapp.com/
   curl -X GET https://catalogue.webdemoapp.com/products
   curl -X POST https://voting.webdemoapp.com/api/votes -d '{"item":"test","vote":"up"}'
   curl -X GET https://recommendation.webdemoapp.com/api/recommendations
   ```

2. **Performance Testing**:
   ```bash
   # Basic load test
   for i in {1..100}; do
     curl -s -o /dev/null -w "%{http_code} %{time_total}\n" https://webdemoapp.com/
   done
   ```

### Data Integrity Verification

```bash
# Verify data integrity
kubectl exec -it deployment/catalogue -n craftista-prod -- python -c "
import pymongo, os
client = pymongo.MongoClient(os.environ['MONGODB_URI'])
count = client.catalogue.products.count_documents({})
print(f'Product count: {count}')
"

kubectl exec -it deployment/voting -n craftista-prod -- psql $POSTGRES_URI -c "
SELECT COUNT(*) as vote_count FROM votes;
SELECT COUNT(*) as user_count FROM users;
"
```

## Communication Plan

### Stakeholder Notification

1. **Immediate Notification** (within 15 minutes):

   ```bash
   # Send initial incident notification
   curl -X POST https://hooks.slack.com/services/xxx/yyy/zzz \
     -H 'Content-type: application/json' \
     --data '{"text":"🚨 DISASTER RECOVERY IN PROGRESS: Craftista system recovery initiated. ETA: 4 hours. Updates every 30 minutes."}'
   ```

2. **Progress Updates** (every 30 minutes):

   ```bash
   # Send progress updates
   curl -X POST https://hooks.slack.com/services/xxx/yyy/zzz \
     -H 'Content-type: application/json' \
     --data '{"text":"📊 RECOVERY UPDATE: Infrastructure restored. Database recovery in progress. ETA: 2 hours remaining."}'
   ```

3. **Recovery Completion**:
   ```bash
   # Send completion notification
   curl -X POST https://hooks.slack.com/services/xxx/yyy/zzz \
     -H 'Content-type: application/json' \
     --data '{"text":"✅ RECOVERY COMPLETE: Craftista system fully restored. All services operational. Post-incident review scheduled."}'
   ```

### Status Page Updates

```bash
# Update status page (if using external service)
curl -X POST https://api.statuspage.io/v1/pages/xxx/incidents \
  -H "Authorization: OAuth xxx" \
  -d "incident[name]=System Recovery in Progress" \
  -d "incident[status]=investigating" \
  -d "incident[impact_override]=major"
```

## Post-Recovery Tasks

### Immediate Tasks (within 24 hours)

1. **System Monitoring**:

   ```bash
   # Monitor system stability
   kubectl top nodes
   kubectl top pods --all-namespaces

   # Check error rates
   kubectl logs -f deployment/frontend -n craftista-prod | grep ERROR
   ```

2. **Performance Validation**:

   ```bash
   # Run performance tests
   ./scripts/performance-test.sh

   # Monitor response times
   curl -w "@curl-format.txt" -o /dev/null -s https://webdemoapp.com/
   ```

3. **Data Validation**:

   ```bash
   # Validate data integrity
   ./scripts/data-integrity-check.sh

   # Compare with pre-disaster metrics
   kubectl exec -it deployment/catalogue -n craftista-prod -- python scripts/data-count.py
   ```

### Follow-up Tasks (within 1 week)

1. **Backup Verification**:

   ```bash
   # Verify all backup systems are working
   ./scripts/backup-test.sh

   # Update backup retention policies if needed
   aws rds modify-db-instance --db-instance-identifier craftista-rds-prod --backup-retention-period 14
   ```

2. **Documentation Updates**:

   ```bash
   # Update disaster recovery documentation
   git add docs/runbooks/disaster-recovery.md
   git commit -m "Update DR procedures based on recent recovery"

   # Update RTO/RPO based on actual recovery times
   ```

3. **Process Improvements**:
   ```bash
   # Schedule post-incident review
   # Update monitoring and alerting
   # Improve automation scripts
   # Update training materials
   ```

### Recovery Checklist

- [ ] Infrastructure fully restored
- [ ] All databases recovered and verified
- [ ] All applications deployed and healthy
- [ ] Secrets and configurations restored
- [ ] ArgoCD operational and syncing
- [ ] External access working (DNS, ingress)
- [ ] Monitoring and alerting functional
- [ ] Backup systems re-enabled
- [ ] Performance within acceptable limits
- [ ] Data integrity verified
- [ ] Stakeholders notified of completion
- [ ] Post-incident review scheduled
- [ ] Documentation updated
- [ ] Lessons learned documented

## Testing and Validation

### Regular DR Testing

1. **Monthly Tests**:

   - Database backup and restore procedures
   - Secret rotation and recovery
   - Application deployment from scratch

2. **Quarterly Tests**:

   - Complete infrastructure recreation
   - Cross-region failover
   - Full disaster recovery simulation

3. **Annual Tests**:
   - Complete disaster scenario
   - Multi-day recovery simulation
   - Third-party vendor coordination

### Test Automation

```bash
#!/bin/bash
# dr-test.sh - Automated disaster recovery testing

# Test database backup and restore
./scripts/test-db-backup.sh

# Test infrastructure recreation
./scripts/test-infra-recreation.sh

# Test application deployment
./scripts/test-app-deployment.sh

# Test secrets recovery
./scripts/test-secrets-recovery.sh

# Generate test report
./scripts/generate-dr-report.sh
```

## Emergency Contacts

### Primary Contacts

- **Incident Commander**: [Contact information]
- **Platform Team Lead**: [Contact information]
- **Database Administrator**: [Contact information]
- **Security Team Lead**: [Contact information]
- **AWS Support**: [Support case URL]

### Vendor Contacts

- **AWS Enterprise Support**: [Contact information]
- **HashiCorp Support**: [Contact information]
- **GitHub Support**: [Contact information]
- **DockerHub Support**: [Contact information]

### Escalation Matrix

| Time      | Action                 | Contact               |
| --------- | ---------------------- | --------------------- |
| 0-15 min  | Initial response       | On-call engineer      |
| 15-30 min | Escalate to team lead  | Platform team lead    |
| 30-60 min | Escalate to management | Engineering manager   |
| 1-2 hours | Vendor support         | AWS/HashiCorp support |
| 2+ hours  | Executive notification | CTO/VP Engineering    |

Remember: Disaster recovery is about preparation and practice. Regular testing and documentation updates are essential for successful recovery when disasters occur.
