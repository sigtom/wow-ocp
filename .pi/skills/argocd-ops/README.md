# ArgoCD Operations Skill

GitOps management toolkit for OpenShift 4.20 homelab using ArgoCD.

## Prerequisites & Login

The argocd CLI requires gRPC access. Since gRPC ingress is typically disabled in OpenShift, use port-forward.

**Easy way (recommended):**
```bash
# Helper script handles port-forward + login
./scripts/argocd-login.sh --keep-alive
```

**Manual way:**
```bash
# Start port-forward (keep running in background)
oc port-forward -n openshift-gitops svc/openshift-gitops-server 8443:443 &

# Login
argocd login localhost:8443 --username admin --insecure

# Get password
oc get secret -n openshift-gitops openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d
```

**No argocd CLI?** Use `scripts/sync-status-oc.sh` which uses `oc` directly.

## Quick Start

```bash
# Check all app status
./scripts/sync-status.sh

# Sync an app and wait for healthy
./scripts/sync-app.sh plex

# Preview what would change
./scripts/diff-app.sh plex

# Rollback to previous version
./scripts/rollback-app.sh plex 42

# Watch sync progress
./scripts/watch-sync.sh plex
```

## Features

✅ **Status Monitoring**
- Table view of all apps with sync/health status
- Color-coded output (green=good, yellow=warning, red=error)
- Summary statistics

✅ **Controlled Sync**
- Sync and wait for healthy state
- Progress monitoring
- Timeout handling
- Prune and force options

✅ **Change Preview**
- Diff between Git and cluster
- See exactly what will change
- Prevent surprise deployments

✅ **Safe Rollback**
- Interactive revision selection
- Confirmation prompt
- Wait for healthy after rollback

✅ **Real-Time Watching**
- Live status updates
- Resource health tracking
- Timeout with status summary

## GitOps Workflow

### The Golden Path

```bash
# 1. Make changes in Git
vim apps/myapp/overlays/prod/deployment.yaml
git commit -am "feat: update myapp to v2.0"
git push

# 2. Preview changes
./scripts/diff-app.sh myapp

# 3. Sync application
./scripts/sync-app.sh myapp

# 4. Verify status
./scripts/sync-status.sh | grep myapp
```

### App of Apps Pattern

```
argocd-apps/
├── root-app.yaml              # Bootstrap (deploys all apps)
├── infrastructure/
│   ├── cert-manager.yaml
│   └── sealed-secrets.yaml
└── applications/
    ├── plex.yaml
    └── sonarr.yaml
```

Deploy everything:
```bash
oc apply -f argocd-apps/root-app.yaml
./scripts/sync-app.sh root-app
```

## Common Issues

### App Stuck OutOfSync

**Cause**: Manual changes or disabled auto-sync

**Fix**:
```bash
./scripts/diff-app.sh myapp     # See what's different
./scripts/sync-app.sh myapp --force --prune
```

### App Stuck Progressing

**Cause**: Pod issues, PVC pending, probe failures

**Fix**:
```bash
# Check what's unhealthy
argocd app resources myapp | grep -v Healthy

# Debug the issue
../openshift-debug/scripts/check-pod.sh <pod-name> <namespace>

# Rollback if needed
./scripts/rollback-app.sh myapp <last-good-revision>
```

### Sync Failed

**Cause**: Invalid manifests, missing CRDs, RBAC issues

**Fix**:
```bash
# Validate locally first
kustomize build apps/myapp/overlays/prod | oc apply --dry-run=client -f -

# Check ArgoCD logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

## Best Practices

✅ **Do:**
- Always commit to Git first
- Preview changes with diff before sync
- Use sync-status before deployments
- Test rollback procedures

❌ **Don't:**
- Never use `oc apply` directly (breaks GitOps)
- Don't disable auto-sync permanently
- Don't sync without reviewing diff
- Don't commit without testing locally

## Documentation

- **Full Guide**: [SKILL.md](SKILL.md)
- **Examples**: [examples/](examples/)
- **Quick Ref**: [references/](references/)

## Validation

```bash
# Check ArgoCD access
argocd app list

# Test scripts
./scripts/sync-status.sh
```
