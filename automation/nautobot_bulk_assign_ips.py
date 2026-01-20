#!/usr/bin/env python3
"""
Bulk assign IP addresses to interfaces in Nautobot using the correct API endpoint.

Uses /api/ipam/ip-address-to-interface/ endpoint (Nautobot 2.0+/3.x)

Usage:
    export BW_SESSION=$(bw unlock --raw)
    export NAUTOBOT_API_TOKEN=$(bw get item "WOW_NB_API_TOKEN" | jq -r .login.password)
    python3 nautobot_bulk_assign_ips.py [--dry-run]
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

# Get all devices, interfaces, and IPs
print("🔍 Fetching data from Nautobot...")
devices = {d['id']: d for d in get_all_results('/dcim/devices/')}
interfaces = get_all_results('/dcim/interfaces/?limit=1000')
ips = get_all_results('/ipam/ip-addresses/?limit=1000')

# Build device name → interface name → interface ID mapping
device_interfaces = {}
for intf in interfaces:
    if intf.get('device'):
        dev_id = intf['device']['id']
        dev_name = devices[dev_id]['name']
        if dev_name not in device_interfaces:
            device_interfaces[dev_name] = {}
        device_interfaces[dev_name][intf['name']] = intf['id']

print(f"📊 Loaded: {len(devices)} devices, {len(interfaces)} interfaces, {len(ips)} IPs\n")

# Define IP-to-interface mappings
mappings = [
    # pfSense
    ('10.1.1.1', 'pfSense', 'em0'),
    ('172.16.100.1', 'pfSense', 'em1'),
    ('172.16.110.1', 'pfSense', 'em1.110'),
    ('172.16.130.1', 'pfSense', 'em1.130'),
    ('172.16.160.1', 'pfSense', 'em1.160'),

    # Mikrotik
    ('172.16.100.50', 'wow-10gb-mik-sw', 'ether1'),

    # Proxmox
    ('172.16.110.101', 'wow-prox1', 'eno1'),
    ('172.16.160.101', 'wow-prox1', 'eno2'),

    # OpenShift Node 2
    ('172.16.100.102', 'wow-ocp-node2', 'eno1'),
    ('172.16.160.102', 'wow-ocp-node2', 'eno2'),
    ('172.16.130.102', 'wow-ocp-node2', 'eno3'),

    # OpenShift Node 3
    ('172.16.100.103', 'wow-ocp-node3', 'eno1'),
    ('172.16.160.103', 'wow-ocp-node3', 'eno2'),
    ('172.16.130.103', 'wow-ocp-node3', 'eno3'),

    # OpenShift Node 4
    ('172.16.100.104', 'wow-ocp-node4', 'eno1'),
    ('172.16.160.104', 'wow-ocp-node4', 'eno2'),
    ('172.16.130.104', 'wow-ocp-node4', 'eno2'),  # VLAN 130 on eno2 (hybrid port)

    # TrueNAS
    ('172.16.110.100', 'wow-ts01', 'eno1'),
    ('172.16.160.100', 'wow-ts01', 'eno2'),
]

# Build IP address → IP ID mapping
ip_lookup = {}
for ip in ips:
    addr = ip['address'].split('/')[0]  # Remove /24 or /32
    ip_lookup[addr] = ip['id']

# Process assignments
assignments = []
for ip_addr, dev_name, intf_name in mappings:
    if ip_addr not in ip_lookup:
        print(f"⚠️  IP {ip_addr} not found in Nautobot")
        continue

    if dev_name not in device_interfaces:
        print(f"⚠️  Device {dev_name} not found")
        continue

    if intf_name not in device_interfaces[dev_name]:
        print(f"⚠️  Interface {dev_name}/{intf_name} not found")
        continue

    assignments.append({
        'ip_addr': ip_addr,
        'ip_id': ip_lookup[ip_addr],
        'dev_name': dev_name,
        'intf_name': intf_name,
        'intf_id': device_interfaces[dev_name][intf_name]
    })

print(f"📋 Found {len(assignments)} valid assignments\n")

if DRY_RUN:
    print("🔍 DRY RUN - No changes will be made\n")

# Group by device for display
by_device = {}
for a in assignments:
    if a['dev_name'] not in by_device:
        by_device[a['dev_name']] = []
    by_device[a['dev_name']].append(a)

for dev in sorted(by_device.keys()):
    print(f"📦 {dev}:")
    for a in by_device[dev]:
        print(f"  {a['intf_name']:15} ← {a['ip_addr']:18}")

if not DRY_RUN:
    print("\n⚙️  Creating IP-to-interface assignments...")
    success = 0
    failed = 0
    skipped = 0

    for a in assignments:
        data = {
            'ip_address': a['ip_id'],
            'interface': a['intf_id']
        }

        try:
            resp = requests.post(
                f"{NAUTOBOT_URL}/ipam/ip-address-to-interface/",
                headers=headers,
                json=data,
                verify=True
            )

            if resp.status_code == 201:
                print(f"  ✅ {a['ip_addr']} → {a['dev_name']}/{a['intf_name']}")
                success += 1
            elif resp.status_code == 400 and 'already exists' in resp.text:
                print(f"  ⏭️  {a['ip_addr']} already assigned")
                skipped += 1
            else:
                print(f"  ❌ {a['ip_addr']}: {resp.status_code} - {resp.text[:100]}")
                failed += 1
        except Exception as e:
            print(f"  ❌ {a['ip_addr']}: {e}")
            failed += 1

    print(f"\n✅ Complete: {success} assigned, {skipped} skipped, {failed} failed")
else:
    print("\n💡 Run without --dry-run to apply changes")
