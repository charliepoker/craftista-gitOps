# Vault Secrets Documentation

This directory contains secret templates for all environments in the Craftista application. These templates document the required secrets structure and serve as a guide for populating Vault with actual secret values.

## Directory Structure

```
vault/secrets/
├── dev/
│   └── secrets-template.yaml       # Development environment secrets
├── staging/
│   └── secrets-template.yaml       # Staging environment secrets
├── prod/
│   └── secrets-template.yaml       # Production environment secrets
└── README.md                        # This file
```

## Secret Path Structure

All secrets in Vault follow this hierarchical structure:

```
secret/
├── craftista/
│   ├── dev/
│   │   ├── frontend/
│   │   │   ├── api-keys
│   │   │   └── config
│   │   ├── catalogue/
│   │   │   ├── mongodb-credentials
│   │   │   ├── mongodb-uri
│   │   │   └── config
│   │   ├── voting/
│   │   │   ├── postgres-credentials
│   │   │   ├── postgres-uri
│   │   │   └── config
│   │   ├── recommendation/
│   │   │   ├── redis-credentials
│   │   │   ├── redis-uri
│   │   │   └── config
│   │   └── common/
│   │       ├── registry
│   │       ├── monitoring
│   │       └── tls
│   ├── staging/
│   │   └── [same structure as dev]
│   └── prod/
│       └── [same structure as dev]
│
├── github-actions/
│   ├── dockerhub-credentials
│   ├── sonarqube-token
│   ├── gitops-deploy-key
│   ├── slack-webhook-url
│   └── nexus-credentials
│
└── argocd/
    ├── admin-password
    └── github-webhook-secret
```

## Required Secrets by Service

### Frontend Service

- **session_secret**: Random string for session encryption (32+ bytes)
- **jwt_secret**: Random string for JWT signing (64+ bytes)
- **node_env**: Environment name (development/staging/production)
- **log_level**: Logging level (debug/info/warn/error)

### Catalogue Service

- **mongodb-credentials**: Username and password for MongoDB
- **mongodb-uri**: Full MongoDB connection string
- **flask_env**: Flask environment (development/staging/production)
- **log_level**: Logging level (DEBUG/INFO/WARNING/ERROR)
- **data_source**: Data source type (mongodb)

### Voting Service

- **postgres-credentials**: Username and password for PostgreSQL
- **postgres-uri**: JDBC URL and connection string for PostgreSQL
- **spring_profiles_active**: Spring profile (dev/staging/prod)
- **log_level**: Logging level (DEBUG/INFO/WARN/ERROR)

### Recommendation Service

- **redis-credentials**: Password for Redis
- **redis-uri**: Redis connection string with host and port
- **environment**: Environment name (development/staging/production)
- **log_level**: Logging level (debug/info/warn/error)

### Common Secrets

- **registry**: DockerHub credentials for pulling images
- **monitoring**: Slack webhook URL for notifications
- **tls**: TLS certificates and keys for HTTPS

### CI/CD Secrets (GitHub Actions)

- **dockerhub-credentials**: Username and password for pushing images
- **sonarqube-token**: Authentication token for SonarQube
- **gitops-deploy-key**: SSH key for pushing to gitops repository
- **slack-webhook-url**: Webhook URL for CI/CD notifications
- **nexus-credentials**: Username and password for Nexus repository

### ArgoCD Secrets

- **admin-password**: ArgoCD admin password
- **github-webhook-secret**: Secret for GitHub webhook validation

## Populating Secrets in Vault

### Prerequisites

1. Vault must be installed and unsealed
2. You must have a Vault token with write permissions
3. Vault policies must be created (see `vault/policies/`)

### Method 1: Using Vault CLI

```bash
# Set Vault address and token
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="your-vault-token"

# Write a secret
vault kv put secret/craftista/dev/frontend/api-keys \
  session_secret="$(openssl rand -base64 32)" \
  jwt_secret="$(openssl rand -base64 64)"

# Write database credentials
vault kv put secret/craftista/dev/catalogue/mongodb-credentials \
  username="catalogue_user" \
  password="secure-password-here" \
  database="catalogue"

# Write connection string
vault kv put secret/craftista/dev/catalogue/mongodb-uri \
  connection_string="mongodb://catalogue_user:secure-password-here@mongodb-dev:27017/catalogue"
```

### Method 2: Using sync-secrets.sh Script

```bash
# Navigate to scripts directory
cd scripts/

# Run the sync-secrets script
./sync-secrets.sh --environment dev --secrets-file ../vault/secrets/dev/secrets-template.yaml

# For production (requires additional confirmation)
./sync-secrets.sh --environment prod --secrets-file ../vault/secrets/prod/secrets-template.yaml
```

### Method 3: Using Vault UI

1. Navigate to Vault UI at `https://vault.example.com`
2. Log in with your token
3. Navigate to `secret/` mount
4. Create the path structure: `craftista/{env}/{service}/`
5. Add key-value pairs for each secret

## Generating Secure Secrets

### Random Strings

```bash
# Generate session secret (32 bytes)
openssl rand -base64 32

# Generate JWT secret (64 bytes)
openssl rand -base64 64

# Generate password (24 characters)
openssl rand -base64 24 | tr -d "=+/" | cut -c1-24
```

### SSH Keys (for GitOps deploy key)

```bash
# Generate SSH key pair
ssh-keygen -t ed25519 -C "github-actions@craftista" -f gitops-deploy-key

# Store private key in Vault
vault kv put secret/github-actions/gitops-deploy-key \
  private_key=@gitops-deploy-key

# Add public key to GitHub repository deploy keys
cat gitops-deploy-key.pub
```

### TLS Certificates

```bash
# For development (self-signed)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout dev-tls.key -out dev-tls.crt \
  -subj "/CN=*.dev.webdemoapp.com"

# For production (use Let's Encrypt or AWS Certificate Manager)
# Store in Vault
vault kv put secret/craftista/prod/common/tls \
  cert=@prod-tls.crt \
  key=@prod-tls.key
```

## Secret Rotation

### Rotation Schedule

- **Development**: No mandatory rotation
- **Staging**: Rotate every 90 days
- **Production**:
  - Database credentials: 90 days
  - API keys: 180 days
  - TLS certificates: 365 days
  - Session secrets: 30 days

### Rotation Process

1. Generate new secret value
2. Update secret in Vault
3. Restart affected pods to pick up new secret
4. Verify application functionality
5. Remove old secret value

### Automated Rotation

Consider using Vault's dynamic secrets for database credentials:

```bash
# Enable database secrets engine
vault secrets enable database

# Configure PostgreSQL connection
vault write database/config/voting-postgres \
  plugin_name=postgresql-database-plugin \
  allowed_roles="voting-role" \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/voting" \
  username="vault_admin" \
  password="vault_admin_password"

# Create role with TTL
vault write database/roles/voting-role \
  db_name=voting-postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

## Security Best Practices

### Access Control

- Use Vault policies to enforce least-privilege access
- Each service should only access its own secrets
- Production secrets should have stricter access controls
- Enable MFA for production Vault access

### Audit Logging

- Enable Vault audit logging for all environments
- Monitor secret access patterns
- Alert on unusual access patterns
- Retain audit logs for compliance

### Backup and Recovery

- Regularly backup Vault data
- Store root tokens securely offline
- Document recovery procedures
- Test recovery process regularly

### Secret Hygiene

- Never commit secrets to Git
- Use `.gitignore` to exclude secret files
- Rotate secrets regularly
- Use strong, unique passwords
- Enable encryption at rest and in transit

## Troubleshooting

### Secret Not Found

```bash
# List all secrets in a path
vault kv list secret/craftista/dev/frontend/

# Read a specific secret
vault kv get secret/craftista/dev/frontend/api-keys
```

### Permission Denied

```bash
# Check your token capabilities
vault token capabilities secret/craftista/dev/frontend/api-keys

# Check policy
vault policy read frontend-policy
```

### Pod Cannot Access Secret

1. Verify service account exists
2. Check Vault role binding
3. Verify Vault policy grants access
4. Check pod annotations for Vault agent
5. Review pod logs for Vault errors

## References

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Vault Agent Injector](https://www.vaultproject.io/docs/platform/k8s/injector)
- [External Secrets Operator](https://external-secrets.io/)
- [Vault Best Practices](https://learn.hashicorp.com/tutorials/vault/production-hardening)
