# ArgoCD Operations Quick Reference

Fast lookup guide for common ArgoCD operations.

## Script Commands

```bash
# Show all app status
./scripts/sync-status.sh
./scripts/sync-status.sh --unhealthy           # Only problematic apps
./scripts/sync-status.sh --namespace media     # Filter by namespace

# Sync application
./scripts/sync-app.sh <app>
./scripts/sync-app.sh <app> --prune            # Delete resources not in Git
./scripts/sync-app.sh <app> --force            # Force even if synced
./scripts/sync-app.sh <app> --no-wait          # Don't wait for healthy

# Show diff
./scripts/diff-app.sh <app>
./scripts/diff-app.sh <app> --local apps/myapp # Diff local changes
./scripts/diff-app.sh <app> --revision HEAD~1  # Diff against prev commit

# Rollback
./scripts/rollback-app.sh <app>                # Interactive (shows history)
./scripts/rollback-app.sh <app> <revision>     # Direct rollback
./scripts/rollback-app.sh <app> <rev> --yes    # Skip confirmation

# Watch
./scripts/watch-sync.sh <app>
./scripts/watch-sync.sh <app> --timeout 1200   # 20min timeout
./scripts/watch-sync.sh <app> --interval 2     # Update every 2s
```

## Native ArgoCD CLI Commands

```bash
# List applications
argocd app list
argocd app list -o wide                        # More details

# Get app details
argocd app get <app>
argocd app get <app> -o yaml                   # Full YAML
argocd app get <app> -o json                   # JSON format

# Sync operations
argocd app sync <app>
argocd app sync <app> --prune                  # Delete removed resources
argocd app sync <app> --force                  # Bypass sync window
argocd app sync <app> --timeout 600            # Wait up to 10min

# Wait for conditions
argocd app wait <app> --health                 # Wait for healthy
argocd app wait <app> --health --timeout 300   # 5min timeout

# Diff
argocd app diff <app>
argocd app diff <app> --local apps/myapp       # Local changes

# History
argocd app history <app>
argocd app history <app> --output wide         # More columns

# Rollback
argocd app rollback <app> <revision>
argocd app rollback <app> <revision> --timeout 300

# Resources
argocd app resources <app>                     # List all resources
argocd app manifests <app>                     # Show deployed manifests

# Delete
argocd app delete <app>                        # Remove app (keeps resources)
argocd app delete <app> --cascade              # Remove app AND resources

# Set
argocd app set <app> --sync-policy automated   # Enable auto-sync
argocd app set <app> --sync-policy none        # Disable auto-sync
```

## Status Meanings

### Sync Status

| Status | Meaning | Action |
|--------|---------|--------|
| Synced | Git == Cluster | ✅ Good |
| OutOfSync | Git != Cluster | Sync needed |
| Unknown | Cannot determine | Check ArgoCD |

### Health Status

| Status | Meaning | Action |
|--------|---------|--------|
| Healthy | All resources ready | ✅ Good |
| Progressing | Deploying (normal) | Wait |
| Degraded | Some unhealthy | Debug resources |
| Missing | Resources not found | Check manifests |
| Suspended | Intentionally paused | Resume if needed |
| Unknown | Cannot determine | Check ArgoCD |

## Common Patterns

### Pre-Deployment Checklist

```bash
# 1. Ensure cluster healthy
./scripts/sync-status.sh

# 2. Validate manifests locally
kustomize build apps/myapp/overlays/prod | oc apply --dry-run=client -f -

# 3. Preview changes
./scripts/diff-app.sh myapp

# 4. Note current revision (for rollback)
argocd app history myapp | head -3
```

### Standard Deployment Flow

```bash
# 1. Make changes
vim apps/myapp/overlays/prod/deployment.yaml

# 2. Commit to Git
git add apps/myapp
git commit -m "feat: update myapp"
git push

# 3. Sync
./scripts/sync-app.sh myapp

# 4. Verify
curl https://myapp.apps.ossus.sigtomtech.com
./scripts/sync-status.sh | grep myapp
```

### Emergency Rollback

```bash
# Find last good revision
argocd app history <app> | grep Succeeded | head -1

# Rollback
./scripts/rollback-app.sh <app> <revision> --yes
```

### Multi-App Operations

```bash
# Sync all media apps
for app in plex sonarr radarr jellyfin; do
  ./scripts/sync-app.sh $app &
done
wait

# Check status
./scripts/sync-status.sh | grep -E "plex|sonarr|radarr|jellyfin"
```

## Troubleshooting Cheat Sheet

| Symptom | Likely Cause | Solution |
|---------|-------------|----------|
| OutOfSync | Manual changes or auto-sync disabled | `./scripts/sync-app.sh <app> --force --prune` |
| Progressing >5min | Pod/PVC issues | `../openshift-debug/scripts/check-pod.sh` |
| Degraded | Resource unhealthy | `argocd app resources <app> \| grep -v Healthy` |
| Sync Failed | Invalid manifests | `kustomize build ... \| oc apply --dry-run` |
| Missing resources | Deleted in Git but not pruned | `./scripts/sync-app.sh <app> --prune` |

## ArgoCD Application YAML Template

```yaml
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
      prune: true       # Delete resources not in Git
      selfHeal: true    # Auto-sync when drift detected
    syncOptions:
      - CreateNamespace=true
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas  # Ignore HPA changes
```

## Sync Options Reference

```yaml
syncOptions:
  - CreateNamespace=true        # Create namespace if missing
  - PruneLast=true              # Delete resources after new ones healthy
  - ApplyOutOfSyncOnly=true     # Only update changed resources
  - RespectIgnoreDifferences=true
  - Validate=false              # Skip validation (use carefully)
```

## Sync Wave Examples

```yaml
# Wave 0: Foundation (namespace, PVCs)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Wave 1: Databases
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"

# Wave 2: Applications
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"

# Wave 3: Ingress/Routes
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "3"
```

## Health Assessment Customization

```yaml
# Custom health check for CRD
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  ignoreDifferences:
    - group: example.com
      kind: MyCustomResource
      jsonPointers:
        - /status
```

## Environment-Specific Overrides

```bash
# Dev environment
argocd app create myapp-dev \
  --repo https://github.com/org/repo.git \
  --path apps/myapp/overlays/dev \
  --dest-namespace myapp-dev \
  --sync-policy automated

# Prod environment
argocd app create myapp-prod \
  --repo https://github.com/org/repo.git \
  --path apps/myapp/overlays/prod \
  --dest-namespace myapp-prod \
  --sync-policy none
```

## Useful Filters and Queries

```bash
# Apps by sync status
argocd app list -o json | jq '.[] | select(.status.sync.status == "OutOfSync") | .metadata.name'

# Apps by health
argocd app list -o json | jq '.[] | select(.status.health.status == "Degraded") | .metadata.name'

# Apps in namespace
argocd app list -o json | jq '.[] | select(.spec.destination.namespace == "media") | .metadata.name'

# Apps with auto-sync
argocd app list -o json | jq '.[] | select(.spec.syncPolicy.automated != null) | .metadata.name'
```

## ArgoCD Server Access

```bash
# Get ArgoCD URL
oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}'

# Get admin password
oc get secret -n openshift-gitops openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d

# Login
argocd login openshift-gitops-server-openshift-gitops.apps.ossus.sigtomtech.com
```

## Exit Codes

### sync-status.sh
- `0` = All apps healthy
- `1` = Some apps degraded
- `2` = Some apps out of sync

### sync-app.sh
- `0` = Synced and healthy
- `1` = Sync failed or timeout
- `2` = Synced but unhealthy

### diff-app.sh
- `0` = No diff (in sync)
- `1` = Error
- `2` = Has diff (out of sync)

### rollback-app.sh
- `0` = Rollback successful and healthy
- `1` = Rollback failed
- `2` = Rollback succeeded but unhealthy

### watch-sync.sh
- `0` = Synced and healthy
- `1` = Timeout
- `2` = Synced but degraded
