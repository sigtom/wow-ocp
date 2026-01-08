---
name: argocd-ops
description: ArgoCD GitOps operations for OpenShift homelab. Manage app sync status, perform controlled rollbacks, diff changes before deployment, and troubleshoot sync issues. Use when deploying apps, checking GitOps status, or debugging ArgoCD problems.
---

# ArgoCD Operations

GitOps management toolkit for OpenShift 4.20 homelab using ArgoCD. Follows the "GitOps First" principle - all changes through Git, never manual `oc apply`.

## Prerequisites

- `argocd` CLI installed and configured
- `oc` CLI with cluster access
- Access to Git repository with ArgoCD apps
- ArgoCD installed in cluster (typically `openshift-gitops` namespace)

Install ArgoCD CLI:
```bash
# macOS
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

### ArgoCD CLI Login

**Important:** ArgoCD CLI requires gRPC access. Since gRPC ingress is typically disabled in OpenShift (for security), you must use port-forward:

```bash
# Start port-forward (keep running in background or separate terminal)
oc port-forward -n openshift-gitops svc/openshift-gitops-server 8443:443 &

# Login via localhost
argocd login localhost:8443 --username admin --insecure

# Get admin password
oc get secret -n openshift-gitops openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d
```

**Why port-forward?** The OpenShift route only exposes HTTP/HTTPS, not gRPC which the argocd CLI needs.

**Alternative:** Use `{baseDir}/scripts/sync-status-oc.sh` which uses `oc get applications` directly and doesn't require argocd CLI login.

## Quick Operations

### Check All Apps Status

```bash
{baseDir}/scripts/sync-status.sh
```

Shows table of all ArgoCD applications with sync and health status.

### Sync an Application

```bash
{baseDir}/scripts/sync-app.sh <app-name>
```

Syncs app and waits for it to become healthy. Shows progress in real-time.

### Preview Changes (Diff)

```bash
{baseDir}/scripts/diff-app.sh <app-name>
```

Shows what would change if you sync now (Git vs. cluster state).

### Rollback Application

```bash
{baseDir}/scripts/rollback-app.sh <app-name> <revision>
```

Rolls back to a previous working revision with confirmation prompt.

### Watch Sync Progress

```bash
{baseDir}/scripts/watch-sync.sh <app-name>
```

Continuously monitors app until synced and healthy (or timeout).

## GitOps Workflow

### The Golden Path (Standard Deployment)

**Philosophy:** Git is source of truth. Manual `oc apply` is forbidden except for emergencies.

**Workflow:**
1. **Change Manifest** in Git repository
   ```bash
   vim apps/plex/overlays/prod/deployment.yaml
   # Update image tag, resources, etc.
   ```

2. **Commit and Push**
   ```bash
   git add apps/plex/overlays/prod/
   git commit -m "feat(plex): upgrade to 1.32.5"
   git push origin main
   ```

3. **Sync via ArgoCD**
   ```bash
   ./scripts/sync-app.sh plex
   # Or wait for auto-sync (if enabled)
   ```

4. **Verify Health**
   ```bash
   ./scripts/sync-status.sh
   # Check plex shows Synced + Healthy
   ```

5. **Rollback if Needed**
   ```bash
   # If deployment fails
   ./scripts/rollback-app.sh plex <previous-revision>
   ```

### App of Apps Pattern

**Structure:**
```
argocd-apps/
├── root-app.yaml              # Parent application (bootstraps everything)
├── infrastructure/
│   ├── cert-manager.yaml
│   ├── democratic-csi.yaml
│   └── sealed-secrets.yaml
└── applications/
    ├── plex.yaml
    ├── jellyfin.yaml
    └── sonarr.yaml
```

**Root App (Bootstrap):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/yourorg/wow-ocp.git
    path: argocd-apps
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**To deploy everything:**
```bash
oc apply -f argocd-apps/root-app.yaml
argocd app sync root-app
```

### Creating a New Application

**Steps:**

1. **Create App Manifests**
   ```bash
   mkdir -p apps/myapp/{base,overlays/prod}
   cd apps/myapp/base
   # Create deployment.yaml, service.yaml, etc.
   ```

2. **Create Kustomization**
   ```yaml
   # apps/myapp/base/kustomization.yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - deployment.yaml
     - service.yaml
   ```

3. **Create ArgoCD Application**
   ```yaml
   # argocd-apps/applications/myapp.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: myapp
     namespace: openshift-gitops
   spec:
     project: default
     source:
       repoURL: https://github.com/yourorg/wow-ocp.git
       path: apps/myapp/overlays/prod
       targetRevision: main
     destination:
       server: https://kubernetes.default.svc
       namespace: myapp
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
   ```

4. **Commit to Git**
   ```bash
   git add apps/myapp argocd-apps/applications/myapp.yaml
   git commit -m "feat: add myapp deployment"
   git push
   ```

5. **Verify Sync**
   ```bash
   ./scripts/sync-status.sh | grep myapp
   # Should show: myapp  Synced  Healthy
   ```

## Troubleshooting Workflows

### Issue 1: App Stuck "OutOfSync"

**Symptoms:**
- App shows `OutOfSync` in ArgoCD UI
- Changes in Git not reflected in cluster
- Auto-sync not working

**Diagnosis:**
```bash
# Check app status
argocd app get <app-name>

# See what's different
./scripts/diff-app.sh <app-name>

# Check sync policy
argocd app get <app-name> -o yaml | grep -A 10 syncPolicy
```

**Common Causes:**
1. **Manual changes in cluster** (violates GitOps)
   - Someone ran `oc apply` directly
   - Operator modified resources

2. **Sync policy disabled**
   - Auto-sync not enabled in Application spec

3. **Prune disabled**
   - Deleted resources in Git still exist in cluster

**Resolution:**
```bash
# Hard sync to force Git state
argocd app sync <app-name> --force

# Or with prune
argocd app sync <app-name> --prune --force

# Using script
./scripts/sync-app.sh <app-name>
```

### Issue 2: App Stuck "Progressing"

**Symptoms:**
- Health status shows `Progressing` for >5 minutes
- Sync shows `Synced` but health never reaches `Healthy`
- Pods may be stuck in `Pending` or `CrashLoopBackOff`

**Diagnosis:**
```bash
# Check detailed app status
argocd app get <app-name>

# Check resources
argocd app resources <app-name>

# Check pods in namespace
oc get pods -n <namespace>

# Check events
oc get events -n <namespace> --sort-by='.lastTimestamp' | tail -20
```

**Common Causes:**
1. **Resource issues** (PVC pending, OOMKilled)
2. **Probe failures** (liveness/readiness)
3. **Image pull errors**
4. **Sync waves** (waiting for dependencies)

**Resolution:**
```bash
# Check what's unhealthy
argocd app resources <app-name> | grep -v Healthy

# For PVC issues
./scripts/check-pvc.sh <pvc-name> <namespace>  # From openshift-debug skill

# For pod crashes
./scripts/check-pod.sh <pod-name> <namespace>  # From openshift-debug skill

# Rollback if needed
./scripts/rollback-app.sh <app-name> <last-good-revision>
```

### Issue 3: Sync Failed with Errors

**Symptoms:**
- Sync status shows `Failed`
- Error messages in ArgoCD UI
- Resources not created

**Diagnosis:**
```bash
# Check sync history
argocd app history <app-name>

# Get detailed error
argocd app get <app-name> -o yaml | grep -A 20 conditions

# Check ArgoCD controller logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

**Common Causes:**
1. **Invalid manifests** (YAML syntax errors)
2. **Missing CRDs** (operator not installed)
3. **RBAC issues** (ArgoCD SA lacks permissions)
4. **Resource conflicts** (namespace already exists, immutable fields)

**Resolution:**
```bash
# Validate manifests locally
kustomize build apps/<app-name>/overlays/prod | oc apply --dry-run=client -f -

# Check for invalid YAML
yamllint apps/<app-name>/

# Fix and re-sync
git add apps/<app-name>
git commit -m "fix: correct manifest errors"
git push
./scripts/sync-app.sh <app-name>
```

### Issue 4: Manual Changes Reverted

**Symptoms:**
- You make a change with `oc edit` or `oc apply`
- Change works temporarily
- ArgoCD reverts it back to Git state

**Root Cause:**
- This is **expected behavior** with GitOps!
- Self-heal policy automatically syncs Git → Cluster

**Resolution:**
```bash
# DON'T fight ArgoCD - update Git instead
vim apps/<app-name>/overlays/prod/deployment.yaml
# Make your changes

git add apps/<app-name>
git commit -m "fix: update configuration"
git push

./scripts/sync-app.sh <app-name>
```

**Emergency Override (Break Glass):**
```bash
# If you MUST make a manual change (NOT RECOMMENDED)
argocd app set <app-name> --sync-policy none

# Make your change
oc edit deployment <name> -n <namespace>

# Re-enable auto-sync later
argocd app set <app-name> --sync-policy automated
```

### Issue 5: Rollback Not Working

**Symptoms:**
- Rollback command succeeds but app still unhealthy
- Old revision deployed but pods still failing

**Diagnosis:**
```bash
# Check rollback happened
argocd app history <app-name>

# Check current deployed manifests
argocd app manifests <app-name>

# Check if issue is environmental (not code)
./scripts/check-pod.sh <pod-name> <namespace>
```

**Common Causes:**
1. **Environmental issue** (PVC full, node pressure)
2. **Dependency missing** (database, secret not sealed)
3. **Wrong revision** (both old and new have same issue)

**Resolution:**
```bash
# Find last known-good revision
argocd app history <app-name> | grep Succeeded

# Rollback further
./scripts/rollback-app.sh <app-name> <older-revision>

# Or debug the underlying issue
./scripts/check-pod.sh <pod-name> <namespace>
```

## Advanced Workflows

### Workflow 1: Controlled Rollout

**Scenario:** Upgrade Plex to new version, test, rollback if needed

```bash
# 1. Check current state
./scripts/sync-status.sh | grep plex
# plex  Synced  Healthy  v1.32.4

# 2. Update image in Git
vim apps/plex/overlays/prod/deployment.yaml
# Change image: plexinc/pms-docker:1.32.5

git add apps/plex/overlays/prod/
git commit -m "feat(plex): upgrade to 1.32.5"
git push

# 3. Preview changes
./scripts/diff-app.sh plex
# Shows image change

# 4. Sync and watch
./scripts/sync-app.sh plex
# Waits for healthy state

# 5. Test manually
curl http://plex.apps.ossus.sigtomtech.com/web
# Verify functionality

# 6. Rollback if issues
./scripts/rollback-app.sh plex 42  # Previous revision
```

### Workflow 2: Multi-App Sync

**Scenario:** Update entire media stack (Plex, Sonarr, Radarr)

```bash
# 1. Make changes to all apps in Git
vim apps/*/overlays/prod/deployment.yaml
git commit -am "feat(media): update all to latest"
git push

# 2. Sync all at once
for app in plex sonarr radarr; do
  ./scripts/sync-app.sh $app &
done
wait

# 3. Check status
./scripts/sync-status.sh | grep -E "plex|sonarr|radarr"
```

### Workflow 3: Emergency Rollback All Apps

**Scenario:** Git commit broke multiple apps

```bash
# 1. Identify bad commit
git log --oneline -10

# 2. Revert in Git
git revert <bad-commit-sha>
git push

# 3. Sync affected apps
./scripts/sync-status.sh | grep -v Healthy
# List unhealthy apps

# 4. Sync each one
for app in $(./scripts/sync-status.sh | grep Degraded | awk '{print $1}'); do
  ./scripts/sync-app.sh $app
done
```

### Workflow 4: Sync Waves for Dependencies

**Scenario:** Deploy app with database dependency

```yaml
# Database deployment
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# App deployment
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

```bash
# Sync respects wave order
./scripts/sync-app.sh myapp
# Database syncs first (wave 0)
# App syncs after database is healthy (wave 1)
```

## Helper Scripts

All scripts located in `{baseDir}/scripts/` with:
- Color-coded output
- Error handling and exit codes
- Usage help with `--help`
- Integration with `argocd` and `oc` CLI

### sync-status.sh

Show all applications in table format with sync and health status.

**Usage:**
```bash
./scripts/sync-status.sh
```

**Output:**
```
NAME          SYNC      HEALTH     AGE
plex          Synced    Healthy    45d
sonarr        Synced    Healthy    45d
radarr        OutOfSync Progressing 12m
jellyfin      Synced    Degraded   30d
```

### sync-app.sh

Sync application and wait for healthy state.

**Usage:**
```bash
./scripts/sync-app.sh <app-name>
```

**Options:**
- Retries sync if initial attempt fails
- Polls health status every 5 seconds
- Timeout after 5 minutes
- Shows resource status during sync

### diff-app.sh

Show differences between Git (desired) and cluster (current).

**Usage:**
```bash
./scripts/diff-app.sh <app-name>
```

**Output:**
- Shows unified diff of changes
- Highlights additions (green) and deletions (red)
- Empty output = no changes needed

### rollback-app.sh

Rollback application to previous revision.

**Usage:**
```bash
./scripts/rollback-app.sh <app-name> <revision>
```

**Features:**
- Shows revision history before rollback
- Confirmation prompt (can override with `--yes`)
- Waits for healthy state after rollback
- Displays what changed in rollback

### watch-sync.sh

Watch application until synced and healthy.

**Usage:**
```bash
./scripts/watch-sync.sh <app-name>
```

**Features:**
- Real-time status updates
- Shows sync progress and resource health
- Timeout after 10 minutes
- Exit on healthy or degraded

## Best Practices

### Do's ✅

1. **Always commit to Git first**
   ```bash
   # Good
   git commit && git push && ./scripts/sync-app.sh myapp
   ```

2. **Preview changes with diff**
   ```bash
   ./scripts/diff-app.sh myapp
   # Review before syncing
   ```

3. **Use sync-status before deployments**
   ```bash
   ./scripts/sync-status.sh
   # Ensure cluster is healthy before changes
   ```

4. **Enable auto-sync for stable apps**
   ```yaml
   syncPolicy:
     automated:
       prune: true
       selfHeal: true
   ```

5. **Test rollback procedure**
   ```bash
   # Know your last-good revision
   argocd app history myapp
   ```

### Don'ts ❌

1. **Never use `oc apply` directly**
   ```bash
   # Bad
   oc apply -f deployment.yaml
   
   # Good
   git add deployment.yaml
   git commit && git push
   ./scripts/sync-app.sh myapp
   ```

2. **Don't disable sync policy permanently**
   ```bash
   # Bad
   argocd app set myapp --sync-policy none
   # ArgoCD becomes useless
   ```

3. **Don't ignore diff before sync**
   ```bash
   # Bad
   ./scripts/sync-app.sh myapp  # Blind sync
   
   # Good
   ./scripts/diff-app.sh myapp  # Review first
   ./scripts/sync-app.sh myapp
   ```

4. **Don't sync without Git commit**
   ```bash
   # Bad
   vim apps/myapp/deployment.yaml
   ./scripts/sync-app.sh myapp  # Local changes not in Git
   
   # Good
   vim apps/myapp/deployment.yaml
   git commit && git push
   ./scripts/sync-app.sh myapp
   ```

## Quick Reference

### Common Commands

```bash
# List all apps
argocd app list

# Get app details
argocd app get <app-name>

# Sync app (manual)
argocd app sync <app-name>

# Wait for healthy
argocd app wait <app-name> --health --timeout 300

# Show diff
argocd app diff <app-name>

# Rollback
argocd app rollback <app-name> <revision>

# History
argocd app history <app-name>

# Delete app (removes from cluster)
argocd app delete <app-name>

# Resources
argocd app resources <app-name>

# Manifests (what's deployed)
argocd app manifests <app-name>
```

### Status Meanings

| Sync Status | Meaning |
|-------------|---------|
| Synced | Git == Cluster (desired state achieved) |
| OutOfSync | Git != Cluster (changes pending) |
| Unknown | Unable to determine sync status |

| Health Status | Meaning |
|---------------|---------|
| Healthy | All resources running and ready |
| Progressing | Resources deploying (normal during sync) |
| Degraded | Some resources unhealthy |
| Missing | Expected resources not found |
| Suspended | App intentionally paused |
| Unknown | Unable to determine health |

## When to Use This Skill

Load this skill when:
- User mentions "argocd", "sync", "gitops"
- User asks about "deployment status", "app health"
- User wants to "deploy", "update", or "rollback" applications
- User reports "out of sync", "not deploying", "stuck"
- User needs to "diff" or "preview" changes
- User asks about GitOps workflow or best practices

## Related Skills

- **openshift-debug**: For debugging unhealthy pods/PVCs identified by ArgoCD
- **sealed-secrets**: For managing secrets in GitOps workflow

## Validation

Test the scripts:
```bash
cd /home/sigtom/wow-ocp/.pi/skills/argocd-ops
./scripts/sync-status.sh
```

Expected: Table showing all ArgoCD applications with their status.
