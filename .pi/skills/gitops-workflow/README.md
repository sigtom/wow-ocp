# GitOps Workflow Skill

Enforce GitOps-first workflow for all cluster changes. **Git is the source of truth. Manual `oc apply` is for emergencies only.**

## Overview

This skill provides tools and documentation for maintaining GitOps discipline:
- **Conventional commits** for clear history
- **Branch-based workflow** for safe deployments
- **Pre-commit validation** to catch errors early
- **ArgoCD sync verification** to ensure Git matches cluster
- **PROGRESS.md updates** for historical record (Scribe Protocol)

## Quick Start

### Create New Feature

```bash
# 1. Create branch
.pi/skills/gitops-workflow/scripts/new-branch.sh feature add-new-app

# 2. Make changes
vim apps/new-app/base/deployment.yaml

# 3. Validate
.pi/skills/gitops-workflow/scripts/validate.sh apps/new-app/base

# 4. Commit
git add apps/new-app/
.pi/skills/gitops-workflow/scripts/commit.sh feat "add new app deployment"

# 5. Push and create PR
git push origin feature/add-new-app

# 6. After merge: verify sync
.pi/skills/gitops-workflow/scripts/sync-check.sh

# 7. Update progress
.pi/skills/gitops-workflow/scripts/update-progress.sh "Deployed new app"
```

### Fix a Bug

```bash
# 1. Create fix branch
.pi/skills/gitops-workflow/scripts/new-branch.sh fix sonarr-pvc-issue

# 2. Fix manifest
vim apps/sonarr/base/deployment.yaml

# 3. Validate and commit
.pi/skills/gitops-workflow/scripts/validate.sh apps/sonarr/base
.pi/skills/gitops-workflow/scripts/commit.sh fix "correct Sonarr PVC permissions"

# 4. Push, PR, merge
git push origin fix/sonarr-pvc-issue

# 5. Force sync
argocd app sync sonarr

# 6. Update progress
.pi/skills/gitops-workflow/scripts/update-progress.sh "Fixed Sonarr PVC permissions"
```

## The Prime Directive

> **Manual `oc apply` is Evil**
>
> If you run `oc apply -f manifest.yaml` manually, ArgoCD will **revert your change** on the next sync.
>
> **ONLY exceptions:**
> - Day 0 cluster bootstrap (before ArgoCD exists)
> - Break-glass emergencies (with documented rollback plan)
> - Testing in scratch namespace (not managed by ArgoCD)

**Why?**
- Git is source of truth (what's in Git = what's in cluster)
- Manual changes create drift and confusion
- ArgoCD provides automated rollback and audit trail
- Reproducible deployments (disaster recovery, staging)

## Structure

```
gitops-workflow/
├── SKILL.md                    # Main skill documentation (24 KB)
├── README.md                   # This file
├── references/
│   └── conventions.md          # Detailed conventions (17 KB)
├── templates/
│   └── pr-template.md          # PR description template (7 KB)
└── scripts/
    ├── new-branch.sh           # Create feature branch
    ├── validate.sh             # Validate manifests
    ├── commit.sh               # Conventional commit
    ├── sync-check.sh           # ArgoCD sync status
    └── update-progress.sh      # Update PROGRESS.md
```

## Scripts

### new-branch.sh

**Purpose:** Create feature branch following conventions

**Usage:**
```bash
./scripts/new-branch.sh <type> <name>

# Types: feature, fix, docs, refactor, chore
# Examples:
./scripts/new-branch.sh feature add-bazarr
./scripts/new-branch.sh fix sonarr-permissions
./scripts/new-branch.sh docs update-readme
```

**What it does:**
- Validates branch type
- Checks if already on main
- Pulls latest changes
- Creates and checks out branch
- Shows next steps

### validate.sh

**Purpose:** Validate manifests before commit

**Usage:**
```bash
./scripts/validate.sh [path]

# Examples:
./scripts/validate.sh apps/sonarr/base
./scripts/validate.sh apps/
./scripts/validate.sh  # Validates current directory
```

**Checks:**
1. YAML syntax (yamllint)
2. Kustomize builds successfully
3. Resource limits present on Deployments
4. No raw Secrets (only SealedSecrets)
5. Ingress has cert-manager annotations
6. Dry-run passes on cluster

**Exit codes:**
- `0` - All checks passed
- `1` - Validation failed (fix before commit)

### commit.sh

**Purpose:** Create conventional commit with validation

**Usage:**
```bash
./scripts/commit.sh <type> <message>

# Types: feat, fix, docs, refactor, chore, ci, test
# Examples:
./scripts/commit.sh feat "add Bazarr deployment"
./scripts/commit.sh fix "correct PVC permissions"
./scripts/commit.sh docs "update README"
```

**What it does:**
- Validates commit type
- Checks staged files exist
- Runs validate.sh on staged YAML files
- Creates commit with conventional format
- Shows next steps

### sync-check.sh

**Purpose:** Check ArgoCD application sync status

**Usage:**
```bash
./scripts/sync-check.sh

# Output: Table of all apps with sync and health status
```

**Exit codes:**
- `0` - All apps synced and healthy
- `1` - Some apps out of sync (warning)
- `2` - Some apps degraded (critical)

### update-progress.sh

**Purpose:** Add dated entry to PROGRESS.md

**Usage:**
```bash
./scripts/update-progress.sh <message>

# Examples:
./scripts/update-progress.sh "Deployed Bazarr for subtitles"
./scripts/update-progress.sh "Fixed Sonarr mount issue"
```

**What it does:**
- Adds dated entry: `- [YYYY-MM-DD]: <message>`
- Appends to top of PROGRESS.md (after header)
- Shows preview and confirms
- Provides next steps for commit

## Conventional Commits

### Format
```
<type>: <description>

<optional body>

<optional footer>
```

### Types
- `feat:` - New feature or application
- `fix:` - Bug fix or issue resolution
- `docs:` - Documentation changes
- `refactor:` - Code restructuring
- `chore:` - Maintenance tasks
- `ci:` - CI/CD changes
- `test:` - Test additions

### Examples

**Good:**
```
feat: add Bazarr for subtitle management
fix: correct Sonarr PVC mount permissions
docs: update media-stack README with TorBox setup
```

**Bad:**
```
update stuff
Fixed bug
Added new app
```

## Branch Naming

### Format
```
<type>/<short-description>
```

### Types
- `feature/` - New features or applications
- `fix/` - Bug fixes
- `docs/` - Documentation
- `refactor/` - Code restructuring
- `chore/` - Maintenance

### Examples

**Good:**
```
feature/add-bazarr-deployment
fix/sonarr-pvc-permissions
docs/update-media-stack-readme
```

**Bad:**
```
new_feature
fix_bug
my-branch
```

## Validation Rules

### Required for All Deployments

1. **Resource Limits:**
   ```yaml
   resources:
     requests:
       memory: "512Mi"
       cpu: "500m"
     limits:
       memory: "2Gi"
       cpu: "2000m"
   ```

2. **Health Probes:**
   ```yaml
   livenessProbe:
     httpGet:
       path: /health
       port: 8080
   readinessProbe:
     httpGet:
       path: /ready
       port: 8080
   ```

3. **No Raw Secrets:**
   ```yaml
   # BAD - Never commit
   kind: Secret
   
   # GOOD - Always use
   kind: SealedSecret
   ```

4. **Ingress Annotations:**
   ```yaml
   metadata:
     annotations:
       cert-manager.io/cluster-issuer: letsencrypt-prod
       route.openshift.io/termination: edge
   ```

## Repository Structure

```
wow-ocp/
├── apps/                    # Application deployments
│   └── <app-name>/
│       ├── base/            # Kustomize base manifests
│       └── overlays/prod/   # Production patches
├── infrastructure/          # Core cluster services
│   ├── storage/
│   ├── operators/
│   └── networking/
├── argocd-apps/             # ArgoCD Application CRDs
│   └── <app>.yaml
├── automation/              # Ansible (out-of-cluster)
│   ├── inventory/
│   └── playbooks/
├── .pi/skills/              # Agent skills
├── SYSTEM.md                # System prompt (immutable)
├── PROGRESS.md              # Project log (append-only)
└── README.md
```

## Typical Workflows

### Deploy New Application

```bash
# 1. Create branch
./scripts/new-branch.sh feature add-myapp

# 2. Create app structure
mkdir -p apps/myapp/base
cd apps/myapp/base

# 3. Create manifests
vim deployment.yaml service.yaml kustomization.yaml

# 4. Create ArgoCD Application
vim ../../../argocd-apps/myapp.yaml

# 5. Validate
cd ~/wow-ocp
./scripts/validate.sh apps/myapp/base

# 6. Commit
git add apps/myapp/ argocd-apps/myapp.yaml
./scripts/commit.sh feat "add myapp deployment"

# 7. Push and PR
git push origin feature/add-myapp

# 8. After merge: sync
argocd app sync myapp

# 9. Update progress
./scripts/update-progress.sh "Deployed myapp"
```

### Fix Production Bug

```bash
# 1. Create fix branch
./scripts/new-branch.sh fix myapp-crash-loop

# 2. Fix manifest
vim apps/myapp/base/deployment.yaml

# 3. Validate and commit
./scripts/validate.sh apps/myapp/base
git add apps/myapp/base/deployment.yaml
./scripts/commit.sh fix "increase memory limit to resolve OOMKilled"

# 4. Push and PR
git push origin fix/myapp-crash-loop

# 5. After merge: force sync
argocd app sync myapp --force

# 6. Verify fix
oc get pods -n myapp
oc logs -n myapp deployment/myapp

# 7. Update progress
./scripts/update-progress.sh "Fixed myapp crash loop (OOM)"
```

### Update Documentation

```bash
# 1. Create docs branch
./scripts/new-branch.sh docs update-myapp-readme

# 2. Update docs
vim apps/myapp/README.md

# 3. Commit (no validation needed)
git add apps/myapp/README.md
./scripts/commit.sh docs "update myapp README with config notes"

# 4. Push and merge
git push origin docs/update-myapp-readme

# 5. No ArgoCD sync needed (docs-only)
```

## Integration with Other Skills

- **sealed-secrets**: Encrypt secrets with `kubeseal` before commit
- **argocd-ops**: Detailed ArgoCD operations (sync, diff, rollback)
- **capacity-planning**: Check capacity before deploying new apps
- **vm-provisioning**: Use Ansible in `automation/` for Proxmox VMs
- **openshift-debug**: Troubleshoot failed ArgoCD syncs

## Troubleshooting

### ArgoCD OutOfSync After Merge

**Symptom:** App shows OutOfSync in ArgoCD

**Causes:**
1. Auto-sync disabled
2. Manual `oc apply` was run (drift)
3. Manifest has errors

**Solution:**
```bash
# Check status
argocd app get <app-name>

# Manual sync
argocd app sync <app-name>

# If errors, check app logs
argocd app get <app-name> --show-operation

# Force sync (bypass validation)
argocd app sync <app-name> --force
```

### Validation Fails

**Symptom:** `validate.sh` fails but manifest looks fine

**Debug:**
```bash
# Test each check individually
yamllint apps/myapp/base/*.yaml
kustomize build apps/myapp/base
oc apply --dry-run=client -f apps/myapp/base/deployment.yaml

# Check for hidden characters
cat -A apps/myapp/base/deployment.yaml
```

### PR Merge Conflicts

**Symptom:** GitHub shows merge conflicts

**Solution:**
```bash
# Update branch with latest main
git checkout feature/my-feature
git fetch origin
git merge origin/main

# Resolve conflicts
vim <conflicting-file>
git add <conflicting-file>
git commit -m "fix: resolve merge conflicts"
git push origin feature/my-feature
```

## Best Practices

1. **Branch Early, Branch Often**
   - One feature = one branch
   - Keep branches short-lived (1-2 days)
   - Delete after merge

2. **Commit Messages Matter**
   - Use conventional commits
   - Be descriptive but concise
   - Include "why" in body if not obvious

3. **Validate Before Push**
   - Run `validate.sh` before every commit
   - Test dry-run on cluster
   - Fix locally, not in PR

4. **Small, Focused PRs**
   - One logical change per PR
   - Easier to review and revert
   - Faster to merge

5. **Verify ArgoCD Sync**
   - Always check after merge
   - Don't assume auto-sync worked
   - Fix sync errors immediately

6. **Update PROGRESS.md**
   - Document significant changes
   - Include context and outcomes
   - Helps future troubleshooting

## Emergency Procedures

**When manual `oc apply` is acceptable:**

1. **Day 0 bootstrap** (before ArgoCD)
2. **Critical outage** requiring immediate fix
3. **Testing** in scratch namespace

**If you must use manual apply:**

1. Document reason
2. Apply change
3. **Immediately sync Git:**
   ```bash
   # Create fix branch
   ./scripts/new-branch.sh fix emergency-sync
   
   # Copy manifest to Git
   cp /tmp/emergency-fix.yaml apps/myapp/base/
   
   # Commit
   git add apps/myapp/base/
   ./scripts/commit.sh fix "sync Git with emergency manual apply"
   
   # Push and merge ASAP
   git push origin fix/emergency-sync
   ```

4. Update PROGRESS.md with incident

**Remember:** Every manual apply creates technical debt. Always sync back to Git.

## Quick Reference

```bash
# Create branch
./scripts/new-branch.sh <type> <name>

# Validate manifests
./scripts/validate.sh [path]

# Commit with validation
./scripts/commit.sh <type> <message>

# Check ArgoCD sync
./scripts/sync-check.sh

# Update progress
./scripts/update-progress.sh <message>

# Common Git commands
git status                  # Check working directory
git diff                    # Show unstaged changes
git log --oneline           # View commit history
git branch -d <name>        # Delete local branch

# Common ArgoCD commands
argocd app list             # List all applications
argocd app get <app>        # Show app status
argocd app sync <app>       # Force sync
argocd app diff <app>       # Show diff vs Git
```

## Files

- `SKILL.md` - Main documentation (24 KB)
- `references/conventions.md` - Detailed conventions (17 KB)
- `templates/pr-template.md` - PR template (7 KB)
- `scripts/new-branch.sh` - Create feature branch
- `scripts/validate.sh` - Validate manifests
- `scripts/commit.sh` - Conventional commit
- `scripts/sync-check.sh` - ArgoCD sync check
- `scripts/update-progress.sh` - Update PROGRESS.md

## Summary

**The GitOps Way:**

1. **Create branch** for every change
2. **Validate** manifests locally
3. **Commit** with conventional message
4. **Push** and create PR
5. **Merge** after review
6. **Verify** ArgoCD sync
7. **Update** PROGRESS.md for significant changes

**Git is source of truth. Always.**

---

Part of wow-ocp homelab infrastructure. Internal use only.
