# ArgoCD Operations - Quick Start

## First Time Setup

```bash
# Port-forward for argocd CLI (gRPC not exposed via route)
oc port-forward -n openshift-gitops svc/openshift-gitops-server 8443:443 &

# Login
argocd login localhost:8443 --username admin --insecure
# Password: oc get secret -n openshift-gitops openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d
```

## 30-Second Workflow

```bash
# Check status
.pi/skills/argocd-ops/scripts/sync-status.sh

# Deploy changes
.pi/skills/argocd-ops/scripts/sync-app.sh myapp

# Watch progress
.pi/skills/argocd-ops/scripts/watch-sync.sh myapp
```

## Common Scenarios

### Deploy New App

```bash
# 1. Create manifests in Git
mkdir -p apps/myapp/{base,overlays/prod}
# Create deployment.yaml, service.yaml, etc.

# 2. Create ArgoCD Application
cat > argocd-apps/applications/myapp.yaml <<EOF
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
EOF

# 3. Commit to Git
git add apps/myapp argocd-apps/applications/myapp.yaml
git commit -m "feat: add myapp"
git push

# 4. Sync
./scripts/sync-app.sh myapp
```

### Update Existing App

```bash
# 1. Update manifest
vim apps/plex/overlays/prod/deployment.yaml
# Change image tag

git commit -am "feat(plex): upgrade to v1.32.5"
git push

# 2. Preview changes
./scripts/diff-app.sh plex

# 3. Sync
./scripts/sync-app.sh plex
```

### Rollback After Failed Deploy

```bash
# 1. Check history
argocd app history plex

# 2. Rollback
./scripts/rollback-app.sh plex 42  # Replace 42 with good revision
```

## Key Commands

```bash
# Status of all apps
./scripts/sync-status.sh

# Sync and wait
./scripts/sync-app.sh <app> [--prune] [--force]

# Show what would change
./scripts/diff-app.sh <app>

# Rollback
./scripts/rollback-app.sh <app> <revision>

# Watch until healthy
./scripts/watch-sync.sh <app>
```

## The Golden Rule

> **Git is source of truth. Never `oc apply` directly.**

```bash
# ❌ BAD
oc apply -f deployment.yaml

# ✅ GOOD
git add deployment.yaml
git commit && git push
./scripts/sync-app.sh myapp
```

## Troubleshooting

### App Stuck OutOfSync
```bash
./scripts/diff-app.sh myapp           # See difference
./scripts/sync-app.sh myapp --force   # Force sync
```

### App Degraded
```bash
argocd app resources myapp | grep -v Healthy  # Find unhealthy
../openshift-debug/scripts/check-pod.sh <pod> <ns>
```

### Sync Failed
```bash
argocd app get myapp -o yaml | grep -A 20 conditions
# Check error message
```

## Documentation

- **Full Guide**: [SKILL.md](SKILL.md)
- **README**: [README.md](README.md)
