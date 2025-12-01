# Vault Integration for Craftista GitOps

This directory contains all Vault-related configurations for the Craftista microservices application, including policies, authentication methods, and secret templates.

## Directory Structure

```
vault/
├── README.md                        # This file
├── policies/                        # Vault policy files
│   ├── frontend-policy.hcl         # Policy for frontend service
│   ├── catalogue-policy.hcl        # Policy for catalogue service
│   ├── voting-policy.hcl           # Policy for voting service
│   ├── recommendation-policy.hcl   # Policy for recommendation service
│   └── github-actions-policy.hcl   # Policy for CI/CD automation
├── auth/                            # Authentication configuration scripts
│   ├── kubernetes-auth.sh          # Configure Kubernetes auth method
│   └── github-oidc-auth.sh         # Configure GitHub OIDC auth method
└── secrets/                         # Secret templates by environment
    ├── README.md                    # Detailed secrets documentation
    ├── dev/
    │   └── secrets-template.yaml   # Development secrets template
    ├── staging/
    │   └── secrets-template.yaml   # Staging secrets template
    └── prod/
        └── secrets-template.yaml   # Production secrets template
```

## Overview

HashiCorp Vault is used as the centralized secrets management system for the Craftista application. It provides:

- **Secure Secret Storage**: All sensitive data (passwords, API keys, certificates) stored encrypted
- **Dynamic Secrets**: Database credentials can be generated on-demand with TTL
- **Access Control**: Fine-grained policies control which services can access which secrets
- **Audit Logging**: Complete audit trail of all secret access
- **Secret Rotation**: Automated rotation of credentials with zero downtime

## Quick Start

### 1. Deploy Vault to Kubernetes

```bash
# Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3

# Initialize and unseal Vault
kubectl exec -n vault vault-0 -- vault operator init
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-1>
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-2>
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-3>
```

### 2. Apply Vault Policies

```bash
# Set Vault address and token
export VAULT_ADDR="http://vault.vault.svc.cluster.local:8200"
export VAULT_TOKEN="<root-token>"

# Apply policies for each service
vault policy write frontend-policy vault/policies/frontend-policy.hcl
vault policy write catalogue-policy vault/policies/catalogue-policy.hcl
vault policy write voting-policy vault/policies/voting-policy.hcl
vault policy write recommendation-policy vault/policies/recommendation-policy.hcl
vault policy write github-actions-policy vault/policies/github-actions-policy.hcl
```

### 3. Configure Authentication Methods

```bash
# Configure Kubernetes authentication
cd vault/auth
./kubernetes-auth.sh

# Configure GitHub OIDC authentication
export GITHUB_ORG="charliepoker"
export GITHUB_REPO="craftista"
./github-oidc-auth.sh
```

### 4. Populate Secrets

```bash
# Use the sync-secrets.sh script (to be created in scripts/)
cd ../../scripts
./sync-secrets.sh --environment dev

# Or manually using Vault CLI
vault kv put secret/craftista/dev/frontend/api-keys \
  session_secret="$(openssl rand -base64 32)" \
  jwt_secret="$(openssl rand -base64 64)"
```

## Vault Policies

### Service Policies

Each microservice has its own Vault policy that grants access only to its specific secrets:

- **frontend-policy.hcl**: Access to `secret/craftista/*/frontend/*` and `secret/craftista/*/common/*`
- **catalogue-policy.hcl**: Access to `secret/craftista/*/catalogue/*` and `secret/craftista/*/common/*`
- **voting-policy.hcl**: Access to `secret/craftista/*/voting/*` and `secret/craftista/*/common/*`
- **recommendation-policy.hcl**: Access to `secret/craftista/*/recommendation/*` and `secret/craftista/*/common/*`

### CI/CD Policy

The **github-actions-policy.hcl** grants GitHub Actions workflows access to:

- DockerHub credentials
- SonarQube tokens
- GitOps repository deploy keys
- Slack webhook URLs
- Nexus credentials
- ArgoCD credentials

### Policy Enforcement

Policies enforce:

- **Environment Isolation**: Services can access secrets across all environments (dev/staging/prod)
- **Service Isolation**: Services cannot access other services' secrets
- **Least Privilege**: Only read and list capabilities, no write access
- **Common Secrets**: All services can access common secrets (registry, monitoring, TLS)

## Authentication Methods

### Kubernetes Authentication

Enables Kubernetes service accounts to authenticate with Vault:

```yaml
# Pod annotation example
metadata:
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "frontend"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/craftista/dev/frontend/api-keys"
```

**Configuration**: `vault/auth/kubernetes-auth.sh`

**Roles Created**:

- `frontend` - Bound to `frontend` service account
- `catalogue` - Bound to `catalogue` service account
- `voting` - Bound to `voting` service account
- `recommendation` - Bound to `recommendation` service account

### GitHub OIDC Authentication

Enables GitHub Actions workflows to authenticate with Vault using OIDC tokens:

```yaml
# GitHub Actions workflow example
- name: Import Secrets from Vault
  uses: hashicorp/vault-action@v2
  with:
    url: ${{ env.VAULT_ADDR }}
    method: jwt
    role: github-actions
    secrets: |
      secret/data/github-actions/dockerhub-credentials username | DOCKER_USERNAME ;
      secret/data/github-actions/dockerhub-credentials password | DOCKER_PASSWORD
```

**Configuration**: `vault/auth/github-oidc-auth.sh`

**Roles Created**:

- `github-actions` - General CI/CD access
- `github-actions-main` - Production deployments (main branch)
- `github-actions-develop` - Development deployments (develop branch)
- `github-actions-staging` - Staging deployments (staging branch)

## Secret Structure

### Application Secrets

```
secret/craftista/{environment}/{service}/
├── api-keys              # API keys, session secrets, JWT secrets
├── {database}-credentials # Database username and password
├── {database}-uri        # Database connection strings
└── config                # Service-specific configuration
```

### CI/CD Secrets

```
secret/github-actions/
├── dockerhub-credentials
├── sonarqube-token
├── gitops-deploy-key
├── slack-webhook-url
└── nexus-credentials
```

### ArgoCD Secrets

```
secret/argocd/
├── admin-password
└── github-webhook-secret
```

## Secret Injection Methods

### Method 1: Vault Agent Injector (Recommended)

Automatically injects secrets as files in pods:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "frontend"
        vault.hashicorp.com/agent-inject-secret-session: "secret/data/craftista/dev/frontend/api-keys"
        vault.hashicorp.com/agent-inject-template-session: |
          {{- with secret "secret/data/craftista/dev/frontend/api-keys" -}}
          export SESSION_SECRET="{{ .Data.data.session_secret }}"
          export JWT_SECRET="{{ .Data.data.jwt_secret }}"
          {{- end }}
```

### Method 2: External Secrets Operator

Syncs Vault secrets to Kubernetes Secrets:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: frontend-secrets
spec:
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: frontend-secrets
  data:
    - secretKey: session_secret
      remoteRef:
        key: secret/data/craftista/dev/frontend/api-keys
        property: session_secret
```

## Security Best Practices

### Access Control

- ✅ Use separate policies for each service
- ✅ Enforce least-privilege access
- ✅ Enable MFA for production access
- ✅ Regularly review and audit policies

### Secret Management

- ✅ Rotate secrets regularly (see rotation schedule in secrets/README.md)
- ✅ Use strong, unique passwords (minimum 24 characters for production)
- ✅ Never commit secrets to Git
- ✅ Use dynamic secrets for database credentials

### Audit and Monitoring

- ✅ Enable Vault audit logging
- ✅ Monitor secret access patterns
- ✅ Alert on unusual access
- ✅ Retain audit logs for compliance

### Backup and Recovery

- ✅ Regularly backup Vault data
- ✅ Store root tokens securely offline
- ✅ Document recovery procedures
- ✅ Test recovery process regularly

## Troubleshooting

### Common Issues

**Issue**: Pod cannot access secrets

```bash
# Check service account
kubectl get sa frontend -n craftista-dev

# Check Vault role
vault read auth/kubernetes/role/frontend

# Check pod logs
kubectl logs <pod-name> -c vault-agent-init
```

**Issue**: GitHub Actions cannot authenticate

```bash
# Verify OIDC configuration
vault read auth/jwt/config

# Check role binding
vault read auth/jwt/role/github-actions

# Verify GitHub Actions has id-token: write permission
```

**Issue**: Permission denied

```bash
# Check token capabilities
vault token capabilities secret/craftista/dev/frontend/api-keys

# Review policy
vault policy read frontend-policy
```

## Maintenance

### Regular Tasks

**Weekly**:

- Review audit logs for unusual access patterns
- Check Vault health and performance metrics

**Monthly**:

- Review and update policies as needed
- Verify backup and recovery procedures

**Quarterly**:

- Rotate non-production secrets
- Review access control lists
- Update documentation

**Annually**:

- Rotate production secrets
- Conduct security audit
- Review and update disaster recovery plan

## References

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Vault on Kubernetes](https://www.vaultproject.io/docs/platform/k8s)
- [Vault Agent Injector](https://www.vaultproject.io/docs/platform/k8s/injector)
- [External Secrets Operator](https://external-secrets.io/)
- [GitHub OIDC with Vault](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-hashicorp-vault)
- [Vault Best Practices](https://learn.hashicorp.com/tutorials/vault/production-hardening)

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review Vault audit logs
3. Consult the detailed secrets documentation in `secrets/README.md`
4. Contact the DevOps team
