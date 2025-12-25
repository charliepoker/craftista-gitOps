# Onboarding Guide

Welcome to the Craftista GitOps team! This guide will help you get up to speed with our GitOps implementation, development workflows, and operational procedures. Follow this guide to set up your local development environment and gain access to all necessary tools and systems.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Local Development Setup](#local-development-setup)
- [Tool Access and Configuration](#tool-access-and-configuration)
- [Repository Structure](#repository-structure)
- [Development Workflow](#development-workflow)
- [Testing Procedures](#testing-procedures)
- [Deployment Process](#deployment-process)
- [Monitoring and Observability](#monitoring-and-observability)
- [Troubleshooting Resources](#troubleshooting-resources)
- [Team Practices](#team-practices)
- [Getting Help](#getting-help)

## Overview

The Craftista application uses a GitOps methodology with a three-repository architecture:

1. **[craftista](https://github.com/charliepoker/craftista.git)**: Application source code and CI workflows
2. **[craftista-iac](https://github.com/charliepoker/Craftista-IaC.git)**: Infrastructure as Code (Terraform)
3. **[craftista-gitops](https://github.com/charliepoker/craftista-gitops.git)**: Kubernetes manifests and deployment configurations

### Key Technologies

- **Kubernetes**: Container orchestration platform
- **ArgoCD**: GitOps continuous delivery
- **HashiCorp Vault**: Secrets management
- **GitHub Actions**: CI/CD automation
- **Helm**: Kubernetes package manager
- **Kustomize**: Kubernetes configuration management
- **Terraform**: Infrastructure as Code
- **AWS EKS**: Managed Kubernetes service

## Prerequisites

### Required Knowledge

Before starting, you should have basic familiarity with:

- **Git**: Version control and branching strategies
- **Kubernetes**: Pods, services, deployments, namespaces
- **Docker**: Container concepts and image building
- **YAML**: Configuration file format
- **Command Line**: Basic shell/terminal usage
- **AWS**: Basic cloud concepts

### Recommended Learning Resources

If you need to brush up on any technologies:

- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [GitOps Principles](https://www.gitops.tech/)
- [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Helm Quickstart](https://helm.sh/docs/intro/quickstart/)
- [Terraform Tutorial](https://learn.hashicorp.com/terraform)

## Local Development Setup

### 1. Install Required Tools

#### macOS (using Homebrew)

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install development tools
brew install git
brew install kubectl
brew install helm
brew install argocd
brew install vault
brew install terraform
brew install docker
brew install awscli
brew install jq
brew install yq

# Install Docker Desktop
brew install --cask docker

# Install VS Code (recommended)
brew install --cask visual-studio-code
```

#### Linux (Ubuntu/Debian)

```bash
# Update package list
sudo apt update

# Install basic tools
sudo apt install -y git curl wget unzip

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd

# Install Vault CLI
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install vault

# Install Terraform
sudo apt-get install terraform

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install Docker
sudo apt-get install docker.io
sudo usermod -aG docker $USER

# Install jq and yq
sudo apt install jq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

#### Windows (using Chocolatey)

```powershell
# Install Chocolatey if not already installed
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install development tools
choco install git
choco install kubernetes-cli
choco install kubernetes-helm
choco install argocd-cli
choco install vault
choco install terraform
choco install docker-desktop
choco install awscli
choco install jq
choco install yq

# Install VS Code
choco install vscode
```

### 2. Verify Tool Installation

```bash
# Verify all tools are installed correctly
git --version
kubectl version --client
helm version
argocd version --client
vault version
terraform version
docker --version
aws --version
jq --version
yq --version
```

### 3. Configure Git

```bash
# Set up Git configuration
git config --global user.name "Your Name"
git config --global user.email "your.email@company.com"

# Set up SSH key for GitHub (recommended)
ssh-keygen -t ed25519 -C "your.email@company.com"
cat ~/.ssh/id_ed25519.pub
# Add the public key to your GitHub account
```

### 4. Clone Repositories

```bash
# Create workspace directory
mkdir -p ~/workspace/craftista
cd ~/workspace/craftista

# Clone all three repositories
git clone git@github.com:charliepoker/craftista.git
git clone git@github.com:charliepoker/Craftista-IaC.git
git clone git@github.com:charliepoker/craftista-gitops.git

# Verify repositories
ls -la
```

## Tool Access and Configuration

### AWS Access

1. **Request AWS Access**:

   - Contact your team lead to request AWS account access
   - You'll need access to the development, staging, and production accounts
   - Request appropriate IAM permissions for your role

2. **Configure AWS CLI**:

   ```bash
   # Configure AWS credentials
   aws configure
   # AWS Access Key ID: [Your access key]
   # AWS Secret Access Key: [Your secret key]
   # Default region name: us-east-1
   # Default output format: json

   # Test AWS access
   aws sts get-caller-identity
   aws eks list-clusters --region us-east-1
   ```

3. **Configure kubectl for EKS**:

   ```bash
   # Update kubeconfig for development cluster
   aws eks update-kubeconfig --region us-east-1 --name craftista-cluster-dev

   # Update kubeconfig for staging cluster
   aws eks update-kubeconfig --region us-east-1 --name craftista-cluster-staging

   # Update kubeconfig for production cluster (read-only access initially)
   aws eks update-kubeconfig --region us-east-1 --name craftista-cluster-prod

   # Verify cluster access
   kubectl get nodes
   kubectl get namespaces
   ```

### ArgoCD Access

1. **Access ArgoCD UI**:

   ```bash
   # Port forward to ArgoCD server (development)
   kubectl port-forward svc/argocd-server -n argocd 8080:443

   # Access https://localhost:8080
   # Or use the public URL: https://argocd.dev.webdemoapp.com
   ```

2. **Get ArgoCD Credentials**:

   ```bash
   # Get initial admin password
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

   # Login with ArgoCD CLI
   argocd login localhost:8080
   # Username: admin
   # Password: [from above command]
   ```

3. **Change Default Password**:
   ```bash
   # Change admin password
   argocd account update-password
   ```

### Vault Access

1. **Access Vault UI**:

   ```bash
   # Port forward to Vault server
   kubectl port-forward svc/vault -n vault 8200:8200

   # Access http://localhost:8200
   ```

2. **Vault Authentication**:

   ```bash
   # Set Vault address
   export VAULT_ADDR="http://localhost:8200"

   # Login with Kubernetes auth (from within cluster)
   vault auth -method=kubernetes role=developer

   # Or login with GitHub (if configured)
   vault auth -method=github token=your-github-token
   ```

### SonarQube Access

1. **Access SonarQube**:

   - URL: https://sonarqube.webdemoapp.com
   - Request account creation from team lead
   - Generate personal access token for CI/CD

2. **Configure SonarQube Scanner**:

   ```bash
   # Install SonarQube scanner
   npm install -g sonarqube-scanner  # For Node.js projects

   # Or download standalone scanner
   wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-4.8.0.2856-linux.zip
   unzip sonar-scanner-cli-4.8.0.2856-linux.zip
   export PATH=$PATH:$(pwd)/sonar-scanner-4.8.0.2856-linux/bin
   ```

### Nexus Repository Access

1. **Access Nexus**:

   - URL: https://nexus.webdemoapp.com
   - Request account creation from team lead
   - Configure Docker registry authentication

2. **Configure Docker for Nexus**:
   ```bash
   # Login to Nexus Docker registry
   docker login nexus.webdemoapp.com:8082
   # Username: [your-nexus-username]
   # Password: [your-nexus-password]
   ```

## Repository Structure

### Understanding the Three-Repository Model

```
craftista/                    # Application source code
├── frontend/                 # Node.js/Express frontend
├── catalogue/                # Python/Flask API
├── voting/                   # Java/Spring Boot API
├── recommendation/           # Go API
└── .github/workflows/        # CI/CD workflows

craftista-iac/                # Infrastructure as Code
├── terraform/
│   ├── modules/              # Reusable Terraform modules
│   └── environments/         # Environment-specific configs
└── scripts/                  # Infrastructure automation

craftista-gitops/             # Deployment configurations
├── kubernetes/               # Kubernetes manifests
├── helm/                     # Helm charts
├── argocd/                   # ArgoCD configurations
├── vault/                    # Vault policies
└── scripts/                  # Operational scripts
```

### Key Files and Directories

**In craftista repository**:

- `frontend/package.json`: Node.js dependencies and scripts
- `catalogue/requirements.txt`: Python dependencies
- `voting/pom.xml`: Java Maven configuration
- `recommendation/go.mod`: Go module dependencies
- `.github/workflows/`: CI/CD pipeline definitions

**In craftista-iac repository**:

- `terraform/environments/dev/`: Development infrastructure
- `terraform/environments/staging/`: Staging infrastructure
- `terraform/environments/prod/`: Production infrastructure
- `terraform/modules/`: Reusable infrastructure components

**In craftista-gitops repository**:

- `kubernetes/base/`: Base Kubernetes manifests
- `kubernetes/overlays/`: Environment-specific overlays
- `helm/charts/`: Helm charts for each service
- `argocd/applications/`: ArgoCD application definitions

## Development Workflow

### 1. Feature Development Process

```bash
# 1. Create feature branch
cd ~/workspace/craftista/craftista
git checkout develop
git pull origin develop
git checkout -b feature/your-feature-name

# 2. Make your changes
# Edit code in your preferred editor

# 3. Test locally
cd frontend/
npm install
npm test
npm run build

# 4. Commit changes
git add .
git commit -m "feat(frontend): add new feature description"

# 5. Push and create PR
git push origin feature/your-feature-name
# Create pull request through GitHub UI
```

### 2. GitOps Configuration Changes

```bash
# 1. Create branch in GitOps repo
cd ~/workspace/craftista/craftista-gitops
git checkout main
git pull origin main
git checkout -b config/update-frontend-resources

# 2. Make configuration changes
# Edit Kubernetes manifests or Helm values

# 3. Validate changes
kubectl apply --dry-run=client -f kubernetes/overlays/dev/frontend/
helm lint helm/charts/frontend/

# 4. Commit and push
git add .
git commit -m "config(frontend): increase resource limits for dev"
git push origin config/update-frontend-resources
```

### 3. Testing Changes

```bash
# Test in development environment
kubectl apply -k kubernetes/overlays/dev/frontend/

# Verify deployment
kubectl get pods -n craftista-dev
kubectl logs -f deployment/frontend -n craftista-dev

# Test application
curl -k https://frontend.dev.webdemoapp.com/health
```

### 4. Code Review Process

1. **Create Pull Request**:

   - Use descriptive title and description
   - Link to relevant issues or tickets
   - Add appropriate reviewers
   - Ensure CI checks pass

2. **Review Checklist**:

   - Code follows team standards
   - Tests are included and passing
   - Documentation is updated
   - Security considerations addressed
   - Performance impact considered

3. **Merge Process**:
   - Squash commits for feature branches
   - Use conventional commit messages
   - Delete feature branch after merge

## Testing Procedures

### Local Testing

1. **Unit Tests**:

   ```bash
   # Frontend (Node.js)
   cd frontend/
   npm test
   npm run test:coverage

   # Catalogue (Python)
   cd catalogue/
   python -m pytest tests/
   python -m pytest --cov=app tests/

   # Voting (Java)
   cd voting/
   mvn test
   mvn jacoco:report

   # Recommendation (Go)
   cd recommendation/
   go test ./...
   go test -cover ./...
   ```

2. **Integration Tests**:

   ```bash
   # Run integration tests
   cd test-framework/
   python scripts/run-integration-tests.py --environment dev
   ```

3. **Local Development Environment**:

   ```bash
   # Start local services with Docker Compose
   docker-compose -f docker-compose-simple.yml up -d

   # Test local services
   curl http://localhost:3000/health
   curl http://localhost:5000/health
   curl http://localhost:8080/health
   curl http://localhost:8081/health
   ```

### Kubernetes Testing

1. **Manifest Validation**:

   ```bash
   # Validate Kubernetes YAML
   kubectl apply --dry-run=client -f kubernetes/overlays/dev/frontend/

   # Validate with kubeval
   kubeval kubernetes/overlays/dev/frontend/*.yaml
   ```

2. **Helm Chart Testing**:

   ```bash
   # Lint Helm charts
   helm lint helm/charts/frontend/

   # Test template rendering
   helm template frontend helm/charts/frontend/ --values helm/charts/frontend/values-dev.yaml

   # Test installation
   helm install frontend-test helm/charts/frontend/ --values helm/charts/frontend/values-dev.yaml --dry-run
   ```

### Property-Based Testing

```bash
# Run property-based tests (when implemented)
cd tests/property/
python -m pytest test_network_policies.py -v
```

## Deployment Process

### Development Deployment

1. **Automatic Deployment**:

   - Push to `develop` branch triggers CI/CD
   - GitHub Actions builds and tests code
   - Docker image is built and pushed
   - GitOps repo is updated with new image tag
   - ArgoCD syncs changes to dev cluster

2. **Manual Deployment**:

   ```bash
   # Deploy specific service to dev
   argocd app sync craftista-frontend-dev

   # Monitor deployment
   kubectl get pods -n craftista-dev -w
   argocd app get craftista-frontend-dev
   ```

### Staging Deployment

1. **Promotion Process**:

   ```bash
   # Promote from dev to staging
   ./scripts/promote-to-staging.sh frontend v1.2.3

   # Or manually update staging overlay
   cd kubernetes/overlays/staging/frontend/
   # Update image tag in kustomization.yaml
   git add .
   git commit -m "promote(frontend): v1.2.3 to staging"
   git push origin main
   ```

### Production Deployment

1. **Production Deployment** (requires approval):

   ```bash
   # Production deployments require manual approval
   argocd app sync craftista-frontend-prod --dry-run

   # After approval
   argocd app sync craftista-frontend-prod
   ```

## Monitoring and Observability

### Application Monitoring

1. **Health Checks**:

   ```bash
   # Check application health
   curl -k https://webdemoapp.com/health
   curl -k https://catalogue.webdemoapp.com/health
   curl -k https://voting.webdemoapp.com/health
   curl -k https://recommendation.webdemoapp.com/health
   ```

2. **Pod Monitoring**:

   ```bash
   # Check pod status
   kubectl get pods --all-namespaces | grep craftista

   # Check resource usage
   kubectl top pods -n craftista-prod
   kubectl top nodes
   ```

3. **Application Logs**:

   ```bash
   # View application logs
   kubectl logs -f deployment/frontend -n craftista-prod
   kubectl logs -f deployment/catalogue -n craftista-prod --tail=100

   # View logs from all containers
   kubectl logs -f deployment/voting -n craftista-prod --all-containers
   ```

### ArgoCD Monitoring

1. **Application Status**:

   ```bash
   # Check ArgoCD application status
   argocd app list
   argocd app get craftista-frontend-prod

   # Check sync history
   argocd app history craftista-frontend-prod
   ```

2. **ArgoCD UI**:
   - Access: https://argocd.webdemoapp.com
   - Monitor deployment status
   - View application topology
   - Check sync policies and health

### Infrastructure Monitoring

1. **Cluster Health**:

   ```bash
   # Check cluster status
   kubectl cluster-info
   kubectl get nodes -o wide

   # Check system pods
   kubectl get pods -n kube-system
   kubectl get pods -n argocd
   kubectl get pods -n vault
   ```

## Troubleshooting Resources

### Common Issues and Solutions

1. **Pod Startup Issues**:

   ```bash
   # Check pod events
   kubectl describe pod <pod-name> -n craftista-dev

   # Check logs
   kubectl logs <pod-name> -n craftista-dev --previous

   # Check resource constraints
   kubectl top nodes
   kubectl describe nodes
   ```

2. **ArgoCD Sync Issues**:

   ```bash
   # Force refresh and sync
   argocd app get craftista-frontend-dev --refresh
   argocd app sync craftista-frontend-dev --force

   # Check application events
   kubectl describe application craftista-frontend-dev -n argocd
   ```

3. **Secret Issues**:

   ```bash
   # Check External Secrets status
   kubectl get externalsecrets -n craftista-dev
   kubectl describe externalsecret frontend-secrets -n craftista-dev

   # Check Vault connectivity
   kubectl exec vault-0 -n vault -- vault status
   ```

### Documentation References

- [Troubleshooting Guide](runbooks/troubleshooting.md)
- [Rollback Procedures](runbooks/rollback-procedure.md)
- [Secrets Rotation](runbooks/secrets-rotation.md)
- [Disaster Recovery](runbooks/disaster-recovery.md)

## Team Practices

### Communication

1. **Slack Channels**:

   - `#craftista-dev`: Development discussions
   - `#craftista-ops`: Operations and incidents
   - `#craftista-alerts`: Automated alerts
   - `#craftista-deployments`: Deployment notifications

2. **Stand-up Meetings**:

   - Daily at 9:00 AM
   - Share progress, blockers, and plans
   - Discuss any production issues

3. **Incident Response**:
   - Use `#craftista-ops` for incident coordination
   - Follow incident response procedures
   - Document lessons learned

### Code Standards

1. **Commit Messages**:

   ```
   feat(frontend): add user authentication
   fix(catalogue): resolve database connection issue
   docs(gitops): update deployment guide
   config(k8s): increase memory limits for prod
   ```

2. **Branch Naming**:

   ```
   feature/user-authentication
   bugfix/database-connection
   config/increase-memory-limits
   hotfix/security-patch
   ```

3. **Pull Request Guidelines**:
   - Use descriptive titles and descriptions
   - Include testing instructions
   - Link to relevant issues
   - Request appropriate reviewers
   - Ensure CI checks pass

### Security Practices

1. **Secret Management**:

   - Never commit secrets to Git
   - Use Vault for all sensitive data
   - Rotate secrets regularly
   - Follow least-privilege principles

2. **Access Control**:

   - Use strong passwords and 2FA
   - Regularly review access permissions
   - Follow principle of least privilege
   - Report security incidents immediately

3. **Code Security**:
   - Run security scans on all code
   - Keep dependencies up to date
   - Follow secure coding practices
   - Review security scan results

## Getting Help

### Internal Resources

1. **Team Members**:

   - **Platform Team Lead**: [Name] - [Contact]
   - **Senior DevOps Engineer**: [Name] - [Contact]
   - **Security Engineer**: [Name] - [Contact]
   - **Database Administrator**: [Name] - [Contact]

2. **Documentation**:

   - [Architecture Documentation](architecture.md)
   - [Deployment Guide](deployment-guide.md)
   - [Directory Structure](directory-structure.md)
   - [Operational Runbooks](runbooks/)

3. **Knowledge Base**:
   - Internal wiki: [URL]
   - Team documentation: [URL]
   - Incident reports: [URL]

### External Resources

1. **Official Documentation**:

   - [Kubernetes Documentation](https://kubernetes.io/docs/)
   - [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
   - [Helm Documentation](https://helm.sh/docs/)
   - [Vault Documentation](https://www.vaultproject.io/docs)
   - [Terraform Documentation](https://www.terraform.io/docs)

2. **Community Resources**:
   - [CNCF Slack](https://slack.cncf.io/)
   - [Kubernetes Slack](https://kubernetes.slack.com/)
   - [ArgoCD Slack](https://argoproj.github.io/community/join-slack/)

### Escalation Process

1. **Level 1**: Ask team members or check documentation
2. **Level 2**: Create issue in appropriate repository
3. **Level 3**: Contact team lead or on-call engineer
4. **Level 4**: Escalate to management or vendor support

## Next Steps

### First Week Goals

- [ ] Complete local development setup
- [ ] Access all required tools and systems
- [ ] Clone and explore all repositories
- [ ] Deploy a simple change to development environment
- [ ] Complete security training and access reviews
- [ ] Shadow a team member during deployment
- [ ] Review all documentation and runbooks

### First Month Goals

- [ ] Make your first production deployment
- [ ] Participate in incident response
- [ ] Complete a feature from start to finish
- [ ] Contribute to documentation improvements
- [ ] Understand the complete CI/CD pipeline
- [ ] Learn operational procedures and runbooks

### Ongoing Learning

- [ ] Stay updated with Kubernetes and GitOps best practices
- [ ] Participate in team knowledge sharing sessions
- [ ] Contribute to process improvements
- [ ] Mentor new team members
- [ ] Attend relevant conferences and training

## Feedback and Improvements

This onboarding guide is a living document. Please provide feedback and suggestions for improvements:

1. **Create an issue** in the craftista-gitops repository
2. **Submit a pull request** with improvements
3. **Discuss in team meetings** for major changes
4. **Share feedback** with your team lead

Welcome to the team! We're excited to have you contribute to the Craftista GitOps platform. Don't hesitate to ask questions and seek help as you get up to speed.
