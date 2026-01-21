# Bitwarden Placement Analysis: Cluster vs. Proxmox VM

## The Dilemma

Where should Bitwarden (vault.sigtom.dev) run when it becomes a critical dependency for cluster secrets?

```
Option 1: Keep on OpenShift Cluster

   OpenShift Cluster


    Bitwarden     ESO
    (vault)           Operator




                      Apps need
                      secrets



Option 2: External Proxmox VM

 Proxmox VM                  OpenShift Cluster


  Bitwarden    ESO
  (vault)                    Operator




                                Apps need
                                secrets


```

## Analysis

### The Chicken-and-Egg Problem

**If Bitwarden is ON the cluster:**
```
1. Cluster boots up
2. ESO operator starts
3. ESO tries to fetch secrets from Bitwarden
4. But Bitwarden pod needs secrets to start!
5.  DEADLOCK
```

**Example deadlock scenario:**
- Bitwarden needs PostgreSQL password (from where?)
- PostgreSQL needs storage (needs CSI driver)
- CSI driver needs TrueNAS credentials (from where?)
- TrueNAS credentials should be in Bitwarden...
-  Circular dependency!

### The Bootstrap Problem

Even with ESO, you still need **bootstrap secrets**:

| Secret Type | Example | Bootstrap Method |
|-------------|---------|------------------|
| ESO Bitwarden Session | `BW_SESSION` | SealedSecret or manual |
| Cluster Infrastructure | CSI driver creds, registry pull secrets | SealedSecret |
| Core Services | ArgoCD admin password | SealedSecret |
| Application Secrets | Plex tokens, API keys | ESO (after bootstrap) |

**Key insight:** You can't eliminate bootstrap secrets entirely, but you can minimize them.

## Option 1: Bitwarden ON Cluster

### Pros
 **Single platform management** - Everything in Kubernetes
 **GitOps all the way** - Bitwarden deployment in git
 **Automated backups** - Velero/OADP handles it
 **High availability** - Multiple replicas possible
 **Resource sharing** - Use cluster storage, networking
 **Monitoring integrated** - Prometheus/Grafana already there

### Cons
 **Circular dependency** - Cluster needs secrets to run Bitwarden
 **Bootstrap complexity** - Still need SealedSecrets for Bitwarden's DB password
 **Disaster recovery** - If cluster is dead, can't access secrets to fix it
 **Maintenance risk** - Cluster upgrades could break secret access
 **Single point of failure** - Cluster down = no secret access

### Architecture with Bitwarden ON Cluster

```yaml
# Bootstrap layer (still need SealedSecrets)
bootstrap/
 sealed-secret-bitwarden-db-password.yaml    # Bitwarden's PostgreSQL
 sealed-secret-csi-driver-creds.yaml         # TrueNAS access
 sealed-secret-registry-pull-secret.yaml     # Image registry
 sealed-secret-argocd-admin.yaml             # Break-glass access

# Core services (after bootstrap)
core/
 postgresql/                                  # For Bitwarden
 bitwarden/                                   # Vaultwarden deployment
 external-secrets-operator/
     namespace.yaml
     cluster-secret-store.yaml                # Points to Bitwarden on cluster
     sealed-secret-bw-session.yaml            # ESO's session token

# Applications (ESO managed)
apps/
 media/
    plex/external-secret.yaml                # Fetches from Bitwarden
 nautobot/
     external-secret.yaml
```

**Workflow:**
1. Cluster boots → SealedSecrets controller decrypts bootstrap secrets
2. PostgreSQL starts with unsealed DB password
3. Bitwarden starts, connects to PostgreSQL
4. ESO starts, uses BW_SESSION to connect to Bitwarden
5. Apps start, ESO fetches their secrets from Bitwarden

**Disaster Recovery:**
- Cluster completely dead? → Can't access Bitwarden → Can't get secrets → Stuck
- Need manual intervention with SealedSecrets private key

## Option 2: Bitwarden EXTERNAL on Proxmox

### Pros
 **Break circular dependency** - Bitwarden available before cluster boots
 **Better disaster recovery** - Cluster dead? Access Bitwarden from anywhere
 **Simpler bootstrap** - Only need BW_SESSION in cluster, not Bitwarden's own secrets
 **Lower blast radius** - Cluster issues don't affect secret access
 **Multi-cluster support** - One Bitwarden for multiple clusters
 **Dedicated resources** - Doesn't compete with cluster workloads

### Cons
 **Another platform to manage** - Proxmox + OpenShift
 **Separate backups** - Need Proxmox VM backup strategy
 **Manual deployment** - Ansible playbook, not GitOps
 **Network dependency** - Cluster needs network access to Proxmox VLAN
 **Lower availability** - Single VM (but can be HA later)
 **Split monitoring** - Need to monitor VM separately

### Architecture with Bitwarden EXTERNAL

```yaml
# Proxmox VM (Ansible deployed)
proxmox/
 vms/
     vault.sigtom.dev/
         vaultwarden (Docker Compose)
         postgresql (dedicated)
         nginx (reverse proxy + SSL)
         backups → TrueNAS

# OpenShift bootstrap (minimal!)
bootstrap/
 sealed-secret-bw-session.yaml                # Only this!

# Core services (clean!)
core/
 external-secrets-operator/
     namespace.yaml
     cluster-secret-store.yaml                # Points to external Bitwarden

# Applications (ESO managed)
apps/
 media/
    plex/external-secret.yaml
 nautobot/
     external-secret.yaml
```

**Workflow:**
1. Bitwarden VM running independently on Proxmox
2. Cluster boots → Only needs BW_SESSION (one SealedSecret!)
3. ESO starts, connects to external Bitwarden
4. All app secrets fetched from Bitwarden via ESO
5. Zero circular dependencies!

**Disaster Recovery:**
- Cluster dead? → Bitwarden still accessible → Get secrets → Rebuild cluster
- Bitwarden dead? → Cluster keeps running with cached secrets → Fix Bitwarden → ESO reconnects

## Decision Matrix

| Factor | On Cluster | External VM | Winner |
|--------|-----------|-------------|--------|
| **Bootstrap Complexity** | High (many SealedSecrets) | Low (one SealedSecret) | 🟢 External |
| **Disaster Recovery** | Poor (cluster dead = no secrets) | Good (independent) | 🟢 External |
| **Operational Overhead** | Low (GitOps) | Medium (Ansible + Proxmox) | 🟢 Cluster |
| **High Availability** | Easy (K8s replicas) | Hard (need Proxmox HA) | 🟢 Cluster |
| **Multi-Cluster Support** | Each cluster needs Bitwarden | One Bitwarden for all | 🟢 External |
| **Blast Radius** | High (cluster issues affect secrets) | Low (isolated) | 🟢 External |
| **Network Dependency** | None (same cluster) | Yes (cross-VLAN) | 🟢 Cluster |
| **Backup Strategy** | Integrated (Velero/OADP) | Separate (Proxmox) | 🟢 Cluster |

## Real-World Scenario Analysis

### Scenario 1: Cluster Upgrade Goes Wrong

**Bitwarden ON Cluster:**
```
1. Start OpenShift upgrade 4.20 → 4.21
2. Control plane nodes reboot
3. Etcd temporarily unavailable
4. All pods restart, including Bitwarden
5. ESO can't fetch secrets during restart window
6. App pods fail to start
7. Upgrade completes, everything recovers
Result: 10-15 minute outage for apps
```

**Bitwarden EXTERNAL:**
```
1. Start OpenShift upgrade 4.20 → 4.21
2. Control plane nodes reboot
3. Etcd temporarily unavailable
4. Bitwarden still running on Proxmox
5. ESO reconnects to Bitwarden immediately
6. App pods start normally with fresh secrets
7. Upgrade completes smoothly
Result: 2-3 minute outage (normal upgrade)
```

### Scenario 2: Need to Rebuild Cluster from Scratch

**Bitwarden ON Cluster:**
```
1. Cluster catastrophically fails
2. Need bootstrap secrets to rebuild
3. Where are they? In Bitwarden!
4. But Bitwarden was on the cluster...
5. Must restore from Velero backup
6. But need secrets to configure Velero...
7. Circular dependency hell!
Result: Need offline access to SealedSecrets private key
```

**Bitwarden EXTERNAL:**
```
1. Cluster catastrophically fails
2. Bitwarden still running on Proxmox
3. Rebuild cluster with basic config
4. Get BW_SESSION from Bitwarden
5. Create sealed-secret for BW_SESSION
6. ESO fetches all other secrets from Bitwarden
7. Apps deploy normally
Result: Clean recovery path
```

### Scenario 3: Adding Second OpenShift Cluster

**Bitwarden ON Cluster:**
```
1. Deploy second OpenShift cluster
2. Need separate Bitwarden instance? Or share?
3. If shared, need cross-cluster networking
4. If separate, secrets diverge between clusters
5. Operational complexity multiplies
Result: Messy multi-cluster story
```

**Bitwarden EXTERNAL:**
```
1. Deploy second OpenShift cluster
2. Point ESO to same vault.sigtom.dev
3. Use collections to separate secrets
4. Same secrets available to both clusters
Result: Clean multi-cluster architecture
```

## Recommendation: **External Proxmox VM**

### Why External Wins

**For a homelab with future growth:**
1. **You will have multiple clusters** - Dev, prod, maybe edge
2. **You will have disasters** - It's a homelab, things break
3. **You value learning** - Managing both Proxmox + K8s is educational
4. **You're already using Ansible** - Deployment is already automated

**The killer argument:**
> "When your cluster is completely dead, you should still be able to access your secrets to fix it."

### Recommended Architecture

```
Infrastructure Layer (Proxmox):
 vault.sigtom.dev (VM)           ← Bitwarden
 ipmgmt.sigtom.dev (VM)          ← Nautobot (already external)
 dns1.sigtom.dev (LXC)           ← Technitium (already external)

Kubernetes Layer (OpenShift):
 Bootstrap: 1 SealedSecret (BW_SESSION)
 Everything else: ESO → External Bitwarden

Future Growth:
 wow-ocp-prod (OpenShift cluster 1)
 wow-ocp-dev (OpenShift cluster 2)   → All use same Bitwarden
 wow-k3s-edge (K3s cluster)
```

## Implementation Plan

### Phase 1: Deploy Bitwarden VM on Proxmox

```bash
cd automation

# Create Bitwarden VM playbook
cat <<EOF > playbooks/deploy-bitwarden.yaml
---
- name: Deploy Bitwarden Vault
  hosts: bitwarden
  become: yes
  roles:
    - proxmox_vm
    - docker_host
    - vaultwarden_server
    - nginx_ssl
EOF

# Run deployment
./bsec-wrapper.sh playbooks/deploy-bitwarden.yaml
```

**VM Specs:**
- Hostname: vault.sigtom.dev
- IP: 172.16.110.214 (static)
- vCPU: 2
- RAM: 4GB
- Disk: 50GB
- OS: Ubuntu 24.04 LTS

### Phase 2: Migrate Data from Cluster to VM

```bash
# Export from cluster Bitwarden
oc exec -n vaultwarden deployment/vaultwarden -- \
  sqlite3 /data/db.sqlite3 .dump > bitwarden-export.sql

# Import to VM Bitwarden
scp bitwarden-export.sql vault.sigtom.dev:/tmp/
ssh vault.sigtom.dev "docker exec vaultwarden-db psql -U vaultwarden < /tmp/bitwarden-export.sql"
```

### Phase 3: Update ESO Configuration

```bash
# Update ClusterSecretStore to point to external Bitwarden
oc patch clustersecretstore bitwarden-store --type merge -p '
spec:
  provider:
    bitwarden:
      url: https://vault.sigtom.dev  # Changed from in-cluster service
'
```

### Phase 4: Verify and Cleanup

```bash
# Verify ESO still works
oc get externalsecret -A
oc describe externalsecret plex-token -n media

# Scale down cluster Bitwarden
oc scale deployment vaultwarden -n vaultwarden --replicas=0

# Wait 24 hours to ensure no issues

# Delete cluster Bitwarden
oc delete namespace vaultwarden
```

## Alternative: Hybrid Approach

**Run both for ultimate reliability:**

```
Primary: External Bitwarden on Proxmox
 Used by ESO for all secrets

Backup: Bitwarden on Cluster
 Manual fallback if Proxmox is down
 Periodic sync from primary
```

But this adds complexity. Start simple with external only.

## Monitoring & Backups

### VM Monitoring
```yaml
# Add to Prometheus config
- job_name: 'bitwarden-vm'
  static_configs:
    - targets: ['vault.sigtom.dev:9090']
```

### VM Backups
```bash
# Proxmox scheduled backup
vzdump 214 --mode snapshot --storage truenas-backups --compress zstd

# Or Ansible automated
ansible-playbook playbooks/backup-critical-vms.yaml
```

### Database Backups (Inside VM)
```bash
# Daily cron on vault.sigtom.dev
0 2 * * * /usr/local/bin/backup-vaultwarden.sh
```

## Migration Checklist

- [ ] Provision Bitwarden VM on Proxmox (172.16.110.214)
- [ ] Deploy Vaultwarden with Docker Compose
- [ ] Configure PostgreSQL backend
- [ ] Set up NGINX with Let's Encrypt SSL
- [ ] Migrate data from cluster Bitwarden
- [ ] Test access from external network
- [ ] Update DNS record (vault.sigtom.dev → 172.16.110.214)
- [ ] Update ESO ClusterSecretStore configuration
- [ ] Verify all ExternalSecrets still syncing
- [ ] Test secret rotation workflow
- [ ] Scale down cluster Bitwarden (monitor 48 hours)
- [ ] Delete cluster Bitwarden namespace
- [ ] Configure VM backups (Proxmox + internal DB)
- [ ] Add monitoring to Prometheus
- [ ] Update documentation
- [ ] Document disaster recovery procedures

## Conclusion

**Recommendation: Move Bitwarden to External Proxmox VM**

**Reasons:**
1.  Eliminates circular dependencies
2.  Better disaster recovery story
3.  Enables multi-cluster future
4.  Follows infrastructure layer pattern (like Nautobot, DNS)
5.  Lower blast radius
6.  Homelab best practice: critical infrastructure outside the cluster

**Trade-offs accepted:**
- Need to manage VM separately (but you're already doing this for Nautobot, DNS)
- Need Ansible deployment (already have automation directory)
- Need separate backups (but more reliable than in-cluster)

**Next Steps:**
1. Create Ansible playbook for Bitwarden VM deployment
2. Test deployment on fresh VM
3. Plan migration from cluster → VM (low-risk, can run both temporarily)
4. Execute migration during maintenance window
5. Monitor for 48 hours before decommissioning cluster instance

Would you like me to create the Ansible playbook for deploying Bitwarden on Proxmox?
