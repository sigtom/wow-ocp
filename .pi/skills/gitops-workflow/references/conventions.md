# GitOps Conventions and Standards

This document details the conventions, standards, and best practices for the wow-ocp GitOps repository.

---

## Conventional Commits

### Format

```
<type>(<scope>): <short description>

<optional detailed body>

<optional footer>
```

### Types

| Type | Purpose | Example |
|------|---------|---------|
| `feat` | New feature or application | `feat: add Sonarr deployment` |
| `fix` | Bug fix or issue resolution | `fix: correct Plex PVC permissions` |
| `docs` | Documentation changes | `docs: update media-stack README` |
| `refactor` | Code restructuring (no functional change) | `refactor: consolidate rclone ConfigMap` |
| `chore` | Maintenance tasks | `chore: bump cert-manager to v1.14.0` |
| `ci` | CI/CD pipeline changes | `ci: add GitHub Actions for validation` |
| `test` | Test additions or modifications | `test: add integration test for DNS` |
| `perf` | Performance improvements | `perf: optimize Prometheus query` |
| `style` | Formatting, whitespace (no code change) | `style: fix YAML indentation` |
| `revert` | Revert a previous commit | `revert: revert "feat: add XYZ"` |

### Scope (Optional)

Scope provides additional context about which part of the codebase changed.

**Examples:**
- `feat(media-stack): add Bazarr for subtitles`
- `fix(storage): resolve LVM thin pool deadlock`
- `docs(argocd): update sync troubleshooting guide`

### Description

- Use imperative mood ("add" not "added" or "adds")
- Lowercase first letter (unless proper noun)
- No period at the end
- Max 72 characters

**Good:**
```
feat: add Technitium DNS deployment
fix: correct Sonarr mount propagation
docs: update GitOps workflow documentation
```

**Bad:**
```
feat: Added new DNS server.
fix: Fixed the mount issue in Sonarr
docs: Documentation update
```

### Body (Optional)

Use body for:
- Explaining **why** the change was made
- Providing context or background
- Referencing related issues

**Example:**
```
feat: migrate DNS from Pi-hole to Technitium

Pi-hole lacked native Kubernetes integration and required
manual configuration. Technitium provides API-first
management and better integration with GitOps workflows.

Refs: #42
```

### Footer (Optional)

Use footer for:
- Breaking changes: `BREAKING CHANGE: <description>`
- Issue references: `Fixes #123`, `Closes #456`, `Refs #789`
- Co-authors: `Co-authored-by: Name <email>`

**Example:**
```
fix: update ArgoCD API version to v1alpha1

BREAKING CHANGE: ArgoCD applications now use apiVersion
networking.k8s.io/v1 instead of networking.k8s.io/v1beta1.
Update all Application CRDs before applying.

Fixes #89
```

### Examples

**Simple feature:**
```
feat: add Prowlarr for indexer management
```

**Bug fix with context:**
```
fix: resolve Plex unable to access media library

Plex pod couldn't read /mnt/media due to FUSE mount propagation
issue. Added rclone sidecar with bidirectional mount propagation
to resolve.

Fixes #52
```

**Documentation update:**
```
docs: add TorBox configuration to media-stack README
```

**Breaking change:**
```
refactor: change NFS StorageClass from truenas-nfs to truenas-nfs-dynamic

BREAKING CHANGE: All PVCs must be manually migrated to new
StorageClass. Backup data before migration.

Migration guide: docs/storage-migration.md
```

---

## Branch Naming

### Format

```
<type>/<short-description>
```

### Types

| Type | Purpose |
|------|---------|
| `feature` | New features or applications |
| `fix` | Bug fixes or issue resolution |
| `docs` | Documentation changes |
| `refactor` | Code restructuring |
| `chore` | Maintenance tasks |

### Description

- Use kebab-case (lowercase with hyphens)
- Be descriptive but concise
- Avoid special characters

**Good:**
```
feature/add-bazarr-deployment
fix/sonarr-pvc-permissions
docs/update-media-stack-readme
refactor/consolidate-rclone-configmap
chore/bump-prometheus-version
```

**Bad:**
```
new_feature
fix_bug
docs
my-branch
```

### Branch Lifecycle

**Create:**
```bash
git checkout -b feature/add-new-app
```

**Push:**
```bash
git push origin feature/add-new-app
```

**Delete after merge:**
```bash
# Delete local branch
git branch -d feature/add-new-app

# Delete remote branch
git push origin --delete feature/add-new-app
```

### Protected Branches

- `main` - production, requires PR and review
- `develop` - staging (if used), requires PR

**Never:**
- Commit directly to `main`
- Force push to `main` (`git push --force`)
- Delete `main` branch

---

## Repository Structure

### Directory Layout

```
wow-ocp/
├── apps/                      # Application deployments (namespaced)
├── infrastructure/            # Cluster-wide services
├── argocd-apps/               # ArgoCD Application CRDs
├── automation/                # Ansible for out-of-cluster
├── .pi/                       # Agent skills and documentation
├── SYSTEM.md                  # System prompt (immutable)
├── PROGRESS.md                # Project log (append-only)
├── README.md                  # Repository overview
└── .gitignore                 # Ignored files
```

### apps/

**Purpose:** Application deployments (one app per directory)

**Structure:**
```
apps/
├── <app-name>/
│   ├── base/                  # Kustomize base
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── configmap.yaml     # (if needed)
│   │   ├── sealed-secret.yaml # (encrypted secrets)
│   │   └── kustomization.yaml
│   ├── overlays/
│   │   ├── dev/               # (if multi-env)
│   │   └── prod/
│   │       ├── kustomization.yaml
│   │       └── patches.yaml
│   └── README.md              # (optional) app-specific docs
```

**Conventions:**
- App name = namespace name (e.g., `apps/sonarr/` → namespace: `sonarr`)
- Use Kustomize for all manifests (no raw YAML in root)
- Base contains all standard resources
- Overlays contain environment-specific patches

**Example: Sonarr**
```
apps/sonarr/
├── base/
│   ├── deployment.yaml        # Sonarr + rclone sidecars
│   ├── service.yaml           # ClusterIP service
│   ├── ingress.yaml           # Route with TLS
│   ├── pvc.yaml               # Persistent storage
│   └── kustomization.yaml     # References all above
└── README.md                  # Sonarr setup and config notes
```

### infrastructure/

**Purpose:** Cluster-wide services (not namespaced or shared)

**Structure:**
```
infrastructure/
├── storage/
│   ├── democratic-csi/        # NFS provisioner
│   ├── lvms/                  # Local LVM storage
│   └── media/                 # Static PVs for media library
├── operators/
│   ├── sealed-secrets/        # Bitnami Sealed Secrets
│   ├── cert-manager/          # Certificate management
│   └── metallb/               # Load balancer
├── networking/
│   ├── multus/                # Additional networks
│   └── network-policies/      # Cluster-wide policies
├── monitoring/
│   ├── prometheus/            # Metrics collection
│   ├── grafana/               # Dashboards
│   └── alertmanager/          # Alerting
├── virtualization/
│   └── kubevirt/              # VM management
└── argocd/                    # ArgoCD installation
    └── bootstrap/             # Initial ArgoCD setup
```

**Conventions:**
- Organized by function (storage, operators, networking)
- May span multiple namespaces (e.g., monitoring)
- Use Kustomize for consistency

### argocd-apps/

**Purpose:** ArgoCD Application CRDs that sync from Git

**Structure:**
```
argocd-apps/
├── root-app.yaml              # App of Apps (bootstraps cluster)
├── sonarr.yaml                # Deploys apps/sonarr/
├── plex.yaml                  # Deploys apps/plex/
├── democratic-csi.yaml        # Deploys infrastructure/storage/democratic-csi/
└── ...
```

**Convention:**
- One Application CRD per app or infrastructure component
- Name matches app directory (e.g., `sonarr.yaml` → `apps/sonarr/`)
- All Applications are tracked by `root-app.yaml` (App of Apps pattern)

**Example: Sonarr Application**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sonarr
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/sigtom/wow-ocp.git
    targetRevision: HEAD
    path: apps/sonarr/base
  destination:
    server: https://kubernetes.default.svc
    namespace: sonarr
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### automation/

**Purpose:** Ansible playbooks for out-of-cluster automation

**Structure:**
```
automation/
├── inventory/
│   └── hosts.yaml             # Proxmox hosts, VMs, LXCs
├── group_vars/
│   └── all.yaml               # Global variables
├── playbooks/
│   ├── deploy-vm.yaml         # Deploy Proxmox VM
│   └── deploy-lxc.yaml        # Deploy LXC container
└── roles/
    ├── proxmox_vm/            # VM provisioning role
    ├── proxmox_lxc/           # LXC provisioning role
    ├── technitium_dns/        # DNS server setup
    └── technitium_record/     # DNS record management
```

**Conventions:**
- Ansible for Proxmox VMs/LXCs (not managed by ArgoCD)
- Also used for external DNS, backup scripts, etc.
- Does not interact with OpenShift cluster directly

### .pi/

**Purpose:** Agent skills and internal documentation

**Structure:**
```
.pi/
└── skills/
    ├── gitops-workflow/       # This skill
    ├── sealed-secrets/        # Secret encryption
    ├── argocd-ops/            # ArgoCD operations
    ├── capacity-planning/     # Resource tracking
    └── ...
```

**Convention:**
- Skills follow Agent Skills standard
- SKILL.md + references/ + templates/ + scripts/
- Not synced by ArgoCD (documentation only)

---

## PR Workflow

### 1. Create Branch

```bash
git checkout main
git pull origin main
git checkout -b feature/add-new-app
```

### 2. Make Changes

```bash
# Edit files
vim apps/new-app/base/deployment.yaml

# Stage changes
git add apps/new-app/
```

### 3. Validate

```bash
./scripts/validate.sh apps/new-app/base
```

### 4. Commit

```bash
git commit -m "feat: add new app deployment"
```

### 5. Push

```bash
git push origin feature/add-new-app
```

### 6. Create PR

- Go to GitHub
- Create Pull Request
- Base: `main`, Compare: `feature/add-new-app`
- Fill PR template

### 7. Review

- Self-review or request team review
- Address feedback
- Merge when approved

### 8. Verify

```bash
# After merge
argocd app sync new-app
oc get pods -n new-app
```

### 9. Update PROGRESS.md

```bash
./scripts/update-progress.sh "Deployed new app"
```

### 10. Cleanup

```bash
git checkout main
git pull origin main
git branch -d feature/add-new-app
git push origin --delete feature/add-new-app
```

---

## File Naming Conventions

### YAML Files

**Standard Kubernetes resources:**
- `deployment.yaml` - Deployment resource
- `service.yaml` - Service resource
- `ingress.yaml` - Ingress or Route
- `configmap.yaml` - ConfigMap
- `sealed-secret.yaml` - SealedSecret (encrypted)
- `pvc.yaml` - PersistentVolumeClaim
- `networkpolicy.yaml` - NetworkPolicy

**Multiple resources of same type:**
- `deployment-app.yaml`
- `deployment-sidecar.yaml`
- `service-main.yaml`
- `service-metrics.yaml`

**Kustomize:**
- `kustomization.yaml` - Kustomize config (never `kustomization.yml`)
- `patches.yaml` - Kustomize patches
- `resources.yaml` - Additional resources

### Documentation

- `README.md` - Directory or app overview
- `CHANGELOG.md` - Version history (if versioned)
- `CONTRIBUTING.md` - Contribution guidelines (repo root)

### Scripts

- Use `.sh` extension for shell scripts
- Use executable permissions: `chmod +x script.sh`
- Include shebang: `#!/bin/bash`

**Examples:**
```
scripts/validate.sh
scripts/new-branch.sh
scripts/sync-check.sh
```

---

## YAML Style Guide

### Indentation

**Use 2 spaces (never tabs):**
```yaml
# Good
apiVersion: v1
kind: Service
metadata:
  name: my-service

# Bad
apiVersion: v1
kind: Service
metadata:
    name: my-service  # 4 spaces
```

### Quotes

**Use double quotes for strings with special characters:**
```yaml
# Good
annotations:
  description: "This is a description with: colons"

# Bad
annotations:
  description: This is a description with: colons  # Syntax error
```

**No quotes for simple strings:**
```yaml
# Good
name: my-app

# Unnecessary
name: "my-app"
```

### Lists

**Use `-` for lists (not inline):**
```yaml
# Good
args:
  - --config=/etc/app/config.yaml
  - --verbose

# Bad (inline)
args: [--config=/etc/app/config.yaml, --verbose]
```

### Multi-line Strings

**Use `|` for literal blocks (preserves newlines):**
```yaml
script: |
  #!/bin/bash
  echo "Starting app"
  ./start.sh
```

**Use `>` for folded blocks (wraps lines):**
```yaml
description: >
  This is a long description that
  will be folded into a single line.
```

### Resource Ordering

**Standard order within a file:**
1. `apiVersion`
2. `kind`
3. `metadata`
4. `spec`
5. `status` (rarely included, usually generated)

**Metadata fields:**
1. `name`
2. `namespace` (if applicable)
3. `labels`
4. `annotations`

---

## Manifest Best Practices

### Resource Requests and Limits

**Always include for Deployments:**
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "2000m"
```

**Exceptions:**
- Jobs/CronJobs (short-lived)
- Init containers (if minimal usage)

### Health Probes

**Always include for Deployments:**
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

### Labels

**Standard labels:**
```yaml
metadata:
  labels:
    app: my-app
    app.kubernetes.io/name: my-app
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: my-system
    app.kubernetes.io/managed-by: argocd
```

### Namespace

**Always specify namespace (except cluster-scoped resources):**
```yaml
metadata:
  name: my-app
  namespace: my-namespace  # Always explicit
```

### Secrets

**Never commit raw Secrets:**
```yaml
# NEVER DO THIS
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
data:
  password: bXlwYXNzd29yZA==  # Base64 is NOT encryption
```

**Always use SealedSecrets:**
```yaml
# DO THIS
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-secret
spec:
  encryptedData:
    password: AgBH8f3k...  # Encrypted with kubeseal
```

---

## Git Best Practices

### Commit Frequency

- Commit often (logical chunks)
- Don't commit half-finished work
- One logical change per commit

### Commit Size

**Good commit:**
```
feat: add Sonarr deployment

- Deployment with rclone sidecar
- PVC for persistent storage
- Service and Ingress
- NetworkPolicy

4 files changed, 150 insertions(+)
```

**Too large commit (split into multiple):**
```
feat: add entire media stack

- Sonarr, Radarr, Plex, Bazarr, Prowlarr
- All PVCs and ConfigMaps
- NetworkPolicies for all apps

23 files changed, 2000 insertions(+)
```

### Branch Lifetime

- Keep branches short-lived (1-2 days max)
- Merge frequently to avoid conflicts
- Delete branches after merge

### Pull Strategy

**Always pull before creating branch:**
```bash
git checkout main
git pull origin main
git checkout -b feature/new-work
```

**Rebase on main if branch is outdated:**
```bash
git fetch origin
git rebase origin/main
```

---

## Validation Requirements

### yamllint

**Configuration:** `.yamllint`
```yaml
extends: default
rules:
  line-length:
    max: 120
  indentation:
    spaces: 2
```

### Kustomize Build

**Must build without errors:**
```bash
cd apps/my-app/base
kustomize build .
```

### Dry-Run

**Must pass dry-run:**
```bash
kustomize build apps/my-app/base | oc apply --dry-run=client -f -
```

### Resource Limits Check

**Every Deployment must have resources:**
```bash
grep -q "resources:" deployment.yaml
```

### Sealed Secrets Check

**No raw Secrets allowed:**
```bash
! grep -q "kind: Secret" *.yaml
```

---

## ArgoCD Integration

### Application CRD

**Standard template:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/sigtom/wow-ocp.git
    targetRevision: HEAD
    path: apps/my-app/base
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true       # Delete resources not in Git
      selfHeal: true    # Auto-sync on Git change
    syncOptions:
    - CreateNamespace=true
```

### Sync Policy

**Auto-sync (recommended for most apps):**
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

**Manual sync (for critical apps):**
```yaml
syncPolicy:
  automated: null  # Requires manual sync
```

### Ignore Differences

**For resources with dynamic fields:**
```yaml
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas  # Ignore replica count (HPA controls)
```

---

## Summary

**Key conventions:**
- Conventional commits (`feat:`, `fix:`, `docs:`)
- Branch naming (`feature/`, `fix/`, `docs/`)
- Repository structure (`apps/`, `infrastructure/`, `argocd-apps/`)
- PR workflow (branch → validate → commit → PR → merge → verify)
- YAML style (2 spaces, no tabs, quotes for special chars)
- Manifest best practices (resources, probes, labels, no raw secrets)
- Git best practices (commit often, keep branches short, pull before branch)
- Validation requirements (yamllint, kustomize, dry-run, no raw secrets)
- ArgoCD integration (Application CRDs, sync policies)

**Always:**
- Validate before commit
- Use conventional commits
- Update PROGRESS.md for significant changes
- Verify ArgoCD sync after merge
- Delete branches after merge

**Never:**
- Commit directly to `main`
- Commit raw Secrets
- Skip validation
- Force push to `main`
- Use `oc apply` manually (except emergencies)
