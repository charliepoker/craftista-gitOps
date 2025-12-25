# Rollback Procedure

This runbook provides step-by-step instructions for rolling back deployments in the Craftista GitOps environment. Use these procedures when you need to revert to a previous working version due to issues with the current deployment.

## Table of Contents

- [Overview](#overview)
- [When to Rollback](#when-to-rollback)
- [Rollback Methods](#rollback-methods)
- [ArgoCD Rollback](#argocd-rollback)
- [Git-Based Rollback](#git-based-rollback)
- [Database Rollback Considerations](#database-rollback-considerations)
- [Verification Steps](#verification-steps)
- [Emergency Procedures](#emergency-procedures)
- [Post-Rollback Actions](#post-rollback-actions)

## Overview

The Craftista GitOps system supports multiple rollback methods depending on the situation and urgency. All rollbacks should be performed with caution and proper verification to ensure system stability.

### Rollback Scope

- **Application Rollback**: Revert application code and configuration
- **Configuration Rollback**: Revert Kubernetes manifests and Helm values
- **Database Rollback**: Handle database schema and data changes (requires special consideration)
- **Infrastructure Rollback**: Revert infrastructure changes (handled in craftista-iac repository)

## When to Rollback

### Immediate Rollback Scenarios

- ✅ Application crashes or fails to start
- ✅ Critical functionality is broken
- ✅ Security vulnerabilities introduced
- ✅ Performance degradation > 50%
- ✅ Data corruption detected
- ✅ Failed health checks for > 5 minutes

### Consider Rollback Scenarios

- ⚠️ Minor bugs that don't affect core functionality
- ⚠️ Performance degradation < 20%
- ⚠️ Non-critical feature issues
- ⚠️ Cosmetic UI problems

### Do Not Rollback Scenarios

- ❌ Database migrations that cannot be reversed
- ❌ Breaking changes that affect dependent services
- ❌ Security patches (fix forward instead)

## Rollback Methods

### Method 1: ArgoCD UI Rollback (Recommended)

**Use Case**: Quick rollback for application issues
**Time**: 2-5 minutes
**Risk**: Low

### Method 2: ArgoCD CLI Rollback

**Use Case**: Automated rollback scripts
**Time**: 1-3 minutes  
**Risk**: Low

### Method 3: Git Revert Rollback

**Use Case**: Complex configuration changes
**Time**: 5-10 minutes
**Risk**: Medium

### Method 4: Emergency Script Rollback

**Use Case**: Critical production issues
**Time**: 30 seconds - 2 minutes
**Risk**: Medium

## ArgoCD Rollback

### Using ArgoCD UI

1. **Access ArgoCD UI**:

   ```bash
   # Port forward if needed
   kubectl port-forward svc/argocd-server -n argocd 8080:443

   # Access https://localhost:8080 or https://argocd.webdemoapp.com
   ```

2. **Navigate to Application**:

   - Select the affected application (e.g., `craftista-frontend-prod`)
   - Click on the application name to view details

3. **View History**:

   - Click on "History and Rollback" tab
   - Review the deployment history
   - Identify the last known good revision

4. **Perform Rollback**:

   - Select the target revision
   - Click "Rollback" button
   - Confirm the rollback action
   - Monitor the sync status

5. **Verify Rollback**:
   - Check application status shows "Healthy" and "Synced"
   - Verify pods are running correctly
   - Test application functionality

### Using ArgoCD CLI

1. **List Application History**:

   ```bash
   # View deployment history
   argocd app history craftista-frontend-prod

   # Example output:
   # ID  DATE                           REVISION
   # 10  2024-01-15 14:30:00 +0000 UTC  abc123 (HEAD)
   # 9   2024-01-15 12:15:00 +0000 UTC  def456
   # 8   2024-01-15 10:00:00 +0000 UTC  ghi789
   ```

2. **Perform Rollback**:

   ```bash
   # Rollback to specific revision
   argocd app rollback craftista-frontend-prod 9

   # Or rollback to previous revision
   argocd app rollback craftista-frontend-prod
   ```

3. **Monitor Rollback**:

   ```bash
   # Watch rollback progress
   argocd app get craftista-frontend-prod --refresh

   # Monitor sync status
   argocd app wait craftista-frontend-prod --health
   ```

### Automated ArgoCD Rollback Script

```bash
#!/bin/bash
# Usage: ./rollback.sh <service> <environment> [revision]

SERVICE=$1
ENVIRONMENT=$2
REVISION=${3:-""}

APP_NAME="craftista-${SERVICE}-${ENVIRONMENT}"

if [ -z "$REVISION" ]; then
    echo "Rolling back $APP_NAME to previous revision..."
    argocd app rollback $APP_NAME
else
    echo "Rolling back $APP_NAME to revision $REVISION..."
    argocd app rollback $APP_NAME $REVISION
fi

echo "Waiting for rollback to complete..."
argocd app wait $APP_NAME --health --timeout 300

echo "Rollback completed. Current status:"
argocd app get $APP_NAME
```

## Git-Based Rollback

### Identify Target Commit

1. **View Git History**:

   ```bash
   # View recent commits
   git log --oneline -10

   # View commits for specific service
   git log --oneline --follow kubernetes/overlays/prod/frontend/

   # View commits with dates
   git log --pretty=format:"%h %ad %s" --date=short -10
   ```

2. **Identify Last Known Good Commit**:

   ```bash
   # Check commit details
   git show <commit-hash>

   # Check what changed in problematic commit
   git diff <good-commit> <bad-commit>
   ```

### Perform Git Revert

1. **Revert Specific Commit**:

   ```bash
   # Revert a single commit (creates new commit)
   git revert <commit-hash>

   # Revert multiple commits
   git revert <commit-hash-1> <commit-hash-2>

   # Revert merge commit
   git revert -m 1 <merge-commit-hash>
   ```

2. **Reset to Previous State** (Use with caution):

   ```bash
   # Hard reset to previous commit (destructive)
   git reset --hard <commit-hash>

   # Force push (only if you're sure)
   git push --force-with-lease origin main
   ```

3. **Create Rollback Branch** (Safer approach):

   ```bash
   # Create rollback branch
   git checkout -b rollback-frontend-prod-$(date +%Y%m%d-%H%M)

   # Reset to target commit
   git reset --hard <target-commit>

   # Push rollback branch
   git push origin rollback-frontend-prod-$(date +%Y%m%d-%H%M)

   # Create pull request for review
   ```

### Using Rollback Script

The provided rollback script automates the Git-based rollback process:

```bash
# Rollback frontend in production to specific commit
./scripts/rollback.sh frontend prod abc123def456

# Rollback catalogue in staging to previous commit
./scripts/rollback.sh catalogue staging HEAD~1

# Emergency rollback (uses last known good commit)
./scripts/rollback.sh voting prod emergency
```

## Database Rollback Considerations

### Database Migration Rollbacks

⚠️ **Warning**: Database rollbacks are complex and risky. Always test in non-production first.

#### Voting Service (PostgreSQL with Flyway)

1. **Check Migration Status**:

   ```bash
   # Connect to voting pod
   kubectl exec -it deployment/voting -n craftista-prod -- bash

   # Check Flyway migration history
   flyway info -url=$POSTGRES_URL -user=$POSTGRES_USER -password=$POSTGRES_PASSWORD
   ```

2. **Rollback Migration** (if supported):

   ```bash
   # Undo last migration (if undo scripts exist)
   flyway undo -url=$POSTGRES_URL -user=$POSTGRES_USER -password=$POSTGRES_PASSWORD
   ```

3. **Manual Rollback** (if no undo scripts):

   ```sql
   -- Connect to database
   psql $POSTGRES_URL

   -- Check schema_version table
   SELECT * FROM flyway_schema_history ORDER BY installed_on DESC LIMIT 5;

   -- Manually revert changes (requires knowledge of what changed)
   -- This is highly dependent on the specific migration
   ```

#### Catalogue Service (MongoDB)

1. **Check Current State**:

   ```bash
   # Connect to catalogue pod
   kubectl exec -it deployment/catalogue -n craftista-prod -- bash

   # Connect to MongoDB
   mongo $MONGODB_URI

   # Check collections and indexes
   db.products.getIndexes()
   ```

2. **Backup Before Rollback**:

   ```bash
   # Create backup
   mongodump --uri="$MONGODB_URI" --out=/tmp/backup-$(date +%Y%m%d-%H%M)
   ```

3. **Rollback Schema Changes**:

   ```javascript
   // Example: Remove index added in recent migration
   db.products.dropIndex("new_index_name");

   // Example: Remove field added in recent migration
   db.products.updateMany({}, { $unset: { new_field: "" } });
   ```

### Data Backup and Restore

1. **Create Point-in-Time Backup**:

   ```bash
   # PostgreSQL backup
   kubectl exec deployment/voting -n craftista-prod -- pg_dump $POSTGRES_URL > backup-$(date +%Y%m%d-%H%M).sql

   # MongoDB backup
   kubectl exec deployment/catalogue -n craftista-prod -- mongodump --uri="$MONGODB_URI" --archive > backup-$(date +%Y%m%d-%H%M).archive
   ```

2. **Restore from Backup**:

   ```bash
   # PostgreSQL restore
   kubectl exec -i deployment/voting -n craftista-prod -- psql $POSTGRES_URL < backup-20240115-1430.sql

   # MongoDB restore
   kubectl exec -i deployment/catalogue -n craftista-prod -- mongorestore --uri="$MONGODB_URI" --archive < backup-20240115-1430.archive
   ```

## Verification Steps

### Application Health Verification

1. **Check Pod Status**:

   ```bash
   # Verify pods are running
   kubectl get pods -n craftista-prod -l app=frontend

   # Check pod events
   kubectl describe pod <pod-name> -n craftista-prod

   # Check application logs
   kubectl logs -f deployment/frontend -n craftista-prod
   ```

2. **Health Check Endpoints**:

   ```bash
   # Test health endpoints
   curl -k https://frontend.webdemoapp.com/health
   curl -k https://catalogue.webdemoapp.com/health
   curl -k https://voting.webdemoapp.com/health
   curl -k https://recommendation.webdemoapp.com/health
   ```

3. **Service Connectivity**:
   ```bash
   # Test internal service connectivity
   kubectl exec -it deployment/frontend -n craftista-prod -- curl http://catalogue:5000/health
   kubectl exec -it deployment/frontend -n craftista-prod -- curl http://voting:8080/health
   kubectl exec -it deployment/frontend -n craftista-prod -- curl http://recommendation:8080/health
   ```

### Functional Testing

1. **Critical Path Testing**:

   ```bash
   # Test main application flow
   curl -k https://webdemoapp.com/

   # Test API endpoints
   curl -k https://catalogue.webdemoapp.com/products
   curl -k https://voting.webdemoapp.com/api/votes
   curl -k https://recommendation.webdemoapp.com/api/recommendations
   ```

2. **Database Connectivity**:

   ```bash
   # Test database connections from application pods
   kubectl exec -it deployment/catalogue -n craftista-prod -- python -c "
   import pymongo
   client = pymongo.MongoClient('$MONGODB_URI')
   print('MongoDB connection:', client.admin.command('ping'))
   "

   kubectl exec -it deployment/voting -n craftista-prod -- java -cp /app/lib/* -Dspring.profiles.active=prod com.craftista.voting.HealthCheck
   ```

### Performance Verification

1. **Response Time Check**:

   ```bash
   # Check response times
   curl -w "@curl-format.txt" -o /dev/null -s https://webdemoapp.com/

   # Where curl-format.txt contains:
   # time_namelookup:  %{time_namelookup}\n
   # time_connect:     %{time_connect}\n
   # time_appconnect:  %{time_appconnect}\n
   # time_pretransfer: %{time_pretransfer}\n
   # time_redirect:    %{time_redirect}\n
   # time_starttransfer: %{time_starttransfer}\n
   # time_total:       %{time_total}\n
   ```

2. **Resource Usage**:
   ```bash
   # Check resource usage
   kubectl top pods -n craftista-prod
   kubectl top nodes
   ```

## Emergency Procedures

### Critical Production Issues

1. **Immediate Response** (< 2 minutes):

   ```bash
   # Scale down problematic service immediately
   kubectl scale deployment frontend --replicas=0 -n craftista-prod

   # Or use emergency rollback script
   ./scripts/rollback.sh frontend prod emergency
   ```

2. **Traffic Diversion**:

   ```bash
   # Update ingress to divert traffic to staging
   kubectl patch ingress frontend-ingress -n craftista-prod -p '{"spec":{"rules":[{"host":"webdemoapp.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"maintenance-page","port":{"number":80}}}}]}}]}}'
   ```

3. **Maintenance Mode**:
   ```bash
   # Deploy maintenance page
   kubectl apply -f - <<EOF
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: maintenance-page
     namespace: craftista-prod
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: maintenance-page
     template:
       metadata:
         labels:
           app: maintenance-page
       spec:
         containers:
         - name: nginx
           image: nginx:alpine
           ports:
           - containerPort: 80
           volumeMounts:
           - name: html
             mountPath: /usr/share/nginx/html
         volumes:
         - name: html
           configMap:
             name: maintenance-html
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: maintenance-page
     namespace: craftista-prod
   spec:
     selector:
       app: maintenance-page
     ports:
     - port: 80
       targetPort: 80
   ---
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: maintenance-html
     namespace: craftista-prod
   data:
     index.html: |
       <!DOCTYPE html>
       <html>
       <head><title>Maintenance</title></head>
       <body>
         <h1>System Maintenance</h1>
         <p>We're currently performing maintenance. Please try again in a few minutes.</p>
       </body>
       </html>
   EOF
   ```

### Rollback Failure Recovery

If rollback fails:

1. **Check ArgoCD Status**:

   ```bash
   # Check ArgoCD application status
   argocd app get craftista-frontend-prod

   # Check ArgoCD server logs
   kubectl logs -f deployment/argocd-application-controller -n argocd
   ```

2. **Manual Intervention**:

   ```bash
   # Force sync with replace
   argocd app sync craftista-frontend-prod --force --replace

   # Or delete and recreate application
   argocd app delete craftista-frontend-prod
   kubectl apply -f argocd/applications/prod/frontend-app.yaml
   ```

3. **Direct Kubernetes Rollback**:

   ```bash
   # Use kubectl rollout undo as last resort
   kubectl rollout undo deployment/frontend -n craftista-prod

   # Check rollout status
   kubectl rollout status deployment/frontend -n craftista-prod
   ```

## Post-Rollback Actions

### Immediate Actions

1. **Verify System Stability**:

   - Monitor application metrics for 15 minutes
   - Check error rates and response times
   - Verify all critical functionality works

2. **Update Stakeholders**:

   - Notify team of rollback completion
   - Update incident ticket with rollback details
   - Communicate status to users if needed

3. **Document Issues**:
   - Record what went wrong
   - Document rollback steps taken
   - Note any data loss or side effects

### Follow-up Actions

1. **Root Cause Analysis**:

   - Investigate what caused the need for rollback
   - Review deployment process for improvements
   - Update testing procedures if needed

2. **Fix Forward Planning**:

   - Plan proper fix for the original issue
   - Implement additional testing
   - Schedule fix deployment

3. **Process Improvement**:
   - Review rollback procedures
   - Update documentation based on lessons learned
   - Improve monitoring and alerting

### Rollback Checklist

- [ ] Rollback completed successfully
- [ ] All services are healthy and responding
- [ ] Database integrity verified
- [ ] Performance metrics are normal
- [ ] Error rates are acceptable
- [ ] Stakeholders notified
- [ ] Incident documented
- [ ] Root cause analysis scheduled
- [ ] Fix forward plan created
- [ ] Monitoring alerts reviewed

## Best Practices

1. **Always Test Rollback Procedures**: Practice rollbacks in non-production environments
2. **Maintain Rollback Scripts**: Keep rollback automation up to date
3. **Monitor After Rollback**: Watch system closely for 30 minutes post-rollback
4. **Document Everything**: Record all actions taken during rollback
5. **Plan Fix Forward**: Don't just rollback, plan to fix the underlying issue
6. **Review and Improve**: Use rollback experiences to improve processes

## Emergency Contacts

- **On-Call Engineer**: [Contact information]
- **Platform Team Lead**: [Contact information]
- **Database Administrator**: [Contact information]
- **Security Team**: [Contact information]

Remember: When in doubt, prioritize system stability and user experience. It's better to rollback quickly and fix forward than to spend time debugging in production.
