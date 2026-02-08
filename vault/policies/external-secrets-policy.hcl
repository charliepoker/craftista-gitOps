# Vault policy for External Secrets Operator
# Grants access to retrieve secrets for external-secrets controller across all environments


# This path grants access to the actual secret data in the dev environment
path "secret/data/craftista/dev/*" {
    capabilities = ["read", "list"]
}


# This path grants access to secret metadata across all craftista environments
# Note: This uses metadata path which only provides secret metadata, not the actual secret values
path "secret/metadata/craftista/*" {
    capabilities = ["read", "list"]
}

