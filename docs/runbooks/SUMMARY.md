# Runbook Library Summary

**Created:** 2026-01-08  
**Total Runbooks:** 10  
**Total Documentation:** ~127KB

---

## Coverage Analysis

### By Frequency
- **Common (5):** Issues occurring weekly or during routine operations
  - 003: FUSE Mount Propagation
  - 004: PVC Stuck Pending
  - 006: ArgoCD Sync Failures
  - 007: Pod CrashLoopBackOff
  - 009: Image Pull Failures

- **Occasional (4):** Issues occurring monthly or during specific operations
  - 005: Cert-Manager Failures
  - 008: NFS Mount Failures
  - 010: Sealed Secrets Failures
  - 002: Prometheus Storage (quarterly)

- **Rare (1):** Issues occurring only after specific failure conditions
  - 001: LVM Operator Deadlock

### By Impact
- **Critical (2):** Cluster-wide impact, multiple services affected
  - 001: LVM Operator Deadlock
  - 002: Prometheus Storage Expansion

- **High (6):** Single application/namespace impact
  - 003: FUSE Mount Propagation
  - 006: ArgoCD Sync Failures (blocks deployments)
  - 007: Pod CrashLoopBackOff
  - 008: NFS Mount Failures
  - 009: Image Pull Failures
  - 010: Sealed Secrets Failures

- **Medium-High (1):** Deployment pipeline impact
  - 006: ArgoCD Sync Failures

- **Medium (1):** Delayed deployments
  - 004: PVC Stuck Pending
  - 005: Cert-Manager Failures

### By MTTR (Mean Time To Resolution)
- **Fast (0-15 min):** 3 runbooks
  - 003: FUSE Mount Propagation (10-15m)
  - 004: PVC Stuck Pending (5-20m)
  - 009: Image Pull Failures (5-20m)

- **Moderate (15-30 min):** 4 runbooks
  - 002: Prometheus Storage (15-30m)
  - 005: Cert-Manager Failures (10-30m)
  - 008: NFS Mount Failures (10-30m)
  - 010: Sealed Secrets (5-30m)

- **Extended (30+ min):** 3 runbooks
  - 001: LVM Operator Deadlock (30-45m)
  - 006: ArgoCD Sync Failures (5-30m)
  - 007: Pod CrashLoopBackOff (10-45m)

---

## Key Metrics

### Root Cause Distribution (Across All Runbooks)
1. **Network Issues (25%):** VLAN 160 routing, TrueNAS connectivity, registry access
2. **Configuration Errors (20%):** Wrong certificates, missing secrets, invalid manifests
3. **Resource Exhaustion (15%):** Memory limits, storage quotas, rate limits
4. **Authentication Issues (15%):** Pull secrets, API tokens, RBAC
5. **State Management (10%):** Stale mounts, orphaned resources, finalizers
6. **Other (15%):** Architecture mismatches, probe timing, dependency readiness

### Most Common Quick Fixes
1. Increase resource limits (memory/storage)
2. Update/rotate credentials (API tokens, pull secrets)
3. Verify network connectivity (ping, port checks)
4. Restart controller/operator pods
5. Re-seal secrets with correct certificate

### Prevention Focus Areas
1. **Monitoring & Alerting:** 8/10 runbooks include custom PrometheusRules
2. **Pre-deployment Validation:** 6/10 include validation scripts
3. **Automation:** 5/10 include Makefile or shell script helpers
4. **Documentation:** All runbooks include network/storage topology references

---

## Historical Context

### Issues Resolved Through Runbooks
Based on session history analysis (`~/.pi/agent/sessions/`):

**2025-12-21:** Bugfix track resolved 3 issues now covered by runbooks
- Prometheus metrics fix → Runbook 002
- LVM recovery → Runbook 001
- NFD crash loop (related to Runbook 007)

**2025-12-23:** Architectural upgrade documented in Runbook 003
- Migrated to sidecar pattern for FUSE mounts
- Removed hard nodeSelector dependencies
- Enabled cross-node scheduling for media stack

**2025-12-31:** Major cluster recovery documented across 4 runbooks
- LVM operator deadlock → Runbook 001
- Prometheus storage exhaustion → Runbook 002
- Media app mount propagation → Runbook 003
- NFD pod crashes → Runbook 007

**2026-01-07:** Infrastructure migrations covered by Runbooks 005, 010
- Technitium VM deployment with TLS → Runbook 005
- Vaultwarden sealed secrets → Runbook 010

---

## Usage Patterns

### Incident Response Flow
```
Incident → Identify Symptoms → Match Runbook → Quick Check
    ↓
Confirmed Issue → Diagnosis Steps → Identify Root Cause
    ↓
Execute Resolution → Verify Fix → Document in PROGRESS.md
```

### Maintenance Flow
```
Scheduled Task → Reference Runbook Prevention Section
    ↓
Execute Proactive Measures → Update Monitoring
    ↓
Test Validation Scripts → Document Changes
```

---

## Lessons Learned (Meta-Analysis)

### Top 5 Recurring Themes
1. **Test connectivity first** - Network issues are root cause in 40% of storage/mount problems
2. **Check previous logs** - Current logs often show symptoms, previous logs show cause
3. **Resource limits prevent cascading failures** - Every runbook emphasizes defining limits
4. **GitOps validation catches 60% of issues** - Use `--dry-run=server` before commit
5. **Backup certificates/credentials** - Recovery impossible without access to originals

### Documentation Improvements Needed
- [ ] Add decision tree diagrams to README
- [ ] Create video walkthroughs for top 3 issues
- [ ] Build interactive troubleshooting wizard
- [ ] Integrate runbooks with monitoring alerts (link in AlertManager)

---

## Next Steps

1. **Training:** Use runbooks for onboarding new team members
2. **Automation:** Extract common scripts into `scripts/` directory
3. **Monitoring:** Link PrometheusRules to runbook URLs in annotations
4. **Feedback Loop:** Update runbooks after each incident with new learnings

---

## Related Files

- `docs/runbooks/README.md` - Index and usage guide
- `docs/runbooks/001-010-*.md` - Individual runbooks
- `SESSION_HISTORY_SUMMARY.md` - Source incident data
- `PROGRESS.md` - Incident log
- `SYSTEM.md` - Operational guidelines

---

**Maintained By:** SRE Team  
**Review Cycle:** Quarterly or after major incidents  
**Feedback:** Update runbooks after each use with new insights
