# OPA Gatekeeper Policies

This directory contains OPA Gatekeeper constraint templates and constraints for enforcing security and operational policies on the LiteLLM EKS cluster.

## Overview

[OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/) is a Kubernetes-native policy controller that enforces policies defined using Rego. It acts as a validating admission webhook to reject resources that violate policies.

## Directory Structure

```
opa-policies/
├── templates/           # ConstraintTemplates (policy definitions)
│   ├── allowed-repos.yaml
│   ├── block-latest-tag.yaml
│   ├── block-nodeport.yaml
│   ├── container-limits.yaml
│   ├── mcpserver-authentication.yaml
│   ├── pod-security.yaml
│   ├── require-probes.yaml
│   └── required-labels.yaml
├── constraints/         # Constraints (policy instances)
│   ├── allowed-repos.yaml
│   ├── block-latest-tag.yaml
│   ├── block-nodeport.yaml
│   ├── container-limits.yaml
│   ├── mcpserver-authentication.yaml
│   ├── pod-security-baseline.yaml
│   ├── require-probes.yaml
│   └── required-labels.yaml
└── README.md
```

## Policies Included

| Policy | Description | Default Mode |
|--------|-------------|--------------|
| **K8sAllowedRepos** | Restricts container images to approved registries | dryrun |
| **K8sBlockLatestTag** | Blocks `latest` tag or untagged images | dryrun |
| **K8sBlockNodePort** | Prevents NodePort services | dryrun |
| **K8sContainerLimits** | Requires CPU/memory requests and limits | dryrun |
| **K8sPodSecurity** | Enforces Pod Security Standards (baseline) | dryrun |
| **K8sRequireProbes** | Requires liveness and readiness probes | dryrun |
| **K8sRequiredLabels** | Requires standard Kubernetes labels | dryrun |
| **MCPServerAuthentication** | Enforces zero-trust authentication for MCP servers | dryrun |

## Deployment

### 1. Install OPA Gatekeeper

```bash
# Add the Gatekeeper Helm repository
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

# Install Gatekeeper
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --values ../helm-values/gatekeeper-values.yaml
```

### 2. Verify Installation

```bash
# Check Gatekeeper pods are running
kubectl get pods -n gatekeeper-system

# Verify webhook is configured
kubectl get validatingwebhookconfigurations
```

### 3. Apply Constraint Templates

```bash
# Apply all constraint templates
kubectl apply -f manifests/opa-policies/templates/
```

### 4. Apply Constraints

```bash
# Apply all constraints (starts in dryrun mode)
kubectl apply -f manifests/opa-policies/constraints/
```

## Enforcement Modes

Constraints support three enforcement modes:

| Mode | Behavior |
|------|----------|
| `dryrun` | Audits violations but allows resources (recommended for initial rollout) |
| `warn` | Logs warning but allows resources |
| `deny` | Blocks non-compliant resources |

### Transitioning to Enforcement

1. **Audit existing resources**:
   ```bash
   # Check for violations in dryrun mode
   kubectl get constraints -o json | jq '.items[].status.violations'
   ```

2. **Fix violations** in existing workloads

3. **Enable enforcement** by changing `enforcementAction: dryrun` to `enforcementAction: deny`:
   ```yaml
   spec:
     enforcementAction: deny
   ```

## Monitoring Violations

### View Constraint Status

```bash
# List all constraints and their violation counts
kubectl get constraints

# View detailed violations for a specific constraint
kubectl describe k8sallowedrepos allowed-image-repos
```

### Prometheus Metrics

Gatekeeper exposes metrics at `/metrics`:
- `gatekeeper_violations` - Total policy violations
- `gatekeeper_constraint_template_status` - Template sync status
- `gatekeeper_constraints` - Constraint status

## Customization

### Adding Approved Registries

Edit `constraints/allowed-repos.yaml`:

```yaml
parameters:
  repos:
    - "ghcr.io/berriai/"
    - "your-private-registry.com/"  # Add your registry
```

### Exempting Specific Images

Most policies support `exemptImages` with glob patterns:

```yaml
parameters:
  exemptImages:
    - "*/special-image:*"
    - "internal-registry.com/*"
```

### Namespace Exclusions

Use `excludedNamespaces` to skip enforcement:

```yaml
match:
  excludedNamespaces:
    - kube-system
    - special-namespace
```

## Troubleshooting

### Policy Not Enforcing

1. Check constraint template is synced:
   ```bash
   kubectl get constrainttemplates
   ```

2. Verify constraint is active:
   ```bash
   kubectl get constraints
   ```

3. Check enforcement action is set to `deny`

### Workload Blocked Incorrectly

1. Check violation message:
   ```bash
   kubectl describe deployment <name>
   ```

2. Temporarily set constraint to `dryrun`:
   ```bash
   kubectl patch k8sallowedrepos allowed-image-repos \
     -p '{"spec":{"enforcementAction":"dryrun"}}' --type=merge
   ```

3. Add exemption if needed

### Gatekeeper Webhook Failures

If webhook is causing cluster issues:

```bash
# Check webhook configuration
kubectl get validatingwebhookconfigurations gatekeeper-validating-webhook-configuration -o yaml

# Check Gatekeeper logs
kubectl logs -n gatekeeper-system -l control-plane=controller-manager
```
