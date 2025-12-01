# Vault policy for GitHub Actions CI/CD
# Grants access to CI/CD secrets needed for automation

# Allow read access to DockerHub credentials
path "secret/data/github-actions/dockerhub-credentials" {
  capabilities = ["read"]
}

# Allow read access to SonarQube token
path "secret/data/github-actions/sonarqube-token" {
  capabilities = ["read"]
}

# Allow read access to GitOps repository deploy key
path "secret/data/github-actions/gitops-deploy-key" {
  capabilities = ["read"]
}

# Allow read access to Slack webhook URL for notifications
path "secret/data/github-actions/slack-webhook-url" {
  capabilities = ["read"]
}

# Allow read access to Nexus credentials
path "secret/data/github-actions/nexus-credentials" {
  capabilities = ["read"]
}

# Allow read access to all GitHub Actions secrets
path "secret/data/github-actions/*" {
  capabilities = ["read", "list"]
}

# Allow listing secret metadata
path "secret/metadata/github-actions/*" {
  capabilities = ["list"]
}

# Allow read access to ArgoCD credentials for deployment automation
path "secret/data/argocd/admin-password" {
  capabilities = ["read"]
}

path "secret/data/argocd/github-webhook-secret" {
  capabilities = ["read"]
}

# Allow listing ArgoCD secret metadata
path "secret/metadata/argocd/*" {
  capabilities = ["list"]
}
