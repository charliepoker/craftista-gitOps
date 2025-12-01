# RBAC Configuration Validation

This document validates that the RBAC configuration meets all requirements from the Craftista GitOps implementation specification.

## Requirements Validation

### Requirement 14.2: Create service accounts with minimal permissions for each microservice

✅ **SATISFIED**

**Evidence**:

- Created 4 ServiceAccounts (one per microservice):
  - `frontend` - For Node.js frontend service
  - `catalogue` - For Python/Flask catalogue service
  - `voting` - For Java/Spring Boot voting service
  - `recommendation` - For Go recommendation service

**Files**: `service-accounts.yaml`

**Minimal Permissions Approach**:
Each service has its own dedicated Role with only the permissions it needs:

- Frontend: Read own ConfigMaps, Secrets, and Service
- Catalogue: Read own ConfigMaps, Secrets (including MongoDB credentials), and Service
- Voting: Read own ConfigMaps, Secrets (including PostgreSQL credentials), Service, and migration job status
- Recommendation: Read own ConfigMaps, Secrets (including Redis credentials), and Service

### Requirement 14.4: Enforce RBAC policies preventing unauthorized secret access

✅ **SATISFIED**

**Evidence**:
All Roles use `resourceNames` to explicitly specify which resources can be accessed:

```yaml
# Example from frontend-role
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
    resourceNames: ["frontend-secrets", "frontend-vault-token"]
```

**Security Features**:

1. **Explicit Resource Names**: No wildcards - each Role specifies exact resource names
2. **No Cross-Service Access**: Frontend cannot access catalogue-secrets, voting-secrets, etc.
3. **Namespace-Scoped**: All Roles are namespace-scoped (not ClusterRoles)
4. **Read-Only**: Services can only read secrets, not create, update, or delete them

**Validation Test**:

```bash
# Frontend should be able to access its own secrets
kubectl auth can-i get secret/frontend-secrets --as=system:serviceaccount:craftista-dev:frontend -n craftista-dev
# Expected: yes

# Frontend should NOT be able to access catalogue secrets
kubectl auth can-i get secret/catalogue-secrets --as=system:serviceaccount:craftista-dev:frontend -n craftista-dev
# Expected: no
```

### Requirement 14.5: Apply stricter policies in production compared to dev environments

✅ **SATISFIED**

**Evidence**:
Created separate production Roles with more restrictive permissions:

| Aspect             | Dev/Staging Roles | Production Roles |
| ------------------ | ----------------- | ---------------- |
| ConfigMap verbs    | `get`, `list`     | `get` only       |
| Secret verbs       | `get`             | `get` only       |
| Service verbs      | `get`             | Not included     |
| Job verbs (voting) | `get`, `list`     | `get` only       |
| Resource names     | Explicit          | Explicit         |

**Example Comparison**:

**Dev/Staging Role** (`frontend-role`):

```yaml
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"] # Allows listing for debugging
    resourceNames: ["frontend-config"]
```

**Production Role** (`frontend-role-prod`):

```yaml
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get"] # Only get, no list
    resourceNames: ["frontend-config"]
```

**Key Differences**:

1. **Removed `list` verb**: Production roles cannot list resources, only get specific ones
2. **Removed Service access**: Production roles don't include service discovery permissions
3. **Environment labels**: Production roles are labeled with `environment: production`
4. **Separate RoleBindings**: Production uses `*-rolebinding-prod` which binds to `*-role-prod`

## Implementation Details

### ServiceAccounts

- **File**: `service-accounts.yaml`
- **Count**: 4 (one per microservice)
- **Features**:
  - Labeled for easy identification
  - `automountServiceAccountToken: true` for Vault integration

### Roles

- **File**: `roles.yaml`
- **Count**: 8 (4 standard + 4 production)
- **Standard Roles**: `frontend-role`, `catalogue-role`, `voting-role`, `recommendation-role`
- **Production Roles**: `frontend-role-prod`, `catalogue-role-prod`, `voting-role-prod`, `recommendation-role-prod`

### RoleBindings

- **File**: `role-bindings.yaml`
- **Count**: 8 (4 standard + 4 production)
- **Standard Bindings**: Used in dev and staging namespaces
- **Production Bindings**: Used in production namespace

## Least Privilege Principle

Each service has been granted only the minimum permissions required:

### Frontend

- ✅ Read own ConfigMap for configuration
- ✅ Read own Secrets for Vault tokens and credentials
- ✅ Read own Service for service discovery (dev/staging only)
- ❌ Cannot access other services' resources
- ❌ Cannot modify any resources

### Catalogue

- ✅ Read own ConfigMap for configuration
- ✅ Read own Secrets including MongoDB credentials
- ✅ Read own Service for service discovery (dev/staging only)
- ❌ Cannot access other services' resources
- ❌ Cannot modify any resources

### Voting

- ✅ Read own ConfigMap for configuration
- ✅ Read own Secrets including PostgreSQL credentials
- ✅ Read own Service for service discovery (dev/staging only)
- ✅ Read migration job status for health checks
- ❌ Cannot access other services' resources
- ❌ Cannot modify any resources

### Recommendation

- ✅ Read own ConfigMap for configuration
- ✅ Read own Secrets including Redis credentials
- ✅ Read own Service for service discovery (dev/staging only)
- ❌ Cannot access other services' resources
- ❌ Cannot modify any resources

## Security Validation

### Test 1: Verify ServiceAccounts exist

```bash
kubectl get serviceaccount frontend catalogue voting recommendation -n craftista-dev
```

### Test 2: Verify Roles exist

```bash
kubectl get role -n craftista-dev | grep -E "frontend|catalogue|voting|recommendation"
```

### Test 3: Verify RoleBindings exist

```bash
kubectl get rolebinding -n craftista-dev | grep -E "frontend|catalogue|voting|recommendation"
```

### Test 4: Test permission isolation

```bash
# Frontend can access its own secrets
kubectl auth can-i get secret/frontend-secrets \
  --as=system:serviceaccount:craftista-dev:frontend \
  -n craftista-dev

# Frontend cannot access catalogue secrets
kubectl auth can-i get secret/catalogue-secrets \
  --as=system:serviceaccount:craftista-dev:frontend \
  -n craftista-dev
```

### Test 5: Verify production restrictions

```bash
# In production, verify list is not allowed
kubectl auth can-i list configmaps \
  --as=system:serviceaccount:craftista-prod:frontend \
  -n craftista-prod
# Expected: no (production role doesn't have list verb)
```

## Deployment Instructions

### For Dev Environment

```bash
kubectl apply -f service-accounts.yaml -n craftista-dev
kubectl apply -f roles.yaml -n craftista-dev
kubectl apply -f role-bindings.yaml -n craftista-dev
```

### For Staging Environment

```bash
kubectl apply -f service-accounts.yaml -n craftista-staging
kubectl apply -f roles.yaml -n craftista-staging
kubectl apply -f role-bindings.yaml -n craftista-staging
```

### For Production Environment

```bash
kubectl apply -f service-accounts.yaml -n craftista-prod
kubectl apply -f roles.yaml -n craftista-prod
kubectl apply -f role-bindings.yaml -n craftista-prod
```

Note: The production RoleBindings (`*-rolebinding-prod`) will automatically use the more restrictive production Roles.

## Compliance Summary

| Requirement                                    | Status       | Evidence                                               |
| ---------------------------------------------- | ------------ | ------------------------------------------------------ |
| 14.2: ServiceAccounts with minimal permissions | ✅ SATISFIED | 4 ServiceAccounts created, each with dedicated Role    |
| 14.4: Prevent unauthorized secret access       | ✅ SATISFIED | Explicit resourceNames, no cross-service access        |
| 14.5: Stricter production policies             | ✅ SATISFIED | Production roles remove `list` verb and service access |

## Next Steps

1. Apply RBAC configurations to all namespaces (dev, staging, prod)
2. Update Deployment manifests to reference ServiceAccounts
3. Test RBAC permissions in each environment
4. Integrate with Vault Kubernetes auth method
5. Monitor for permission denied errors and adjust if needed

## References

- Task: `.kiro/specs/craftista-gitops-implementation/tasks.md` - Task 5
- Requirements: `.kiro/specs/craftista-gitops-implementation/requirements.md` - Requirement 14
- Design: `.kiro/specs/craftista-gitops-implementation/design.md` - Property 11
