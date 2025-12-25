# Secrets Rotation Procedure

This runbook provides step-by-step procedures for rotating secrets in the Craftista GitOps environment. Regular secret rotation is a critical security practice that should be performed according to your organization's security policies.

## Table of Contents

- [Overview](#overview)
- [Rotation Schedule](#rotation-schedule)
- [Pre-Rotation Checklist](#pre-rotation-checklist)
- [Database Credentials Rotation](#database-credentials-rotation)
- [Application Secrets Rotation](#application-secrets-rotation)
- [CI/CD Secrets Rotation](#cicd-secrets-rotation)
- [Infrastructure Secrets Rotation](#infrastructure-secrets-rotation)
- [Emergency Secret Rotation](#emergency-secret-rotation)
- [Verification and Testing](#verification-and-testing)
- [Rollback Procedures](#rollback-procedures)
- [Post-Rotation Tasks](#post-rotation-tasks)

## Overview

The Craftista application uses HashiCorp Vault for centralized secrets management. All secrets are stored in Vault and synchronized to Kubernetes using the External Secrets Operator. This approach allows for secure, auditable secret rotation with minimal application downtime.

### Secret Categories

1. **Database Credentials**: MongoDB, PostgreSQL, Redis connection credentials
2. **Application Secrets**: API keys, session secrets, encryption keys
3. **CI/CD Secrets**: DockerHub credentials, SonarQube tokens, deploy keys
4. **Infrastructure Secrets**: AWS credentials, TLS certificates, service tokens

### Rotation Methods

- **Automated Rotation**: Using Vault's dynamic secrets (recommended for databases)
- **Manual Rotation**: For static secrets that require manual generation
- **Emergency Rotation**: Immediate rotation due to security incidents

## Rotation Schedule

### Regular Rotation Schedule

| Secret Type        | Frequency     | Method    | Downtime |
| ------------------ | ------------- | --------- | -------- |
| Database Passwords | 90 days       | Automated | None     |
| API Keys           | 180 days      | Manual    | Minimal  |
| Session Secrets    | 30 days       | Manual    | None     |
| CI/CD Tokens       | 365 days      | Manual    | None     |
| TLS Certificates   | Before expiry | Automated | None     |
| Deploy Keys        | 365 days      | Manual    | None     |

### Emergency Rotation Triggers

- ✅ Suspected credential compromise
- ✅ Employee departure with access
- ✅ Security incident or breach
- ✅ Compliance requirement
- ✅ Vendor security advisory

## Pre-Rotation Checklist

### Planning Phase

- [ ] Identify secrets to be rotated
- [ ] Check secret dependencies and usage
- [ ] Schedule maintenance window if needed
- [ ] Notify stakeholders of planned rotation
- [ ] Prepare rollback plan
- [ ] Verify backup and recovery procedures

### Environment Preparation

```bash
# Verify Vault connectivity
kubectl exec vault-0 -n vault -- vault status

# Check External Secrets Operator status
kubectl get pods -n external-secrets-system

# Verify current secret versions
kubectl exec vault-0 -n vault -- vault kv metadata secret/craftista/prod/frontend

# Check application health before rotation
kubectl get pods -n craftista-prod
argocd app list | grep craftista
```

### Backup Current Secrets

```bash
# Create backup of current secrets
mkdir -p /tmp/secret-backup-$(date +%Y%m%d)

# Export current secret versions (metadata only, not values)
for env in dev staging prod; do
  for service in frontend catalogue voting recommendation; do
    kubectl exec vault-0 -n vault -- vault kv metadata secret/craftista/$env/$service > /tmp/secret-backup-$(date +%Y%m%d)/$env-$service-metadata.json
  done
done

# Backup Kubernetes secrets (for emergency rollback)
for ns in craftista-dev craftista-staging craftista-prod; do
  kubectl get secrets -n $ns -o yaml > /tmp/secret-backup-$(date +%Y%m%d)/$ns-secrets.yaml
done
```

## Database Credentials Rotation

### MongoDB Credentials (Catalogue Service)

#### Method 1: Vault Dynamic Secrets (Recommended)

1. **Configure MongoDB Database Engine**:

   ```bash
   # Enable database secrets engine
   kubectl exec vault-0 -n vault -- vault secrets enable -path=mongodb database

   # Configure MongoDB connection
   kubectl exec vault-0 -n vault -- vault write mongodb/config/catalogue \
     plugin_name=mongodb-database-plugin \
     connection_url="mongodb://{{username}}:{{password}}@docdb-cluster.cluster-xxx.us-west-2.docdb.amazonaws.com:27017/admin?ssl=true" \
     allowed_roles="catalogue-role" \
     username="vault-admin" \
     password="current-admin-password"

   # Create role for dynamic credentials
   kubectl exec vault-0 -n vault -- vault write mongodb/roles/catalogue-role \
     db_name=catalogue \
     creation_statements='{"db":"catalogue","roles":[{"role":"readWrite","db":"catalogue"}]}' \
     default_ttl="24h" \
     max_ttl="72h"
   ```

2. **Update External Secret Configuration**:

   ```yaml
   # Update external-secrets/external-secrets/catalogue-secrets.yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: catalogue-secrets
     namespace: craftista-prod
   spec:
     refreshInterval: 1h # Refresh every hour for dynamic secrets
     secretStoreRef:
       name: vault-backend
       kind: SecretStore
     target:
       name: catalogue-secrets
       creationPolicy: Owner
     data:
       - secretKey: mongodb-username
         remoteRef:
           key: mongodb/creds/catalogue-role
           property: username
       - secretKey: mongodb-password
         remoteRef:
           key: mongodb/creds/catalogue-role
           property: password
   ```

3. **Apply Updated Configuration**:

   ```bash
   kubectl apply -f external-secrets/external-secrets/catalogue-secrets.yaml

   # Verify new credentials are generated
   kubectl get secret catalogue-secrets -n craftista-prod -o yaml
   ```

#### Method 2: Manual Rotation

1. **Generate New Credentials**:

   ```bash
   # Generate new password
   NEW_PASSWORD=$(openssl rand -base64 32)

   # Connect to MongoDB and create new user
   kubectl run mongodb-admin --rm -it --image=mongo:4.4 -- mongo \
     "mongodb://current-user:current-password@docdb-cluster.cluster-xxx.us-west-2.docdb.amazonaws.com:27017/admin?ssl=true" \
     --eval "
     db.createUser({
       user: 'catalogue-user-new',
       pwd: '$NEW_PASSWORD',
       roles: [{role: 'readWrite', db: 'catalogue'}]
     })
     "
   ```

2. **Update Vault with New Credentials**:

   ```bash
   # Store new credentials in Vault
   kubectl exec vault-0 -n vault -- vault kv put secret/craftista/prod/catalogue/mongodb \
     username="catalogue-user-new" \
     password="$NEW_PASSWORD" \
     uri="mongodb://catalogue-user-new:$NEW_PASSWORD@docdb-cluster.cluster-xxx.us-west-2.docdb.amazonaws.com:27017/catalogue?ssl=true"
   ```

3. **Trigger Secret Refresh**:

   ```bash
   # Force External Secrets to refresh
   kubectl annotate externalsecret catalogue-secrets -n craftista-prod force-sync=$(date +%s)

   # Restart application pods to pick up new secrets
   kubectl rollout restart deployment/catalogue -n craftista-prod
   ```

4. **Verify and Clean Up**:

   ```bash
   # Verify application is working with new credentials
   kubectl logs -f deployment/catalogue -n craftista-prod

   # Test database connectivity
   kubectl exec -it deployment/catalogue -n craftista-prod -- python -c "
   import pymongo
   import os
   client = pymongo.MongoClient(os.environ['MONGODB_URI'])
   print('Connection test:', client.admin.command('ping'))
   "

   # Remove old user after verification
   kubectl run mongodb-admin --rm -it --image=mongo:4.4 -- mongo \
     "mongodb://catalogue-user-new:$NEW_PASSWORD@docdb-cluster.cluster-xxx.us-west-2.docdb.amazonaws.com:27017/admin?ssl=true" \
     --eval "db.dropUser('catalogue-user-old')"
   ```

### PostgreSQL Credentials (Voting Service)

1. **Generate New Credentials**:

   ```bash
   # Generate new password
   NEW_PASSWORD=$(openssl rand -base64 32)

   # Connect to PostgreSQL and create new user
   kubectl run postgres-admin --rm -it --image=postgres:13 -- psql \
     "postgresql://current-user:current-password@rds-instance.xxx.us-west-2.rds.amazonaws.com:5432/voting" \
     -c "
     CREATE USER voting_user_new WITH PASSWORD '$NEW_PASSWORD';
     GRANT CONNECT ON DATABASE voting TO voting_user_new;
     GRANT USAGE ON SCHEMA public TO voting_user_new;
     GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO voting_user_new;
     GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO voting_user_new;
     "
   ```

2. **Update Vault and Restart Application**:

   ```bash
   # Update Vault
   kubectl exec vault-0 -n vault -- vault kv put secret/craftista/prod/voting/postgres \
     username="voting_user_new" \
     password="$NEW_PASSWORD" \
     uri="postgresql://voting_user_new:$NEW_PASSWORD@rds-instance.xxx.us-west-2.rds.amazonaws.com:5432/voting"

   # Trigger secret refresh and restart
   kubectl annotate externalsecret voting-secrets -n craftista-prod force-sync=$(date +%s)
   kubectl rollout restart deployment/voting -n craftista-prod
   ```

### Redis Credentials (Recommendation Service)

1. **Update Redis AUTH Password**:

   ```bash
   # Generate new password
   NEW_PASSWORD=$(openssl rand -base64 32)

   # Update ElastiCache AUTH token (via AWS CLI)
   aws elasticache modify-cache-cluster \
     --cache-cluster-id craftista-redis-prod \
     --auth-token $NEW_PASSWORD \
     --auth-token-update-strategy ROTATE
   ```

2. **Update Vault and Application**:

   ```bash
   # Update Vault
   kubectl exec vault-0 -n vault -- vault kv put secret/craftista/prod/recommendation/redis \
     password="$NEW_PASSWORD" \
     uri="redis://:$NEW_PASSWORD@elasticache-cluster.xxx.cache.amazonaws.com:6379"

   # Restart application
   kubectl annotate externalsecret recommendation-secrets -n craftista-prod force-sync=$(date +%s)
   kubectl rollout restart deployment/recommendation -n craftista-prod
   ```

## Application Secrets Rotation

### Session Secrets and API Keys

1. **Generate New Secrets**:

   ```bash
   # Generate new session secret
   SESSION_SECRET=$(openssl rand -hex 32)

   # Generate new API key
   API_KEY=$(openssl rand -hex 16)

   # Generate new JWT secret
   JWT_SECRET=$(openssl rand -base64 64)
   ```

2. **Update Vault**:

   ```bash
   # Update frontend secrets
   kubectl exec vault-0 -n vault -- vault kv put secret/craftista/prod/frontend/app \
     session-secret="$SESSION_SECRET" \
     api-key="$API_KEY" \
     jwt-secret="$JWT_SECRET"

   # Update for all environments
   for env in dev staging prod; do
     kubectl exec vault-0 -n vault -- vault kv put secret/craftista/$env/frontend/app \
       session-secret="$(openssl rand -hex 32)" \
       api-key="$(openssl rand -hex 16)" \
       jwt-secret="$(openssl rand -base64 64)"
   done
   ```

3. **Rolling Update Applications**:
   ```bash
   # Refresh secrets and restart applications
   for env in dev staging prod; do
     kubectl annotate externalsecret frontend-secrets -n craftista-$env force-sync=$(date +%s)
     kubectl rollout restart deployment/frontend -n craftista-$env
   done
   ```

### Encryption Keys

1. **Generate New Encryption Key**:

   ```bash
   # Generate AES-256 key
   ENCRYPTION_KEY=$(openssl rand -hex 32)

   # For applications that support key rotation, add new key while keeping old
   kubectl exec vault-0 -n vault -- vault kv patch secret/craftista/prod/catalogue/app \
     encryption-key-new="$ENCRYPTION_KEY"
   ```

2. **Implement Key Rotation in Application**:

   ```bash
   # Update application to use new key for encryption, old key for decryption
   # This requires application code changes to support multiple keys

   # After data migration, remove old key
   kubectl exec vault-0 -n vault -- vault kv patch secret/craftista/prod/catalogue/app \
     encryption-key="$ENCRYPTION_KEY"
   ```

## CI/CD Secrets Rotation

### DockerHub Credentials

1. **Generate New DockerHub Token**:

   ```bash
   # Create new access token in DockerHub UI
   # Or use DockerHub API if available

   NEW_DOCKERHUB_TOKEN="dckr_pat_xxxxxxxxxxxxxxxxxxxxx"
   ```

2. **Update Vault**:

   ```bash
   kubectl exec vault-0 -n vault -- vault kv put secret/github-actions/dockerhub \
     username="your-dockerhub-username" \
     password="$NEW_DOCKERHUB_TOKEN"
   ```

3. **Test CI/CD Pipeline**:
   ```bash
   # Trigger a test build to verify new credentials work
   # This would be done through GitHub Actions or your CI/CD system
   ```

### SonarQube Token

1. **Generate New SonarQube Token**:

   ```bash
   # Generate new token via SonarQube UI or API
   curl -u admin:admin-password -X POST \
     "https://sonarqube.webdemoapp.com/api/user_tokens/generate" \
     -d "name=github-actions-$(date +%Y%m%d)" \
     -d "type=USER_TOKEN"
   ```

2. **Update Vault and Revoke Old Token**:

   ```bash
   # Update Vault
   kubectl exec vault-0 -n vault -- vault kv put secret/github-actions/sonarqube \
     token="$NEW_SONARQUBE_TOKEN"

   # Revoke old token
   curl -u admin:admin-password -X POST \
     "https://sonarqube.webdemoapp.com/api/user_tokens/revoke" \
     -d "name=old-token-name"
   ```

### GitHub Deploy Keys

1. **Generate New SSH Key Pair**:

   ```bash
   # Generate new SSH key
   ssh-keygen -t ed25519 -C "gitops-deploy-$(date +%Y%m%d)" -f ~/.ssh/gitops_deploy_key_new -N ""

   # Add public key to GitHub repository deploy keys
   # This must be done through GitHub UI or API
   ```

2. **Update Vault**:

   ```bash
   # Store new private key in Vault
   kubectl exec vault-0 -n vault -- vault kv put secret/github-actions/gitops \
     deploy-key="$(cat ~/.ssh/gitops_deploy_key_new)" \
     deploy-key-pub="$(cat ~/.ssh/gitops_deploy_key_new.pub)"
   ```

3. **Test and Remove Old Key**:

   ```bash
   # Test new key works
   ssh -T git@github.com -i ~/.ssh/gitops_deploy_key_new

   # Remove old deploy key from GitHub repository
   # This must be done through GitHub UI or API
   ```

## Infrastructure Secrets Rotation

### AWS Credentials

1. **Create New IAM User/Role**:

   ```bash
   # Create new IAM user for services
   aws iam create-user --user-name craftista-service-user-new

   # Attach necessary policies
   aws iam attach-user-policy --user-name craftista-service-user-new \
     --policy-arn arn:aws:iam::account:policy/CraftistaServicePolicy

   # Create access key
   aws iam create-access-key --user-name craftista-service-user-new
   ```

2. **Update Vault**:
   ```bash
   kubectl exec vault-0 -n vault -- vault kv put secret/aws/credentials \
     access-key-id="AKIA..." \
     secret-access-key="..."
   ```

### TLS Certificates

1. **Using cert-manager (Automated)**:

   ```bash
   # Check certificate status
   kubectl get certificates -n craftista-prod

   # Force certificate renewal
   kubectl annotate certificate frontend-tls -n craftista-prod cert-manager.io/issue-temporary-certificate=""

   # Monitor renewal
   kubectl describe certificate frontend-tls -n craftista-prod
   ```

2. **Manual Certificate Rotation**:

   ```bash
   # Generate new certificate (if not using Let's Encrypt)
   openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
     -keyout webdemoapp.com.key \
     -out webdemoapp.com.crt \
     -subj "/CN=webdemoapp.com"

   # Update Kubernetes secret
   kubectl create secret tls frontend-tls-new \
     --cert=webdemoapp.com.crt \
     --key=webdemoapp.com.key \
     -n craftista-prod

   # Update ingress to use new secret
   kubectl patch ingress frontend-ingress -n craftista-prod \
     -p '{"spec":{"tls":[{"hosts":["webdemoapp.com"],"secretName":"frontend-tls-new"}]}}'
   ```

## Emergency Secret Rotation

### Immediate Response (< 15 minutes)

1. **Disable Compromised Credentials**:

   ```bash
   # Disable database user immediately
   kubectl run postgres-admin --rm -it --image=postgres:13 -- psql \
     "postgresql://admin:password@rds-instance.xxx.us-west-2.rds.amazonaws.com:5432/voting" \
     -c "ALTER USER compromised_user WITH NOLOGIN;"

   # Revoke API tokens
   curl -X DELETE "https://api.service.com/tokens/compromised-token"
   ```

2. **Generate and Deploy New Credentials**:

   ```bash
   # Use emergency rotation script
   ./scripts/emergency-rotate.sh --service voting --credential postgres --env prod

   # Or manual emergency rotation
   NEW_PASSWORD=$(openssl rand -base64 32)
   kubectl exec vault-0 -n vault -- vault kv put secret/craftista/prod/voting/postgres \
     password="$NEW_PASSWORD" \
     rotated-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     rotation-reason="security-incident"
   ```

3. **Force Application Restart**:
   ```bash
   # Immediately restart affected applications
   kubectl rollout restart deployment/voting -n craftista-prod
   kubectl rollout restart deployment/catalogue -n craftista-prod
   kubectl rollout restart deployment/recommendation -n craftista-prod
   kubectl rollout restart deployment/frontend -n craftista-prod
   ```

### Emergency Rotation Script

```bash
#!/bin/bash
# emergency-rotate.sh - Emergency secret rotation

set -euo pipefail

SERVICE=$1
CREDENTIAL=$2
ENVIRONMENT=$3
REASON=${4:-"emergency-rotation"}

echo "EMERGENCY ROTATION: $SERVICE $CREDENTIAL in $ENVIRONMENT"
echo "Reason: $REASON"
echo "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Generate new credential based on type
case $CREDENTIAL in
  "postgres")
    NEW_PASSWORD=$(openssl rand -base64 32)
    kubectl exec vault-0 -n vault -- vault kv patch secret/craftista/$ENVIRONMENT/$SERVICE/postgres \
      password="$NEW_PASSWORD" \
      rotated-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      rotation-reason="$REASON"
    ;;
  "mongodb")
    NEW_PASSWORD=$(openssl rand -base64 32)
    kubectl exec vault-0 -n vault -- vault kv patch secret/craftista/$ENVIRONMENT/$SERVICE/mongodb \
      password="$NEW_PASSWORD" \
      rotated-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      rotation-reason="$REASON"
    ;;
  "redis")
    NEW_PASSWORD=$(openssl rand -base64 32)
    kubectl exec vault-0 -n vault -- vault kv patch secret/craftista/$ENVIRONMENT/$SERVICE/redis \
      password="$NEW_PASSWORD" \
      rotated-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      rotation-reason="$REASON"
    ;;
esac

# Force secret refresh
kubectl annotate externalsecret $SERVICE-secrets -n craftista-$ENVIRONMENT force-sync=$(date +%s)

# Restart application
kubectl rollout restart deployment/$SERVICE -n craftista-$ENVIRONMENT

echo "Emergency rotation completed for $SERVICE $CREDENTIAL"
```

## Verification and Testing

### Post-Rotation Verification

1. **Application Health Checks**:

   ```bash
   # Check all pods are running
   kubectl get pods -n craftista-prod

   # Test health endpoints
   curl -k https://webdemoapp.com/health
   curl -k https://catalogue.webdemoapp.com/health
   curl -k https://voting.webdemoapp.com/health
   curl -k https://recommendation.webdemoapp.com/health
   ```

2. **Database Connectivity Tests**:

   ```bash
   # Test MongoDB connection
   kubectl exec -it deployment/catalogue -n craftista-prod -- python -c "
   import pymongo, os
   client = pymongo.MongoClient(os.environ['MONGODB_URI'])
   print('MongoDB:', client.admin.command('ping'))
   "

   # Test PostgreSQL connection
   kubectl exec -it deployment/voting -n craftista-prod -- psql $POSTGRES_URI -c "SELECT 1;"

   # Test Redis connection
   kubectl exec -it deployment/recommendation -n craftista-prod -- redis-cli -u $REDIS_URI ping
   ```

3. **Functional Testing**:
   ```bash
   # Test critical application flows
   curl -X GET https://catalogue.webdemoapp.com/products
   curl -X POST https://voting.webdemoapp.com/api/votes -d '{"item":"test","vote":"up"}'
   curl -X GET https://recommendation.webdemoapp.com/api/recommendations
   ```

### Automated Testing Script

```bash
#!/bin/bash
# verify-rotation.sh - Verify secret rotation success

ENVIRONMENT=${1:-prod}
NAMESPACE="craftista-$ENVIRONMENT"

echo "Verifying secret rotation in $ENVIRONMENT environment..."

# Check pod status
echo "Checking pod status..."
kubectl get pods -n $NAMESPACE

# Test database connections
echo "Testing database connections..."
for service in catalogue voting recommendation; do
  echo "Testing $service..."
  kubectl exec deployment/$service -n $NAMESPACE -- timeout 10 sh -c '
    case "$service" in
      "catalogue") python -c "import pymongo,os; print(pymongo.MongoClient(os.environ[\"MONGODB_URI\"]).admin.command(\"ping\"))" ;;
      "voting") psql $POSTGRES_URI -c "SELECT 1;" ;;
      "recommendation") redis-cli -u $REDIS_URI ping ;;
    esac
  ' || echo "FAILED: $service database connection"
done

# Test application endpoints
echo "Testing application endpoints..."
for endpoint in /health /api/health; do
  for service in frontend catalogue voting recommendation; do
    url="https://$service.webdemoapp.com$endpoint"
    if curl -f -s -k "$url" > /dev/null; then
      echo "OK: $url"
    else
      echo "FAILED: $url"
    fi
  done
done

echo "Verification complete."
```

## Rollback Procedures

### Vault Secret Rollback

1. **Rollback to Previous Version**:

   ```bash
   # Check secret version history
   kubectl exec vault-0 -n vault -- vault kv metadata secret/craftista/prod/voting/postgres

   # Rollback to previous version
   kubectl exec vault-0 -n vault -- vault kv rollback -version=2 secret/craftista/prod/voting/postgres

   # Force secret refresh
   kubectl annotate externalsecret voting-secrets -n craftista-prod force-sync=$(date +%s)
   ```

2. **Restore from Backup**:

   ```bash
   # Restore Kubernetes secrets from backup
   kubectl apply -f /tmp/secret-backup-20240115/craftista-prod-secrets.yaml

   # Restart applications to pick up restored secrets
   kubectl rollout restart deployment/voting -n craftista-prod
   ```

### Database User Rollback

1. **Re-enable Previous User**:

   ```bash
   # Re-enable previous database user
   kubectl run postgres-admin --rm -it --image=postgres:13 -- psql \
     "postgresql://admin:password@rds-instance.xxx.us-west-2.rds.amazonaws.com:5432/voting" \
     -c "ALTER USER voting_user_old WITH LOGIN;"

   # Update Vault with old credentials
   kubectl exec vault-0 -n vault -- vault kv put secret/craftista/prod/voting/postgres \
     username="voting_user_old" \
     password="old-password"
   ```

## Post-Rotation Tasks

### Documentation and Audit

1. **Update Documentation**:

   ```bash
   # Record rotation in change log
   echo "$(date): Rotated secrets for $SERVICE in $ENVIRONMENT - Reason: $REASON" >> /var/log/secret-rotations.log

   # Update secret inventory
   kubectl exec vault-0 -n vault -- vault kv metadata secret/craftista/prod/voting/postgres
   ```

2. **Security Audit**:

   ```bash
   # Review Vault audit logs
   kubectl exec vault-0 -n vault -- vault audit list

   # Check access patterns
   kubectl logs -n vault vault-0 | grep "secret/craftista"
   ```

### Cleanup Tasks

1. **Remove Old Credentials**:

   ```bash
   # Remove old database users
   kubectl run postgres-admin --rm -it --image=postgres:13 -- psql \
     "postgresql://new-user:new-password@rds-instance.xxx.us-west-2.rds.amazonaws.com:5432/voting" \
     -c "DROP USER IF EXISTS voting_user_old;"

   # Remove old API tokens
   curl -X DELETE "https://api.service.com/tokens/old-token"
   ```

2. **Update Monitoring**:
   ```bash
   # Update monitoring dashboards with new credential metadata
   # Update alerting rules for credential expiration
   # Verify audit logging is capturing rotation events
   ```

### Rotation Checklist

- [ ] All secrets rotated successfully
- [ ] Applications restarted and healthy
- [ ] Database connectivity verified
- [ ] Functional testing completed
- [ ] Old credentials disabled/removed
- [ ] Documentation updated
- [ ] Audit trail recorded
- [ ] Monitoring updated
- [ ] Stakeholders notified
- [ ] Next rotation scheduled

## Best Practices

1. **Regular Schedule**: Rotate secrets on a regular schedule, not just when required
2. **Automation**: Use Vault dynamic secrets where possible for automatic rotation
3. **Testing**: Always test in non-production environments first
4. **Monitoring**: Monitor applications closely during and after rotation
5. **Documentation**: Keep detailed records of all rotations
6. **Backup**: Always backup current state before rotation
7. **Gradual Rollout**: Rotate secrets in dev → staging → prod order
8. **Verification**: Verify each step before proceeding to the next

## Emergency Contacts

- **Security Team**: [Contact information]
- **On-Call Engineer**: [Contact information]
- **Database Administrator**: [Contact information]
- **Platform Team**: [Contact information]

Remember: Secret rotation is a critical security practice. When in doubt, err on the side of caution and involve the security team in decision-making.
