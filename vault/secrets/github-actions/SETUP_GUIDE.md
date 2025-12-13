# GitHub Actions Secrets Setup Guide

This guide walks you through setting up all required secrets for GitHub Actions CI/CD workflows in HashiCorp Vault.

## Overview

The GitHub Actions CI/CD pipeline requires several secrets to function properly:

1. **DockerHub Credentials** - For pushing container images
2. **SonarQube Token** - For code quality and security analysis
3. **GitOps Deploy Key** - For updating Kubernetes manifests
4. **Slack Webhook** - For CI/CD notifications
5. **Nexus Credentials** - For artifact storage (optional)

## Prerequisites

Before starting, ensure you have:

- [ ] HashiCorp Vault server running and accessible
- [ ] Vault CLI installed locally
- [ ] Valid Vault token with write permissions to `secret/data/github-actions/*`
- [ ] GitHub Actions policy applied in Vault (see `vault/policies/github-actions-policy.hcl`)
- [ ] Access to create tokens/credentials in external services

## Step-by-Step Setup

### Step 1: Prepare External Services

#### DockerHub Access Token

1. Log in to [DockerHub](https://hub.docker.com)
2. Go to Account Settings → Security
3. Click "New Access Token"
4. Name: `craftista-github-actions`
5. Permissions: Read, Write, Delete
6. Copy the generated token

#### SonarQube Token

1. Log in to your SonarQube instance
2. Go to My Account → Security
3. Generate new token: `craftista-github-actions`
4. Copy the token value

#### Slack Webhook

1. Go to your Slack workspace
2. Navigate to Apps → Incoming Webhooks
3. Create webhook for `#ci-cd` channel
4. Copy the webhook URL

#### SSH Key for GitOps

```bash
# Generate SSH key pair
ssh-keygen -t ed25519 -C "github-actions@craftista" -f gitops-deploy-key -N ""

# Add public key to craftista-gitops repository
# Go to GitHub → craftista-gitops → Settings → Deploy keys
# Add the content of gitops-deploy-key.pub with write access
```

### Step 2: Set Environment Variables

```bash
# Required secrets
export DOCKERHUB_USERNAME="your-dockerhub-username"
export DOCKERHUB_ACCESS_TOKEN="dckr_pat_your-token-here"
export SONARQUBE_TOKEN="squ_your-token-here"
export SONARQUBE_URL="https://your-sonarqube-server.com"
export GITOPS_PRIVATE_KEY_FILE="./gitops-deploy-key"
export GITOPS_PUBLIC_KEY_FILE="./gitops-deploy-key.pub"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
export SLACK_CHANNEL="#ci-cd"

# Optional Nexus credentials
export NEXUS_USERNAME="nexus-user"
export NEXUS_PASSWORD="nexus-password"
export NEXUS_URL="https://your-nexus-server.com"

# Vault connection
export VAULT_ADDR="https://your-vault-server.com"
export VAULT_TOKEN="your-vault-token"
```

### Step 3: Run Setup Script

Choose one of the following methods:

#### Method A: Dedicated GitHub Actions Script

```bash
cd scripts/
./setup-github-actions-secrets.sh --from-env
```

#### Method B: General Sync Script

```bash
cd scripts/
./sync-secrets.sh --type github-actions --from-env
```

#### Method C: Interactive Mode

```bash
cd scripts/
./setup-github-actions-secrets.sh --interactive
```

### Step 4: Verify Setup

```bash
# List all GitHub Actions secrets
vault kv list secret/github-actions/

# Check individual secrets (values will be hidden)
vault kv get secret/github-actions/dockerhub-credentials
vault kv get secret/github-actions/sonarqube-token
vault kv get secret/github-actions/gitops-deploy-key
vault kv get secret/github-actions/slack-webhook-url
```

Expected output:

```
====== Secret Path ======
secret/data/github-actions/dockerhub-credentials

======= Metadata =======
Key                Value
---                -----
created_time       2024-01-15T10:30:00Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

====== Data ======
Key         Value
---         -----
password    ***
registry    docker.io
username    your-username
```

### Step 5: Test GitHub Actions Integration

1. **Trigger a CI pipeline** by pushing code to any service directory
2. **Check workflow logs** for successful Vault authentication
3. **Verify image push** to DockerHub
4. **Confirm GitOps update** in craftista-gitops repository
5. **Check Slack notifications** in your configured channel

## Troubleshooting

### Common Issues

#### "Permission Denied" Error

```bash
# Check your Vault token capabilities
vault token capabilities secret/data/github-actions/dockerhub-credentials

# Verify policy is applied
vault policy read github-actions-policy
```

#### "Cannot Connect to Vault"

```bash
# Test Vault connectivity
vault status

# Check VAULT_ADDR
echo $VAULT_ADDR
```

#### "SSH Key Authentication Failed"

1. Verify public key is added to GitHub repository
2. Ensure deploy key has write permissions
3. Check private key format in Vault

#### "Docker Push Failed"

1. Verify DockerHub credentials are correct
2. Check repository exists and you have push permissions
3. Ensure access token has appropriate scopes

### Validation Commands

```bash
# Test DockerHub login
echo "$DOCKERHUB_ACCESS_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin

# Test SonarQube connection
curl -u "$SONARQUBE_TOKEN:" "$SONARQUBE_URL/api/authentication/validate"

# Test Slack webhook
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test from setup script"}' \
  "$SLACK_WEBHOOK_URL"

# Test SSH key
ssh-keygen -l -f gitops-deploy-key
```

## Security Best Practices

### Secret Rotation Schedule

- **DockerHub tokens**: Every 90 days
- **SonarQube tokens**: Every 90 days
- **SSH keys**: Every 180 days
- **Slack webhooks**: As needed

### Monitoring

- Enable Vault audit logging
- Monitor secret access patterns
- Set up alerts for unusual access
- Regular security reviews

### Access Control

- Use least-privilege policies
- Rotate Vault tokens regularly
- Enable MFA for Vault access
- Regular access reviews

## Advanced Configuration

### Using Dynamic Secrets

Consider using Vault's dynamic secrets for database credentials:

```bash
# Enable database secrets engine
vault secrets enable database

# Configure dynamic secrets for PostgreSQL
vault write database/config/voting-postgres \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/voting" \
  allowed_roles="voting-role" \
  username="vault_admin" \
  password="vault_admin_password"
```

### Multiple Environments

For multiple Vault environments:

```bash
# Development Vault
export VAULT_ADDR="https://vault-dev.example.com"
./setup-github-actions-secrets.sh --from-env

# Production Vault
export VAULT_ADDR="https://vault-prod.example.com"
./setup-github-actions-secrets.sh --from-env
```

### Backup and Recovery

```bash
# Backup secrets
vault kv get -format=json secret/github-actions/dockerhub-credentials > backup-dockerhub.json

# Restore secrets
vault kv put secret/github-actions/dockerhub-credentials @backup-dockerhub.json
```

## Next Steps

After completing this setup:

1. **Test the CI/CD pipeline** by making a code change
2. **Monitor the first few deployments** for any issues
3. **Set up monitoring and alerting** for the pipeline
4. **Document any environment-specific configurations**
5. **Train team members** on the new workflow

## Support

For issues or questions:

- Check the troubleshooting section above
- Review Vault audit logs
- Consult the main documentation in `vault/secrets/README.md`
- Check GitHub Actions workflow logs for specific errors

## References

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [DockerHub Access Tokens](https://docs.docker.com/docker-hub/access-tokens/)
- [SonarQube Authentication](https://docs.sonarqube.org/latest/user-guide/user-token/)
