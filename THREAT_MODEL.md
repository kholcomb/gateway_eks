# Threat Model: LiteLLM EKS Deployment

## Overview

This document provides a comprehensive threat model for the LiteLLM EKS deployment, analyzing potential security threats, attack vectors, and mitigation strategies.

**Last Updated:** 2025-12-05
**Version:** 1.0
**Scope:** LiteLLM proxy, OpenWebUI, supporting infrastructure (Redis, PostgreSQL, monitoring stack)

---

## System Components

### In-Scope Components
- LiteLLM Proxy (2 replicas)
- OpenWebUI Frontend (1 replica)
- Redis HA Cluster (3 replicas + Sentinel)
- Amazon RDS PostgreSQL
- Prometheus + Grafana + Jaeger (Observability Stack)
- External Secrets Operator
- EC2 Bastion Host
- AWS Bedrock Integration
- AWS Secrets Manager Integration

### Trust Boundaries
1. **External → Bastion**: Users accessing system via SSH/SSM
2. **Bastion → Kubernetes**: kubectl and port-forwarding access
3. **Kubernetes Internal**: Pod-to-pod communication
4. **Kubernetes → AWS Services**: IRSA-authenticated calls to Bedrock, Secrets Manager, RDS
5. **LiteLLM → Bedrock**: API calls to foundation models

---

## Threat Categories (STRIDE Analysis)

### 1. SPOOFING

#### T1.1: Compromised Master Key
**Threat:** Attacker obtains LiteLLM master key and impersonates legitimate users or admins.

**Attack Vector:**
- Master key leaked in logs, code commits, or environment variables
- Stolen from AWS Secrets Manager via compromised IAM credentials
- Social engineering against administrators

**Impact:** HIGH
- Unauthorized API access to all LLM models
- Ability to create/delete users and API keys
- Access to usage analytics and sensitive metadata

**Mitigations:**
- ✅ Master key stored in AWS Secrets Manager (not in code)
- ✅ IRSA used for pod-level authentication (no long-lived credentials)
- ✅ External Secrets Operator syncs secrets securely
- ⚠️ **RECOMMENDED:** Implement key rotation policy for master key
- ⚠️ **RECOMMENDED:** Enable AWS CloudTrail logging for Secrets Manager access
- ⚠️ **RECOMMENDED:** Add alerts for master key retrieval events

#### T1.2: IRSA Role Assumption
**Threat:** Attacker assumes LiteLLM or External Secrets IRSA roles from compromised pod.

**Attack Vector:**
- Container escape or RCE in LiteLLM/ESO pod
- Malicious image deployment via compromised CI/CD
- Exploitation of Kubernetes RBAC misconfiguration

**Impact:** CRITICAL
- Direct access to AWS Bedrock models (cost abuse)
- Access to all secrets in Secrets Manager (`litellm/*`)
- Potential lateral movement to other AWS services

**Mitigations:**
- ✅ IRSA policies scoped to minimum required permissions
- ✅ Bedrock access limited to specific model ARNs
- ✅ Secrets Manager access limited to `litellm/*` prefix
- ⚠️ **RECOMMENDED:** Implement Pod Security Standards (restricted profile)
- ⚠️ **RECOMMENDED:** Enable runtime security monitoring (Falco, GuardDuty)
- ⚠️ **RECOMMENDED:** Use admission controllers (OPA/Gatekeeper) to validate image sources

#### T1.3: Bastion Host Compromise
**Threat:** Attacker gains access to bastion host and impersonates legitimate administrator.

**Attack Vector:**
- Stolen AWS credentials for SSM Session Manager access
- IAM role compromise via metadata service exploitation
- Malicious insider with legitimate SSM access

**Impact:** CRITICAL
- Full kubectl access to EKS cluster
- Ability to port-forward to all services
- Access to cluster secrets and configuration

**Mitigations:**
- ✅ SSM Session Manager (no SSH keys, MFA-capable)
- ✅ IMDSv2 enforced on bastion instance
- ✅ EKS access via IRSA (temporary credentials)
- ⚠️ **RECOMMENDED:** Require MFA for SSM Session Manager access
- ⚠️ **RECOMMENDED:** Implement session logging and monitoring
- ⚠️ **RECOMMENDED:** Use AWS IAM Identity Center with temporary credentials

---

### 2. TAMPERING

#### T2.1: Secrets Manipulation in AWS Secrets Manager
**Threat:** Attacker modifies secrets in AWS Secrets Manager (database URLs, API keys).

**Attack Vector:**
- Compromised AWS IAM credentials with `secretsmanager:PutSecretValue`
- Malicious insider with AWS admin access
- Cross-account role assumption vulnerability

**Impact:** CRITICAL
- Database connection redirection to attacker-controlled PostgreSQL
- LiteLLM configuration takeover via modified master key
- Denial of service via invalid secret values

**Mitigations:**
- ✅ IRSA roles have read-only access to Secrets Manager
- ⚠️ **RECOMMENDED:** Enable AWS Config rules for Secrets Manager changes
- ⚠️ **RECOMMENDED:** Implement CloudWatch alarms for secret modification events
- ⚠️ **RECOMMENDED:** Use AWS Organizations SCPs to restrict secret deletion
- ⚠️ **RECOMMENDED:** Enable secret versioning and backup

#### T2.2: Kubernetes Manifest Tampering
**Threat:** Attacker modifies deployed Kubernetes resources (Deployments, ConfigMaps, Secrets).

**Attack Vector:**
- Compromised kubectl access from bastion
- Kubernetes API server vulnerability
- Malicious user with RBAC permissions

**Impact:** HIGH
- LiteLLM configuration changes (bypass auth, logging)
- Resource limit removal (resource exhaustion)
- Pod replacement with malicious images

**Mitigations:**
- ✅ All services use ClusterIP (no external exposure)
- ✅ RBAC enforced by EKS
- ⚠️ **RECOMMENDED:** Implement Kubernetes audit logging
- ⚠️ **RECOMMENDED:** Use GitOps (ArgoCD/Flux) for declarative deployments
- ⚠️ **RECOMMENDED:** Enable admission webhooks for change validation
- ⚠️ **RECOMMENDED:** Implement RBAC with least privilege per namespace

#### T2.3: Redis Cache Poisoning
**Threat:** Attacker injects malicious data into Redis cache to manipulate LLM responses.

**Attack Vector:**
- Direct Redis access from compromised pod
- Redis protocol exploitation
- Man-in-the-middle attack on Redis connections

**Impact:** MEDIUM
- Serving stale or malicious cached responses
- Bypassing rate limiting mechanisms
- Data leakage via cache timing attacks

**Mitigations:**
- ✅ Redis authentication with password (synced from Secrets Manager)
- ✅ ClusterIP service (no external access)
- ⚠️ **RECOMMENDED:** Implement NetworkPolicy to restrict Redis access to LiteLLM pods only
- ⚠️ **RECOMMENDED:** Enable TLS for Redis connections
- ⚠️ **RECOMMENDED:** Set appropriate cache TTLs (currently 1 hour)
- ⚠️ **RECOMMENDED:** Monitor cache hit rates for anomalies

---

### 3. REPUDIATION

#### T3.1: Lack of Request Audit Trail
**Threat:** Users deny making LLM requests or actions cannot be attributed to specific users.

**Attack Vector:**
- Shared API keys across multiple users
- Insufficient logging of user identity
- Log tampering or deletion

**Impact:** MEDIUM
- Cannot attribute usage costs to specific users/teams
- Compliance violations (data access logging)
- Difficulty investigating security incidents

**Mitigations:**
- ✅ Prometheus metrics track requests by model/user
- ✅ Jaeger distributed tracing for request flows
- ⚠️ **RECOMMENDED:** Enable detailed audit logging in LiteLLM
- ⚠️ **RECOMMENDED:** Implement log aggregation (Loki/CloudWatch Logs)
- ⚠️ **RECOMMENDED:** Enforce unique API keys per user (disable shared keys)
- ⚠️ **RECOMMENDED:** Enable immutable logs (S3 with versioning/object lock)

#### T3.2: Monitoring Data Manipulation
**Threat:** Attacker modifies Prometheus/Grafana data to hide malicious activity.

**Attack Vector:**
- Direct access to Prometheus storage volume
- Grafana admin account compromise
- Tampering with time-series data via API

**Impact:** LOW
- Hiding usage spikes or anomalous behavior
- Masking cost overruns
- Obscuring security events

**Mitigations:**
- ✅ Grafana admin password stored in secret (auto-generated)
- ✅ ClusterIP services (no external access)
- ⚠️ **RECOMMENDED:** Enable Prometheus remote write to immutable storage (S3/Cortex)
- ⚠️ **RECOMMENDED:** Implement separate log analysis pipeline
- ⚠️ **RECOMMENDED:** Configure Grafana RBAC with viewer-only access for most users

---

### 4. INFORMATION DISCLOSURE

#### T4.1: LLM Request/Response Interception
**Threat:** Attacker intercepts sensitive data in LLM requests or responses (PII, secrets, proprietary info).

**Attack Vector:**
- Network sniffing within Kubernetes cluster
- Compromised pod with access to network traffic
- Prometheus metrics exposing request content
- Jaeger traces containing sensitive payloads

**Impact:** CRITICAL
- Exposure of user data, business secrets, PII
- Compliance violations (GDPR, HIPAA)
- Intellectual property theft

**Mitigations:**
- ✅ ClusterIP services (internal traffic only)
- ✅ OpenWebUI → LiteLLM → Bedrock traffic stays within AWS network
- ⚠️ **RECOMMENDED:** Implement NetworkPolicy for pod-to-pod isolation
- ⚠️ **RECOMMENDED:** Enable service mesh with mTLS (Istio/Linkerd)
- ⚠️ **RECOMMENDED:** Sanitize sensitive data from traces/metrics
- ⚠️ **RECOMMENDED:** Implement data loss prevention (DLP) controls
- ⚠️ **RECOMMENDED:** Encrypt etcd at rest (EKS default, verify configuration)

#### T4.2: Secrets Exposure via Logs/Metrics
**Threat:** Secrets inadvertently logged or exposed in Prometheus metrics.

**Attack Vector:**
- Application logs containing secrets
- Environment variables dumped in crash reports
- Kubernetes event logs showing secret values
- Grafana dashboards accessible to unauthorized users

**Impact:** HIGH
- Master key exposure
- Database credentials leak
- Redis password disclosure

**Mitigations:**
- ✅ Secrets mounted as environment variables (not in args)
- ✅ External Secrets Operator manages secret lifecycle
- ⚠️ **RECOMMENDED:** Implement secret scanning in CI/CD (Gitleaks, TruffleHog)
- ⚠️ **RECOMMENDED:** Configure log redaction for sensitive patterns
- ⚠️ **RECOMMENDED:** Regular audit of Grafana dashboards for exposed secrets
- ⚠️ **RECOMMENDED:** Restrict access to pod logs and events via RBAC

#### T4.3: PostgreSQL Database Breach
**Threat:** Attacker gains unauthorized access to RDS PostgreSQL containing user data, API keys, usage history.

**Attack Vector:**
- SQL injection in LiteLLM queries
- Stolen database credentials from Secrets Manager
- RDS publicly accessible (misconfiguration)
- Unpatched PostgreSQL vulnerability

**Impact:** CRITICAL
- Complete user data breach
- API key theft (hashed but vulnerable to offline attacks)
- Usage pattern analysis for competitive intelligence

**Mitigations:**
- ✅ Database URL stored in AWS Secrets Manager
- ✅ External Secrets Operator provides credentials to LiteLLM
- ⚠️ **RECOMMENDED:** Ensure RDS is in private subnet (not publicly accessible)
- ⚠️ **RECOMMENDED:** Enable RDS encryption at rest
- ⚠️ **RECOMMENDED:** Use IAM database authentication instead of passwords
- ⚠️ **RECOMMENDED:** Implement database activity monitoring (RDS Enhanced Monitoring)
- ⚠️ **RECOMMENDED:** Regular security patching of RDS PostgreSQL
- ⚠️ **RECOMMENDED:** Parameterized queries to prevent SQL injection

#### T4.4: Grafana Dashboard Data Exposure
**Threat:** Unauthorized users view sensitive operational metrics or usage patterns.

**Attack Vector:**
- Default Grafana admin credentials
- Anonymous access enabled
- Overly permissive Grafana RBAC
- Port-forwarding access from bastion

**Impact:** MEDIUM
- Competitive intelligence (usage patterns, costs)
- Reconnaissance for targeted attacks
- Privacy violations (user activity visibility)

**Mitigations:**
- ✅ Grafana admin password auto-generated and stored in secret
- ✅ ClusterIP service (bastion-only access)
- ⚠️ **RECOMMENDED:** Disable anonymous access
- ⚠️ **RECOMMENDED:** Implement Grafana RBAC with team-based access
- ⚠️ **RECOMMENDED:** Audit dashboard permissions regularly
- ⚠️ **RECOMMENDED:** Consider OAuth/OIDC integration for authentication

---

### 5. DENIAL OF SERVICE

#### T5.1: API Rate Limit Bypass
**Threat:** Attacker bypasses rate limiting to cause cost overruns or service degradation.

**Attack Vector:**
- Multiple API keys from different accounts
- Exploiting rate limit configuration errors
- Redis cache unavailability (rate limiting fails open)
- Direct Bedrock access bypassing LiteLLM

**Impact:** HIGH
- Massive AWS Bedrock costs (per-token pricing)
- Service unavailability for legitimate users
- Resource exhaustion (memory, CPU)

**Mitigations:**
- ✅ Redis HA with 3 replicas and Sentinel (rate limiting backend)
- ✅ Resource limits on all pods (CPU/memory)
- ✅ PodDisruptionBudgets for critical services
- ⚠️ **RECOMMENDED:** Configure rate limits per API key and per model
- ⚠️ **RECOMMENDED:** Implement budget alerts in AWS Bedrock
- ⚠️ **RECOMMENDED:** Add LiteLLM fallback behavior when Redis unavailable
- ⚠️ **RECOMMENDED:** Implement Horizontal Pod Autoscaler (HPA) for LiteLLM

#### T5.2: Resource Exhaustion via Large Requests
**Threat:** Attacker sends extremely large prompts or requests long outputs to exhaust resources.

**Attack Vector:**
- Maximum token limits not enforced
- Large file uploads in prompts
- Streaming requests held open indefinitely
- Memory leaks in LiteLLM processing

**Impact:** MEDIUM
- Pod OOM kills and service restarts
- Increased latency for legitimate users
- Cost overruns from large token consumption

**Mitigations:**
- ✅ Request size limit: 50MB configured in LiteLLM
- ✅ Max tokens configured per model (2048-8192)
- ✅ Resource limits prevent unbounded memory usage
- ⚠️ **RECOMMENDED:** Implement timeout for long-running requests
- ⚠️ **RECOMMENDED:** Monitor memory usage and set alerts
- ⚠️ **RECOMMENDED:** Implement streaming request timeouts

#### T5.3: Redis HA Failure
**Threat:** Redis cluster failure causes rate limiting and caching to fail, degrading LiteLLM performance.

**Attack Vector:**
- All 3 Redis replicas crash simultaneously
- Sentinel quorum failure
- Persistent volume corruption
- Resource exhaustion on Redis pods

**Impact:** HIGH
- No caching (increased latency and Bedrock costs)
- Rate limiting disabled (abuse potential)
- Session management failures

**Mitigations:**
- ✅ Redis HA with 3 replicas and Sentinel (quorum=2)
- ✅ Hard pod anti-affinity (replicas on different nodes)
- ✅ PodDisruptionBudget: maxUnavailable=1
- ✅ Persistent storage (8Gi gp3 per replica)
- ⚠️ **RECOMMENDED:** Implement Redis backups to S3
- ⚠️ **RECOMMENDED:** Monitor Redis metrics (latency, memory, connections)
- ⚠️ **RECOMMENDED:** Test failover scenarios regularly
- ⚠️ **RECOMMENDED:** Configure LiteLLM graceful degradation without Redis

#### T5.4: EKS Node Failure
**Threat:** Worker node failures impact service availability.

**Attack Vector:**
- EC2 instance hardware failure
- Auto-scaling group misconfiguration
- Insufficient cluster capacity
- AZ-wide outage

**Impact:** MEDIUM
- Service degradation if pods cannot reschedule
- Potential data loss if persistent volumes affected
- Cascading failures due to resource constraints

**Mitigations:**
- ✅ Pod anti-affinity spreads replicas across nodes
- ✅ PodDisruptionBudgets prevent simultaneous evictions
- ✅ Readiness/liveness probes for automatic recovery
- ⚠️ **RECOMMENDED:** Multi-AZ node groups in EKS
- ⚠️ **RECOMMENDED:** Cluster autoscaler for automatic capacity scaling
- ⚠️ **RECOMMENDED:** Regular backup of persistent volumes
- ⚠️ **RECOMMENDED:** Node monitoring and auto-replacement

---

### 6. ELEVATION OF PRIVILEGE

#### T6.1: Container Escape
**Threat:** Attacker escapes container to gain node-level access.

**Attack Vector:**
- Kernel vulnerability exploitation
- Privileged container misconfiguration
- Docker/containerd vulnerability
- Volume mount exploitation

**Impact:** CRITICAL
- Access to all pods on the same node
- Kubernetes node compromise
- Lateral movement to other nodes
- Access to instance metadata (IRSA credentials)

**Mitigations:**
- ✅ Non-root containers configured (Redis, OpenWebUI)
- ✅ IMDSv2 enforced (hop limit prevents SSRF to metadata)
- ⚠️ **RECOMMENDED:** Implement Pod Security Standards (restricted profile)
- ⚠️ **RECOMMENDED:** Disable privileged containers via admission controller
- ⚠️ **RECOMMENDED:** Use minimal base images (distroless, Alpine)
- ⚠️ **RECOMMENDED:** Enable seccomp and AppArmor profiles
- ⚠️ **RECOMMENDED:** Regular kernel and container runtime patching
- ⚠️ **RECOMMENDED:** Runtime security monitoring (Falco)

#### T6.2: Kubernetes RBAC Bypass
**Threat:** Attacker escalates from limited pod access to cluster-admin privileges.

**Attack Vector:**
- Overly permissive ServiceAccount permissions
- Misconfigured RoleBindings/ClusterRoleBindings
- Kubernetes API server vulnerability
- Exploiting default service account

**Impact:** CRITICAL
- Full cluster control
- Access to all secrets and configurations
- Ability to deploy malicious workloads
- Data exfiltration across namespaces

**Mitigations:**
- ✅ Namespace isolation (4 separate namespaces)
- ✅ IRSA service accounts with scoped AWS permissions
- ⚠️ **RECOMMENDED:** Disable default service account auto-mount
- ⚠️ **RECOMMENDED:** Implement least-privilege RBAC per namespace
- ⚠️ **RECOMMENDED:** Regular RBAC audit (rbac-tool, kubectl-who-can)
- ⚠️ **RECOMMENDED:** Enable Kubernetes audit logging
- ⚠️ **RECOMMENDED:** Use admission controllers to enforce RBAC policies

#### T6.3: Supply Chain Attack via Malicious Images
**Threat:** Compromised container images introduce backdoors or vulnerabilities.

**Attack Vector:**
- Malicious public Helm chart repositories
- Compromised base images (Alpine, Ubuntu)
- Typosquatting on Docker Hub
- CI/CD pipeline compromise

**Impact:** CRITICAL
- Arbitrary code execution in cluster
- Credential theft (IRSA tokens, secrets)
- Data exfiltration
- Persistent backdoor access

**Mitigations:**
- ✅ Using official Helm charts from trusted repos
- ✅ Pinned image versions (e.g., `litellm:1.80.5-stable`)
- ⚠️ **RECOMMENDED:** Image scanning in CI/CD (Trivy, Snyk)
- ⚠️ **RECOMMENDED:** Enforce image signature verification (Sigstore/Cosign)
- ⚠️ **RECOMMENDED:** Use private container registry with vulnerability scanning
- ⚠️ **RECOMMENDED:** Admission controller to block unverified images
- ⚠️ **RECOMMENDED:** Regular Dependabot updates (already configured)
- ⚠️ **RECOMMENDED:** SBOM generation and tracking

---

## High-Priority Recommendations

### Critical (Implement Immediately)
1. **NetworkPolicy Implementation**: Isolate pods to prevent lateral movement
2. **Pod Security Standards**: Enforce restricted profile cluster-wide
3. **MFA for Bastion Access**: Require MFA for SSM Session Manager
4. **RDS Security Review**: Verify private subnet placement, encryption, IAM auth
5. **Image Scanning**: Implement automated vulnerability scanning for all images

### High (Implement Within 30 Days)
1. **Secrets Rotation**: Implement master key and Redis password rotation
2. **Service Mesh with mTLS**: Deploy Istio/Linkerd for encrypted pod-to-pod traffic
3. **Audit Logging**: Enable Kubernetes and AWS CloudTrail audit logs
4. **Runtime Security**: Deploy Falco or similar for threat detection
5. **GitOps**: Implement ArgoCD/Flux for declarative, auditable deployments

### Medium (Implement Within 90 Days)
1. **Log Aggregation**: Deploy Loki or CloudWatch Logs for centralized logging
2. **Secret Scanning**: Integrate Gitleaks/TruffleHog in CI/CD
3. **Cost Controls**: Implement AWS Budgets and Bedrock usage quotas
4. **Disaster Recovery**: Document and test backup/restore procedures
5. **Penetration Testing**: Conduct security assessment of entire stack

---

## Threat Summary Matrix

| Threat ID | Category | Impact | Likelihood | Risk | Status |
|-----------|----------|--------|------------|------|--------|
| T1.1 | Spoofing | HIGH | MEDIUM | HIGH | Partial Mitigation |
| T1.2 | Spoofing | CRITICAL | LOW | HIGH | Partial Mitigation |
| T1.3 | Spoofing | CRITICAL | LOW | MEDIUM | Partial Mitigation |
| T2.1 | Tampering | CRITICAL | LOW | MEDIUM | Partial Mitigation |
| T2.2 | Tampering | HIGH | MEDIUM | HIGH | Partial Mitigation |
| T2.3 | Tampering | MEDIUM | LOW | LOW | Partial Mitigation |
| T3.1 | Repudiation | MEDIUM | MEDIUM | MEDIUM | Minimal Mitigation |
| T3.2 | Repudiation | LOW | LOW | LOW | Partial Mitigation |
| T4.1 | Info Disclosure | CRITICAL | MEDIUM | CRITICAL | Partial Mitigation |
| T4.2 | Info Disclosure | HIGH | MEDIUM | HIGH | Minimal Mitigation |
| T4.3 | Info Disclosure | CRITICAL | LOW | MEDIUM | Partial Mitigation |
| T4.4 | Info Disclosure | MEDIUM | MEDIUM | MEDIUM | Partial Mitigation |
| T5.1 | Denial of Service | HIGH | HIGH | HIGH | Partial Mitigation |
| T5.2 | Denial of Service | MEDIUM | MEDIUM | MEDIUM | Partial Mitigation |
| T5.3 | Denial of Service | HIGH | LOW | MEDIUM | Good Mitigation |
| T5.4 | Denial of Service | MEDIUM | MEDIUM | MEDIUM | Partial Mitigation |
| T6.1 | Privilege Escalation | CRITICAL | LOW | MEDIUM | Partial Mitigation |
| T6.2 | Privilege Escalation | CRITICAL | LOW | MEDIUM | Partial Mitigation |
| T6.3 | Privilege Escalation | CRITICAL | MEDIUM | HIGH | Partial Mitigation |

**Risk Calculation:** Risk = Impact × Likelihood
