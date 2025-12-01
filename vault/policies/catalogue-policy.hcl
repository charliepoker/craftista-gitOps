# Vault policy for Catalogue service
# Grants access to catalogue-specific secrets across all environments

# Allow read access to catalogue secrets in dev environment
path "secret/data/craftista/dev/catalogue/*" {
  capabilities = ["read", "list"]
}

# Allow read access to catalogue secrets in staging environment
path "secret/data/craftista/staging/catalogue/*" {
  capabilities = ["read", "list"]
}

# Allow read access to catalogue secrets in production environment
path "secret/data/craftista/prod/catalogue/*" {
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
path "secret/metadata/craftista/*/catalogue/*" {
  capabilities = ["list"]
}

path "secret/metadata/craftista/*/common/*" {
  capabilities = ["list"]
}
