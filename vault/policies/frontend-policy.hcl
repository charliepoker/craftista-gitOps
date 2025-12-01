# Vault policy for Frontend service
# Grants access to frontend-specific secrets across all environments

# Allow read access to frontend secrets in dev environment
path "secret/data/craftista/dev/frontend/*" {
  capabilities = ["read", "list"]
}

# Allow read access to frontend secrets in staging environment
path "secret/data/craftista/staging/frontend/*" {
  capabilities = ["read", "list"]
}

# Allow read access to frontend secrets in production environment
path "secret/data/craftista/prod/frontend/*" {
  capabilities = ["read", "list"]
}

# Allow read access to common secrets in dev environment
path "secret/data/craftista/dev/common/*" {
  capabilities = ["read", "list"]
}

# Allow read access to common secrets in staging environment
path "secret/data/craftista/staging/common/*" {
  capabilities = ["read", "list"]
}

# Allow read access to common secrets in production environment
path "secret/data/craftista/prod/common/*" {
  capabilities = ["read", "list"]
}

# Allow listing secret metadata
path "secret/metadata/craftista/*/frontend/*" {
  capabilities = ["list"]
}

path "secret/metadata/craftista/*/common/*" {
  capabilities = ["list"]
}
