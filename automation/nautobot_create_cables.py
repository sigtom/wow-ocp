#!/usr/bin/env python3
"""
Create cable connections in Nautobot based on MikroTik topology.

Maps physical cable connections between devices using the Nautobot Cable API.

Usage:
    export BW_SESSION=$(bw unlock --raw)
    export NAUTOBOT_API_TOKEN=$(bw get item "WOW_NB_API_TOKEN" | jq -r .login.password)
    python3 nautobot_create_cables.py [--dry-run]
"""

import requests
import os
import sys

NAUTOBOT_URL = "https://ipmgmt.sigtom.dev/api"
TOKEN = os.getenv("NAUTOBOT_API_TOKEN")
DRY_RUN = "--dry-run" in sys.argv

if not TOKEN:
    print("❌ ERROR: NAUTOBOT_API_TOKEN not set")
    sys.exit(1)

headers = {'Authorization': f'Token {TOKEN}', 'Content-Type': 'application/json'}

def get_all_results(endpoint):
    """Paginate through all results"""
    results = []
    url = f"{NAUTOBOT_URL}/{endpoint.lstrip('/')}"
    while url:
        resp = requests.get(url, headers=headers, verify=True)
        resp.raise_for_status()
        data = resp.json()
        results.extend(data['results'])
        url = data.get('next')
    return results

print("🔍 Fetching devices and interfaces from Nautobot...")
devices_list = get_all_results('/dcim/devices/')
devices = {d['name']: d for d in devices_list}
devices_by_id = {d['id']: d for d in devices_list}

interfaces = get_all_results('/dcim/interfaces/?limit=1000')

# Build device → interface → interface_id mapping
device_intfs = {}
for intf in interfaces:
    if intf.get('device'):
        dev_id = intf['device']['id']
        if dev_id in devices_by_id:
            dev_name = devices_by_id[dev_id]['name']
            if dev_name not in device_intfs:
                device_intfs[dev_name] = {}
            device_intfs[dev_name][intf['name']] = intf['id']

print(f"📊 Loaded: {len(devices)} devices, {len(interfaces)} interfaces\n")

# Get cable status
cable_status_resp = requests.get(f'{NAUTOBOT_URL}/extras/statuses/?content_types=dcim.cable', headers=headers, verify=True)
cable_statuses = {s['name']: s['id'] for s in cable_status_resp.json()['results']}
active_status = cable_statuses.get('Active') or cable_statuses.get('Connected')

if not active_status:
    print("⚠️  No 'Active' or 'Connected' status found for cables, will use first available")
    active_status = list(cable_statuses.values())[0] if cable_statuses else None

# Define cable connections based on MikroTik topology
# Format: (device_a, interface_a, device_b, interface_b, label)
cable_mappings = [
    # MikroTik to Cisco uplinks
    ('wow-10gb-mik-sw', 'sfp-plus16', 'cisco-sg300-28', 'Port24', 'Uplink to Cisco (10G trunk)'),
    ('wow-10gb-mik-sw', 'ether1', 'cisco-sg300-28', 'Port1', 'Management uplink (1G)'),
    
    # MikroTik to Node 2 (SFP1-4 → FN2210S/A1 ports 9-12)
    ('wow-10gb-mik-sw', 'sfp-plus1', 'wow-ocp-node2', 'eno1', 'Node2 Machine network'),
    ('wow-10gb-mik-sw', 'sfp-plus2', 'wow-ocp-node2', 'eno2', 'Node2 Storage network'),
    ('wow-10gb-mik-sw', 'sfp-plus3', 'wow-ocp-node2', 'eno3', 'Node2 Workload network'),
    # SFP4 likely eno4 but we don't have eno4 in Nautobot yet - skip for now
    
    # MikroTik to Node 3 (SFP5-8 → FN2210S/A2 ports 9-12)
    ('wow-10gb-mik-sw', 'sfp-plus5', 'wow-ocp-node3', 'eno1', 'Node3 Machine network'),
    ('wow-10gb-mik-sw', 'sfp-plus6', 'wow-ocp-node3', 'eno2', 'Node3 Storage network'),
    ('wow-10gb-mik-sw', 'sfp-plus7', 'wow-ocp-node3', 'eno3', 'Node3 Workload network'),
    # SFP8 likely eno4 - skip for now
    
    # MikroTik to TrueNAS
    ('wow-10gb-mik-sw', 'sfp-plus10', 'wow-ts01', 'eno1', 'TrueNAS Management'),
    # TrueNAS LACP ports - need to know exact interface names (eno2/3/4?)
    # Skip for now until we verify TrueNAS interface names
]

# Check which cables can be created
valid_cables = []
missing_interfaces = []

for dev_a, intf_a, dev_b, intf_b, label in cable_mappings:
    # Check if devices exist
    if dev_a not in devices:
        print(f"⚠️  Device {dev_a} not found")
        continue
    if dev_b not in devices:
        print(f"⚠️  Device {dev_b} not found")
        continue
    
    # Check if interfaces exist
    if dev_a not in device_intfs or intf_a not in device_intfs[dev_a]:
        missing_interfaces.append(f"{dev_a}/{intf_a}")
        continue
    if dev_b not in device_intfs or intf_b not in device_intfs[dev_b]:
        missing_interfaces.append(f"{dev_b}/{intf_b}")
        continue
    
    valid_cables.append({
        'dev_a': dev_a,
        'intf_a': intf_a,
        'intf_a_id': device_intfs[dev_a][intf_a],
        'dev_b': dev_b,
        'intf_b': intf_b,
        'intf_b_id': device_intfs[dev_b][intf_b],
        'label': label
    })

print(f"📋 Cable Plan:")
print(f"  ✅ {len(valid_cables)} cables ready to create")
if missing_interfaces:
    print(f"  ⚠️  {len(missing_interfaces)} cables skipped (missing interfaces):")
    for mi in missing_interfaces:
        print(f"      - {mi}")

if DRY_RUN:
    print("\n🔍 DRY RUN - No changes will be made\n")

# Display cables
print("\n🔌 CABLE CONNECTIONS TO CREATE:\n")
for cable in valid_cables:
    print(f"  {cable['dev_a']:20} {cable['intf_a']:15} ↔ {cable['intf_b']:15} {cable['dev_b']:20}")
    print(f"    └─ {cable['label']}")

if not DRY_RUN:
    print("\n⚙️  Creating cables in Nautobot...")
    success = 0
    failed = 0
    
    for cable in valid_cables:
        # Cable data structure for Nautobot API
        data = {
            'termination_a_type': 'dcim.interface',
            'termination_a_id': cable['intf_a_id'],
            'termination_b_type': 'dcim.interface',
            'termination_b_id': cable['intf_b_id'],
            'label': cable['label'],
            'type': 'smf',  # Single-mode fiber (10G SFP+)
            'status': active_status
        }
        
        # Override type for copper connections
        if 'ether1' in cable['intf_a'] or 'Port1' in cable['intf_b']:
            data['type'] = 'cat6'  # 1G copper
        
        try:
            resp = requests.post(
                f"{NAUTOBOT_URL}/dcim/cables/",
                headers=headers,
                json=data,
                verify=True
            )
            
            if resp.status_code == 201:
                print(f"  ✅ {cable['dev_a']}/{cable['intf_a']} ↔ {cable['dev_b']}/{cable['intf_b']}")
                success += 1
            else:
                print(f"  ❌ Failed: {resp.status_code} - {resp.text[:100]}")
                failed += 1
        except Exception as e:
            print(f"  ❌ Error: {e}")
            failed += 1
    
    print(f"\n✅ Complete: {success} cables created, {failed} failed")
else:
    print("\n💡 Run without --dry-run to create cables")
