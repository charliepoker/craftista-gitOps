# GitHub Actions CI/CD Secrets

This directory contains documentation and templates for secrets required by GitHub Actions CI/CD workflows. These secrets are stored in Vault and accessed by GitHub Actions workflows during the CI/CD process.

## Secret Paths

All GitHub Actions secrets are stored in Vault under the following path structure:

```
secret/data/github-actions/
├── dockerhub-credentials      # DockerHub registry credentials
├── sonarqube-token           # SonarQube authentication token
├── gitops-deploy-key         # SSH key for pushing to craftista-gitops repo
├── slack-webhook-url         # Slack webhook for CI/CD notifications
└── nexus-credentials         # Nexus repository credentials
```

## Required Secrets

### 1. DockerHub Credentials

**Path**: `secret/data/github-actions/dockerhub-credentials`

Used for pushing Docker images to DockerHub registry.

**Required Keys**:

- `username`: DockerHub username
- `password`: DockerHub password or access token

**Usage**: Referenced in GitHub Actions workflows for docker login and push operations.

### 2. SonarQube Token

**Path**: `secret/data/github-actions/sonarqube-token`

Authentication token for SonarQube code quality and security analysis.

**Required Keys**:

- `token`: SonarQube authentication token
- `url`: SonarQube server URL

**Usage**: Used in SAST (Static Application Security Testing) workflows.

### 3. GitOps Deploy Key

**Path**: `secret/data/github-actions/gitops-deploy-key`

SSH private key for pushing image tag updates to the craftista-gitops repository.

**Required Keys**:

- `private_key`: SSH private key (ED25519 or RSA)
- `public_key`: SSH public key (for reference)

**Usage**: Allows GitHub Actions to update Kubernetes manifests with new image tags.

### 4. Slack Webhook URL

**Path**: `secret/data/github-actions/slack-webhook-url`

Webhook URL for sending CI/CD notifications to Slack.

**Required Keys**:

- `webhook_url`: Slack incoming webhook URL
- `channel`: Target Slack channel (optional)

**Usage**: Sends build status, deployment notifications, and alerts to Slack.

### 5. Nexus Credentials (Optional)

**Path**: `secret/data/github-actions/nexus-credentials`

Credentials for Nexus Repository Manager (if used for artifact storage).

**Required Keys**:

- `username`: Nexus username
- `password`: Nexus password
- `url`: Nexus server URL

**Usage**: Upload and download build artifacts, dependency caching.

## Vault Policy

The GitHub Actions workflows authenticate with Vault using GitHub OIDC and are granted access through the `github-actions-policy`. This policy provides read-only access to the secrets listed above.

See: `vault/policies/github-actions-policy.hcl`

## Secret Generation

### DockerHub Credentials

1. Log in to DockerHub
2. Go to Account Settings > Security
3. Create a new Access Token with appropriate permissions
4. Use your username and the access token as the password

### SonarQube Token

1. Log in to SonarQube
2. Go to My Account > Security
3. Generate a new token with appropriate permissions
4. Copy the token value

### GitOps Deploy Key

```bash
# Generate SSH key pair
ssh-keygen -t ed25519 -C "github-actions@craftista" -f gitops-deploy-key -N ""

# The private key will be stored in Vault
# The public key needs to be added to the craftista-gitops repository as a deploy key
```

### Slack Webhook URL

1. Go to your Slack workspace
2. Navigate to Apps > Incoming Webhooks
3. Create a new webhook for your desired channel
4. Copy the webhook URL

## Populating Secrets

Use the provided script to populate these secrets in Vault:

```bash
# Navigate to scripts directory
cd scripts/

# Run the GitHub Actions secrets setup script
./setup-github-actions-secrets.sh

# Or use the general sync script
./sync-secrets.sh --type github-actions
```

## Security Considerations

1. **Least Privilege**: Each secret should only grant the minimum permissions required
2. **Rotation**: Rotate secrets regularly (recommended: every 90 days)
3. **Monitoring**: Monitor secret access through Vault audit logs
4. **Backup**: Ensure secrets are included in Vault backup procedures

## Troubleshooting

### GitHub Actions Cannot Access Vault

1. Verify GitHub OIDC authentication is configured
2. Check that the repository is allowed in the Vault role
3. Verify the github-actions-policy grants required permissions

### Docker Push Fails

1. Verify DockerHub credentials are correct
2. Check that the repository exists and you have push permissions
3. Ensure the access token has appropriate scopes

### GitOps Update Fails

1. Verify the SSH key is added to the craftista-gitops repository
2. Check that the deploy key has write permissions
3. Ensure the private key format is correct in Vault

### SonarQube Scan Fails

1. Verify the SonarQube token is valid and not expired
2. Check that the token has appropriate permissions for the project
3. Verify the SonarQube server URL is accessible

## References

- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Vault GitHub OIDC Auth](https://www.vaultproject.io/docs/auth/jwt/oidc_providers#github-actions)
- [DockerHub Access Tokens](https://docs.docker.com/docker-hub/access-tokens/)
- [SonarQube Authentication](https://docs.sonarqube.org/latest/user-guide/user-token/)
