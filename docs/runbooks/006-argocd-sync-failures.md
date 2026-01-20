# Runbook 006: ArgoCD Application Sync Failures

**Frequency:** Common (after Git commits, manifest changes)
**Impact:** Medium-High - Blocks deployment updates
**Last Occurred:** Ongoing (routine operations)
**MTTR:** 5-30 minutes

---

## Symptoms

- ArgoCD Application shows `OutOfSync` status
- Application health shows `Degraded` or `Unknown`
- Sync operation fails with errors
- Changes in Git not reflecting in cluster
- Red/yellow status in ArgoCD UI

**Quick Check:**
```bash
# List all applications
argocd app list

# Check specific app
argocd app get <app-name>

# View sync status
argocd app sync <app-name> --dry-run
```

---

## Root Cause Analysis

### Common Causes (Priority Order)

1. **Resource Already Exists (Server-Side Apply Conflict)** (35% of cases)
   - Resource created manually outside ArgoCD
   - Resource owned by different Application
   - Field manager conflict

2. **Invalid Manifest Syntax** (25% of cases)
   - YAML indentation error
   - Missing required fields
   - Invalid field values
   - Kustomize build failure

3. **Namespace Does Not Exist** (15% of cases)
   - Application tries to create resources before namespace
   - Namespace deleted but Application still references it

4. **RBAC / Permission Issues** (10% of cases)
   - ArgoCD service account lacks permissions
   - Namespace has admission webhooks blocking creation

5. **Resource Deletion Protected** (10% of cases)
   - PVC/PV has `Retain` policy preventing deletion
   - Finalizers blocking resource removal

6. **Git Repository Issues** (5% of cases)
   - Branch doesn't exist
   - Invalid credentials
   - Repository unreachable

---

## Diagnosis Steps

### Step 1: Check Application Status
```bash
argocd app get <app-name>
```

**Example Output:**
```
Name:               media-stack
Project:            default
Server:             https://kubernetes.default.svc
Namespace:          media-stack
URL:                https://argocd.apps.ossus.sigtomtech.com/applications/media-stack
Repo:               https://github.com/sigtom/wow-ocp.git
Target:             HEAD
Path:               apps/media-stack/base
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        OutOfSync from HEAD (abc123)
Health Status:      Degraded
```

### Step 2: View Sync Errors
```bash
argocd app sync <app-name> --dry-run
```

**Or check UI:** ArgoCD Dashboard → Application → Sync Status tab

**Common Error Patterns:**

| Error Message | Probable Cause |
|---------------|----------------|
| `the server could not find the requested resource` | CRD not installed or wrong API version |
| `field is immutable` | Trying to change immutable field (requires delete/recreate) |
| `denied by admission webhook` | OPA/Gatekeeper policy violation |
| `failed to create: AlreadyExists` | Resource exists with different owner |
| `namespace "X" not found` | Namespace missing or not synced yet |

### Step 3: Check Resource Diff
```bash
argocd app diff <app-name>
```

**Shows:**
- What's in Git vs. what's in cluster
- Fields that differ
- Resources that will be created/deleted

### Step 4: Check Application Events
```bash
oc get events -n openshift-gitops --field-selector involvedObject.name=<app-name> --sort-by='.lastTimestamp'
```

### Step 5: Check ArgoCD Controller Logs
```bash
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller --tail=100 | grep <app-name>
```

**Look for:**
- `failed to sync` - Permission or validation errors
- `rpc error: code = NotFound` - CRD or API version missing
- `field manager conflict` - Resource managed by multiple sources

### Step 6: Validate Manifest Locally
```bash
# For raw YAML
oc apply -f <manifest>.yaml --dry-run=server

# For Kustomize
kustomize build apps/<app-name>/base | oc apply --dry-run=server -f -
```

**Expected:** `created (dry run)`
**Problem:** Validation errors explaining what's wrong

---

## Resolution

### Fix 1: Resource Already Exists (Field Manager Conflict)

**Symptom:** Error shows `field managed by X but applied by Y`.

**Resolution (Option A: Adopt Resource):**
```bash
# Add ArgoCD label to existing resource
oc label <resource-type> <resource-name> -n <namespace> \
  app.kubernetes.io/instance=<app-name> --overwrite

# Add ArgoCD tracking annotation
oc annotate <resource-type> <resource-name> -n <namespace> \
  argocd.argoproj.io/tracking-id=<app-name>:<namespace>/<resource-type>/<resource-name> --overwrite

# Retry sync
argocd app sync <app-name>
```

**Resolution (Option B: Delete and Recreate):**
```bash
# Delete manually created resource (CAUTION: data loss risk)
oc delete <resource-type> <resource-name> -n <namespace>

# Sync to recreate via ArgoCD
argocd app sync <app-name>
```

### Fix 2: Invalid Manifest Syntax

**Symptom:** Sync fails with YAML parsing errors or `invalid field` messages.

**Resolution:**

1. **Validate YAML locally:**
```bash
# Check YAML syntax
yamllint apps/<app-name>/base/*.yaml

# Validate against cluster
kustomize build apps/<app-name>/base | oc apply --dry-run=server -f -
```

2. **Common Issues:**

**Indentation Error:**
```yaml
# WRONG
metadata:
name: my-app  # Missing indent
  namespace: default

# CORRECT
metadata:
  name: my-app
  namespace: default
```

**Missing Required Field:**
```yaml
# WRONG
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - port: 8080
  # MISSING: selector

# CORRECT
spec:
  selector:
    app: my-app
  ports:
    - port: 8080
```

3. **Fix and commit:**
```bash
git add apps/<app-name>/base/*.yaml
git commit -m "fix: correct YAML syntax in <app-name>"
git push origin main
```

4. **Sync:**
```bash
argocd app sync <app-name>
```

### Fix 3: Namespace Does Not Exist

**Symptom:** Error shows `namespace "X" not found`.

**Resolution:**

**Option A: Enable Auto-Namespace Creation (Recommended):**

**File:** `argocd-apps/<app-name>.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: openshift-gitops
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true  # ADD THIS
```

**Option B: Create Namespace Separately:**

**File:** `apps/<app-name>/base/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <app-name>
```

**Update Kustomization:**
```yaml
resources:
  - namespace.yaml  # Add to top of list
  - deployment.yaml
  - service.yaml
```

### Fix 4: RBAC / Permission Issues

**Symptom:** Error shows `forbidden: User "system:serviceaccount:openshift-gitops:..." cannot...`

**Resolution:**

1. **Check ArgoCD service account permissions:**
```bash
oc auth can-i create deployment --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller -n <namespace>
```

2. **Grant permissions (if needed):**

**File:** `infrastructure/gitops/argocd-rbac.yaml`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-application-controller-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin  # Or more restricted role
subjects:
  - kind: ServiceAccount
    name: openshift-gitops-argocd-application-controller
    namespace: openshift-gitops
```

**Apply:**
```bash
oc apply -f infrastructure/gitops/argocd-rbac.yaml
```

### Fix 5: Resource Deletion Protected (Finalizers)

**Symptom:** Application stuck in `Deleting` state, resources have finalizers preventing deletion.

**Resolution:**

1. **Check finalizers:**
```bash
oc get <resource-type> <resource-name> -n <namespace> -o jsonpath='{.metadata.finalizers}'
```

2. **Remove finalizers (CAUTION):**
```bash
oc patch <resource-type> <resource-name> -n <namespace> \
  -p '{"metadata":{"finalizers":[]}}' --type=merge
```

**⚠️ WARNING:** Only remove finalizers if you understand the impact (e.g., orphaned cloud resources).

### Fix 6: Immutable Field Change

**Symptom:** Error shows `field is immutable` (e.g., PVC `storageClassName`).

**Resolution:**

**Cannot be fixed in-place. Must delete and recreate.**

1. **Backup data (if PVC):**
```bash
# For PVCs, create snapshot or copy data
oc exec deployment/<app> -- tar czf /tmp/backup.tar.gz /data
oc cp <pod>:/tmp/backup.tar.gz ./backup.tar.gz
```

2. **Delete resource:**
```bash
oc delete <resource-type> <resource-name> -n <namespace>
```

3. **Update manifest with correct value**

4. **Sync to recreate:**
```bash
argocd app sync <app-name>
```

5. **Restore data (if needed)**

---

## Prevention

### 1. Use Automated Sync with Caution

**Recommended:**
```yaml
syncPolicy:
  automated:
    prune: true      # Auto-delete removed resources
    selfHeal: true   # Auto-correct drift
  syncOptions:
    - CreateNamespace=true
    - PruneLast=true  # Delete resources last (safer)
```

**For Critical Apps (Manual Sync):**
```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true
  # NO automated section - requires manual sync
```

### 2. Validate Before Commit

**Pre-commit hook:** `.git/hooks/pre-commit`

```bash
#!/bin/bash
set -e

echo "Validating manifests..."

# Check YAML syntax
find apps/ infrastructure/ -name "*.yaml" -exec yamllint {} \;

# Validate Kustomize builds
for dir in $(find apps/ -type f -name kustomization.yaml -exec dirname {} \;); do
  echo "Building $dir..."
  kustomize build "$dir" | oc apply --dry-run=server -f - || exit 1
done

echo "✓ All validations passed"
```

**Make executable:**
```bash
chmod +x .git/hooks/pre-commit
```

### 3. Use App-of-Apps for Dependency Ordering

**File:** `root-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/sigtom/wow-ocp.git
    targetRevision: HEAD
    path: argocd-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
  syncPolicy:
    automated:
      prune: false  # Don't auto-delete apps
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Benefits:**
- Single Application manages all others
- Sync order: infrastructure → operators → apps
- Easier to reason about dependencies

### 4. Set Up Health Checks

**Custom Health Check Example:**

**File:** `argocd-apps/<app-name>.yaml`

```yaml
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
  # Custom health check for Deployment
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas  # Ignore HPA-managed replicas
```

---

## Troubleshooting

### Issue: Sync Hangs at "Progressing" Forever

**Symptom:** Application stuck in `Progressing` state, never reaches `Healthy`.

**Cause:** Resource health check failing (e.g., pod not starting).

**Fix:**
```bash
# Check resource status
argocd app resources <app-name>

# Check specific resource health
oc get <resource-type> -n <namespace>

# Check pod events
oc describe pod <pod-name> -n <namespace>
```

### Issue: Application Shows "Unknown" Health

**Symptom:** Health status is gray/unknown instead of green/red.

**Cause:** ArgoCD doesn't know how to check health for custom CRD.

**Fix:**

**Define custom health check:**

**File:** `infrastructure/gitops/argocd-cm.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: openshift-gitops
data:
  resource.customizations: |
    example.com/MyCustomResource:
      health.lua: |
        hs = {}
        if obj.status ~= nil then
          if obj.status.phase == "Ready" then
            hs.status = "Healthy"
            hs.message = "Resource is ready"
            return hs
          end
        end
        hs.status = "Progressing"
        hs.message = "Waiting for resource"
        return hs
```

### Issue: Diff Shows Changes But Nothing Actually Different

**Symptom:** ArgoCD shows resources out of sync, but diff looks identical.

**Cause:** Server-side defaulting or mutating webhooks changing values.

**Fix:**

**Add ignore rule:**

**File:** `argocd-apps/<app-name>.yaml`

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/template/spec/containers/0/resources  # Ignore LimitRange defaults
    - group: ""
      kind: Service
      jsonPointers:
        - /spec/clusterIP  # Ignore auto-assigned IP
        - /spec/clusterIPs
```

---

## Related Issues

- **Issue:** GitOps operator metrics (2025-12-21)
- **Runbook:** [007-gitops-operator-health.md](007-gitops-operator-health.md)
- **Documentation:** `infrastructure/operators/openshift-gitops-operator/`

---

## Lessons Learned

1. **Validate locally first** - Use `--dry-run=server` before commit
2. **Use `CreateNamespace=true`** - Prevents namespace ordering issues
3. **Don't mix manual and GitOps** - Pick one ownership model per resource
4. **Ignore auto-generated fields** - ClusterIP, replicas (if HPA), etc.
5. **Test sync with `--dry-run`** - Preview changes before applying

---

## Verification Checklist

- [ ] Application shows `Synced` status
- [ ] Application shows `Healthy` status
- [ ] All resources show green checkmarks in ArgoCD UI
- [ ] `argocd app diff <app-name>` shows no differences
- [ ] Pods are `Running` and passing health checks
- [ ] No error events: `oc get events -n <namespace>`

---

**Document Version:** 1.0
**Last Updated:** 2026-01-08
**Owner:** SRE Team
