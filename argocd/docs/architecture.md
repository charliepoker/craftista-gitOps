# Craftista GitOps Architecture

This document provides a comprehensive overview of the Craftista GitOps architecture, detailing the three-repository structure, CI/CD pipeline flow, and component interactions.

## Table of Contents

- [Overview](#overview)
- [Three-Repository Architecture](#three-repository-architecture)
- [CI/CD Pipeline Flow](#cicd-pipeline-flow)
- [GitOps Sync Process](#gitops-sync-process)
- [Component Interactions](#component-interactions)
- [Security Architecture](#security-architecture)
- [Network Architecture](#network-architecture)
- [Data Flow](#data-flow)

## Overview

The Craftista application implements a modern GitOps architecture that separates concerns across three distinct repositories, each serving a specific purpose in the software delivery lifecycle. This architecture ensures scalability, security, and maintainability while following DevSecOps best practices.

### Key Architectural Principles

1. **Separation of Concerns**: Application code, infrastructure, and deployment configurations are managed separately
2. **GitOps Methodology**: Git serves as the single source of truth for all configurations
3. **Security by Design**: Secrets management, network policies, and RBAC are built into the architecture
4. **Environment Parity**: Consistent deployment patterns across dev, staging, and production
5. **Automation First**: Minimal manual intervention in the deployment process

## Three-Repository Architecture

### Repository Responsibilities

```mermaid
graph TB
    subgraph "Application Development"
        A[craftista Repository]
        A1[Source Code]
        A2[Dockerfiles]
        A3[Unit Tests]
        A4[CI Workflows]
        A --> A1
        A --> A2
        A --> A3
        A --> A4
    end

    subgraph "Infrastructure Management"
        B[craftista-iac Repository]
        B1[Terraform Modules]
        B2[EKS Configuration]
        B3[Database Setup]
        B4[DevOps Tools]
        B --> B1
        B --> B2
        B --> B3
        B --> B4
    end

    subgraph "Deployment Configuration"
        C[craftista-gitops Repository]
        C1[Kubernetes Manifests]
        C2[Helm Charts]
        C3[ArgoCD Applications]
        C4[Vault Policies]
        C --> C1
        C --> C2
        C --> C3
        C --> C4
    end

    A4 -->|Updates Image Tags| C1
    B2 -->|Provisions| EKS[EKS Cluster]
    C3 -->|Deploys To| EKS
```

### 1. craftista Repository (Application Code)

**Purpose**: Contains all application source code and CI/CD workflows

**Contents**:

- **Microservices Source Code**:
  - `frontend/` - Node.js/Express application
  - `catalogue/` - Python/Flask API service
  - `voting/` - Java/Spring Boot service
  - `recommendation/` - Go service
- **Build Configurations**:
  - Dockerfiles for each service
  - Package management files (package.json, requirements.txt, pom.xml, go.mod)
- **Testing**:
  - Unit tests for each service
  - Integration test suites
- **CI/CD Workflows**:
  - GitHub Actions workflows for each service
  - Security scanning configurations
  - Image build and push automation

**Key Responsibilities**:

- Source code version control
- Automated testing execution
- Security scanning (SAST, SCA, container scanning)
- Docker image building and publishing
- GitOps repository updates with new image tags

### 2. craftista-iac Repository (Infrastructure as Code)

**Purpose**: Manages all AWS infrastructure using Terraform

**Contents**:

- **Core Infrastructure**:
  - VPC and networking components
  - EKS cluster configuration
  - Security groups and IAM roles
- **Database Infrastructure**:
  - RDS PostgreSQL for voting service
  - DocumentDB MongoDB for catalogue service
  - ElastiCache Redis for recommendation service
- **DevOps Tools**:
  - SonarQube EC2 instance
  - Nexus Repository EC2 instance
  - Application Load Balancers
- **Environment Configurations**:
  - Separate configurations for dev, staging, prod
  - Environment-specific sizing and settings

**Key Responsibilities**:

- Infrastructure provisioning and management
- Environment isolation and configuration
- Security group and network policy management
- Database and storage provisioning
- DevOps tooling infrastructure

### 3. craftista-gitops Repository (Deployment Configuration)

**Purpose**: Contains all Kubernetes deployment configurations and GitOps workflows

**Contents**:

- **Kubernetes Manifests**:
  - Base configurations using Kustomize
  - Environment-specific overlays
  - Network policies and RBAC configurations
- **Helm Charts**:
  - Templated application deployments
  - Environment-specific value files
  - Dependency management
- **ArgoCD Configurations**:
  - Application definitions
  - Project configurations
  - Sync policies and health checks
- **Security Configurations**:
  - Vault policies and secret templates
  - External Secrets Operator configurations
  - Service account and RBAC definitions

**Key Responsibilities**:

- Deployment configuration management
- Environment-specific customizations
- Secrets management integration
- GitOps workflow orchestration
- Operational documentation and runbooks

## CI/CD Pipeline Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub (craftista)
    participant CI as GitHub Actions
    participant SQ as SonarQube
    participant TR as Trivy Scanner
    participant DH as DockerHub
    participant GO as GitOps Repo
    participant AC as ArgoCD
    participant EKS as EKS Cluster

    Dev->>GH: Push code changes
    GH->>CI: Trigger workflow

    CI->>CI: Build application
    CI->>CI: Run unit tests
    CI->>SQ: SAST scan
    CI->>CI: Dependency scan (SCA)
    CI->>CI: Build Docker image
    CI->>TR: Container scan

    alt All scans pass
        CI->>DH: Push image with tags
        CI->>GO: Update image tag in manifests
        GO->>AC: Detect changes
        AC->>EKS: Sync deployment
        EKS->>AC: Report health status
    else Security scan fails
        CI->>GH: Fail pipeline with report
    end
```

### Pipeline Stages

1. **Code Commit**: Developer pushes changes to feature branch
2. **Build Stage**:
   - Checkout source code
   - Install dependencies
   - Compile/build application
3. **Test Stage**:
   - Execute unit tests
   - Run integration tests
   - Generate test coverage reports
4. **Security Stage**:
   - SAST analysis with SonarQube
   - Dependency vulnerability scanning
   - License compliance checking
5. **Image Stage**:
   - Build Docker image
   - Scan image with Trivy
   - Tag with commit SHA and branch name
6. **Publish Stage**:
   - Push image to DockerHub registry
   - Update GitOps repository with new image tag
7. **Deploy Stage**:
   - ArgoCD detects GitOps changes
   - Syncs new configuration to cluster
   - Monitors deployment health

## GitOps Sync Process

```mermaid
graph LR
    subgraph "GitOps Repository"
        GM[Git Manifests]
        HC[Helm Charts]
        AA[ArgoCD Apps]
    end

    subgraph "ArgoCD"
        AC[Application Controller]
        RS[Repo Server]
        RC[Redis Cache]
    end

    subgraph "Kubernetes Cluster"
        NS1[craftista-dev]
        NS2[craftista-staging]
        NS3[craftista-prod]
    end

    GM --> RS
    HC --> RS
    AA --> AC
    RS --> RC
    AC --> NS1
    AC --> NS2
    AC --> NS3

    AC -->|Health Check| AC
    NS1 -->|Status| AC
    NS2 -->|Status| AC
    NS3 -->|Status| AC
```

### Sync Policies by Environment

| Environment | Sync Policy | Prune | Self-Heal | Manual Approval |
| ----------- | ----------- | ----- | --------- | --------------- |
| Development | Automatic   | ✅    | ✅        | ❌              |
| Staging     | Automatic   | ✅    | ✅        | ❌              |
| Production  | Manual      | ✅    | ❌        | ✅              |

### ArgoCD Application Structure

Each microservice has dedicated ArgoCD Applications per environment:

```yaml
# Example: Frontend Development Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: craftista-frontend-dev
  namespace: argocd
spec:
  project: craftista-dev
  source:
    repoURL: https://github.com/charliepoker/craftista-gitops.git
    targetRevision: main
    path: kubernetes/overlays/dev/frontend
  destination:
    server: https://kubernetes.default.svc
    namespace: craftista-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Component Interactions

### Service Communication

```mermaid
graph TB
    subgraph "External Traffic"
        ALB[Application Load Balancer]
        CF[CloudFront CDN]
    end

    subgraph "Kubernetes Cluster"
        subgraph "Ingress Layer"
            IC[Ingress Controller]
        end

        subgraph "Application Layer"
            FE[Frontend Service]
            CA[Catalogue Service]
            VO[Voting Service]
            RE[Recommendation Service]
        end

        subgraph "Data Layer"
            MG[(MongoDB)]
            PG[(PostgreSQL)]
            RD[(Redis)]
        end
    end

    CF --> ALB
    ALB --> IC
    IC --> FE
    FE --> CA
    FE --> VO
    FE --> RE
    CA --> MG
    VO --> PG
    RE --> RD
```

### Network Policies

Network policies enforce micro-segmentation:

- **Default Deny**: All pod-to-pod communication blocked by default
- **Frontend Policy**: Can communicate with all backend services
- **Catalogue Policy**: Can only communicate with MongoDB and receive from frontend/voting
- **Voting Policy**: Can communicate with PostgreSQL and catalogue, receive from frontend
- **Recommendation Policy**: Can only communicate with Redis and receive from frontend

### RBAC Structure

```mermaid
graph TB
    subgraph "Service Accounts"
        SA1[frontend-sa]
        SA2[catalogue-sa]
        SA3[voting-sa]
        SA4[recommendation-sa]
        SA5[argocd-sa]
    end

    subgraph "Roles"
        R1[frontend-role]
        R2[catalogue-role]
        R3[voting-role]
        R4[recommendation-role]
        R5[argocd-role]
    end

    subgraph "Resources"
        SEC[Secrets]
        CM[ConfigMaps]
        POD[Pods]
        SVC[Services]
    end

    SA1 --> R1
    SA2 --> R2
    SA3 --> R3
    SA4 --> R4
    SA5 --> R5

    R1 --> SEC
    R2 --> SEC
    R3 --> SEC
    R4 --> SEC
    R5 --> POD
    R5 --> SVC
```

## Security Architecture

### Secrets Management Flow

```mermaid
sequenceDiagram
    participant V as Vault
    participant ESO as External Secrets Operator
    participant K8S as Kubernetes Secret
    participant POD as Application Pod

    V->>ESO: Poll for secret changes
    ESO->>V: Authenticate with service account
    V->>ESO: Return secret data
    ESO->>K8S: Create/update Kubernetes secret
    K8S->>POD: Mount secret as volume/env var
```

### Vault Secret Hierarchy

```
secret/
├── craftista/
│   ├── dev/
│   │   ├── frontend/
│   │   │   ├── session-secret
│   │   │   └── api-keys
│   │   ├── catalogue/
│   │   │   ├── mongodb-uri
│   │   │   └── mongodb-credentials
│   │   ├── voting/
│   │   │   ├── postgres-uri
│   │   │   └── postgres-credentials
│   │   └── recommendation/
│   │       ├── redis-uri
│   │       └── redis-password
│   ├── staging/ (same structure)
│   └── prod/ (same structure)
├── github-actions/
│   ├── dockerhub-credentials
│   ├── sonarqube-token
│   └── gitops-deploy-key
└── argocd/
    ├── admin-password
    └── github-webhook-secret
```

## Network Architecture

### EKS Cluster Network Design

```mermaid
graph TB
    subgraph "AWS VPC"
        subgraph "Public Subnets"
            ALB[Application Load Balancer]
            NAT[NAT Gateway]
        end

        subgraph "Private Subnets"
            subgraph "EKS Worker Nodes"
                WN1[Worker Node 1]
                WN2[Worker Node 2]
                WN3[Worker Node 3]
            end

            subgraph "Database Subnets"
                RDS[(RDS PostgreSQL)]
                DOC[(DocumentDB)]
                ELC[(ElastiCache)]
            end
        end

        subgraph "Management Subnets"
            SQ[SonarQube EC2]
            NX[Nexus EC2]
        end
    end

    Internet --> ALB
    ALB --> WN1
    ALB --> WN2
    ALB --> WN3
    WN1 --> RDS
    WN2 --> DOC
    WN3 --> ELC
    WN1 --> NAT
    WN2 --> NAT
    WN3 --> NAT
    NAT --> Internet
```

### Security Groups

| Component        | Inbound Rules                    | Outbound Rules                              |
| ---------------- | -------------------------------- | ------------------------------------------- |
| EKS Worker Nodes | ALB (80,443), Node-to-Node (All) | Internet (443), Databases (5432,27017,6379) |
| RDS PostgreSQL   | EKS Nodes (5432)                 | None                                        |
| DocumentDB       | EKS Nodes (27017)                | None                                        |
| ElastiCache      | EKS Nodes (6379)                 | None                                        |
| SonarQube        | GitHub Actions (9000)            | Internet (443)                              |
| Nexus            | GitHub Actions (8081)            | Internet (443)                              |

## Data Flow

### Application Request Flow

```mermaid
sequenceDiagram
    participant U as User
    participant CF as CloudFront
    participant ALB as Load Balancer
    participant FE as Frontend
    participant CA as Catalogue
    participant VO as Voting
    participant RE as Recommendation
    participant DB as Databases

    U->>CF: HTTP Request
    CF->>ALB: Forward request
    ALB->>FE: Route to frontend
    FE->>CA: Get products
    CA->>DB: Query MongoDB
    DB->>CA: Return products
    FE->>RE: Get recommendations
    RE->>DB: Query Redis
    DB->>RE: Return recommendations
    FE->>VO: Get voting data
    VO->>DB: Query PostgreSQL
    DB->>VO: Return votes
    FE->>U: Render page with data
```

### Deployment Data Flow

```mermaid
graph LR
    subgraph "Source"
        SC[Source Code]
        DF[Dockerfile]
    end

    subgraph "CI Pipeline"
        BLD[Build]
        TST[Test]
        SCN[Scan]
    end

    subgraph "Registry"
        DH[DockerHub]
    end

    subgraph "GitOps"
        GM[Git Manifests]
        AC[ArgoCD]
    end

    subgraph "Runtime"
        K8S[Kubernetes]
        POD[Running Pods]
    end

    SC --> BLD
    DF --> BLD
    BLD --> TST
    TST --> SCN
    SCN --> DH
    DH --> GM
    GM --> AC
    AC --> K8S
    K8S --> POD
```

This architecture ensures:

- **Scalability**: Horizontal pod autoscaling and multi-AZ deployment
- **Security**: Defense in depth with multiple security layers
- **Reliability**: Health checks, self-healing, and automated rollbacks
- **Observability**: Comprehensive logging, metrics, and tracing
- **Maintainability**: Clear separation of concerns and automated operations
