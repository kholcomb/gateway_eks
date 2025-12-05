# Implementation Plan: Interactive Skip-If-Exists for Deployment Scripts

## Overview
Add interactive prompts to deployment scripts allowing users to skip steps when AWS resources already exist (EKS cluster, VPC, IAM roles, Secrets Manager entries, Kubernetes namespaces, Helm releases, EC2 instances).

## User Requirements
- **Skippable Resources**: IAM roles, Secrets Manager entries, K8s namespaces, Helm releases, AWS resources (EKS, VPC, EC2)
- **Helm Behavior**: Keep `helm upgrade --install` (idempotent) but add interactive option to skip
- **UX**: Interactive prompts asking user before each major step

## Implementation Strategy

### Core Architecture
Add interactive prompt system with resource existence checks before each deployment step. When resources exist, prompt user with options:
- **[S]kip**: Skip this step (default, safest)
- **[P]roceed**: Run deployment (may update resource)
- **[V]iew**: Show resource details, then re-prompt
- **[A]uto**: Auto-skip all remaining healthy resources
- **[Q]uit**: Exit deployment

### Environment Variables for Control
```bash
INTERACTIVE_MODE="${INTERACTIVE_MODE:-true}"    # Enable/disable prompts
AUTO_SKIP_HEALTHY="${AUTO_SKIP_HEALTHY:-false}" # Auto-skip healthy resources
SKIP_ALL="${SKIP_ALL:-false}"                   # Non-interactive skip all
```

## Modifications Required

### File 1: `scripts/deploy.sh`

#### Section 1: Add Interactive Prompt Helper Functions (after line 33)
Add new section with ~150 lines:
- `is_interactive()` - Check if terminal supports interactive prompts
- `prompt_for_action()` - Main prompt function with S/P/V/A/Q options
- `show_resource_details()` - Display resource information (IAM, secrets, namespaces, Helm releases)

#### Section 2: Add Resource Existence Check Functions (after prompts section)
Add new section with ~120 lines:
- `check_iam_role_exists()` - Check IAM role via `aws iam get-role`
- `check_aws_secret_exists()` - Check secret via `aws secretsmanager describe-secret`
- `check_namespace_exists()` - Check namespace via `kubectl get namespace`
- `check_helm_release_exists()` - Check Helm release status (0=healthy, 1=missing, 2=unhealthy)
- `check_eks_cluster_exists()` - Check EKS cluster status
- `check_ec2_instance_exists()` - Check EC2 instance by tag
- `get_existing_namespaces()` - Batch check multiple namespaces

#### Section 3: Modify `create_irsa_roles()` (lines 185-273)
**Current behavior**: Logs "already exists" but doesn't offer skip option
**New behavior**:
1. Check if `litellm-bedrock-role` exists
2. If exists, call `prompt_for_action()`
3. If skip chosen, log and continue
4. If proceed chosen, update role policies
5. Repeat for `external-secrets-role`

**Key changes**:
- Wrap existing role creation in conditional blocks
- Add update logic for when user chooses to proceed on existing roles
- Add clear logging of decisions

#### Section 4: Enhance `create_aws_secrets()` (lines 278-328)
**Current behavior**: Already checks existence, creates if missing
**New behavior**:
1. For each secret (master-key, redis-password, salt-key):
   - If exists, prompt user
   - If skip chosen, log and continue
   - If proceed chosen, **warn about consequences** (especially for salt-key and master-key)
   - Require double confirmation for regeneration
2. For database-url: Error if missing (required dependency)

**Critical safeguard**: Warn that regenerating `master-key` breaks existing API keys and `salt-key` cannot be changed after initial deployment.

#### Section 5: Modify `create_namespaces()` (lines 350-354)
**Current behavior**: Applies namespace manifest unconditionally
**New behavior**:
1. Call `get_existing_namespaces()` with list: litellm, open-webui, monitoring, external-secrets
2. If any exist, prompt with count info
3. If skip chosen, log (even though `kubectl apply` is idempotent)
4. If proceed chosen, run `kubectl apply`

#### Section 6: Modify Helm Deployment Functions
Apply same pattern to all Helm functions (external-secrets, monitoring, jaeger, redis, litellm, openwebui):

**Pattern** (lines 359-577):
1. Call `check_helm_release_exists(release, namespace)`
2. Check return code:
   - 0 = healthy: Prompt user, offer skip
   - 1 = missing: Deploy normally
   - 2 = unhealthy: Warn user, recommend proceeding, don't allow skip for critical deps
3. If skip chosen, verify release with `verify_helm_release()` and return
4. If proceed chosen, run `helm upgrade --install` (existing code)

**Functions to modify**:
- `deploy_external_secrets()` - lines 359-379
- `deploy_monitoring()` - lines 425-446
- `deploy_jaeger()` - lines 471-487
- `deploy_redis()` - lines 492-516
- `deploy_litellm()` - lines 521-556
- `deploy_openwebui()` - lines 561-577

#### Section 7: Add Dependency Checking (new function)
Add after resource check functions:
```bash
check_deployment_dependencies() {
    # Verify dependencies exist before allowing skip
    # Examples:
    # - litellm requires: external-secrets, redis, litellm namespace
    # - secret-stores requires: external-secrets
    # - openwebui requires: open-webui namespace, litellm
}
```

#### Section 8: Enhance `check_prerequisites()` (lines 152-172)
Add kubectl context fix:
1. If `kubectl cluster-info` fails, offer to run `aws eks update-kubeconfig`
2. Prompt user: "Would you like to update kubeconfig now? [Y/n]"
3. If yes, run update command and recheck
4. If still fails, error with instructions

#### Section 9: Update Help/Usage (lines 690-693)
Add environment variables documentation and examples:
```
ENVIRONMENT VARIABLES:
    INTERACTIVE_MODE     - Enable interactive prompts (default: true)
    AUTO_SKIP_HEALTHY    - Auto-skip healthy resources (default: false)
    SKIP_ALL             - Non-interactive skip all existing (default: false)

EXAMPLES:
    # Interactive deployment (default)
    ./deploy.sh all

    # Auto-skip all healthy resources
    AUTO_SKIP_HEALTHY=true ./deploy.sh all

    # Non-interactive mode for CI/CD
    INTERACTIVE_MODE=false ./deploy.sh all
```

**Estimated changes for deploy.sh**: ~500 lines added, ~150 lines modified

---

### File 2: `scripts/setup-bastion.sh`

#### Section 1: Add Interactive Prompt Helpers (after line 26)
Add condensed version of prompt functions from deploy.sh (~100 lines):
- `is_interactive()`
- `prompt_for_action()`
- `show_resource_details()` - Support EC2 instances, IAM roles

#### Section 2: Modify `create_ssm_instance_profile()` (lines 79-158)
**Current behavior**: Checks if role exists, logs, skips creation
**New behavior**:
1. Check if `$BASTION_NAME-ssm-role` exists
2. If exists, prompt user
3. If skip chosen, verify it has required policies and continue
4. If proceed chosen, update policies (attach SSM policy, put EKS policy)
5. Repeat pattern for instance profile

#### Section 3: Modify `launch_instance()` (lines 230-279)
**Current behavior**: Returns existing instance if found
**New behavior**:
1. Check for existing instance with tag `$BASTION_NAME`
2. If exists, prompt user with instance ID
3. If skip chosen, use existing instance and return
4. If proceed chosen:
   - **Warn**: "Proceeding will terminate existing instance and create new one"
   - Require confirmation: "Continue? [y/N]"
   - If yes: Terminate old instance, wait for termination, create new
   - If no: Keep existing instance, return

**Safety**: Double confirmation required before terminating existing instance.

#### Section 4: Add Help/Usage (lines 413-416)
Add environment variables and examples similar to deploy.sh.

**Estimated changes for setup-bastion.sh**: ~200 lines added, ~80 lines modified

---

## Example Interactive Session Flow

```bash
$ ./deploy.sh all

[2025-12-05 10:00:00] Starting LiteLLM infrastructure deployment...
[2025-12-05 10:00:01] Checking prerequisites...
[2025-12-05 10:00:02] Prerequisites check passed
[2025-12-05 10:00:03] Validating YAML files...
[2025-12-05 10:00:05] All YAML files validated successfully
[2025-12-05 10:00:06] Creating IRSA roles...

[2025-12-05 10:00:07] WARN: IAM Role 'litellm-bedrock-role' already exists
    Used for LiteLLM Bedrock access

What would you like to do?
  [S] Skip - Skip this step (recommended if resource is healthy)
  [P] Proceed - Run deployment anyway (may update existing resource)
  [V] View - Show resource details
  [A] Auto - Auto-skip all remaining healthy resources
  [Q] Quit - Exit deployment

Choose [S/p/v/a/q]: a

[2025-12-05 10:00:10] Auto-skip mode enabled for remaining resources
[2025-12-05 10:00:11] Skipping IAM Role: litellm-bedrock-role
[2025-12-05 10:00:12] Skipping IAM Role: external-secrets-role
[2025-12-05 10:00:13] Creating secrets in AWS Secrets Manager...
[2025-12-05 10:00:14] Skipping litellm/master-key (auto-skip enabled)
[2025-12-05 10:00:15] Skipping litellm/redis-password (auto-skip enabled)
...
```

## Edge Cases & Safety Features

### 1. Unhealthy Helm Releases
If release exists but status != "deployed":
- Warn user: "Release exists but is unhealthy"
- Recommend proceeding to fix
- Don't allow skip for critical dependencies (external-secrets, redis)

### 2. Missing Dependencies
Check dependencies before allowing skip:
- Can't skip external-secrets if deploying secret-stores
- Can't skip redis if deploying litellm
- Can't skip litellm if deploying openwebui
- Error with clear message if dependency missing

### 3. Secret Regeneration Risks
When user chooses to proceed on existing secrets:
```
WARN: Proceeding will regenerate the master key
      This will BREAK all existing API keys!

Are you absolutely sure? [y/N]:
```

### 4. kubectl Connection Issues
In `check_prerequisites()`:
- If kubectl not connected, offer to fix
- Run `aws eks update-kubeconfig` interactively
- Recheck connection after fix

### 5. Non-Interactive Mode
When `INTERACTIVE_MODE=false`:
- Auto-skip all existing healthy resources
- Proceed with missing resources
- Error on unhealthy resources with clear message
- Log all decisions for audit trail

## Testing Strategy

### Test Scenarios
1. **Fresh deployment**: No resources exist → No prompts, create everything
2. **Partial deployment**: Some resources exist → Prompt for each existing resource
3. **Full re-deployment**: All healthy → Prompt for all, or use auto-skip mode
4. **Unhealthy resources**: Release exists but failed → Warn and recommend proceeding
5. **Non-interactive mode**: CI/CD simulation → Skip all healthy, error on unhealthy
6. **Dependency validation**: Skip upstream resource → Error when deploying dependent

### Manual Test Commands
```bash
# Test 1: Fresh deployment
./deploy.sh all

# Test 2: Run again (all exist)
./deploy.sh all
# Expected: Prompts for each resource

# Test 3: Auto-skip mode
AUTO_SKIP_HEALTHY=true ./deploy.sh all
# Expected: Single decision, then auto-skip all

# Test 4: Non-interactive
INTERACTIVE_MODE=false ./deploy.sh all
# Expected: No prompts, skip all existing

# Test 5: Individual commands still work
./deploy.sh irsa
./deploy.sh secrets
./deploy.sh litellm
```

## Backward Compatibility

All changes maintain backward compatibility:
- ✅ Default behavior (INTERACTIVE_MODE=true) is safest
- ✅ Individual commands unchanged (./deploy.sh irsa works as before)
- ✅ Existing automation can set INTERACTIVE_MODE=false
- ✅ No breaking changes to function signatures
- ✅ helm upgrade --install remains idempotent

## Success Criteria

- ✅ Users can run `./deploy.sh all` on existing infrastructure without errors
- ✅ Interactive prompts appear for all existing resources
- ✅ Auto-skip mode reduces prompt fatigue for users
- ✅ View option provides useful resource information
- ✅ Dependencies properly validated (can't skip required resources)
- ✅ Non-interactive mode works for CI/CD pipelines
- ✅ All existing modular commands preserved
- ✅ Clear logging of all skip/proceed decisions

## Files to Modify

1. **`scripts/deploy.sh`** (Primary)
   - Add interactive prompt system (~150 lines)
   - Add resource check functions (~120 lines)
   - Modify 7 deployment functions (~150 lines modified)
   - Update help/usage (~30 lines)

2. **`scripts/setup-bastion.sh`** (Secondary)
   - Add interactive prompt system (~100 lines)
   - Modify 2 functions (~80 lines modified)
   - Update help/usage (~20 lines)

## Implementation Order

1. **Phase 1**: Add helper functions to deploy.sh (prompts + checks)
2. **Phase 2**: Modify IAM roles and secrets functions (test basic flow)
3. **Phase 3**: Modify all Helm deployment functions
4. **Phase 4**: Add dependency checking
5. **Phase 5**: Enhance prerequisites checking
6. **Phase 6**: Update help documentation
7. **Phase 7**: Apply same pattern to setup-bastion.sh
8. **Phase 8**: Test all scenarios

## Risk Mitigation

- **Safety First**: Default choice is always Skip (safest)
- **Double Confirmation**: Required for destructive actions (regenerate secrets, terminate instances)
- **Dependency Validation**: Prevent skipping required dependencies
- **Clear Warnings**: Explain consequences before destructive operations
- **Audit Trail**: Log all decisions (skip/proceed) with timestamps
- **Rollback**: Can disable with INTERACTIVE_MODE=false if issues arise

## Future Enhancements (Out of Scope)

- Dry-run mode showing what would be deployed
- Config file for storing skip preferences
- Diff view showing resource changes
- Resource snapshots for rollback
- Parallel deployment of independent components
