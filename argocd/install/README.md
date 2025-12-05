# ArgoCD Installation

This directory contains the configuration files for installing and configuring ArgoCD in the EKS cluster.

## Overview

ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes. It monitors the `craftista-gitops` repository and automatically syncs the desired state to the target Kubernetes clusters.

## Installation

### Prerequisites

- EKS cluster is provisioned and accessible via kubectl
- kubectl is configured to access the cluster
- Helm 3.x installed (optional, for Helm-based installation)

### Option 1: Using the Setup Script (Recommended)

```bash
# Run the automated setup script
./scripts/setup-argocd.sh
```

This script will:

1. Create the argocd namespace
2. Install ArgoCD using the official manifest
3. Apply custom configuration (argocd-cm.yaml, argocd-rbac-cm.yaml)
4. Wait for all pods to be ready
5. Retrieve the initial admin password
6. Provide instructions for accessing the UI

### Option 2: Manual Installation

#### Step 1: Create Namespace

```bash
kubectl apply -f namespace.yaml
```

#### Step 2: Install ArgoCD

For standard installation:

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.9.3/manifests/install.yaml
```

For High Availability installation (recommended for production):

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.9.3/manifests/ha/install.yaml
```

#### Step 3: Wait for Pods to be Ready

```bash
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

#### Step 4: Apply Custom Configuration

```bash
kubectl apply -f argocd-cm.yaml
kubectl apply -f argocd-rbac-cm.yaml
```

#### Step 5: Restart ArgoCD Components

```bash
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout restart deployment argocd-application-controller -n argocd
```

## Accessing ArgoCD

### Get Initial Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

### Access via Port Forward

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open your browser to: https://localhost:8080

- **Username**: admin
- **Password**: (from the command above)

### Access via Ingress (Production)

For production environments, configure an Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.webdemoapp.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  name: https
  tls:
    - hosts:
        - argocd.webdemoapp.com
      secretName: argocd-server-tls
```

## ArgoCD CLI Installation

### macOS

```bash
brew install argocd
```

### Linux

```bash
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/v2.9.3/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

### Windows

```powershell
$version = "v2.9.3"
$url = "https://github.com/argoproj/argo-cd/releases/download/$version/argocd-windows-amd64.exe"
$output = "$env:USERPROFILE\argocd.exe"
Invoke-WebRequest -Uri $url -OutFile $output
```

## CLI Login

```bash
# Port forward method
argocd login localhost:8080

# Direct access method (if using ingress)
argocd login argocd.webdemoapp.com
```

## Post-Installation Configuration

### 1. Change Admin Password

```bash
argocd account update-password
```

### 2. Add Repository Credentials (if private)

```bash
# Via CLI
argocd repo add https://github.com/charliepoker/craftista-gitops.git \
  --username <username> \
  --password <token>

# Via Vault (recommended)
# Credentials will be injected via External Secrets Operator
```

### 3. Create AppProjects

```bash
kubectl apply -f ../projects/craftista-dev.yaml
kubectl apply -f ../projects/craftista-staging.yaml
kubectl apply -f ../projects/craftista-prod.yaml
```

### 4. Create Applications

```bash
# Dev environment
kubectl apply -f ../applications/dev/

# Staging environment
kubectl apply -f ../applications/staging/

# Production environment
kubectl apply -f ../applications/prod/
```

## Configuration Files

### argocd-cm.yaml

Contains ArgoCD server configuration:

- Repository URLs and credentials
- Application settings
- Timeout configurations
- Resource tracking method
- Kustomize and Helm options
- SSO/OIDC configuration
- Webhook secrets
- Resource exclusions/inclusions

### argocd-rbac-cm.yaml

Contains RBAC policies:

- **admin**: Full access to all resources
- **developer**: Can manage dev and staging applications
- **devops**: Can manage all applications
- **prod-deployer**: Can only sync production applications
- **readonly**: View-only access
- **cicd**: Service account for CI/CD pipelines
- **monitoring**: View status and logs only

## User Management

### Create Additional Users

Edit `argocd-cm.yaml` and add:

```yaml
data:
  accounts.newuser: apiKey, login
```

Then set the password:

```bash
argocd account update-password --account newuser
```

### Assign Roles

Edit `argocd-rbac-cm.yaml` and add:

```yaml
policy.csv: |
  g, newuser, role:developer
```

## SSO Integration (Optional)

### GitHub SSO

1. Create a GitHub OAuth App:

   - Go to GitHub Settings → Developer settings → OAuth Apps
   - Set Authorization callback URL: `https://argocd.webdemoapp.com/api/dex/callback`

2. Update `argocd-cm.yaml`:

```yaml
data:
  dex.config: |
    connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: $dex.github.clientId
        clientSecret: $dex.github.clientSecret
        orgs:
        - name: your-github-org
```

3. Store credentials in Vault and inject via External Secrets

## Monitoring

### Check ArgoCD Status

```bash
# Check all pods
kubectl get pods -n argocd

# Check application status
argocd app list

# Get application details
argocd app get <app-name>

# View sync history
argocd app history <app-name>
```

### View Logs

```bash
# Server logs
kubectl logs -n argocd deployment/argocd-server -f

# Application controller logs
kubectl logs -n argocd deployment/argocd-application-controller -f

# Repo server logs
kubectl logs -n argocd deployment/argocd-repo-server -f
```

### Metrics

ArgoCD exposes Prometheus metrics at:

- Server: `http://argocd-server-metrics:8083/metrics`
- Repo Server: `http://argocd-repo-server:8084/metrics`
- Application Controller: `http://argocd-application-controller-metrics:8082/metrics`

## Troubleshooting

### Application Not Syncing

1. Check application status:

   ```bash
   argocd app get <app-name>
   ```

2. Check sync errors:

   ```bash
   argocd app sync <app-name> --dry-run
   ```

3. View detailed logs:
   ```bash
   kubectl logs -n argocd deployment/argocd-application-controller -f | grep <app-name>
   ```

### Repository Connection Issues

1. Test repository access:

   ```bash
   argocd repo list
   ```

2. Re-add repository:
   ```bash
   argocd repo add <repo-url> --username <user> --password <token>
   ```

### Permission Denied Errors

1. Check RBAC configuration:

   ```bash
   kubectl get cm argocd-rbac-cm -n argocd -o yaml
   ```

2. Verify user role:
   ```bash
   argocd account get --account <username>
   ```

### Pods Not Starting

1. Check pod status:

   ```bash
   kubectl get pods -n argocd
   ```

2. Describe problematic pod:

   ```bash
   kubectl describe pod <pod-name> -n argocd
   ```

3. Check resource constraints:
   ```bash
   kubectl top pods -n argocd
   ```

## Backup and Disaster Recovery

### Backup ArgoCD Configuration

```bash
# Export all applications
argocd app list -o yaml > argocd-apps-backup.yaml

# Export all projects
kubectl get appprojects -n argocd -o yaml > argocd-projects-backup.yaml

# Export configuration
kubectl get cm argocd-cm -n argocd -o yaml > argocd-cm-backup.yaml
kubectl get cm argocd-rbac-cm -n argocd -o yaml > argocd-rbac-cm-backup.yaml
```

### Restore from Backup

```bash
kubectl apply -f argocd-projects-backup.yaml
kubectl apply -f argocd-apps-backup.yaml
kubectl apply -f argocd-cm-backup.yaml
kubectl apply -f argocd-rbac-cm-backup.yaml
```

## Upgrade ArgoCD

```bash
# Check current version
argocd version

# Upgrade to new version
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/install.yaml

# Verify upgrade
kubectl rollout status deployment/argocd-server -n argocd
```

## Security Best Practices

1. **Change default admin password immediately**
2. **Enable SSO for production environments**
3. **Use RBAC to enforce least privilege access**
4. **Store sensitive credentials in Vault, not in Git**
5. **Enable TLS for all external access**
6. **Regularly update ArgoCD to latest stable version**
7. **Enable audit logging**
8. **Use network policies to restrict ArgoCD access**
9. **Implement webhook signatures for GitHub integration**
10. **Regular backup of ArgoCD configuration**

## References

- [ArgoCD Official Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD GitHub Repository](https://github.com/argoproj/argo-cd)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [ArgoCD RBAC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
