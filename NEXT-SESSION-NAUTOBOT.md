# Next Session Handoff - Nautobot IPAM Integration

## Context
We're setting up Nautobot as the network source of truth for the WOW homelab. Nautobot is deployed and accessible at https://ipmgmt.sigtom.dev (login: admin, password in Bitwarden: NAUTOBOT_SUPERUSER_PASSWORD).

## Where We Left Off
- ✅ Nautobot deployed in production with SSL via Traefik
- ✅ Physical topology fully documented
- ✅ Network device access configured (pfSense, Cisco, MikroTik)
- ✅ IP inventory analyzed (automation/IP-INVENTORY.md)
- ⚠️ Python automation script hit Nautobot 3.x API compatibility issues
- **DECISION:** Use web UI to create physical hierarchy (faster than debugging API quirks)

## Physical Infrastructure to Create

### Location Hierarchy
```
Tampa (Location Type: Site)
 └── WOW-DC (Location Type: Datacenter)
     └── RACK 1 (42U rack)
```

### RACK 1 Layout (Top to Bottom)
```
U42: pfSense (front, 1U half-depth) | Cisco SG300-28 (rear, 1U)
U41: MikroTik CRS317-1G-16S+ (1U, 16x 10G SFP+ core switch)
U40: (empty)
U38-39: Dell FX2s Chassis (2U blade chassis)
  ├─ Slot 1: wow-prox1 (Proxmox VE - FC630 blade)
  ├─ Slot 2: wow-ocp-node2 (OpenShift - FC630 blade)
  ├─ Slot 3: wow-ocp-node3 (OpenShift - FC630 blade)
  └─ Slot 4: wow-ocp-node4 (OpenShift - FC630 blade)
U36-37: wow-ts01 (TrueNAS - Supermicro 6028U-TR4T+, 2U)
```

### Network Device Details
**pfSense:**
- Access: SSH via sre-bot user, key: ~/.ssh/id_pfsense_sre
- Management IP: 10.1.1.1 (SSH port 1815)
- Interfaces: WAN, 2x uplinks to MikroTik, OOB network to CMCs
- Can pull: DHCP leases, ARP table, interface configs

**Cisco SG300-28:**
- Access: Web UI at 10.1.1.2 OR 172.16.100.50, sre-bot user + password
- SSH key auth failed (firmware doesn't support ED25519 or RSA properly)
- 28-port gigabit switch
- Uplink to pfSense

**MikroTik CRS317-1G-16S+:**
- Access: Web UI at http://172.16.100.50/ (RouterOS)
- Need to configure: sre-bot user with API access
- 16x 10G SFP+ ports + 1x gigabit management
- Core/backbone switch
- 2x uplinks from pfSense, downlinks to all servers

## Immediate Next Steps (Priority Order)

### 1. Create Physical Hierarchy in Nautobot (Web UI)
Walk through creating:
- Location Types: Site, Datacenter
- Locations: Tampa → WOW-DC
- Rack: RACK 1 (42U)
- Manufacturers: Netgate, Cisco, MikroTik, Dell, Supermicro
- Device Types:
  - pfSense Firewall (1U, half-depth)
  - Cisco SG300-28 (1U)
  - MikroTik CRS317-1G-16S+ (1U)
  - Dell PowerEdge FX2s (2U, parent device)
  - Dell PowerEdge FC630 (blade, child device)
  - Supermicro 6028U-TR4T+ (2U)
- Device Roles: Firewall, Switch, Core Switch, Blade Chassis, Compute Node, Storage
- Devices: Place all in correct rack positions
- Blades: Add 4x FC630 blades in FX2s chassis

### 2. Test Network Device Access
```bash
# pfSense SSH test
ssh -i ~/.ssh/id_pfsense_sre -p 1815 sre-bot@10.1.1.1

# Commands to run:
ifconfig  # Get interface list
cat /var/dhcpd/var/db/dhcpd.leases  # DHCP leases
arp -an  # ARP table
```

### 3. Configure MikroTik sre-bot User
- Login to RouterOS at http://172.16.100.50/
- Create sre-bot user with API access (read-only)
- Test API connectivity

### 4. Create Network Interfaces on Devices
In Nautobot, add interfaces to each device:
- pfSense: WAN, LAN interfaces, OOB interface
- Cisco: 28x gigabit ports
- MikroTik: 16x SFP+ ports + 1x mgmt port
- Dell blades: eno1 (Machine), eno2 (Storage), eno3 (Workload) where applicable
- TrueNAS: Management NIC (VLAN 110), Storage NIC (VLAN 160)

### 5. Begin IP Import from IP-INVENTORY.md
Create script to parse automation/IP-INVENTORY.md and bulk import IPs:
- Create VLANs: 100, 110, 120, 130, 160
- Create Prefixes: 172.16.{100,110,120,130,160}.0/24, 10.1.1.0/24
- Create IP Ranges for protection (DHCP pools, MetalLB pools)
- Import all known IP addresses with correct status/tags

## Key Files

**Credentials:**
- Nautobot admin password: `bw get password NAUTOBOT_SUPERUSER_PASSWORD`
- Nautobot API token: `bw get password WOW_NB_API_TOKEN`
- pfSense SSH key: `~/.ssh/id_pfsense_sre`
- Cisco sre-bot: Password auth (web UI at 10.1.1.2)

**Documentation:**
- IP allocations: `automation/IP-INVENTORY.md`
- Physical topology: Documented in PROGRESS.md (2026-01-10 entry)
- Incomplete automation script: `/tmp/nautobot_setup_complete.py` (needs API fixes)

**Network Access:**
- Nautobot: https://ipmgmt.sigtom.dev
- pfSense: ssh -i ~/.ssh/id_pfsense_sre -p 1815 sre-bot@10.1.1.1
- Cisco: http://10.1.1.2/ (web UI)
- MikroTik: http://172.16.100.50/ (web UI)

## Success Criteria for Next Session

- [ ] Physical hierarchy created in Nautobot (Tampa → WOW-DC → RACK 1)
- [ ] All 6 devices + 4 blades added to rack elevation
- [ ] Network interfaces created on all devices
- [ ] pfSense SSH access tested and data pulled
- [ ] MikroTik sre-bot user configured with API access
- [ ] VLANs and prefixes created in Nautobot
- [ ] IP import script started or plan created

## Questions to Address

1. Should we automate IP import via Python script or manual import via CSV?
2. Do we want to track physical cables in Nautobot (patch panel documentation)?
3. Should we set up pfSense DHCP lease sync (cron job) immediately or defer?
4. Priority: Network discovery automation vs manual IP population?

## Prompt for Next Instance

```
I'm continuing work on Nautobot IPAM integration for my OpenShift homelab. 

READ THESE FILES FIRST:
- ~/wow-ocp/PROGRESS.md (last entry: 2026-01-10 - Nautobot integration planning)
- ~/wow-ocp/NEXT-SESSION-NAUTOBOT.md (this handoff document)
- ~/wow-ocp/automation/IP-INVENTORY.md (complete IP allocation inventory)

CONTEXT:
- Nautobot is deployed at https://ipmgmt.sigtom.dev (admin login in Bitwarden)
- Physical topology documented: Tampa → WOW-DC → RACK 1
- Network device access configured (pfSense SSH, Cisco/MikroTik web UI)
- Python automation hit Nautobot 3.x API issues - switching to web UI approach

IMMEDIATE GOAL:
Help me create the physical infrastructure hierarchy in Nautobot via web UI, then move to network discovery automation.

START BY:
1. Review the physical rack layout in NEXT-SESSION-NAUTOBOT.md
2. Guide me through Nautobot web UI to create location hierarchy
3. Walk through device type creation and rack population
4. Then we'll tackle network interface creation and IP imports

Ready to proceed with Nautobot setup!
```
