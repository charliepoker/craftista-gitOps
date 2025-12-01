# Vault policy for Recommendation service
# Grants access to recommendation-specific secrets across all environments

# Allow read access to recommendation secrets in dev environment
path "secret/data/craftista/dev/recommendation/*" {
  capabilities = ["read", "list"]
}

# Allow read access to recommendation secrets in staging environment
path "secret/data/craftista/staging/recommendation/*" {
  capabilities = ["read", "list"]
}

# Allow read access to recommendation secrets in production environment
path "secret/data/craftista/prod/recommendation/*" {
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
path "secret/metadata/craftista/*/recommendation/*" {
  capabilities = ["list"]
}

path "secret/metadata/craftista/*/common/*" {
  capabilities = ["list"]
}
