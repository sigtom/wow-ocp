# IP Address Inventory - WOW Homelab

**Last Updated:** January 9, 2026
**Discovery Method:** nmap scans + OpenShift queries + manual documentation review

---

## 172.16.100.0/24 - Apps Network (Native VLAN on vmbr0)

### Network Information
- **Gateway:** 172.16.100.1 (pfSense)
- **Subnet:** 172.16.100.0/24
- **Bridge:** vmbr0 (native/untagged)
- **DNS Servers:** 172.16.100.2, 172.16.110.100
- **Purpose:** Primary application network for VMs, LXCs, and services

### IP Allocations

#### Infrastructure (172.16.100.1-9)
| IP | Hostname | Type | Description | Status |
|----|----------|------|-------------|--------|
| 172.16.100.1 | pfSense | Router | Gateway, DNS, DHCP, NTP | Active |
| 172.16.100.2 | wow-pihole1 | LXC (101) | Pi-hole DNS server | Active |
| 172.16.100.3-9 | - | Reserved | Future infrastructure | Available |

#### Static VMs/LXC (172.16.100.10-49) ✅ Use for new deployments
| IP | Hostname | Type | Description | Status |
|----|----------|------|-------------|--------|
| 172.16.100.10-29 | - | Reserved | Available for static VM/LXC assignment | Available |
| 172.16.100.30 | test-phase2-vm | VM (351) | Phase 2 testing (temporary) | Testing |
| 172.16.100.31-49 | - | Reserved | Available for static VM/LXC assignment | Available |

#### DHCP Pool (172.16.100.50-99)
| IP Range | Description | Managed By | Status |
|----------|-------------|------------|--------|
| 172.16.100.50-99 | DHCP reservation pool | pfSense | Active |

**Known DHCP Clients:**
| IP | Hostname | MAC/ID | Description | Status |
|----|----------|--------|-------------|--------|
| 172.16.100.50 | wow-10gb-mik-sw | - | Mikrotik 10Gb switch | Active |
| 172.16.100.54 | Unknown | - | Unknown DHCP client | Active |
| 172.16.100.55 | Unknown | - | Unknown DHCP client | Active |
| 172.16.100.79 | linux | - | Unknown Linux host | Active |

#### OpenShift Control Plane (172.16.100.100-119)
| IP | Hostname | Type | Description | Status |
|----|----------|------|-------------|--------|
| 172.16.100.102 | wow-ocp-node2 | Bare Metal | OpenShift node 2 | Active |
| 172.16.100.103 | wow-ocp-node3 | Bare Metal | OpenShift node 3 | Active |
| 172.16.100.104 | api-int.ossus.sigtomtech.com | VIP | OpenShift internal API | Active |
| 172.16.100.105 | api.ossus.sigtomtech.com | VIP | OpenShift external API | Active |
| 172.16.100.106 | overseerr.sigtom.dev | VIP | OpenShift apps ingress (*.apps.ossus) | Active |
| 172.16.100.110 | iventoy | LXC (102) | iVentoy boot server | Active |

#### MetalLB Machine Pool (172.16.100.200-220) ⚠️ DO NOT USE
| IP Range | Description | Managed By | Status |
|----------|-------------|------------|--------|
| 172.16.100.200-220 | MetalLB machine network pool | OpenShift MetalLB | Reserved |

**Known MetalLB Services:**
| IP | Service | Namespace | Description | Status |
|----|---------|-----------|-------------|--------|
| 172.16.100.200 | plex.sigtom.dev | media | Plex Media Server | Active |

#### Static Services (172.16.100.221-254)
| IP | Hostname | Type | Description | Status |
|----|----------|------|-------------|--------|
| 172.16.100.221-254 | - | Reserved | Available for additional static services | Available |

---

## 172.16.110.0/24 - Proxmox Management (VLAN 110)

### Network Information
- **Gateway:** 172.16.110.1 (pfSense)
- **Subnet:** 172.16.110.0/24
- **Bridge:** vmbr0.110 (VLAN tagged)
- **DNS Servers:** 172.16.100.2, 172.16.110.100
- **Purpose:** Proxmox management plane - infrastructure critical only
- **⚠️ RESTRICTED:** Requires justification for new deployments

### IP Allocations

#### Infrastructure (172.16.110.1-9)
| IP | Hostname | Type | Description | Status |
|----|----------|------|-------------|--------|
| 172.16.110.1 | pfSense | Router | Gateway (VLAN 110 interface) | Active |
| 172.16.110.2-9 | - | Reserved | Future infrastructure | Available |

#### Static Critical Infrastructure (172.16.110.10-49)
| IP | Hostname | Type | Description | Status |
|----|----------|------|-------------|--------|
| 172.16.110.10-49 | - | Reserved | Available for critical infrastructure | Available |

#### DHCP Pool (172.16.110.50-99)
| IP Range | Description | Managed By | Status |
|----------|-------------|------------|--------|
| 172.16.110.50-99 | DHCP reservation pool | pfSense | Active |

**Known DHCP Clients:**
| IP | Hostname | Type | Description | Migration Plan |
|----|----------|------|-------------|----------------|
| 172.16.110.76 | wow-clawdbot | VM (300) | Dev/bot VM | ⚠️ Migrate to 172.16.100.x |

#### Management Hosts (172.16.110.100-119)
| IP | Hostname | Type | Description | Status |
|----|----------|------|-------------|--------|
| 172.16.110.100 | wow-ts01 | Physical | TrueNAS Scale 25.10 - management interface | Active |
| 172.16.110.101 | wow-prox1 (wow-esxi1) | Physical | Proxmox VE host | Active |
| 172.16.110.105 | vaultwarden (vault.sigtom.dev) | LXC (105) | Vaultwarden password manager | ⚠️ Migrate to 172.16.100.x |

#### MetalLB VLAN110 Pool (172.16.110.120-150) ⚠️ DO NOT USE
| IP Range | Description | Managed By | Status |
|----------|-------------|------------|--------|
| 172.16.110.120-150 | MetalLB vlan110 pool | OpenShift MetalLB | Reserved |

#### Monitoring/Backup (172.16.110.151-199)
| IP | Hostname | Type | Description | Status |
|----|----------|------|-------------|--------|
| 172.16.110.151-199 | - | Reserved | Available for monitoring/backup systems | Available |

#### Infrastructure Services (172.16.110.200-254)
| IP | Hostname | Type | Description | Migration Plan |
|----|----------|------|-------------|----------------|
| 172.16.110.211 | dns2.sigtom.dev | VM (211) | Technitium DNS server | ⚠️ Migrate to 172.16.100.x |
| 172.16.110.213 | ipmgmt.sigtom.dev | VM (212) | Nautobot IPAM server | ⚠️ Migrate to 172.16.100.x |
| 172.16.110.214-254 | - | Reserved | Available for infrastructure services | Available |

---

## 172.16.120.0/24 - Unknown VLAN 120

### Network Information
- **Gateway:** 172.16.120.1 (assumed)
- **Subnet:** 172.16.120.0/24
- **Purpose:** Unknown - discovered via MetalLB pool

### IP Allocations

#### MetalLB VLAN120 Pool (172.16.120.120-150)
| IP Range | Description | Managed By | Status |
|----------|-------------|------------|--------|
| 172.16.120.120-150 | MetalLB vlan120 pool | OpenShift MetalLB | Reserved |

**Note:** No active hosts discovered on this network. May be reserved for future use.

---

## 172.16.130.0/24 - Workload Network (VLAN 130) - OpenShift Only

### Network Information
- **Gateway:** 172.16.130.1 (pfSense)
- **Subnet:** 172.16.130.0/24
- **Bridge:** N/A (OpenShift nodes only)
- **Purpose:** OpenShift application traffic
- **⚠️ OFF LIMITS:** Do NOT provision VMs/LXC on this network

### IP Allocations

#### MetalLB Workload Pool (172.16.130.40-99)
| IP Range | Description | Managed By | Status |
|----------|-------------|------------|--------|
| 172.16.130.40-99 | MetalLB workload pool | OpenShift MetalLB | Reserved |

**Note:** This network is exclusively for OpenShift workload traffic. All IPs managed by OpenShift/MetalLB.

---

## 172.16.160.0/24 - Storage Network (VLAN 160) - OFF LIMITS

### Network Information
- **Gateway:** 172.16.160.1 (pfSense)
- **Subnet:** 172.16.160.0/24
- **Bridge:** vmbr1.160 (dedicated storage bridge)
- **Purpose:** NFS/iSCSI storage backend traffic
- **⚠️ OFF LIMITS:** Exclusively for storage - do NOT provision VMs/LXC

### IP Allocations

#### Storage Infrastructure
| IP | Hostname | Type | Description | Status |
|----|----------|------|-------------|--------|
| 172.16.160.1 | pfSense | Router | Gateway (VLAN 160 interface) | Active |
| 172.16.160.100 | wow-ts01 | Physical | TrueNAS storage interface (Democratic CSI) | Active |
| 172.16.160.101 | wow-prox1 | Physical | Proxmox storage interface | Active |

**Note:** OpenShift nodes also have interfaces on this network for Democratic CSI NFS access.

---

## 10.0.0.0/8 - Management/OOB Networks

### 10.1.1.0/24 - pfSense Management
| IP | Hostname | Type | Description | Status |
|----|----------|------|-------------|--------|
| 10.1.1.1 | pfSense | Router | pfSense management interface, NTP server | Active |

---

## Migration Plan - VMs/LXC Currently on Wrong Network

The following resources are currently on VLAN 110 (proxmox-mgmt) but should be moved to the apps network (172.16.100.0/24):

| Current IP | Hostname | Type | Target Network | Suggested New IP | Priority | Notes |
|------------|----------|------|----------------|------------------|----------|-------|
| 172.16.110.76 | wow-clawdbot | VM (300) | apps | 172.16.100.20 | Medium | Dev/bot workstation |
| 172.16.110.105 | vaultwarden | LXC (105) | apps | 172.16.100.25 | High | Password manager (critical service) |
| 172.16.110.211 | dns2 | VM (211) | apps | 172.16.100.5 | High | Technitium DNS (infrastructure) |
| 172.16.110.213 | ipmgmt | VM (212) | apps | 172.16.100.15 | High | Nautobot IPAM server |

**Migration Steps (for each host):**
1. Assign new IP in 172.16.100.0/24 range
2. Create DNS A record for new IP
3. Add DHCP reservation on pfSense (if desired)
4. Update VM/LXC network configuration:
   - Change bridge from `vmbr0,tag=110` to `vmbr0` (native)
   - Update IP address and gateway
5. Update inventory in `automation/inventory/hosts.yaml`
6. Update Nautobot (once deployed)
7. Verify connectivity
8. Update firewall rules if needed
9. Remove old DNS records
10. Remove old DHCP reservations

---

## IP Allocation Guidelines

### For New Deployments

#### Apps Network (172.16.100.0/24) - PRIMARY
- **Use:** 172.16.100.10-49 for static VMs/LXCs
- **Next Available:** 172.16.100.31 (after Phase 2 test cleanup)
- **Process:**
  1. Check this document for conflicts
  2. Update `ip_allocations.apps.next_available` in `group_vars/all.yml`
  3. Add entry to `ip_allocations.apps.in_use`
  4. Create DHCP reservation on pfSense (optional but recommended)
  5. Add DNS A record
  6. Deploy VM/LXC
  7. Update Nautobot (once deployed)

#### Proxmox Management Network (172.16.110.0/24) - RESTRICTED
- **Use:** Only for infrastructure-critical systems
- **Requires:** Justification documented in inventory
- **Available:** 172.16.110.10-49, 172.16.110.151-199
- **Process:** Same as above + add `network_justification` in inventory

### Networks to AVOID

- **172.16.100.50-99** - DHCP pool (managed by pfSense)
- **172.16.100.100-119** - OpenShift nodes/VIPs
- **172.16.100.200-220** - MetalLB machine pool
- **172.16.110.50-99** - DHCP pool
- **172.16.110.120-150** - MetalLB vlan110 pool
- **172.16.120.120-150** - MetalLB vlan120 pool
- **172.16.130.40-99** - MetalLB workload pool
- **172.16.160.0/24** - Storage network (entire subnet off-limits)

---

## Unknown/Unidentified Hosts

The following IPs responded to nmap but could not be identified:

| IP | Hostname | Last Seen | Notes |
|----|----------|-----------|-------|
| 172.16.100.54 | Unknown | 2026-01-09 | DHCP client |
| 172.16.100.55 | Unknown | 2026-01-09 | DHCP client |
| 172.16.100.79 | linux | 2026-01-09 | Generic hostname |

**Action Required:** Investigate these hosts and update documentation.

---

## Nautobot Import Checklist

When Nautobot is deployed, import the following:

- [ ] Create site: "WOW Homelab"
- [ ] Create VLANs: 110 (mgmt), 130 (workload), 160 (storage)
- [ ] Create Prefixes:
  - [ ] 172.16.100.0/24 (apps network)
  - [ ] 172.16.110.0/24 (proxmox-mgmt)
  - [ ] 172.16.120.0/24 (unknown)
  - [ ] 172.16.130.0/24 (workload)
  - [ ] 172.16.160.0/24 (storage)
  - [ ] 10.1.1.0/24 (pfSense mgmt)
- [ ] Create IP address objects for all IPs in this document
- [ ] Create device types: Proxmox VM, LXC Container, Bare Metal
- [ ] Create devices for all hosts
- [ ] Assign interfaces to devices
- [ ] Tag OpenShift-managed IPs
- [ ] Tag MetalLB pools
- [ ] Document migration plan in Nautobot

---

## Discovery Commands Used

```bash
# Scan networks
nmap -sn 172.16.100.0/24
nmap -sn 172.16.110.0/24
nmap -sn 172.16.160.0/24

# Check OpenShift MetalLB pools
oc get ipaddresspool -A -o yaml

# Check Proxmox VMs
ssh root@172.16.110.101 "qm list"
ssh root@172.16.110.101 "for vm in \$(qm list | awk 'NR>1 {print \$1}'); do qm config \$vm | grep net0; done"

# Check Proxmox LXC
ssh root@172.16.110.101 "pct list"
ssh root@172.16.110.101 "for ct in \$(pct list | awk 'NR>1 {print \$1}'); do pct config \$ct | grep net0; done"
```

---

**End of IP Inventory**
