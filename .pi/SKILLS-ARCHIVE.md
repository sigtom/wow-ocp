# Recommended Pi Skills for wow-ocp OpenShift Cluster

Based on the Pi Skills documentation and your wow-ocp repository patterns, here are custom skills you should create for your cluster operations.

---

## Skills You Should Create

### 1. **`openshift-debug`** (HIGH PRIORITY)

**Purpose:** Systematic troubleshooting workflows for common OpenShift issues

```markdown
---
name: openshift-debug
description: Troubleshooting workflows for OpenShift clusters - PVC stuck, pod crashes, operator issues, network debugging. Use when diagnosing cluster problems or when user says "debug", "troubleshoot", or "not working".
---

# OpenShift Debug

## Workflows

### PVC Stuck in Pending
1. Check PVC events: `oc describe pvc <name> -n <ns>`
2. Check CSI driver: `oc logs -n democratic-csi -l app=democratic-csi-nfs --tail=50`
3. Test storage network: `oc debug node/<node> -- ping 172.16.160.100`
4. Verify TrueNAS export: `ssh truenas "zfs list | grep <dataset>"`

### Pod CrashLoopBackOff
1. Check events: `oc describe pod <name> -n <ns>`
2. Current logs: `oc logs <name> -n <ns>`
3. Previous logs: `oc logs <name> -n <ns> --previous`
4. Debug shell: `oc debug <pod> -n <ns>`

### Operator Issues
1. Check operator pod: `oc get pods -n <operator-namespace>`
2. Check operator logs: `oc logs -n <operator-namespace> -l app=<operator>`
3. Check CRD status: `oc get <crd-name> -n <ns> -o yaml`

### Network Debugging
1. Test pod-to-pod: `oc debug node/<node> -- ping <pod-ip>`
2. Test VLAN routing: Check Node 2/3 (10G) vs Node 4 (1G hybrid)
3. Storage network: Verify VLAN 160 connectivity to 172.16.160.100
```

---

### 2. **`argocd-ops`** (HIGH PRIORITY)

**Purpose:** ArgoCD operations - sync, diff, rollback, app management

```markdown
---
name: argocd-ops
description: ArgoCD GitOps operations including sync, diff, rollback, and health checks. Use when deploying apps, checking sync status, or troubleshooting ArgoCD issues.
---

# ArgoCD Operations

## Quick Checks

```bash
./scripts/check-sync-status.sh      # All apps status
./scripts/check-health.sh <app>     # Detailed health
```

## Deployment Workflow

1. Create ArgoCD Application manifest in `argocd-apps/`
2. Commit to Git
3. Sync: `argocd app sync <name>`
4. Watch: `argocd app wait <name> --health`
5. Verify: `argocd app get <name>`

## Troubleshooting

### Out of Sync
```bash
argocd app diff <name>
# Shows what's different between Git and cluster
```

### Sync Failed
```bash
argocd app history <name>
# Find last good revision
argocd app rollback <name> <revision>
```

### Stuck in Progressing
```bash
argocd app get <name>
# Check health status and sync waves
oc get pods -n <namespace>
# Check if pods are actually running
```

## Scripts

**scripts/check-sync-status.sh:**
```bash
#!/bin/bash
argocd app list -o json | jq -r '.[] | "\(.metadata.name): \(.status.sync.status) / \(.status.health.status)"'
```

**scripts/check-health.sh:**
```bash
#!/bin/bash
APP=$1
argocd app get $APP -o json | jq -r '.status | "Sync: \(.sync.status)\nHealth: \(.health.status)\nMessage: \(.health.message)"'
```
```

---

### 3. **`sealed-secrets`** (HIGH PRIORITY)

**Purpose:** Secret management workflow with kubeseal

```markdown
---
name: sealed-secrets
description: Create and manage sealed secrets with kubeseal. Use when creating secrets, API keys, tokens, or when user mentions "secret", "password", or "credentials".
---

# Sealed Secrets

## Create Sealed Secret

```bash
./scripts/seal-secret.sh <secret-name> <namespace>
```

Prompts for key-value pairs, seals with `pub-sealed-secrets.pem`, outputs to stdout.

## Manual Workflow

```bash
# 1. Create raw secret (dry-run, NEVER apply)
oc create secret generic my-secret \
  --from-literal=API_KEY=supersecret \
  --dry-run=client -o yaml > /tmp/secret.yaml

# 2. Seal it
kubeseal --cert pub-sealed-secrets.pem \
  --format yaml < /tmp/secret.yaml > sealed-secret.yaml

# 3. Commit sealed secret to Git
git add sealed-secret.yaml
git commit -m "feat: add sealed secret for my-app"

# 4. Clean up raw secret
rm /tmp/secret.yaml
```

## Troubleshooting

### Secret Not Appearing in Namespace
```bash
# Check sealed-secrets controller
oc logs -n kube-system -l name=sealed-secrets-controller

# Check SealedSecret resource
oc get sealedsecret -n <namespace>
oc describe sealedsecret <name> -n <namespace>
```

### Decryption Failed
- Verify certificate matches cluster: `kubeseal --fetch-cert`
- Check sealed-secrets controller version compatibility

## Scripts

**scripts/seal-secret.sh:**
```bash
#!/bin/bash
set -euo pipefail

SECRET_NAME=$1
NAMESPACE=$2

echo "Creating sealed secret: $SECRET_NAME in namespace $NAMESPACE"
echo "Enter key-value pairs (empty line to finish):"

LITERALS=""
while true; do
    read -p "Key (or empty to finish): " KEY
    [ -z "$KEY" ] && break
    read -sp "Value: " VALUE
    echo
    LITERALS="$LITERALS --from-literal=$KEY=$VALUE"
done

# Create and seal
oc create secret generic $SECRET_NAME $LITERALS \
  --dry-run=client -o yaml -n $NAMESPACE | \
kubeseal --cert pub-sealed-secrets.pem --format yaml

echo "Sealed secret created. Copy output to your manifest file."
```
```

---

### 4. **`truenas-ops`** (MEDIUM PRIORITY)

**Purpose:** TrueNAS dataset management for PVC provisioning

```markdown
---
name: truenas-ops
description: TrueNAS dataset and NFS export management for democratic-csi. Use when creating datasets, debugging storage, or when PVC provisioning fails.
---

# TrueNAS Operations

## Create Dataset for PVC

```bash
./scripts/create-dataset.sh <dataset-name> <quota>
```

Creates dataset under `tank/k8s/` with NFS export configured.

## Check Storage

```bash
./scripts/check-capacity.sh    # Shows available space
./scripts/list-datasets.sh     # Shows all k8s datasets
```

## Troubleshooting

### PVC Pending - Dataset Missing
```bash
# SSH to TrueNAS
ssh truenas

# List datasets
zfs list | grep tank/k8s

# Create manually if needed
zfs create tank/k8s/<dataset-name>
zfs set quota=<size>G tank/k8s/<dataset-name>
```

### Permission Denied
- Check NFS export has `mapall=root` or `no_root_squash`
- Verify dataset permissions: `zfs get all tank/k8s/<dataset>`

### Network Connectivity
```bash
# From cluster node
oc debug node/<node-name>
chroot /host
ping 172.16.160.100  # TrueNAS storage IP

# Check VLAN 160 routing (especially on Node 4 hybrid)
ip route | grep 172.16.160
```

## Scripts

**scripts/check-capacity.sh:**
```bash
#!/bin/bash
ssh truenas "zfs list -o name,used,avail,refer tank/k8s"
```

**scripts/list-datasets.sh:**
```bash
#!/bin/bash
ssh truenas "zfs list -r tank/k8s | grep -v tank/k8s$"
```
```

---

### 5. **`media-stack`** (MEDIUM PRIORITY)

**Purpose:** Media app deployment pattern with sidecar rclone

```markdown
---
name: media-stack
description: Deploy media applications (Sonarr, Radarr, etc.) with rclone sidecar pattern. Use when deploying Plex, Arr-stack apps, or media-related services.
---

# Media Stack Deployment

## Generate Media App Manifests

```bash
./scripts/generate-media-app.sh <app-name> <image> <port>
```

Outputs complete deployment with:
- rclone-zurg sidecar
- rclone-torbox sidecar
- `/mnt/media` emptyDir volume with Bidirectional propagation
- nodeAffinity for Node 2/3 (10G NICs)
- Resource limits (default: medium profile)
- Liveness and readiness probes

## Mount Structure

```
/mnt/media/                 # Parent mount (emptyDir)
├── __all__/                # Zurg cloud content (movies/TV)
├── torrents/               # TorBox downloads
└── local/                  # Local storage (if used)
```

## Pattern Requirements (CRITICAL)

**MUST include:**
1. Both rclone sidecars (zurg + torbox)
2. `/mnt/media` as emptyDir volume
3. `mountPropagation: Bidirectional` on sidecar volumeMounts
4. `nodeAffinity` (preferred) for Node 2/3, NOT hard `nodeSelector`

**Why:** Standalone rclone pods don't propagate FUSE mounts across nodes. Sidecars solve this permanently (lesson learned Dec 2025).

## Example Usage

```bash
# Generate Prowlarr deployment
./scripts/generate-media-app.sh prowlarr linuxserver/prowlarr:latest 9696

# Output: apps/prowlarr/base/deployment.yaml
# Then create service, ingress, ArgoCD app
```

## Scheduling Strategy

- **Preferred:** Node 2 & 3 (10G NICs, better CPU)
- **Fallback:** Node 4 allowed (1G NIC, slower)
- **Never:** Hard `nodeSelector` (breaks during node maintenance)

## Scripts

**scripts/generate-media-app.sh:**
```bash
#!/bin/bash
# Template generator for media apps with sidecar pattern
APP_NAME=$1
IMAGE=$2
PORT=$3

cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values:
                      - wow-ocp-node2
                      - wow-ocp-node3
      containers:
        - name: $APP_NAME
          image: $IMAGE
          ports:
            - containerPort: $PORT
          volumeMounts:
            - name: media
              mountPath: /mnt/media
            - name: config
              mountPath: /config
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "2000m"
              memory: "2Gi"
          livenessProbe:
            httpGet:
              path: /
              port: $PORT
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: $PORT
            initialDelaySeconds: 5
            periodSeconds: 5
        - name: rclone-zurg
          image: rclone/rclone:latest
          command: ["/bin/sh", "-c"]
          args:
            - "rclone mount zurg: /mnt/media/__all__ --allow-other --vfs-cache-mode writes"
          securityContext:
            privileged: true
          volumeMounts:
            - name: media
              mountPath: /mnt/media
              mountPropagation: Bidirectional
        - name: rclone-torbox
          image: rclone/rclone:latest
          command: ["/bin/sh", "-c"]
          args:
            - "rclone mount torbox: /mnt/media/torrents --allow-other --vfs-cache-mode writes"
          securityContext:
            privileged: true
          volumeMounts:
            - name: media
              mountPath: /mnt/media
              mountPropagation: Bidirectional
      volumes:
        - name: media
          emptyDir: {}
        - name: config
          persistentVolumeClaim:
            claimName: $APP_NAME-config
EOF
```
```

---

### 6. **`vm-provisioning`** (MEDIUM PRIORITY)

**Purpose:** KubeVirt VM creation workflow

```markdown
---
name: vm-provisioning
description: Create and manage VMs with OpenShift Virtualization (KubeVirt). Use when deploying RHEL or Windows VMs, or when user mentions "virtual machine" or "VM".
---

# VM Provisioning

## Create VM

```bash
./scripts/create-vm.sh <vm-name> <os> <vcpu> <ram> <disk>
```

Options:
- `<os>`: rhel9 | rhel8 | windows2022
- `<vcpu>`: Number of vCPUs (2, 4, 8)
- `<ram>`: RAM in GB (4, 8, 16, 32)
- `<disk>`: Disk size in GB (50, 100, 200)

Generates VirtualMachine manifest with:
- Master SSH key injected (sigtom@ilum)
- truenas-nfs storage (RWX, required for live migration)
- Cloud-init for RHEL
- virtio-win container disk for Windows
- Guest agent configuration

## Post-Deployment

```bash
# 1. Wait for VM to start
oc get vmi -n <namespace>

# 2. Console access
virtctl console <vm-name> -n <namespace>

# 3. Install guest agent (inside VM)
# RHEL:
sudo dnf install qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent

# Windows:
# Install from virtio-win ISO (attached as CD-ROM)
```

## Resource Guidelines

| Profile | vCPU | RAM | Use Case |
|---------|------|-----|----------|
| Light | 2 | 4GB | Utility servers, dev boxes |
| Standard | 4 | 8GB | Application servers |
| Heavy | 8 | 16-32GB | Databases, Windows desktop |

**Important:** 3 blades = ~384GB total RAM. Plan for 70-80% allocation max.

## Storage Requirements

- **MUST use truenas-nfs (RWX)** for live migration support
- LVM (RWO) pins VM to single node - defeats purpose of virtualization
- CSI Smart Cloning available for instant provisioning from templates

## Networking Options

- **masquerade:** Default, pod network (easiest)
- **bridge:** Direct VLAN access (requires NetworkAttachmentDefinition)
- **SR-IOV:** High performance (requires SR-IOV operator and hardware)

## Scripts

**scripts/create-vm.sh:**
```bash
#!/bin/bash
VM_NAME=$1
OS=$2
VCPU=$3
RAM=$4
DISK=$5

# Template generation for VM manifest
# Includes cloud-init, storage, networking
```
```

---

### 7. **`capacity-planning`** (LOW PRIORITY)

**Purpose:** Resource tracking and planning

```markdown
---
name: capacity-planning
description: Track cluster resource allocation and plan capacity. Use when checking available resources, planning new deployments, or when cluster feels "full".
---

# Capacity Planning

## Check Current Allocation

```bash
./scripts/cluster-capacity.sh
```

Shows:
- **vCPU:** allocated vs total (~72 vCPUs across 3 blades)
- **RAM:** allocated vs total (~384GB across 3 blades)
- **Storage:** NFS (11TB media + dynamic PVCs) and LVM (~2TB local)
- **Network:** Per-node bandwidth (Node 2/3: 10G, Node 4: 1G)

## Before Deploying New Workload

```bash
./scripts/estimate-impact.sh <cpu> <ram> <replicas>
```

Calculates:
- Impact on cluster capacity
- Warns if >85% threshold exceeded
- Suggests resource adjustments or scaling down existing workloads

## Monthly Review

```bash
./scripts/capacity-report.sh > capacity-report-$(date +%Y-%m).md
```

Generates report:
- Current allocation trends
- Top resource consumers
- Recommendations for optimization
- Updates capacity tracking in PROGRESS.md

## Alert Thresholds

- **85% CPU/RAM:** Warning - plan capacity expansion
- **90% CPU/RAM:** Critical - defer new workloads
- **95% Storage:** Warning - clean up old PVCs or expand pool

## Scripts

**scripts/cluster-capacity.sh:**
```bash
#!/bin/bash
echo "=== Cluster Capacity Report ==="
echo
echo "Compute Resources:"
oc adm top nodes
echo
echo "Storage:"
echo "NFS (TrueNAS):"
ssh truenas "zfs list -o name,used,avail tank/k8s | head -1"
echo "LVM (Local):"
oc get pv | grep lvms-vg1
```
```

---

### 8. **`gitops-workflow`** (LOW PRIORITY)

**Purpose:** Standard GitOps workflow helpers

```markdown
---
name: gitops-workflow
description: Standard Git workflow for GitOps changes - create branch, commit, PR, sync. Use when making cluster changes or deploying new apps.
---

# GitOps Workflow

## New Feature Branch

```bash
./scripts/new-feature.sh <feature-name>
```

Creates branch: `feature/<feature-name>`, sets up tracking.

## Commit with Conventional Commits

```bash
./scripts/commit.sh <type> <message>
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `refactor`: Code refactoring
- `chore`: Maintenance

Automatically:
- Follows conventional commits format
- Updates PROGRESS.md if significant change
- Runs pre-commit validation (yamllint, kustomize build)

## Deployment Flow

1. **Make changes** in feature branch
2. **Test locally:**
   ```bash
   kustomize build apps/<app>/base | oc apply --dry-run=server -f -
   ```
3. **Commit:**
   ```bash
   ./scripts/commit.sh feat "add sonarr deployment"
   ```
4. **Push and create PR:**
   ```bash
   git push origin feature/<feature-name>
   gh pr create
   ```
5. **After merge:** Verify ArgoCD sync
   ```bash
   argocd app sync <app-name>
   argocd app wait <app-name> --health
   ```

## Pre-Commit Checks

Automatically run by commit script:
- YAML syntax validation (yamllint)
- Kustomize build test
- Resource limit verification
- Sealed secret validation

## Scripts

**scripts/new-feature.sh:**
```bash
#!/bin/bash
FEATURE=$1
git checkout -b feature/$FEATURE
git push -u origin feature/$FEATURE
```

**scripts/commit.sh:**
```bash
#!/bin/bash
TYPE=$1
MESSAGE=$2

# Validate type
case $TYPE in
  feat|fix|docs|refactor|chore) ;;
  *) echo "Invalid type: $TYPE"; exit 1 ;;
esac

# Run pre-commit checks
./scripts/validate-manifests.sh || exit 1

# Commit
git add .
git commit -m "$TYPE: $MESSAGE"
```
```

---

## Recommended Priority Order

### Create Immediately (Daily Use)
1. **`openshift-debug`** - You'll use this every time something breaks
2. **`sealed-secrets`** - Needed for any app with secrets
3. **`argocd-ops`** - Core to your GitOps workflow

### Create Next (Weekly Use)
4. **`media-stack`** - You deploy media apps frequently
5. **`truenas-ops`** - Storage troubleshooting is common

### Create Later (As Needed)
6. **`vm-provisioning`** - When you need to deploy VMs
7. **`capacity-planning`** - Periodic review (monthly)
8. **`gitops-workflow`** - Nice-to-have automation

---

## Where to Put Them

### Option A: Project-Specific (Recommended)

```bash
mkdir -p ~/wow-ocp/.pi/skills/
cd ~/wow-ocp/.pi/skills/

# Create each skill
mkdir openshift-debug
cd openshift-debug
# Create SKILL.md and scripts/ directory
```

**Pros:**
- Skills travel with the repo
- Team members get same skills
- Version controlled

### Option B: User-Wide

```bash
mkdir -p ~/.pi/agent/skills/
# Same structure
```

**Pros:**
- Available in all projects
- Good for generic skills (git, docker, etc.)

---

## Quick Start

To create your first skill:

```bash
cd ~/wow-ocp
mkdir -p .pi/skills/openshift-debug/scripts
cd .pi/skills/openshift-debug

# Create SKILL.md (copy content from above)
vi SKILL.md

# Create helper scripts
vi scripts/check-pvc.sh
chmod +x scripts/*.sh

# Commit to repo
git add .pi/skills/openshift-debug
git commit -m "feat: add openshift-debug skill for Pi"
```

Then test:
```bash
cd ~/wow-ocp
pi

You: "I have a PVC stuck in Pending. Help me debug it."
Pi: [loads openshift-debug skill, follows workflow]
```

---

## Next Steps

1. **Start with `openshift-debug`** - it will immediately pay dividends
2. **Have Pi help you build the others:**
   ```
   You: "Create the sealed-secrets skill based on the template I showed you. 
        Include the interactive seal-secret.sh script."
   ```
3. **Iterate based on actual usage** - add workflows as you encounter them
4. **Share with the community** - your skills could help other OpenShift homelabbers!