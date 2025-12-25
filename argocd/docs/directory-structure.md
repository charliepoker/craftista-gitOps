# Directory Structure Documentation

This document explains the organization and purpose of each directory and file in the craftista-gitops repository. Understanding this structure is essential for maintaining and extending the GitOps configuration.

## Table of Contents

- [Repository Overview](#repository-overview)
- [Top-Level Directories](#top-level-directories)
- [Kubernetes Manifests Organization](#kubernetes-manifests-organization)
- [Helm Chart Structure](#helm-chart-structure)
- [ArgoCD Application Organization](#argocd-application-organization)
- [Vault Configuration](#vault-configuration)
- [Scripts and Automation](#scripts-and-automation)
- [Documentation Structure](#documentation-structure)
- [File Naming Conventions](#file-naming-conventions)

## Repository Overview

```
craftista-gitops/
├── README.md                    # Main repository documentation
├── docs/                        # Detailed documentation
├── argocd/                      # ArgoCD configurations
├── kubernetes/                  # Kubernetes manifests with Kustomize
├── helm/                        # Helm charts for all services
├── vault/                       # Vault policies and configurations
├── external-secrets/            # External Secrets Operator configs
├── scripts/                     # Operational and deployment scripts
└── tests/                       # Property-based tests (future)
```

## Top-Level Directories

### `/docs/` - Documentation

Contains comprehensive documentation for the GitOps implementation:

```
docs/
├── architecture.md              # System architecture and design
├── deployment-guide.md          # Step-by-step deployment instructions
├── directory-structure.md       # This document
├── onboarding.md               # New team member guide
├── runbooks/                   # Operational procedures
│   ├── rollback-procedure.md   # Rollback instructions
│   ├── troubleshooting.md      # Common issues and solutions
│   ├── secrets-rotation.md     # Secret rotation procedures
│   └── disaster-recovery.md    # Backup and restore procedures
└── diagrams/                   # Architecture diagrams (future)
    ├── ci-pipeline.png         # CI/CD pipeline flow
    └── gitops-flow.png         # GitOps sync process
```

**Purpose**: Centralized documentation for all operational and architectural knowledge.

### `/argocd/` - ArgoCD Configurations

Contains all ArgoCD-related configurations for GitOps deployment:

```
argocd/
├── install/                    # ArgoCD installation manifests
│   ├── namespace.yaml          # ArgoCD namespace definition
│   ├── argocd-install.yaml     # Core ArgoCD installation
│   ├── argocd-cm.yaml          # ArgoCD configuration map
│   └── argocd-rbac-cm.yaml     # RBAC configuration
├── projects/                   # ArgoCD project definitions
│   ├── craftista-dev.yaml      # Development project
│   ├── craftista-staging.yaml  # Staging project
│   └── craftista-prod.yaml     # Production project
└── applications/               # ArgoCD application definitions
    ├── dev/                    # Development applications
    │   ├── frontend-app.yaml
    │   ├── catalogue-app.yaml
    │   ├── voting-app.yaml
    │   └── recommendation-app.yaml
    ├── staging/                # Staging applications
    │   └── [same structure as dev]
    └── prod/                   # Production applications
        └── [same structure as dev]
```

**Purpose**: Defines how ArgoCD manages and deploys applications across environments.

### `/kubernetes/` - Kubernetes Manifests

Organized using Kustomize for environment-specific configurations:

```
kubernetes/
├── base/                       # Base Kubernetes manifests
│   ├── frontend/
│   │   ├── kustomization.yaml  # Kustomize configuration
│   │   ├── deployment.yaml     # Base deployment spec
│   │   ├── service.yaml        # Service definition
│   │   ├── configmap.yaml      # Configuration data
│   │   └── ingress.yaml        # Ingress rules
│   ├── catalogue/
│   │   └── [same structure]
│   ├── voting/
│   │   ├── [same structure]
│   │   └── migration-job.yaml  # Database migration job
│   └── recommendation/
│       └── [same structure]
├── overlays/                   # Environment-specific overlays
│   ├── dev/
│   │   ├── namespace.yaml      # Development namespace
│   │   ├── frontend/
│   │   │   ├── kustomization.yaml
│   │   │   ├── deployment-patch.yaml
│   │   │   ├── configmap-patch.yaml
│   │   │   └── resources-patch.yaml
│   │   ├── catalogue/
│   │   │   └── [same structure]
│   │   ├── voting/
│   │   │   └── [same structure]
│   │   └── recommendation/
│   │       └── [same structure]
│   ├── staging/
│   │   └── [same structure as dev]
│   └── prod/
│       └── [same structure as dev with production-specific patches]
└── common/                     # Shared configurations
    ├── network-policies/       # Network security policies
    │   ├── default-deny.yaml
    │   ├── frontend-policy.yaml
    │   ├── catalogue-policy.yaml
    │   ├── voting-policy.yaml
    │   └── recommendation-policy.yaml
    └── rbac/                   # Role-based access control
        ├── service-accounts.yaml
        ├── roles.yaml
        └── role-bindings.yaml
```

**Purpose**: Provides environment-specific Kubernetes configurations using Kustomize overlays.

### `/helm/` - Helm Charts

Templated Kubernetes deployments with environment-specific values:

```
helm/
├── charts/                     # Individual service charts
│   ├── frontend/
│   │   ├── Chart.yaml          # Chart metadata
│   │   ├── values.yaml         # Default values
│   │   ├── values-dev.yaml     # Development overrides
│   │   ├── values-staging.yaml # Staging overrides
│   │   ├── values-prod.yaml    # Production overrides
│   │   └── templates/          # Kubernetes templates
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── configmap.yaml
│   │       ├── secret.yaml
│   │       ├── ingress.yaml
│   │       ├── hpa.yaml        # Horizontal Pod Autoscaler
│   │       └── _helpers.tpl    # Template helpers
│   ├── catalogue/
│   │   └── [same structure]
│   ├── voting/
│   │   ├── [same structure]
│   │   └── templates/
│   │       ├── [common templates]
│   │       └── migration-job.yaml
│   └── recommendation/
│       └── [same structure]
└── umbrella/                   # Umbrella chart (future)
    └── craftista/
        ├── Chart.yaml
        ├── values-dev.yaml
        ├── values-staging.yaml
        ├── values-prod.yaml
        └── Chart.lock
```

**Purpose**: Provides templated, versioned application packages with environment-specific configurations.

### `/vault/` - Vault Configuration

HashiCorp Vault policies, authentication, and secret templates:

```
vault/
├── policies/                   # Vault access policies
│   ├── frontend-policy.hcl     # Frontend service policy
│   ├── catalogue-policy.hcl    # Catalogue service policy
│   ├── voting-policy.hcl       # Voting service policy
│   ├── recommendation-policy.hcl # Recommendation service policy
│   └── github-actions-policy.hcl # CI/CD pipeline policy
├── auth/                       # Authentication configuration
│   ├── kubernetes-auth.sh      # Kubernetes auth method setup
│   └── github-oidc-auth.sh     # GitHub OIDC auth setup
└── secrets/                    # Secret templates and examples
    ├── dev/
    │   └── secrets-template.yaml
    ├── staging/
    │   └── secrets-template.yaml
    ├── prod/
    │   └── secrets-template.yaml
    └── github-actions/
        ├── README.md
        ├── SETUP_GUIDE.md
        ├── example-setup.sh
        └── secrets-template.yaml
```

**Purpose**: Manages secrets access policies and provides templates for secret population.

### `/external-secrets/` - External Secrets Operator

Configuration for syncing secrets from Vault to Kubernetes:

```
external-secrets/
├── secret-store.yaml           # Namespace-scoped SecretStore
├── cluster-secret-store.yaml   # Cluster-wide SecretStore
└── external-secrets/           # ExternalSecret definitions
    ├── frontend-secrets.yaml   # Frontend service secrets
    ├── catalogue-secrets.yaml  # Catalogue service secrets
    ├── voting-secrets.yaml     # Voting service secrets
    └── recommendation-secrets.yaml # Recommendation service secrets
```

**Purpose**: Defines how secrets are synchronized from Vault to Kubernetes Secrets.

### `/scripts/` - Operational Scripts

Automation scripts for deployment and operations:

```
scripts/
├── setup-argocd.sh            # ArgoCD installation script
├── setup-vault.sh             # Vault installation and configuration
├── sync-secrets.sh            # Populate Vault with secrets
├── promote-to-staging.sh      # Promote images to staging
├── promote-to-prod.sh         # Promote images to production
└── rollback.sh                # Rollback deployments
```

**Purpose**: Provides automation for common operational tasks.

## Kubernetes Manifests Organization

### Base Manifests Structure

Each service has a consistent base structure:

```
kubernetes/base/{service}/
├── kustomization.yaml          # Defines resources and configurations
├── deployment.yaml             # Pod template and container spec
├── service.yaml               # Service discovery and load balancing
├── configmap.yaml             # Non-sensitive configuration data
├── ingress.yaml               # External access routing
└── [migration-job.yaml]       # Database migrations (voting service only)
```

### Overlay Structure

Environment overlays follow a consistent pattern:

```
kubernetes/overlays/{environment}/{service}/
├── kustomization.yaml          # References base and applies patches
├── deployment-patch.yaml       # Environment-specific deployment changes
├── configmap-patch.yaml        # Environment-specific configuration
├── resources-patch.yaml        # CPU/memory limits per environment
└── [ingress-patch.yaml]        # Environment-specific ingress (prod only)
```

### Kustomization File Structure

Each `kustomization.yaml` follows this pattern:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# For base configurations
resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml
  - ingress.yaml

# For overlays
bases:
  - ../../../base/frontend

patches:
  - path: deployment-patch.yaml
  - path: resources-patch.yaml

replicas:
  - name: frontend
    count: 1

images:
  - name: charliepoker/craftista-frontend
    newTag: latest
```

## Helm Chart Structure

### Chart Metadata

Each Helm chart includes standardized metadata:

```yaml
# Chart.yaml
apiVersion: v2
name: frontend
description: Craftista Frontend Service Helm Chart
type: application
version: 1.0.0
appVersion: "1.0.0"
keywords:
  - craftista
  - frontend
  - nodejs
maintainers:
  - name: Craftista Team
    email: team@craftista.com
```

### Values File Hierarchy

Values files are organized by specificity:

1. **values.yaml**: Default values for all environments
2. **values-dev.yaml**: Development-specific overrides
3. **values-staging.yaml**: Staging-specific overrides
4. **values-prod.yaml**: Production-specific overrides

### Template Organization

Templates follow Kubernetes resource types:

```
templates/
├── deployment.yaml             # Main application deployment
├── service.yaml               # Service for pod discovery
├── configmap.yaml             # Configuration data
├── secret.yaml                # Secret references (Vault integration)
├── ingress.yaml               # External access
├── hpa.yaml                   # Horizontal Pod Autoscaler
├── serviceaccount.yaml        # Service account for RBAC
└── _helpers.tpl               # Reusable template functions
```

## ArgoCD Application Organization

### Project Structure

ArgoCD projects provide environment isolation:

```yaml
# Example project structure
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: craftista-dev
spec:
  description: Craftista Development Environment
  sourceRepos:
    - https://github.com/charliepoker/craftista-gitops.git
  destinations:
    - namespace: craftista-dev
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
```

### Application Naming Convention

Applications follow the pattern: `craftista-{service}-{environment}`

Examples:

- `craftista-frontend-dev`
- `craftista-catalogue-staging`
- `craftista-voting-prod`

### Application Configuration

Each application specifies:

```yaml
spec:
  project: craftista-{environment}
  source:
    repoURL: https://github.com/charliepoker/craftista-gitops.git
    targetRevision: main
    path: kubernetes/overlays/{environment}/{service}
  destination:
    server: https://kubernetes.default.svc
    namespace: craftista-{environment}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true # false for production
```

## Vault Configuration

### Policy Structure

Vault policies follow the principle of least privilege:

```hcl
# Example policy structure
path "secret/data/craftista/{environment}/{service}/*" {
  capabilities = ["read", "list"]
}

path "secret/data/craftista/{environment}/common/*" {
  capabilities = ["read", "list"]
}
```

### Secret Path Hierarchy

Secrets are organized hierarchically:

```
secret/
├── craftista/
│   ├── {environment}/          # dev, staging, prod
│   │   ├── {service}/          # frontend, catalogue, voting, recommendation
│   │   │   ├── database-credentials
│   │   │   ├── api-keys
│   │   │   └── session-secrets
│   │   └── common/             # Shared secrets
│   │       ├── registry-credentials
│   │       └── monitoring-tokens
├── github-actions/             # CI/CD secrets
│   ├── dockerhub-credentials
│   ├── sonarqube-token
│   └── gitops-deploy-key
└── argocd/                     # ArgoCD secrets
    ├── admin-password
    └── webhook-secrets
```

## Scripts and Automation

### Script Categories

Scripts are organized by function:

1. **Setup Scripts**: Initial installation and configuration
2. **Operational Scripts**: Day-to-day operations
3. **Promotion Scripts**: Environment promotion workflows
4. **Maintenance Scripts**: Backup, restore, and cleanup

### Script Naming Convention

- `setup-*.sh`: Installation and initial configuration
- `sync-*.sh`: Data synchronization operations
- `promote-*.sh`: Environment promotion
- `rollback.sh`: Rollback operations

### Script Structure

All scripts follow this structure:

```bash
#!/bin/bash
set -euo pipefail

# Script description and usage
# Usage: ./script-name.sh [arguments]

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Functions
function usage() {
    echo "Usage: $0 [options]"
    exit 1
}

function main() {
    # Main script logic
}

# Execute main function
main "$@"
```

## Documentation Structure

### Documentation Categories

1. **Architecture**: System design and component interactions
2. **Deployment**: Step-by-step operational procedures
3. **Reference**: Directory structure and configuration details
4. **Runbooks**: Troubleshooting and maintenance procedures
5. **Onboarding**: New team member guidance

### Documentation Standards

- Use Markdown format for all documentation
- Include table of contents for documents > 100 lines
- Use code blocks with language specification
- Include diagrams using Mermaid syntax where helpful
- Cross-reference related documents

## File Naming Conventions

### General Conventions

- Use lowercase with hyphens for directories: `external-secrets/`
- Use lowercase with hyphens for files: `deployment-guide.md`
- Use descriptive names that indicate purpose
- Include environment in filename when applicable: `values-prod.yaml`

### Kubernetes Resources

- Use singular resource type: `deployment.yaml`, not `deployments.yaml`
- Include service name for patches: `frontend-deployment-patch.yaml`
- Use descriptive suffixes: `-patch.yaml`, `-template.yaml`

### Configuration Files

- Use `.yaml` extension for YAML files
- Use `.hcl` extension for Vault policies
- Use `.sh` extension for shell scripts
- Use `.md` extension for documentation

### Version Control

- Commit messages should reference the component changed
- Use conventional commit format: `feat(frontend): add health check endpoint`
- Tag releases with semantic versioning: `v1.2.3`

## Best Practices

### Directory Organization

1. **Consistency**: Maintain consistent structure across all services
2. **Separation**: Keep environment-specific configurations separate
3. **Reusability**: Use base configurations with overlays/values
4. **Documentation**: Document the purpose of each directory and file

### File Management

1. **Atomic Changes**: Make focused changes to single components
2. **Validation**: Validate YAML syntax before committing
3. **Testing**: Test changes in development environment first
4. **Backup**: Maintain backups of critical configurations

### Security Considerations

1. **No Secrets**: Never commit secrets to Git repositories
2. **Least Privilege**: Apply minimal required permissions
3. **Encryption**: Use encrypted storage for sensitive data
4. **Audit**: Maintain audit logs for all changes

This directory structure provides a scalable, maintainable foundation for GitOps operations while ensuring clear separation of concerns and environment isolation.
