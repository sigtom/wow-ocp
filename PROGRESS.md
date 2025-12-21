# OpenShift 4.20 Homelab Progress Tracker

## 🚀 Completed Milestones

### 1. Infrastructure Foundation
- [x] **GitOps Bootstrap**: Initialized `wow-ocp` repo and established the "App of Apps" pattern using ArgoCD.
- [x] **Root Application**: Deployed `root-app` to manage all cluster configurations.
- [x] **Sealed Secrets**: Installed Bitnami Sealed Secrets controller in the `sealed-secrets` namespace.
    - [x] **OpenShift Security Patch**: Applied custom SCC (`anyuid`) and Deployment patches to allow the controller to run on OCP 4.20.
    - [x] **Public Cert**: Fetched and committed `pub-sealed-secrets.pem` to Git.

### 2. Storage & Networking
- [x] **The 11TB Monster**: Established static NFS connectivity to TrueNAS Scale (Fangtooth).
    - [x] **PV/PVC**: Successfully bound `media-library-pvc` (11Ti, RWX) in the `media-stack` namespace.
- [x] **Namespace Scaffolding**: Created `media-stack` namespace with:
    - [x] **LimitRange**: Enforcing resource discipline (256Mi/1Gi RAM).
    - [x] **NetworkPolicy**: Defaulting to allow-same-namespace.
    - [x] **VLAN Bridges**: Configured br110, br120, br130 across all nodes via NMState (NodeNetworkConfigurationPolicy).
    - [x] **MetalLB**: Configured Layer 2 advertisements and address pools for all workload VLANs.
    - [x] **MetalLB Machine Pool**: Added Layer 2 pool (172.16.100.200-220) on br-ex.

### 3. Hybrid Media Stack (In Progress)

- [x] **Security Contexts**: Configured `privileged` and `anyuid` SCC bindings for media-stack ServiceAccounts to support FUSE/Rclone mounts.

- [x] **Zone 1 (Cloud Gateway)**: 
    - [x] **Deployments**: Zurg (Public Image), Rclone (TorBox), rdt-client (RogerFar), Riven deployed.
    - [x] **Fixes**: Solved FUSE mount conflicts (subpaths), Image Pull Auth (Global Secret), and Token Injection (Zurg).
    - [x] **Connectivity**: Validated Zurg->RealDebrid (WebDAV) and Rclone->TorBox (WebDAV with Auth) mounts.

- [x] **Zone 3 (The Player)**:
    - [x] **Plex Architecture**: Refactored to Sidecar Pattern (Plex + Rclone-Zurg + Rclone-TorBox in one pod).
    - [x] **Visibility**: Verified Plex can see cloud content via local FUSE mounts.
    - [x] **Network**: Configured Service on Machine Network (MetalLB) and updated NetworkPolicy.

- [x] **Secret Templates**: Established SealedSecret structure for Real-Debrid and TorBox APIs.



---

## 🔐 How to Use Sealed Secrets

**The Rule:** Never commit a raw Secret to Git. Only commit `SealedSecret` objects.

### 1. Requirements
- `kubeseal` CLI installed locally.
- Access to `pub-sealed-secrets.pem` (stored in the root of this repo).

### 2. The Workflow (With "Safety Net")
1. **Generate Raw Secret (JSON)**:
   Always use the `-raw.json` suffix (this is ignored by Git).
   ```bash
   oc create secret generic my-secret --from-literal=key=value --dry-run=client -o json > my-secret-raw.json
   ```
2. **Seal It**:
   ```bash
   kubeseal --format=yaml --cert=pub-sealed-secrets.pem < my-secret-raw.json > sealed-secret.yaml
   ```
3. **Clean Up**:
   - Delete `my-secret-raw.json` (though Git will ignore it if you forget).
   - Move `sealed-secret.yaml` to your app's folder.
   - `git add` and `git push`.

---

## 📅 Next Steps
- [ ] **OIDC Authentication**: Configure Google/GitHub identity provider (Issue #2).
- [ ] **Monitoring Remediation**: Fix rejected ServiceMonitors and configure Alertmanager receivers (Issues #1, #5, #9).
- [ ] **Storage Tuning**: Resolve LVM vg-manager rollout issues (Issue #10).
- [ ] **Media Stack Phase 2**: Deploy Zone 2 Managers (Sonarr/Radarr) and integrate with Zone 1.

---

## 📝 Operational Notes
- [2025-12-20]: Operationalized Homelab - Completed Networking (VLANs/MetalLB), Storage (GitOps/CSI), Monitoring (UWM/PVs), and Node Tuning.
- [2025-12-20]: Alert Investigation - Investigating NFD and Storage rollout issues.
- [2025-12-21]: Hybrid Media Stack - Deployed Zone 1 (Cloud Gateway) and configured security context constraints for FUSE.
- [2025-12-21]: Design Pivot - Backtracking from `bootstrap_project_v1.sh` multi-agent design in favor of sequential Conductor-led batching.