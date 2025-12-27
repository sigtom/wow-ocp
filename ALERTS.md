# Homelab Unified Notification System

This cluster uses **Apprise API** as a central notification gateway. All applications should route their alerts here, and Apprise forwards them to the final destination (currently Slack).

## Global Connection Details
- **Internal API URL:** `http://apprise-api.media-stack.svc.cluster.local`
- **External API URL:** `https://apprise.sigtom.dev`
- **Default Tag (Notify ID):** `apprise`

---

## Application Configuration

### 1. Sonarr / Radarr / Prowlarr
1. Go to **Settings** -> **Connect**.
2. Click **+** -> **Apprise**.
3. **Name:** `Slack via Apprise`
4. **Apprise API URL:** `http://apprise-api.media-stack.svc.cluster.local`
5. **Apprise ID:** `apprise`
6. Click **Test** then **Save**.

### 2. Bazarr
1. Go to **Settings** -> **Notifications**.
2. Enable **Apprise**.
3. **Apprise API URL:** `http://apprise-api.media-stack.svc.cluster.local`
4. **Notify ID:** `apprise`
5. Click **Save**.

### 3. Overseerr
1. Go to **Settings** -> **Notifications** -> **Apprise**.
2. Enable the agent.
3. **Apprise API URL:** `http://apprise-api.media-stack.svc.cluster.local`
4. **Notify ID:** `apprise`
5. Click **Test** then **Save Changes**.

### 4. Alertmanager (System Alerts)
System alerts are managed via the **Apprise-Bridge**. 
- **Path:** `Alertmanager` -> `Apprise-Bridge` -> `Apprise API` -> `Slack`.
- Configuration is stored in Git: `infrastructure/monitoring/alertmanager-main-secret.yaml`.

---

## Management (GitOps)
To change where alerts go (e.g., move from Slack to Discord), update the following file in Git:
`apps/apprise-api/base/apprise.yml`

After committing, ArgoCD will sync the secret, but you must restart the `apprise-api` deployment to pick up the changes:
```bash
oc rollout restart deployment/apprise-api -n media-stack
```
