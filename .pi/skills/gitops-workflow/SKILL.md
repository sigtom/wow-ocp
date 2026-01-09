---
name: gitops-workflow
description: Enforce GitOps-first workflow for all cluster changes using Git and ArgoCD. Create feature branches, validate manifests, commit with conventional commits, create PRs, verify ArgoCD sync, and update PROGRESS.md. Use for all cluster changes - Git is source of truth, manual oc apply is for emergencies only.
---

# GitOps Workflow Skill

**Purpose**: Enforce GitOps-first workflow for all cluster changes. Git is the source of truth. Manual `oc apply` is for emergencies only.

**When to use**:
- Creating new applications or infrastructure
- Modifying existing manifests
- Deploying features, fixes, or configuration changes
- Every time you touch the cluster (except break-glass emergencies)

## Prerequisites

### Git Repository
- Clone: `git clone git@github.com:sigtom/wow-ocp.git` (or your fork)
- Working directory: `~/wow-ocp/`
- Main branch: `main` (protected, requires PR)

### Tools Required
- `git` (obviously)
- `oc` (OpenShift CLI)
- `argocd` CLI (for sync verification)
- `yamllint` (YAML validation)
- `kustomize` (manifest building)
- `kubeseal` (sealed secrets)

### ArgoCD Access
- URL: https://openshift-gitops-server-openshift-gitops.apps.ossus.sigtomtech.com
- Login: `argocd login openshift-gitops-server-openshift-gitops.apps.ossus.sigtomtech.com`
- Verify: `argocd app list`

## The Prime Directive: GitOps First

> **"Manual `oc apply` is Evil"**
> 
> If you run `oc apply -f manifest.yaml` manually, ArgoCD will **revert your change** on the next sync.
> 
> The ONLY exceptions:
> - Day 0 cluster bootstrap (before ArgoCD exists)
> - Break-glass emergencies (with documented rollback plan)
> - Testing in a scratch namespace (not managed by ArgoCD)

**Why this rule exists:**
- Git is source of truth (what's in Git = what's in cluster)
- Manual changes create drift and confusion
- ArgoCD provides automated rollback and audit trail
- Reproducible deployments (disaster recovery, staging environments)

---

## Workflows

### 1. Create Feature Branch for New Work

**Purpose**: Isolate changes in a branch before merging to main.

**Steps:**

1. **Ensure main is up-to-date:**
   ```bash
   cd ~/wow-ocp
   git checkout main
   git pull origin main
   ```

2. **Create feature branch:**
   ```bash
   # Option A: Use helper script
   ./scripts/new-branch.sh feature my-new-feature
   
   # Option B: Manual
   git checkout -b feature/my-new-feature
   ```

3. **Verify branch:**
   ```bash
   git branch --show-current
   # Should show: feature/my-new-feature
   ```

**Branch naming conventions:**
- `feature/<name>` - New features or applications
- `fix/<name>` - Bug fixes or issue resolution
- `docs/<name>` - Documentation changes
- `refactor/<name>` - Code restructuring without functional changes

**Examples:**
```bash
./scripts/new-branch.sh feature add-prometheus-alerts
./scripts/new-branch.sh fix sonarr-pvc-permissions
./scripts/new-branch.sh docs update-media-stack-readme
```

---

### 2. Commit Changes with Conventional Commits

**Purpose**: Standardized commit messages for clear history and automated changelog generation.

**Conventional Commit Format:**
```
<type>: <short description>

<optional detailed body>

<optional footer>
```

**Types:**
- `feat:` - New feature or application
- `fix:` - Bug fix or issue resolution
- `docs:` - Documentation changes
- `refactor:` - Code restructuring
- `chore:` - Maintenance tasks (dependency updates, cleanup)
- `ci:` - CI/CD pipeline changes
- `test:` - Test additions or modifications

**Steps:**

1. **Make your changes:**
   ```bash
   # Example: Add new Sonarr deployment
   vim apps/sonarr/base/deployment.yaml
   vim apps/sonarr/base/kustomization.yaml
   ```

2. **Stage changes:**
   ```bash
   git add apps/sonarr/
   ```

3. **Commit with conventional format:**
   ```bash
   # Option A: Use helper script (validates commit message)
   ./scripts/commit.sh feat "add Sonarr deployment with rclone sidecar"
   
   # Option B: Manual
   git commit -m "feat: add Sonarr deployment with rclone sidecar"
   ```

4. **Detailed commit (with body):**
   ```bash
   git commit -m "feat: add Sonarr deployment with rclone sidecar" \
              -m "Includes persistent storage, resource limits, and network policies." \
              -m "Refs: #42"
   ```

**Examples:**
```bash
# New application
git commit -m "feat: deploy Technitium DNS with persistent NFS storage"

# Bug fix
git commit -m "fix: correct Plex PVC mount path in deployment"

# Documentation
git commit -m "docs: update media-stack README with TorBox configuration"

# Refactor
git commit -m "refactor: consolidate rclone sidecar into shared ConfigMap"

# Chore
git commit -m "chore: bump Prometheus operator to v0.68.0"
```

**Bad examples (avoid):**
```bash
# Too vague
git commit -m "update stuff"

# Not conventional
git commit -m "Updated Sonarr deployment"

# No context
git commit -m "fix"
```

---

### 3. Validate Manifests Before Commit

**Purpose**: Catch errors early before they break the cluster or cause ArgoCD sync failures.

**Validation Checklist:**
- ✅ YAML syntax is valid
- ✅ Kustomize builds successfully
- ✅ Resources have requests/limits
- ✅ No raw secrets (only SealedSecrets)
- ✅ Ingress uses correct annotations
- ✅ Dry-run passes on cluster

**Steps:**

1. **Run validation script:**
   ```bash
   # Validate specific path
   ./scripts/validate.sh apps/sonarr/base
   
   # Validate entire apps directory
   ./scripts/validate.sh apps/
   
   # Validate all manifests
   ./scripts/validate.sh
   ```

2. **Manual validation (if script unavailable):**

   **YAML Syntax:**
   ```bash
   yamllint apps/sonarr/base/*.yaml
   ```

   **Kustomize Build:**
   ```bash
   cd apps/sonarr/base
   kustomize build .
   # Should output valid YAML without errors
   ```

   **Dry-Run:**
   ```bash
   kustomize build apps/sonarr/base | oc apply --dry-run=client -f -
   # Should show "created (dry run)" without errors
   ```

3. **Fix any errors:**
   - YAML syntax: Check indentation, quotes, colons
   - Kustomize errors: Verify `kustomization.yaml` references
   - Dry-run errors: Check API versions, required fields

4. **Commit only after validation passes:**
   ```bash
   ./scripts/validate.sh apps/sonarr/base && \
   git add apps/sonarr/ && \
   ./scripts/commit.sh feat "add Sonarr deployment"
   ```

**Common Validation Errors:**

**Missing resource limits:**
```yaml
# BAD - will fail validation
spec:
  containers:
  - name: sonarr
    image: ghcr.io/linuxserver/sonarr:latest

# GOOD - includes requests/limits
spec:
  containers:
  - name: sonarr
    image: ghcr.io/linuxserver/sonarr:latest
    resources:
      requests:
        memory: "512Mi"
        cpu: "500m"
      limits:
        memory: "2Gi"
        cpu: "2000m"
```

**Raw secret (NEVER commit):**
```yaml
# BAD - plain text secret
apiVersion: v1
kind: Secret
metadata:
  name: api-key
data:
  key: c3VwZXJzZWNyZXQ=  # base64 encoded but still wrong

# GOOD - sealed secret
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: api-key
spec:
  encryptedData:
    key: AgBH8f3k...  # encrypted with kubeseal
```

**Invalid kustomization:**
```yaml
# BAD - references non-existent file
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
- missing-file.yaml  # ERROR

# GOOD - only existing files
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
```

---

### 4. Create PR and Verify ArgoCD Sync After Merge

**Purpose**: Peer review, automated checks, and safe deployment to cluster.

**Steps:**

1. **Push branch to remote:**
   ```bash
   git push origin feature/my-new-feature
   ```

2. **Create Pull Request:**
   - Go to GitHub: https://github.com/sigtom/wow-ocp/pulls
   - Click "New pull request"
   - Base: `main`, Compare: `feature/my-new-feature`
   - Fill PR template (see `templates/pr-template.md`)

3. **PR Template Checklist:**
   ```markdown
   ## What Changed
   - [ ] Added Sonarr deployment with rclone sidecar
   - [ ] Configured persistent storage (NFS)
   - [ ] Added NetworkPolicy for same-namespace traffic
   
   ## Why It Changed
   Deploying Sonarr to automate TV show downloads via TorBox.
   
   ## How to Verify
   1. After merge: `argocd app sync sonarr`
   2. Check pod status: `oc get pods -n sonarr`
   3. Access UI: https://sonarr.apps.wow.sigtomtech.com
   
   ## Pre-Merge Checklist
   - [x] Validated with `./scripts/validate.sh`
   - [x] Tested dry-run: `oc apply --dry-run=client`
   - [x] Resource limits present
   - [x] No raw secrets committed
   - [ ] PROGRESS.md updated (post-merge)
   ```

4. **Review and Merge:**
   - Wait for CI checks (if configured)
   - Self-review or request team review
   - Merge PR via GitHub UI

5. **Verify ArgoCD Sync:**

   **Option A: Use helper script:**
   ```bash
   ./scripts/sync-check.sh
   # Shows status of all ArgoCD apps
   ```

   **Option B: Manual verification:**
   ```bash
   # Check specific app
   argocd app get sonarr
   
   # Expected output:
   # Sync Status: Synced
   # Health Status: Healthy
   
   # Force sync if needed (auto-sync may be disabled)
   argocd app sync sonarr
   
   # Watch sync progress
   argocd app wait sonarr --health
   ```

6. **Verify in cluster:**
   ```bash
   # Check pods are running
   oc get pods -n sonarr
   
   # Check deployment status
   oc get deployment -n sonarr
   
   # Check ArgoCD application status
   oc get application sonarr -n argocd
   ```

7. **If sync fails:**
   ```bash
   # Check ArgoCD app for errors
   argocd app get sonarr
   
   # Check pod events
   oc get events -n sonarr --sort-by='.lastTimestamp'
   
   # Check pod logs
   oc logs -n sonarr deployment/sonarr
   
   # If invalid manifest: fix in Git and commit
   # If transient issue: manual sync
   argocd app sync sonarr
   ```

**Common ArgoCD Sync Issues:**

**Issue: OutOfSync but not auto-syncing**
```bash
# Solution: Enable auto-sync or manual sync
argocd app sync sonarr
```

**Issue: Sync error due to invalid manifest**
```bash
# Solution: Fix in Git and merge fix
git checkout -b fix/sonarr-sync-error
# Fix manifest
git commit -m "fix: correct Sonarr PVC storageClassName"
git push origin fix/sonarr-sync-error
# Create PR, merge, sync again
```

**Issue: Resource already exists (from manual apply)**
```bash
# Solution: Delete manually-created resource
oc delete deployment sonarr -n sonarr
# ArgoCD will recreate from Git
argocd app sync sonarr
```

---

### 5. Update PROGRESS.md with Completed Work

**Purpose**: Maintain historical record of significant changes (Scribe Protocol).

**When to update:**
- After merging PR for significant features
- After resolving major issues
- After infrastructure changes
- Monthly summary of smaller changes

**Format:**
```markdown
- [YYYY-MM-DD]: **CATEGORY**: Description.
    - **Change**: What was changed.
    - **Result**: Outcome or impact.
    - **Action**: Follow-up actions (if any).
```

**Steps:**

1. **Use helper script:**
   ```bash
   ./scripts/update-progress.sh "Deployed Sonarr with rclone sidecar for TorBox integration"
   
   # Opens editor with dated entry template
   # Add details and save
   ```

2. **Manual update:**
   ```bash
   vim PROGRESS.md
   
   # Add at the top (after header):
   - [2026-01-08]: **MEDIA STACK**: Deployed Sonarr with rclone sidecar.
       - **Change**: Added Sonarr deployment with persistent NFS storage and TorBox rclone mount.
       - **Result**: Automated TV show downloads now functional.
       - **Action**: Configure indexers and quality profiles in UI.
   ```

3. **Commit PROGRESS.md update:**
   ```bash
   git add PROGRESS.md
   git commit -m "docs: update PROGRESS.md with Sonarr deployment"
   git push origin main
   ```

**Examples:**

**Feature deployment:**
```markdown
- [2026-01-08]: **APPLICATION**: Deployed Technitium DNS.
    - **Change**: Migrated from Pi-hole to Technitium DNS on OpenShift.
    - **Persistence**: Configured private NFS share for config and zones.
    - **Result**: DNS now managed via GitOps with 80+ records migrated.
```

**Bug fix:**
```markdown
- [2026-01-08]: **FIX**: Resolved Plex mount permissions.
    - **Issue**: Plex pod couldn't access /mnt/media due to FUSE propagation.
    - **Solution**: Added rclone sidecar with bidirectional mount propagation.
    - **Result**: Media library now visible in Plex UI.
```

**Infrastructure change:**
```markdown
- [2026-01-08]: **INFRASTRUCTURE**: Expanded Prometheus storage.
    - **Issue**: Prometheus PVC hit 100% (20GB), metrics collection stopped.
    - **Action**: Increased PVC to 100GB via GitOps, reduced retention to 15d.
    - **Result**: Monitoring restored, alert added for 80% usage.
```

**What NOT to add:**
- Minor typo fixes
- Routine dependency updates (unless breaking)
- Daily operational commands
- Work-in-progress (only completed work)

---

## Repository Structure

Understanding where files live is critical for GitOps workflow.

```
wow-ocp/
├── apps/                           # Application deployments
│   ├── <app-name>/
│   │   ├── base/                   # Base Kustomize manifests
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── ingress.yaml
│   │   │   └── kustomization.yaml
│   │   └── overlays/
│   │       └── prod/               # Production-specific patches
│   │           ├── kustomization.yaml
│   │           └── patches.yaml
│   └── ...
├── infrastructure/                 # Core cluster services
│   ├── storage/
│   │   ├── democratic-csi/
│   │   ├── media/                  # Static PVs for media library
│   │   └── lvms/                   # Local LVM storage
│   ├── operators/
│   │   ├── sealed-secrets/
│   │   ├── cert-manager/
│   │   └── metallb/
│   ├── networking/
│   │   └── multus/                 # Additional network interfaces
│   └── monitoring/
│       ├── prometheus/
│       └── grafana/
├── argocd-apps/                    # ArgoCD Application CRDs
│   ├── root-app.yaml               # App of Apps (deploys everything)
│   ├── sonarr.yaml
│   ├── plex.yaml
│   └── ...
├── automation/                     # Ansible playbooks (out-of-cluster)
│   ├── inventory/
│   ├── playbooks/
│   └── roles/
│       ├── proxmox_vm/
│       └── proxmox_lxc/
├── .pi/                            # Agent skills (this documentation)
│   └── skills/
│       ├── gitops-workflow/        # This skill
│       ├── sealed-secrets/
│       └── ...
├── SYSTEM.md                       # System prompt (immutable history)
├── PROGRESS.md                     # Project progress log (append-only)
└── README.md                       # Repository overview
```

**Key principles:**
- **apps/**: Namespaced applications (one app per directory)
- **infrastructure/**: Cluster-wide services (storage, operators, networking)
- **argocd-apps/**: ArgoCD Application CRDs that point to apps/ or infrastructure/
- **automation/**: Ansible for out-of-cluster automation (Proxmox, DNS)

---

## Pre-Commit Validation Rules

The `validate.sh` script checks for common issues:

### 1. YAML Syntax
```bash
yamllint -c .yamllint *.yaml
```

**Common errors:**
- Indentation (use 2 spaces, not tabs)
- Missing colons
- Unquoted special characters

### 2. Kustomize Build
```bash
kustomize build . >/dev/null
```

**Checks:**
- All referenced files exist
- `kustomization.yaml` is valid
- No circular dependencies

### 3. Resource Limits Present
```bash
grep -q "resources:" deployment.yaml
```

**Requirement**: Every Deployment must have `resources.requests` and `resources.limits`.

**Exception**: Jobs, CronJobs (short-lived workloads)

### 4. No Raw Secrets
```bash
! grep -q "kind: Secret" *.yaml
```

**Requirement**: Only `SealedSecret` kind allowed, never raw `Secret`.

**Exception**: Temporary secrets in `/tmp` for `kubeseal` input (never committed).

### 5. Ingress Annotations
```bash
grep -q "cert-manager.io/cluster-issuer" ingress.yaml
```

**Required annotations for Ingress:**
```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    route.openshift.io/termination: edge
```

### 6. Health Probes
```bash
grep -q "livenessProbe:" deployment.yaml
grep -q "readinessProbe:" deployment.yaml
```

**Requirement**: Every Deployment must have both probes.

**Example:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
```

---

## Common Workflows

### Deploying a New Application

**Full workflow:**
```bash
# 1. Create branch
./scripts/new-branch.sh feature add-bazarr

# 2. Create app structure
mkdir -p apps/bazarr/base
cd apps/bazarr/base

# 3. Create manifests
vim deployment.yaml
vim service.yaml
vim kustomization.yaml

# 4. Validate
cd ~/wow-ocp
./scripts/validate.sh apps/bazarr/base

# 5. Create ArgoCD Application
vim argocd-apps/bazarr.yaml

# 6. Commit
git add apps/bazarr/ argocd-apps/bazarr.yaml
./scripts/commit.sh feat "add Bazarr for subtitle management"

# 7. Push and create PR
git push origin feature/add-bazarr
# Create PR on GitHub

# 8. After merge: verify sync
./scripts/sync-check.sh

# 9. Update PROGRESS.md
./scripts/update-progress.sh "Deployed Bazarr for subtitle management"
```

### Fixing a Bug

**Full workflow:**
```bash
# 1. Create fix branch
./scripts/new-branch.sh fix sonarr-pvc-permissions

# 2. Modify manifest
vim apps/sonarr/base/deployment.yaml
# Fix PVC mount permissions

# 3. Validate
./scripts/validate.sh apps/sonarr/base

# 4. Commit
git add apps/sonarr/base/deployment.yaml
./scripts/commit.sh fix "correct Sonarr PVC mount permissions"

# 5. Push and create PR
git push origin fix/sonarr-pvc-permissions
# Create PR on GitHub

# 6. After merge: force sync
argocd app sync sonarr

# 7. Verify fix
oc get pods -n sonarr
oc logs -n sonarr deployment/sonarr

# 8. Update PROGRESS.md (if significant)
./scripts/update-progress.sh "Fixed Sonarr PVC permissions issue"
```

### Updating Documentation

**Full workflow:**
```bash
# 1. Create docs branch
./scripts/new-branch.sh docs update-media-stack-readme

# 2. Update docs
vim apps/README.md

# 3. Commit (no validation needed for docs)
git add apps/README.md
./scripts/commit.sh docs "update media stack README with TorBox setup"

# 4. Push and merge
git push origin docs/update-media-stack-readme
# Create PR on GitHub

# 5. No ArgoCD sync needed (docs-only change)
```

---

## Troubleshooting

### ArgoCD Shows OutOfSync After Merge

**Symptom**: Manifest in Git differs from cluster.

**Causes:**
1. Manual `oc apply` was run (drift)
2. Auto-sync disabled
3. Manifest has errors

**Solution:**
```bash
# Check sync status
argocd app get <app-name>

# Manual sync
argocd app sync <app-name>

# If sync fails, check app logs
argocd app get <app-name> --show-operation

# Force sync (ignore warnings)
argocd app sync <app-name> --force
```

### Validation Fails But Manifest Looks Correct

**Symptom**: `validate.sh` fails but YAML looks fine.

**Debug:**
```bash
# Test each validation step individually
yamllint apps/myapp/base/*.yaml
kustomize build apps/myapp/base
oc apply --dry-run=client -f apps/myapp/base/deployment.yaml

# Check for hidden characters
cat -A apps/myapp/base/deployment.yaml | less

# Verify file references
ls -la apps/myapp/base/
cat apps/myapp/base/kustomization.yaml
```

### PR Conflicts with Main Branch

**Symptom**: GitHub shows merge conflicts.

**Solution:**
```bash
# Update branch with latest main
git checkout feature/my-feature
git fetch origin
git merge origin/main

# Resolve conflicts
vim <conflicting-file>
git add <conflicting-file>
git commit -m "fix: resolve merge conflicts with main"
git push origin feature/my-feature
```

### Forgot to Update PROGRESS.md

**Symptom**: Realized after merge that PROGRESS.md wasn't updated.

**Solution:**
```bash
# Update directly on main (docs-only change)
git checkout main
git pull origin main
vim PROGRESS.md
git add PROGRESS.md
git commit -m "docs: update PROGRESS.md with recent changes"
git push origin main
```

---

## Best Practices

1. **Branch Early, Branch Often**
   - One feature = one branch
   - Keep branches short-lived (1-2 days max)
   - Delete branches after merge

2. **Commit Messages Matter**
   - Use conventional commits
   - Be descriptive but concise
   - Include "why" in commit body if not obvious

3. **Validate Before Push**
   - Run `validate.sh` before every commit
   - Test dry-run on cluster
   - Fix errors locally, not in PR review

4. **Small, Focused PRs**
   - One logical change per PR
   - Easier to review and revert
   - Faster to merge

5. **Verify ArgoCD Sync**
   - Always check sync after merge
   - Don't assume auto-sync worked
   - Fix sync errors immediately

6. **Update PROGRESS.md**
   - Document significant changes
   - Include context and outcomes
   - Helps with future troubleshooting

7. **Never Skip Validation**
   - Even for "quick fixes"
   - Broken manifests break auto-sync
   - Prevention > repair

8. **Use Conventional Commits**
   - Enables automated changelog
   - Clear history for rollbacks
   - Easier to filter commits

---

## Integration with Other Skills

- **sealed-secrets**: Use `kubeseal` workflow before committing secrets
- **argocd-ops**: Sync, diff, rollback ArgoCD applications
- **capacity-planning**: Check capacity before deploying new apps
- **vm-provisioning**: Use Ansible in `automation/` for out-of-cluster VMs
- **openshift-debug**: Troubleshoot failed syncs or deployment issues

---

## Quick Reference

**Create branch:**
```bash
./scripts/new-branch.sh <type> <name>
```

**Validate manifests:**
```bash
./scripts/validate.sh [path]
```

**Commit with validation:**
```bash
./scripts/commit.sh <type> <message>
```

**Check ArgoCD sync:**
```bash
./scripts/sync-check.sh
```

**Update PROGRESS.md:**
```bash
./scripts/update-progress.sh <message>
```

**Common Git commands:**
```bash
git status                    # Check working directory
git diff                      # Show unstaged changes
git log --oneline             # View commit history
git branch -d <name>          # Delete local branch
git push origin --delete <name>  # Delete remote branch
```

**Common ArgoCD commands:**
```bash
argocd app list               # List all applications
argocd app get <app>          # Show app status
argocd app sync <app>         # Force sync
argocd app diff <app>         # Show diff vs Git
argocd app rollback <app>     # Rollback to previous sync
```

---

## Emergency Break-Glass Procedures

**When manual `oc apply` is acceptable:**

1. **Day 0 cluster bootstrap** (before ArgoCD exists)
2. **Critical production outage** requiring immediate fix
3. **Testing in scratch namespace** (not managed by ArgoCD)

**If you must use manual apply:**

1. **Document the reason:**
   ```bash
   echo "[$(date)] Emergency manual apply: <reason>" >> /tmp/manual-apply-log.txt
   ```

2. **Apply change:**
   ```bash
   oc apply -f /tmp/emergency-fix.yaml
   ```

3. **Immediately create PR to sync Git:**
   ```bash
   ./scripts/new-branch.sh fix emergency-manual-fix
   # Copy manifest to Git
   git add apps/myapp/base/
   ./scripts/commit.sh fix "sync Git with emergency manual apply"
   git push origin fix/emergency-manual-fix
   # Create PR and merge ASAP
   ```

4. **Update PROGRESS.md with incident details:**
   ```markdown
   - [2026-01-08]: **EMERGENCY**: Manual apply to fix production outage.
       - **Issue**: Plex pod crash loop, media unavailable.
       - **Action**: Manual `oc apply` to increase memory limit.
       - **Follow-up**: PR #123 merged to sync Git with emergency fix.
   ```

**Remember**: Every manual apply creates technical debt. Always sync back to Git.

---

## Files Reference

- `SKILL.md` (this file) - Main skill documentation
- `references/conventions.md` - Detailed conventions and standards
- `templates/pr-template.md` - PR description template
- `scripts/new-branch.sh` - Create feature branch
- `scripts/validate.sh` - Validate manifests
- `scripts/commit.sh` - Conventional commit with validation
- `scripts/sync-check.sh` - Verify ArgoCD sync status
- `scripts/update-progress.sh` - Update PROGRESS.md

---

## Summary: The GitOps Way

1. **Create branch** for every change
2. **Validate** manifests locally
3. **Commit** with conventional message
4. **Push** and create PR
5. **Merge** after review
6. **Verify** ArgoCD sync
7. **Update** PROGRESS.md for significant changes

**Git is source of truth. Always.**
