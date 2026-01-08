# OpenShift Homelab Runbooks

**Version:** 1.0  
**Last Updated:** 2026-01-08  
**Cluster:** OpenShift 4.20 (wow-ocp)

---

## Overview

This directory contains operational runbooks for the top 10 most critical and frequent issues encountered in our OpenShift 4.20 homelab environment. Each runbook follows a standardized format with symptoms, diagnosis steps, resolution procedures, and prevention strategies.

---

## Quick Reference

| ID | Runbook | Frequency | Impact | Avg MTTR |
|----|---------|-----------|--------|----------|
| [001](001-lvm-operator-deadlock-recovery.md) | LVM Operator Deadlock Recovery | Rare | Critical | 30-45m |
| [002](002-prometheus-storage-expansion.md) | Prometheus Storage Expansion | Quarterly | Critical | 15-30m |
| [003](003-fuse-mount-propagation-media-apps.md) | FUSE Mount Propagation (Media Apps) | Common | High | 10-15m |
| [004](004-pvc-stuck-pending.md) | PVC Stuck in Pending | Common | Medium | 5-20m |
| [005](005-cert-manager-certificate-failures.md) | Cert-Manager Certificate Failures | Occasional | Medium | 10-30m |
| [006](006-argocd-sync-failures.md) | ArgoCD Application Sync Failures | Common | Med-High | 5-30m |
| [007](007-pod-crashloopbackoff.md) | Pod CrashLoopBackOff | Common | High | 10-45m |
| [008](008-nfs-mount-failures.md) | NFS Mount Failures (TrueNAS) | Occasional | High | 10-30m |
| [009](009-image-pull-failures.md) | Image Pull Failures (Docker Hub) | Common | High | 5-20m |
| [010](010-sealed-secrets-failures.md) | Sealed Secrets Decryption Failures | Occasional | High | 5-30m |

---

## Runbook Format

Each runbook follows this structure:

1. **Header**
   - Frequency: How often this issue occurs
   - Impact: Severity of the issue
   - Last Occurred: Most recent incident
   - MTTR: Mean Time To Resolution

2. **Symptoms**
   - Observable indicators of the problem
   - Quick check commands

3. **Root Cause Analysis**
   - Common causes ranked by frequency
   - Technical explanations

4. **Diagnosis Steps**
   - Step-by-step investigation procedures
   - Commands and expected outputs

5. **Resolution**
   - Detailed fix procedures for each root cause
   - Code examples and commands

6. **Prevention**
   - Proactive measures to avoid recurrence
   - Monitoring and alerting configurations

7. **Troubleshooting**
   - Common pitfalls and edge cases
   - Decision trees

8. **Related Issues**
   - Cross-references to related runbooks
   - Historical context

9. **Lessons Learned**
   - Key takeaways from past incidents
   - Best practices

10. **Verification Checklist**
    - Post-resolution validation steps

---

## Usage Guidelines

### When to Use a Runbook

1. **Active Incident:** Follow diagnosis steps sequentially
2. **Preventive Maintenance:** Review prevention sections quarterly
3. **Knowledge Transfer:** Use for onboarding or training
4. **Post-Mortem:** Reference lessons learned

### How to Use a Runbook

```bash
# 1. Identify the issue
oc get pods -A | grep -v Running

# 2. Find the matching runbook from symptoms
cat docs/runbooks/README.md

# 3. Follow diagnosis steps
# Start with Quick Check, then move to detailed diagnosis

# 4. Execute resolution
# Always test in dev/staging first if possible

# 5. Verify fix
# Use verification checklist at end of runbook

# 6. Document
# Update PROGRESS.md with incident summary
```

---

## Incident Response Flow

```
Incident Detected
    │
    ├─ Identify Symptoms
    │   └─ Match to Runbook Quick Reference
    │
    ├─ Execute Quick Check
    │   ├─ Issue confirmed → Continue
    │   └─ Issue not found → Check other runbooks
    │
    ├─ Run Diagnosis Steps
    │   └─ Identify Root Cause
    │
    ├─ Execute Resolution
    │   ├─ Test fix
    │   └─ Verify with checklist
    │
    └─ Post-Incident
        ├─ Update PROGRESS.md
        ├─ Review lessons learned
        └─ Implement prevention measures
```

---

## Runbook Summaries

### 001: LVM Operator Deadlock Recovery
**Problem:** LVM Volume Groups won't initialize due to stale metadata  
**Common Cause:** Failed initialization attempts leave orphaned thin pools  
**Quick Fix:** Manually clean LVM metadata on nodes, operator will reinitialize  
**Key Learning:** Use hardware-specific `by-path` device IDs with `optionalPaths`

### 002: Prometheus Storage Expansion
**Problem:** Prometheus crashes with "disk quota exceeded"  
**Common Cause:** 20Gi PVC too small for cluster with 200+ scrape targets  
**Quick Fix:** Edit PVC to increase size, restart pod to trigger resize  
**Key Learning:** Monitor PVC usage monthly, 20Gi insufficient for >1 node

### 003: FUSE Mount Propagation (Media Apps)
**Problem:** Media apps can't see rclone mounts from standalone pods  
**Common Cause:** FUSE namespace isolation prevents cross-pod mount visibility  
**Quick Fix:** Use sidecar pattern with `mountPropagation: Bidirectional`  
**Key Learning:** Never use standalone mount pods, always use sidecars

### 004: PVC Stuck in Pending
**Problem:** PVC remains `Pending`, pod can't start  
**Common Cause:** Network connectivity to TrueNAS or CSI driver issues  
**Quick Fix:** Check network to 172.16.160.100, verify CSI driver running  
**Key Learning:** 40% of PVC issues are network-related, test connectivity first

### 005: Cert-Manager Certificate Failures
**Problem:** Certificate issuance fails, apps show "Not Trusted"  
**Common Cause:** Cloudflare API token invalid/expired or DNS-01 challenge failure  
**Quick Fix:** Update API token in sealed secret, restart cert-manager  
**Key Learning:** Use wildcard certs to reduce per-app certificate management

### 006: ArgoCD Sync Failures
**Problem:** Application shows `OutOfSync`, changes not applying  
**Common Cause:** Resource already exists with different owner  
**Quick Fix:** Add ArgoCD labels to adopt resource or delete and recreate  
**Key Learning:** Validate manifests locally with `--dry-run=server` before commit

### 007: Pod CrashLoopBackOff
**Problem:** Pod continuously restarts, application unavailable  
**Common Cause:** OOMKilled (35%), missing env vars (25%), or liveness probe issues (15%)  
**Quick Fix:** Check `--previous` logs, increase memory limits if OOM  
**Key Learning:** Always check previous container logs to see what caused crash

### 008: NFS Mount Failures (TrueNAS)
**Problem:** Pod stuck in `ContainerCreating`, mount timeout  
**Common Cause:** Network connectivity to TrueNAS on VLAN 160  
**Quick Fix:** Verify ping and NFS port (2049) reachable from node  
**Key Learning:** Node 4 uses VLAN trunk, requires NNCP for VLAN 160 interface

### 009: Image Pull Failures
**Problem:** Pod shows `ImagePullBackOff`, Docker Hub rate limit  
**Common Cause:** Rate limit exceeded (100 pulls per 6h anonymous)  
**Quick Fix:** Add Docker Hub credentials to global pull secret  
**Key Learning:** Always authenticate to Docker Hub, even for public images

### 010: Sealed Secrets Failures
**Problem:** SealedSecret exists but regular Secret not created  
**Common Cause:** Wrong public certificate used for sealing  
**Quick Fix:** Fetch current cert from cluster, re-seal secret  
**Key Learning:** Always fetch cert from cluster, don't trust local copy

---

## Common Troubleshooting Commands

### Quick Status Checks
```bash
# Cluster health overview
oc get nodes
oc get pods -A | grep -v Running
oc adm top nodes

# Storage status
oc get pvc -A | grep -v Bound
oc get pv | grep -v Bound

# ArgoCD sync status
argocd app list | grep -v Synced

# Recent events (cluster-wide)
oc get events -A --sort-by='.lastTimestamp' | tail -n 20
```

### Deep Dive Commands
```bash
# Pod troubleshooting
oc describe pod <pod-name> -n <namespace>
oc logs <pod-name> -n <namespace> --previous
oc logs <pod-name> -n <namespace> --all-containers=true

# Node debugging
oc debug node/<node-name>
# Inside debug pod: chroot /host

# Network testing from pod
oc run test-pod --rm -i --tty --image=nicolaka/netshoot -- /bin/bash
# Inside pod: ping, curl, nslookup, etc.
```

### GitOps Validation
```bash
# Validate manifest before commit
oc apply -f <manifest>.yaml --dry-run=server

# Validate Kustomize build
kustomize build apps/<app-name>/base | oc apply --dry-run=server -f -

# Check ArgoCD diff
argocd app diff <app-name>
```

---

## Maintenance Schedule

| Task | Frequency | Runbook Reference |
|------|-----------|-------------------|
| Check Prometheus storage usage | Monthly | 002 |
| Review Docker Hub rate limit | Weekly | 009 |
| Backup Sealed Secrets cert | Monthly | 010 |
| Test storage network connectivity | Quarterly | 008 |
| Review ArgoCD sync errors | Weekly | 006 |
| Capacity planning (CPU/RAM/Storage) | Quarterly | 001, 002 |

---

## Escalation Paths

### Level 1: Runbook Self-Service
- Follow runbook diagnosis and resolution steps
- Use quick check commands
- Check troubleshooting section for edge cases

### Level 2: Extended Investigation
- Review related issues and lessons learned
- Check session history: `~/.pi/agent/sessions/`
- Search PROGRESS.md for similar past incidents

### Level 3: Upstream Support
- Red Hat Support (OpenShift issues)
- Democratic-CSI GitHub (storage issues)
- ArgoCD Slack (GitOps issues)
- Community forums (general Kubernetes)

---

## Contributing

### When to Create a New Runbook

1. Issue occurs 3+ times in 30 days
2. MTTR exceeds 1 hour without documentation
3. Issue causes customer impact (in homelab context: services down)
4. Complex diagnosis requires multiple team members

### Runbook Template

See any existing runbook for format. Key sections:
- Clear symptoms and quick checks
- Prioritized root causes with percentages
- Step-by-step diagnosis commands
- Multiple resolution options
- Prevention measures
- Lessons learned

### Update Process

1. After resolving incident, update relevant runbook
2. Add new lessons learned
3. Update frequency/last occurred dates
4. Commit with: `docs: update runbook XXX with new learnings`

---

## Related Documentation

- **Project Progress:** `PROGRESS.md` (incident log)
- **System Architecture:** `SYSTEM.md` (operational guidelines)
- **Agent Context:** `AGENTS.md` (AI assistant directives)
- **Session History:** `SESSION_HISTORY_SUMMARY.md` (past incidents)
- **Infrastructure:** `infrastructure/` (manifest repositories)

---

## Version History

- **v1.0** (2026-01-08): Initial runbook collection covering top 10 critical issues

---

## Feedback

These runbooks are living documents. If you encounter:
- Missing information
- Outdated commands
- New edge cases
- Better resolution procedures

Update the runbook and commit changes with clear descriptions.

**Goal:** Every incident should improve our runbooks.

---

**Document Maintained By:** SRE Team  
**Review Cycle:** Quarterly or after major incidents
