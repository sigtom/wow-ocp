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

---

## 🔐 How to Use Sealed Secrets

**The Rule:** Never commit a raw Secret to Git. Only commit `SealedSecret` objects.

### 1. Requirements
- `kubeseal` CLI installed locally.
- Access to `pub-sealed-secrets.pem` (stored in the root of this repo).

### 2. The Workflow
1. **Generate Raw Secret (JSON)**:
   ```bash
   oc create secret generic my-secret --from-literal=key=value --dry-run=client -o json > raw.json
   ```
2. **Seal It**:
   ```bash
   kubeseal --format=yaml --cert=pub-sealed-secrets.pem < raw.json > sealed-secret.yaml
   ```
3. **Commit & Push**:
   - Delete `raw.json` immediately.
   - Move `sealed-secret.yaml` to your app's `base/` or `overlays/` folder.
   - `git add` and `git push`.

---

## 📅 Next Steps
- [ ] **Cert-Manager / Cloudflare**: Configure DNS-01 challenge for "Green Lock" SSL.
- [ ] **Media Apps**: Deploy Plex/Jellyfin/Arr-stack using the 11TB mount.
- [ ] **Backup Verification**: Audit OADP/Velero labels on critical PVCs.
