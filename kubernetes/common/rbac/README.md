# RBAC Configuration for Craftista Microservices

This directory contains Role-Based Access Control (RBAC) configurations for the Craftista microservices application. The RBAC setup follows the principle of least privilege, ensuring each service has only the minimum permissions required to function.

## Overview

The RBAC configuration consists of three main components:

1. **ServiceAccounts**: Dedicated identity for each microservice
2. **Roles**: Define permissions for accessing Kubernetes resources
3. **RoleBindings**: Bind ServiceAccounts to their respective Roles

## Files

- `service-accounts.yaml`: ServiceAccount definitions for all microservices
- `roles.yaml`: Role definitions with minimal permissions for each service
- `role-bindings.yaml`: RoleBinding definitions connecting ServiceAccounts to Roles

## ServiceAccounts

Each microservice has its own ServiceAccount:

- `frontend`: For the Node.js frontend service
- `catalogue`: For the Python/Flask catalogue service
- `voting`: For the Java/Spring Boot voting service
- `recommendation`: For the Go recommendation service

## Roles and Permissions

### Frontend Role

**Permissions**:

- Read own ConfigMaps (`frontend-config`)
- Read own Secrets (`frontend-secrets`, `frontend-vault-token`)
- Read own Service (`frontend`)

**Production Restrictions**:

- Removes `list` verb on ConfigMaps
- Limits to specific resource names only

### Catalogue Role

**Permissions**:

- Read own ConfigMaps (`catalogue-config`)
- Read own Secrets (`catalogue-secrets`, `catalogue-vault-token`, `catalogue-mongodb-credentials`)
- Read own Service (`catalogue`)

**Production Restrictions**:

- Removes `list` verb on ConfigMaps
- Limits to specific resource names only

### Voting Role

**Permissions**:

- Read own ConfigMaps (`voting-config`)
- Read own Secrets (`voting-secrets`, `voting-vault-token`, `voting-postgres-credentials`)
- Read own Service (`voting`)
- Read migration job status (`voting-migration`)

**Production Restrictions**:

- Removes `list` verb on ConfigMaps and Jobs
- Limits to specific resource names only
- Read-only access to migration jobs

### Recommendation Role

**Permissions**:

- Read own ConfigMaps (`recommendation-config`)
- Read own Secrets (`recommendation-secrets`, `recommendation-vault-token`, `recommendation-redis-credentials`)
- Read own Service (`recommendation`)

**Production Restrictions**:

- Removes `list` verb on ConfigMaps
- Limits to specific resource names only

## Environment-Specific Roles

The RBAC configuration includes two sets of roles:

1. **Standard Roles** (`*-role`): Used in dev and staging environments

   - Allow `get` and `list` verbs for better debugging
   - More permissive for development workflows

2. **Production Roles** (`*-role-prod`): Used in production environment
   - Only allow `get` verb (no `list`)
   - Strictly limited to specific resource names
   - Minimal permissions for security hardening

## Usage

### Applying RBAC Configuration

To apply the RBAC configuration to a namespace:

```bash
# Apply to dev namespace
kubectl apply -f service-accounts.yaml -n craftista-dev
kubectl apply -f roles.yaml -n craftista-dev
kubectl apply -f role-bindings.yaml -n craftista-dev

# Apply to staging namespace
kubectl apply -f service-accounts.yaml -n craftista-staging
kubectl apply -f roles.yaml -n craftista-staging
kubectl apply -f role-bindings.yaml -n craftista-staging

# Apply to production namespace (uses prod roles)
kubectl apply -f service-accounts.yaml -n craftista-prod
kubectl apply -f roles.yaml -n craftista-prod
kubectl apply -f role-bindings.yaml -n craftista-prod
```

### Using ServiceAccounts in Deployments

Reference the ServiceAccount in your Deployment spec:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  template:
    spec:
      serviceAccountName: frontend # Use the frontend ServiceAccount
      containers:
        - name: frontend
          image: 8060633493/craftista-frontend:latest
```

### Environment-Specific RoleBindings

For production deployments, ensure you're using the production RoleBinding:

```bash
# In production namespace, apply the prod RoleBinding
kubectl apply -f role-bindings.yaml -n craftista-prod
```

The production RoleBinding (`*-rolebinding-prod`) will automatically bind to the more restrictive production Role (`*-role-prod`).

## Security Considerations

1. **Least Privilege**: Each service can only access its own resources
2. **No Cross-Service Access**: Services cannot read secrets or configs of other services
3. **No Cluster-Wide Permissions**: All roles are namespace-scoped
4. **Production Hardening**: Production roles are more restrictive than dev/staging
5. **Explicit Resource Names**: All permissions specify exact resource names (no wildcards)

## Validation

To verify RBAC is working correctly:

```bash
# Check if ServiceAccount exists
kubectl get serviceaccount frontend -n craftista-dev

# Check if Role exists
kubectl get role frontend-role -n craftista-dev

# Check if RoleBinding exists
kubectl get rolebinding frontend-rolebinding -n craftista-dev

# Test permissions (from within a pod)
kubectl auth can-i get configmap/frontend-config --as=system:serviceaccount:craftista-dev:frontend -n craftista-dev
# Should return: yes

kubectl auth can-i get configmap/catalogue-config --as=system:serviceaccount:craftista-dev:frontend -n craftista-dev
# Should return: no (frontend cannot access catalogue resources)
```

## Troubleshooting

### Permission Denied Errors

If a pod reports permission denied errors:

1. Verify the ServiceAccount is correctly specified in the Deployment
2. Check that the RoleBinding exists and references the correct ServiceAccount
3. Verify the Role includes the required permissions
4. Check the namespace matches between ServiceAccount, Role, and RoleBinding

```bash
# Debug RBAC for a specific ServiceAccount
kubectl describe serviceaccount frontend -n craftista-dev
kubectl describe role frontend-role -n craftista-dev
kubectl describe rolebinding frontend-rolebinding -n craftista-dev
```

### Production vs Dev/Staging Roles

Remember that production uses different, more restrictive roles:

- Dev/Staging: `frontend-role`, `catalogue-role`, etc.
- Production: `frontend-role-prod`, `catalogue-role-prod`, etc.

Ensure the correct RoleBinding is applied for each environment.

## Integration with Vault

These ServiceAccounts are used by Vault's Kubernetes auth method to authenticate pods and inject secrets. The Vault policies should reference these ServiceAccount names:

```hcl
# Example Vault policy for frontend
path "secret/data/craftista/*/frontend/*" {
  capabilities = ["read", "list"]
}
```

## Compliance

This RBAC configuration helps meet the following requirements:

- **Requirement 14.2**: Create service accounts with minimal permissions for each microservice
- **Requirement 14.4**: Enforce RBAC policies preventing unauthorized secret access
- **Requirement 14.5**: Apply stricter policies in production compared to dev environments

## References

- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
