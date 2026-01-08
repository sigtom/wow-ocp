## Example ArgoCD Workflows

Real-world scenarios for GitOps operations in the OpenShift homelab.

## Scenario 1: Upgrade Plex to New Version

**Goal**: Safely upgrade Plex from 1.32.4 to 1.32.5 with rollback plan

**Steps**:

```bash
# 1. Check current state
cd /home/sigtom/wow-ocp
./pi/skills/argocd-ops/scripts/sync-status.sh | grep plex
# Output: plex  Synced  Healthy

# 2. Update image in Git
vim apps/plex/overlays/prod/deployment.yaml
# Change: image: plexinc/pms-docker:1.32.5

# 3. Validate locally
kustomize build apps/plex/overlays/prod | oc apply --dry-run=client -f -
# No errors

# 4. Commit to Git
git add apps/plex/overlays/prod/deployment.yaml
git commit -m "feat(plex): upgrade to 1.32.5"
git push origin main

# 5. Preview what will change
.pi/skills/argocd-ops/scripts/diff-app.sh plex
# Shows image tag change

# 6. Record current revision (for rollback)
argocd app history plex | head -5
# Note revision number (e.g., 42)

# 7. Sync and watch
.pi/skills/argocd-ops/scripts/sync-app.sh plex
# Waits for healthy, shows progress

# 8. Test manually
curl -I https://plex.apps.ossus.sigtomtech.com
# Verify 200 OK

# 9. If issues arise, rollback
.pi/skills/argocd-ops/scripts/rollback-app.sh plex 42
```

**Result**: Clean upgrade with safety net

---

## Scenario 2: Deploy New Media App (Sonarr)

**Goal**: Deploy Sonarr from scratch using GitOps

**Steps**:

```bash
# 1. Create app structure
cd /home/sigtom/wow-ocp
mkdir -p apps/sonarr/{base,overlays/prod}

# 2. Create base manifests
cat > apps/sonarr/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarr
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarr
  template:
    metadata:
      labels:
        app: sonarr
    spec:
      containers:
      - name: sonarr
        image: linuxserver/sonarr:latest
        ports:
        - containerPort: 8989
        env:
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        - name: TZ
          value: "America/New_York"
        volumeMounts:
        - name: config
          mountPath: /config
        - name: media
          mountPath: /mnt/media
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: sonarr-config
      - name: media
        persistentVolumeClaim:
          claimName: media-library
EOF

cat > apps/sonarr/base/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: sonarr
spec:
  selector:
    app: sonarr
  ports:
  - port: 8989
    targetPort: 8989
EOF

cat > apps/sonarr/base/pvc.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sonarr-config
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: truenas-nfs
  resources:
    requests:
      storage: 10Gi
EOF

cat > apps/sonarr/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - pvc.yaml
EOF

# 3. Create prod overlay
mkdir -p apps/sonarr/overlays/prod

cat > apps/sonarr/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../../base
namespace: media
resources:
  - namespace.yaml
  - ingress.yaml
EOF

cat > apps/sonarr/overlays/prod/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: media
EOF

cat > apps/sonarr/overlays/prod/ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sonarr
  annotations:
    cert-manager.io/cluster-issuer: cloudflare-prod
    route.openshift.io/termination: edge
spec:
  tls:
  - hosts:
    - sonarr.apps.ossus.sigtomtech.com
    secretName: sonarr-tls
  rules:
  - host: sonarr.apps.ossus.sigtomtech.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sonarr
            port:
              number: 8989
EOF

# 4. Create ArgoCD Application
mkdir -p argocd-apps/applications

cat > argocd-apps/applications/sonarr.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sonarr
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/yourorg/wow-ocp.git
    path: apps/sonarr/overlays/prod
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: media
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# 5. Commit everything
git add apps/sonarr argocd-apps/applications/sonarr.yaml
git commit -m "feat: add sonarr deployment"
git push

# 6. Verify sync (root-app should pick it up)
.pi/skills/argocd-ops/scripts/sync-status.sh | grep sonarr

# If not auto-synced yet:
.pi/skills/argocd-ops/scripts/sync-app.sh sonarr

# 7. Watch until healthy
.pi/skills/argocd-ops/scripts/watch-sync.sh sonarr

# 8. Verify
curl https://sonarr.apps.ossus.sigtomtech.com
```

**Result**: Fully deployed app via GitOps

---

## Scenario 3: Emergency Rollback (Bad Deployment)

**Goal**: Quickly rollback multiple apps after bad Git commit

**Steps**:

```bash
# 1. Identify bad commit
cd /home/sigtom/wow-ocp
git log --oneline -10
# Found: abc1234 "feat: update all media apps"

# 2. Check which apps are unhealthy
.pi/skills/argocd-ops/scripts/sync-status.sh --unhealthy
# Output shows: plex, sonarr, radarr all Degraded

# 3. Quick Git revert
git revert abc1234
git push

# 4. Sync all affected apps
for app in plex sonarr radarr; do
  .pi/skills/argocd-ops/scripts/sync-app.sh $app &
done
wait

# 5. Verify recovery
.pi/skills/argocd-ops/scripts/sync-status.sh
# All back to Healthy
```

**Alternative: Manual revision rollback**:

```bash
# 1. Find last good revision for each app
for app in plex sonarr radarr; do
  echo "=== $app ==="
  argocd app history $app | grep Succeeded | head -2
done

# 2. Rollback each
.pi/skills/argocd-ops/scripts/rollback-app.sh plex 42 --yes
.pi/skills/argocd-ops/scripts/rollback-app.sh sonarr 38 --yes
.pi/skills/argocd-ops/scripts/rollback-app.sh radarr 51 --yes
```

**Result**: Quick recovery from bad deployment

---

## Scenario 4: Controlled Multi-App Update (Media Stack)

**Goal**: Update entire media stack with validation at each step

**Steps**:

```bash
# 1. Check current state
.pi/skills/argocd-ops/scripts/sync-status.sh | grep -E "plex|sonarr|radarr|jellyfin"
# All Synced + Healthy

# 2. Update images in Git (one commit)
vim apps/plex/overlays/prod/deployment.yaml      # Update image
vim apps/sonarr/overlays/prod/deployment.yaml    # Update image
vim apps/radarr/overlays/prod/deployment.yaml    # Update image
vim apps/jellyfin/overlays/prod/deployment.yaml  # Update image

git add apps/
git commit -m "feat(media): update all to latest versions"
git push

# 3. Preview all changes
for app in plex sonarr radarr jellyfin; do
  echo "=== Diff for $app ==="
  .pi/skills/argocd-ops/scripts/diff-app.sh $app
done

# 4. Sync one at a time (staged rollout)
.pi/skills/argocd-ops/scripts/sync-app.sh plex
# Verify plex works before continuing

.pi/skills/argocd-ops/scripts/sync-app.sh sonarr
# Verify sonarr works

.pi/skills/argocd-ops/scripts/sync-app.sh radarr
# Verify radarr works

.pi/skills/argocd-ops/scripts/sync-app.sh jellyfin
# Verify jellyfin works

# 5. Final status check
.pi/skills/argocd-ops/scripts/sync-status.sh
```

**Result**: Controlled rollout with validation gates

---

## Scenario 5: Out-of-Sync Recovery (Manual Changes)

**Goal**: Fix app that was manually edited (violating GitOps)

**Situation**: Someone ran `oc edit deployment plex -n media` directly

**Steps**:

```bash
# 1. Detect out-of-sync
.pi/skills/argocd-ops/scripts/sync-status.sh | grep plex
# Output: plex  OutOfSync  Healthy

# 2. See what's different
.pi/skills/argocd-ops/scripts/diff-app.sh plex
# Shows manual changes not in Git

# 3. Decision point:
#    A. Keep manual change → Update Git
#    B. Revert to Git → Force sync

# Option A: Update Git with manual change
oc get deployment plex -n media -o yaml > /tmp/plex-manual.yaml
# Extract the changes you want to keep
vim apps/plex/overlays/prod/deployment.yaml
# Apply the good parts of manual change

git commit -am "fix(plex): incorporate manual change to Git"
git push

.pi/skills/argocd-ops/scripts/sync-app.sh plex

# Option B: Revert to Git (discard manual change)
.pi/skills/argocd-ops/scripts/sync-app.sh plex --force --prune
# ArgoCD overwrites manual changes with Git state
```

**Result**: Git and cluster back in sync

---

## Scenario 6: Sync Wave Dependencies

**Goal**: Deploy app with database, ensuring database is ready first

**Steps**:

```bash
# 1. Add sync waves to manifests
cat > apps/myapp/overlays/prod/database.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-db
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # Deploy first
spec:
  # ... database deployment ...
EOF

cat > apps/myapp/overlays/prod/app.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Deploy after DB
spec:
  # ... app deployment ...
EOF

# 2. Commit
git add apps/myapp/overlays/prod/
git commit -m "feat(myapp): add sync waves for dependencies"
git push

# 3. Sync (ArgoCD respects wave order)
.pi/skills/argocd-ops/scripts/sync-app.sh myapp

# Watch shows:
# Wave 0: myapp-db deploying...
# Wave 0: myapp-db healthy
# Wave 1: myapp deploying...
# Wave 1: myapp healthy
```

**Result**: Ordered deployment with dependencies

---

## Best Practices from Examples

1. **Always preview with diff before sync**
2. **Record current revision before upgrades**
3. **One app at a time for critical changes**
4. **Use sync waves for dependencies**
5. **Git revert > manual rollback for multi-app issues**
6. **Validate locally with `kustomize build` before push**
7. **Use `--unhealthy` flag to quickly find problems**

## Quick Reference

```bash
# Pre-deployment checklist
./scripts/sync-status.sh              # All apps healthy?
./scripts/diff-app.sh myapp           # Preview changes
argocd app history myapp | head -3    # Note current revision

# Deployment
git commit && git push
./scripts/sync-app.sh myapp

# Post-deployment
curl https://myapp.apps.ossus.sigtomtech.com  # Test
./scripts/sync-status.sh | grep myapp          # Verify

# Emergency
./scripts/rollback-app.sh myapp <rev>
```
