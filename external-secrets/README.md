# External Secrets Operator Integration

This directory contains the External Secrets Operator (ESO) configuration for the Craftista GitOps repository. ESO synchronizes secrets from HashiCorp Vault to Kubernetes Secrets, providing a secure and automated way to manage sensitive data.

## Overview

The External Secrets Operator provides an alternative to Vault Agent Injector for secret management. Instead of injecting secrets as files into pods, ESO creates native Kubernetes Secrets that can be consumed by applications through environment variables or volume mounts.

### Benefits

- **Native Kubernetes Secrets**: Applications consume secrets as standard Kubernetes Secrets
- **Automatic Synchronization**: Secrets are automatically synced from Vault at configurable intervals
- **Declarative Configuration**: Secret mappings are defined as Kubernetes resources
- **Multi-Provider Support**: Can integrate with Vault, AWS Secrets Manager, Azure Key Vault, etc.
- **Namespace Isolation**: SecretStores provide namespace-scoped access control

## Directory Structure

```
external-secrets/
├── README.md                           # This file
├── secret-store.yaml                   # Namespace-scoped SecretStores
├── cluster-secret-store.yaml          # Cluster-wide SecretStores
└── external-secrets/                   # ExternalSecret resources
    ├── frontend-secrets.yaml          # Frontend service secrets
    ├── catalogue-secrets.yaml         # Catalogue service secrets
    ├── voting-secrets.yaml            # Voting service secrets
    └── recommendation-secrets.yaml    # Recommendation service secrets
```

## Components

### SecretStore

A **SecretStore** is a namespaced resource that defines how to connect to a secret backend (Vault). Each namespace (craftista-dev, craftista-staging, craftista-prod) has its own SecretStore.

**File**: `secret-store.yaml`

**Key Configuration**:
- Vault server URL: `http://vault.vault.svc.cluster.local:8200`
- Authentication: Kubernetes service account
- Secret path: `secret/data/craftista/{environment}/{service}/*`

### ClusterSecretStore

A **ClusterSecretStore** is a cluster-wide resource that can be referenced from any namespace. Useful for shared secrets and cross-namespace access.

**File**: `cluster-secret-store.yaml`

**Stores Defined**:
- `vault-backend-cluster`: General cluster-wide access
- `vault-github-actions`: CI/CD pipeline secrets
- `vault-argocd`: ArgoCD repository credentials

### ExternalSecret

An **ExternalSecret** defines which secrets to fetch from Vault and how to map them to Kubernetes Secret fields.

**Files**:
- `external-secrets/frontend-secrets.yaml`
- `external-secrets/catalogue-secrets.yaml`
- `external-secrets/voting-secrets.yaml`
- `external-secrets/recommendation-secrets.yaml`

Each file contains three ExternalSecret resources (one per environment: dev, staging, prod).

## Installation

### 1. Install External Secrets Operator

```bash
# Add External Secrets Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install External Secrets Operator
helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets-operator \
  --create-namespace \
  --set installCRDs=true

# Verify installation
kubectl get pods -n external-secrets-operator
```

### 2. Create Service Accounts

```bash
# Create service account for External Secrets Operator in each namespace
kubectl create serviceaccount external-secrets-sa -n craftista-dev
kubectl create serviceaccount external-secrets-sa -n craftista-staging
kubectl create serviceaccount external-secrets-sa -n craftista-prod

# Create cluster-wide service accounts
kubectl create serviceaccount external-secrets-sa -n external-secrets-operator
kubectl create serviceaccount github-actions-sa -n external-secrets-operator
kubectl create serviceaccount argocd-sa -n argocd
```

### 3. Configure Vault Authentication

```bash
# Enable Kubernetes auth in Vault
vault auth enable kubernetes

# Configure Kubernetes auth
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

# Create Vault role for External Secrets Operator
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets-sa \
  bound_service_account_namespaces=craftista-dev,craftista-staging,craftista-prod,external-secrets-operator \
  policies=frontend-policy,catalogue-policy,voting-policy,recommendation-policy \
  ttl=1h
```

### 4. Deploy SecretStores

```bash
# Apply namespace-scoped SecretStores
kubectl apply -f external-secrets/secret-store.yaml

# Apply cluster-wide SecretStores
kubectl apply -f external-secrets/cluster-secret-store.yaml

# Verify SecretStores
kubectl get secretstores -A
kubectl get clustersecretstores
```

### 5. Deploy ExternalSecrets

```bash
# Apply ExternalSecret resources for all services
kubectl apply -f external-secrets/external-secrets/frontend-secrets.yaml
kubectl apply -f external-secrets/external-secrets/catalogue-secrets.yaml
kubectl apply -f external-secrets/external-secrets/voting-secrets.yaml
kubectl apply -f external-secrets/external-secrets/recommendation-secrets.yaml

# Verify ExternalSecrets
kubectl get externalsecrets -A

# Check synchronization status
kubectl describe externalsecret frontend-secrets -n craftista-dev
```

## Usage

### Consuming Secrets in Deployments

Once ExternalSecrets are deployed, they create Kubernetes Secrets that can be consumed by pods:

#### Method 1: Environment Variables

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  template:
    spec:
      containers:
        - name: frontend
          image: 8060633493/craftista-frontend:latest
          envFrom:
            - secretRef:
                name: frontend-secrets  # Created by ExternalSecret
```

#### Method 2: Volume Mounts

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalogue
spec:
  template:
    spec:
      containers:
        - name: catalogue
          image: 8060633493/craftista-catalogue:latest
          volumeMounts:
            - name: secrets
              mountPath: /etc/secrets
              readOnly: true
      volumes:
        - name: secrets
          secret:
            secretName: catalogue-secrets  # Created by ExternalSecret
```

#### Method 3: Specific Environment Variables

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: voting
spec:
  template:
    spec:
      containers:
        - name: voting
          image: 8060633493/craftista-voting:latest
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: voting-secrets  # Created by ExternalSecret
                  key: POSTGRES_PASSWORD
            - name: JDBC_URL
              valueFrom:
                secretKeyRef:
                  name: voting-secrets
                  key: JDBC_URL
```

## Secret Refresh

ExternalSecrets automatically refresh secrets from Vault at configurable intervals:

- **Development**: Every 1 hour (`refreshInterval: 1h`)
- **Staging**: Every 1 hour (`refreshInterval: 1h`)
- **Production**: Every 30 minutes (`refreshInterval: 30m`)

When secrets are updated in Vault, ESO will:
1. Detect the change during the next refresh cycle
2. Update the Kubernetes Secret
3. Pods consuming the secret will need to be restarted to pick up changes (unless using a sidecar that watches for changes)

### Manual Refresh

To force an immediate refresh:

```bash
# Annotate the ExternalSecret to trigger refresh
kubectl annotate externalsecret frontend-secrets \
  -n craftista-dev \
  force-sync=$(date +%s) \
  --overwrite
```

## Monitoring

### Check ExternalSecret Status

```bash
# List all ExternalSecrets
kubectl get externalsecrets -A

# Check specific ExternalSecret status
kubectl describe externalsecret frontend-secrets -n craftista-dev

# View ExternalSecret events
kubectl get events -n craftista-dev --field-selector involvedObject.name=frontend-secrets
```

### Check Created Secrets

```bash
# List secrets created by ExternalSecrets
kubectl get secrets -n craftista-dev -l app=frontend

# View secret data (base64 encoded)
kubectl get secret frontend-secrets -n craftista-dev -o yaml

# Decode secret values
kubectl get secret frontend-secrets -n craftista-dev -o jsonpath='{.data.SESSION_SECRET}' | base64 -d
```

### Check SecretStore Status

```bash
# Check SecretStore status
kubectl get secretstore vault-backend -n craftista-dev -o yaml

# Check ClusterSecretStore status
kubectl get clustersecretstore vault-backend-cluster -o yaml
```

## Troubleshooting

### ExternalSecret Not Syncing

**Symptoms**: ExternalSecret shows `SecretSyncedError` status

**Possible Causes**:
1. Vault authentication failure
2. Secret path doesn't exist in Vault
3. Insufficient Vault policy permissions
4. Network connectivity issues

**Resolution**:

```bash
# Check ExternalSecret status
kubectl describe externalsecret frontend-secrets -n craftista-dev

# Check SecretStore status
kubectl describe secretstore vault-backend -n craftista-dev

# Check External Secrets Operator logs
kubectl logs -n external-secrets-operator -l app.kubernetes.io/name=external-secrets

# Verify Vault connectivity from pod
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://vault.vault.svc.cluster.local:8200/v1/sys/health

# Test Vault authentication
kubectl exec -it -n craftista-dev <pod-name> -- \
  vault login -method=kubernetes role=external-secrets
```

### Secret Not Found in Vault

**Symptoms**: ExternalSecret shows error "secret not found"

**Resolution**:

```bash
# Verify secret exists in Vault
vault kv get secret/craftista/dev/frontend/api-keys

# If missing, create the secret
vault kv put secret/craftista/dev/frontend/api-keys \
  session_secret="$(openssl rand -base64 32)" \
  jwt_secret="$(openssl rand -base64 64)"
```

### Permission Denied

**Symptoms**: ExternalSecret shows "permission denied" error

**Resolution**:

```bash
# Check Vault policy
vault policy read frontend-policy

# Verify service account has correct role binding
vault read auth/kubernetes/role/external-secrets

# Update policy if needed
vault policy write frontend-policy vault/policies/frontend-policy.hcl
```

### Pods Not Picking Up Secret Changes

**Symptoms**: Secrets updated in Vault but pods still use old values

**Resolution**:

```bash
# Restart pods to pick up new secret values
kubectl rollout restart deployment frontend -n craftista-dev

# Or use a tool like Reloader to automatically restart pods on secret changes
# https://github.com/stakater/Reloader
```

## Security Considerations

### Access Control

- ✅ Each service has its own ExternalSecret with specific secret mappings
- ✅ SecretStores are namespace-scoped, preventing cross-namespace access
- ✅ Vault policies enforce least-privilege access
- ✅ Service accounts are bound to specific Vault roles

### Secret Rotation

When rotating secrets:

1. Update secret in Vault
2. Wait for ExternalSecret refresh interval (or force refresh)
3. Restart pods to pick up new values
4. Verify application functionality
5. Remove old secret version from Vault

### Audit Logging

- Enable Vault audit logging to track secret access
- Monitor ExternalSecret events for sync failures
- Alert on repeated authentication failures
- Review secret access patterns regularly

## Comparison: ESO vs Vault Agent Injector

| Feature | External Secrets Operator | Vault Agent Injector |
|---------|---------------------------|----------------------|
| Secret Format | Kubernetes Secrets | Files in pod filesystem |
| Consumption | Environment variables or volumes | File reads |
| Refresh | Automatic at intervals | Requires sidecar for updates |
| Overhead | Minimal (controller only) | Sidecar per pod |
| Complexity | Simple | Moderate |
| Use Case | Standard applications | Applications requiring file-based secrets |

**Recommendation**: Use External Secrets Operator for most use cases. Use Vault Agent Injector when:
- Application requires secrets as files
- Need template rendering for complex secret formats
- Require real-time secret updates without pod restarts

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [ESO Vault Provider](https://external-secrets.io/latest/provider/hashicorp-vault/)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [HashiCorp Vault Kubernetes Auth](https://www.vaultproject.io/docs/auth/kubernetes)
- [Vault KV Secrets Engine](https://www.vaultproject.io/docs/secrets/kv/kv-v2)

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review External Secrets Operator logs
3. Verify Vault connectivity and authentication
4. Consult the Vault README in `vault/README.md`
5. Contact the DevOps tea