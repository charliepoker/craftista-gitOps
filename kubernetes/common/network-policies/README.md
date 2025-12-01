# Network Policies

This directory contains Kubernetes NetworkPolicy resources that implement network segmentation and service isolation for the Craftista microservices application.

## Overview

NetworkPolicies control traffic flow between pods and network endpoints. By default, all traffic is denied, and specific policies allow only required communication paths.

## Policy Files

### default-deny.yaml

Implements a default-deny-all policy for ingress and egress traffic across all namespaces (dev, staging, prod). This ensures that no traffic is allowed unless explicitly permitted by other policies.

**Applied to**: All pods in craftista-dev, craftista-staging, and craftista-prod namespaces

### frontend-policy.yaml

Controls traffic for the Frontend service (Node.js application).

**Ingress**:

- Allows traffic from ingress controller (nginx-ingress) on port 3000

**Egress**:

- Allows traffic to catalogue service on port 5000
- Allows traffic to voting service on port 8080
- Allows traffic to recommendation service on port 8080
- Allows DNS resolution (UDP port 53)

### catalogue-policy.yaml

Controls traffic for the Catalogue service (Python/Flask application).

**Ingress**:

- Allows traffic from frontend service on port 5000
- Allows traffic from voting service on port 5000

**Egress**:

- Allows traffic to MongoDB/DocumentDB on port 27017
- Allows DNS resolution (UDP port 53)
- Allows HTTPS (port 443) for external DocumentDB connections

### voting-policy.yaml

Controls traffic for the Voting service (Java/Spring Boot application).

**Ingress**:

- Allows traffic from frontend service on port 8080

**Egress**:

- Allows traffic to PostgreSQL/RDS on port 5432
- Allows traffic to catalogue service on port 5000
- Allows DNS resolution (UDP port 53)
- Allows HTTPS (port 443) for external RDS connections

### recommendation-policy.yaml

Controls traffic for the Recommendation service (Go application).

**Ingress**:

- Allows traffic from frontend service on port 8080

**Egress**:

- Allows traffic to Redis/ElastiCache on port 6379
- Allows DNS resolution (UDP port 53)
- Allows HTTPS (port 443) for external ElastiCache connections

## Service Communication Flow

```
Internet
    │
    ▼
Ingress Controller
    │
    ▼
Frontend (port 3000)
    │
    ├──> Catalogue (port 5000) ──> MongoDB (port 27017)
    │
    ├──> Voting (port 8080) ──> PostgreSQL (port 5432)
    │        │
    │        └──> Catalogue (port 5000)
    │
    └──> Recommendation (port 8080) ──> Redis (port 6379)
```

## Applying NetworkPolicies

NetworkPolicies are namespace-scoped. Apply them to each environment:

```bash
# Apply to dev environment
kubectl apply -f default-deny.yaml -n craftista-dev
kubectl apply -f frontend-policy.yaml -n craftista-dev
kubectl apply -f catalogue-policy.yaml -n craftista-dev
kubectl apply -f voting-policy.yaml -n craftista-dev
kubectl apply -f recommendation-policy.yaml -n craftista-dev

# Apply to staging environment
kubectl apply -f default-deny.yaml -n craftista-staging
kubectl apply -f frontend-policy.yaml -n craftista-staging
kubectl apply -f catalogue-policy.yaml -n craftista-staging
kubectl apply -f voting-policy.yaml -n craftista-staging
kubectl apply -f recommendation-policy.yaml -n craftista-staging

# Apply to production environment
kubectl apply -f default-deny.yaml -n craftista-prod
kubectl apply -f frontend-policy.yaml -n craftista-prod
kubectl apply -f catalogue-policy.yaml -n craftista-prod
kubectl apply -f voting-policy.yaml -n craftista-prod
kubectl apply -f recommendation-policy.yaml -n craftista-prod
```

## Testing NetworkPolicies

To verify NetworkPolicies are working correctly:

1. **Test allowed connections**:

   ```bash
   # From frontend pod, test connection to catalogue
   kubectl exec -it <frontend-pod> -n craftista-dev -- curl http://catalogue:5000/health
   ```

2. **Test denied connections**:

   ```bash
   # From recommendation pod, try to connect to catalogue (should fail)
   kubectl exec -it <recommendation-pod> -n craftista-dev -- curl http://catalogue:5000/health
   ```

3. **View applied policies**:
   ```bash
   kubectl get networkpolicies -n craftista-dev
   kubectl describe networkpolicy frontend-policy -n craftista-dev
   ```

## Security Considerations

- **Default Deny**: All traffic is denied by default, implementing a zero-trust network model
- **Least Privilege**: Each service can only communicate with its required dependencies
- **DNS Access**: All services have DNS access for service discovery
- **External Databases**: Policies allow connections to AWS managed services (DocumentDB, RDS, ElastiCache)
- **No Direct Service-to-Service**: Services like recommendation cannot directly access databases of other services

## Troubleshooting

If services cannot communicate:

1. Check if NetworkPolicies are applied:

   ```bash
   kubectl get networkpolicies -n <namespace>
   ```

2. Verify pod labels match policy selectors:

   ```bash
   kubectl get pods --show-labels -n <namespace>
   ```

3. Check NetworkPolicy details:

   ```bash
   kubectl describe networkpolicy <policy-name> -n <namespace>
   ```

4. Temporarily remove policies to test connectivity:
   ```bash
   kubectl delete networkpolicy <policy-name> -n <namespace>
   ```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [NetworkPolicy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)

