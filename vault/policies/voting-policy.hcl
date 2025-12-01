# Vault policy for Voting service
# Grants access to voting-specific secrets across all environments

# Allow read access to voting secrets in dev environment
path "secret/data/craftista/dev/voting/*" {
  capabilities = ["read", "list"]
}

# Allow read access to voting secrets in staging environment
path "secret/data/craftista/staging/voting/*" {
  capabilities = ["read", "list"]
}

# Allow read access to voting secrets in production environment
path "secret/data/craftista/prod/voting/*" {
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
path "secret/metadata/craftista/*/voting/*" {
  capabilities = ["list"]
}

path "secret/metadata/craftista/*/common/*" {
  capabilities = ["list"]
}
