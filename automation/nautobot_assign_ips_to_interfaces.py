#!/usr/bin/env python3
"""
Assign IP addresses to device interfaces in Nautobot.

This script matches IP addresses to device interfaces based on:
1. IP address pattern matching (e.g., 172.16.100.102 → wow-ocp-node2 eno1)
2. DNS name matching
3. Network subnet matching

Usage:
    export BW_SESSION=$(bw unlock --raw)
    python3 nautobot_assign_ips_to_interfaces.py [--dry-run]
"""

import requests
import sys
import os
from typing import Dict, List, Optional

# Configuration
NAUTOBOT_URL = "https://ipmgmt.sigtom.dev/api"
DRY_RUN = "--dry-run" in sys.argv

def get_api_token() -> str:
    """Get API token from Bitwarden."""
    result = os.popen('bw get item "WOW_NB_API_TOKEN" 2>/dev/null | jq -r .login.password').read().strip()
    if not result or result == "null":
        print("❌ ERROR: Could not retrieve API token from Bitwarden")
        print("Run: export BW_SESSION=$(bw unlock --raw)")
        sys.exit(1)
    return result

def api_request(method: str, endpoint: str, headers: Dict, data: Optional[Dict] = None) -> Dict:
    """Make API request to Nautobot."""
    url = f"{NAUTOBOT_URL}/{endpoint.lstrip('/')}"
    if method == "GET":
        response = requests.get(url, headers=headers, verify=True)
    elif method == "POST":
        response = requests.post(url, headers=headers, json=data, verify=True)
    elif method == "PATCH":
        response = requests.patch(url, headers=headers, json=data, verify=True)
    else:
        raise ValueError(f"Unsupported method: {method}")

    response.raise_for_status()
    return response.json()

def main():
    token = get_api_token()
    headers = {
        'Authorization': f'Token {token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json'
    }

    print("🔍 Fetching data from Nautobot...")

    # Get all devices
    devices_resp = api_request("GET", "/dcim/devices/?limit=500", headers)
    devices = {d['id']: d for d in devices_resp['results']}

    # Get all interfaces
    interfaces_resp = api_request("GET", "/dcim/interfaces/?limit=500", headers)
    interfaces = interfaces_resp['results']

    # Get all IP addresses
    ips_resp = api_request("GET", "/ipam/ip-addresses/?limit=500", headers)
    ips = ips_resp['results']

    print(f"📊 Found: {len(devices)} devices, {len(interfaces)} interfaces, {len(ips)} IPs\n")

    # Build mapping: device_name → interface_name → interface_id
    device_interfaces = {}
    for interface in interfaces:
        if interface.get('device'):
            device_id = interface['device']['id']
            device_name = devices[device_id]['name']
            if device_name not in device_interfaces:
                device_interfaces[device_name] = {}
            device_interfaces[device_name][interface['name']] = interface['id']

    # IP to Interface mapping rules
    assignments = []

    # Rule 1: pfSense interfaces
    pfsense_mappings = {
        '10.1.1.1': 'ix4',       # TRANSIT interface
        '172.16.100.1': 'ix3',   # Mikrotik_MGMT
        '172.16.110.1': 'ix5',   # Mikrotik trunk (VLAN 110)
        '172.16.130.1': 'ix5',   # Mikrotik trunk (VLAN 130)
        '172.16.160.1': 'ix5',   # Mikrotik trunk (VLAN 160)
    }

    # Rule 2: OpenShift nodes (machine network on eno1, storage on eno2, workload on eno3)
    node_mappings = {
        'wow-ocp-node2': {
            '172.16.100.102': 'eno1',  # Machine
            '172.16.160.152': 'eno2',  # Storage
            '172.16.130.102': 'eno3',  # Workload
        },
        'wow-ocp-node3': {
            '172.16.100.103': 'eno1',  # Machine
            '172.16.160.153': 'eno2',  # Storage
            '172.16.130.103': 'eno3',  # Workload
        },
        'wow-ocp-node4': {
            '172.16.100.104': 'eno1',  # Machine (also used for VIPs, but different IP)
            '172.16.160.154': 'eno2',  # Storage (VLAN 160 tagged on eno2)
            '172.16.130.104': 'eno2',  # Workload (VLAN 130 native on eno2 - hybrid port)
        },
    }

    # Rule 3: Proxmox (mgmt on vmbr0, storage on vmbr0.160)
    proxmox_mappings = {
        '172.16.110.101': 'vmbr0',
        '172.16.160.101': 'vmbr0.160',
    }

    # Rule 4: TrueNAS (mgmt on eno1, storage on eno2)
    truenas_mappings = {
        '172.16.110.100': 'eno1',
        '172.16.160.100': 'eno2',
    }

    # Rule 5: Network devices (single interface or management)
    network_device_mappings = {
        'cisco-sg300-28': {'10.1.1.2': 'Management'},
        'wow-10gb-mik-sw': {'172.16.100.50': 'ether1'},  # Management port
    }

    # Process all IPs and create assignments
    assigned_count = 0
    skipped_count = 0
    error_count = 0

    for ip in ips:
        ip_addr = ip['address'].split('/')[0]  # Remove /32 or /24 suffix
        ip_id = ip['id']

        # Skip if already assigned
        if ip.get('assigned_object'):
            skipped_count += 1
            continue

        # Try to find matching interface
        interface_id = None
        device_name = None
        interface_name = None

        # Check pfSense
        if ip_addr in pfsense_mappings:
            device_name = 'pfSense'
            interface_name = pfsense_mappings[ip_addr]

        # Check OpenShift nodes
        for node, mapping in node_mappings.items():
            if ip_addr in mapping:
                device_name = node
                interface_name = mapping[ip_addr]
                break

        # Check Proxmox
        if ip_addr in proxmox_mappings:
            device_name = 'wow-prox1'
            interface_name = proxmox_mappings[ip_addr]

        # Check TrueNAS
        if ip_addr in truenas_mappings:
            device_name = 'wow-ts01'
            interface_name = truenas_mappings[ip_addr]

        # Check network devices
        for dev, mapping in network_device_mappings.items():
            if ip_addr in mapping:
                device_name = dev
                interface_name = mapping[ip_addr]
                break

        # If we found a match, get the interface ID
        if device_name and interface_name:
            if device_name in device_interfaces and interface_name in device_interfaces[device_name]:
                interface_id = device_interfaces[device_name][interface_name]
                assignments.append({
                    'ip': ip_addr,
                    'ip_id': ip_id,
                    'device': device_name,
                    'interface': interface_name,
                    'interface_id': interface_id,
                    'dns_name': ip.get('dns_name', '')
                })
            else:
                print(f"⚠️  Interface not found: {device_name} / {interface_name} for IP {ip_addr}")
                error_count += 1
        else:
            # No mapping rule found - skip
            skipped_count += 1

    print(f"📋 Assignment Plan:")
    print(f"  - {len(assignments)} IPs will be assigned to interfaces")
    print(f"  - {skipped_count} IPs already assigned or no mapping found")
    print(f"  - {error_count} errors (interface not found)\n")

    if DRY_RUN:
        print("🔍 DRY RUN MODE - No changes will be made\n")

    # Display assignments grouped by device
    devices_used = {}
    for assignment in assignments:
        device = assignment['device']
        if device not in devices_used:
            devices_used[device] = []
        devices_used[device].append(assignment)

    for device in sorted(devices_used.keys()):
        print(f"\n📦 {device}:")
        for a in sorted(devices_used[device], key=lambda x: x['interface']):
            dns_info = f" ({a['dns_name']})" if a['dns_name'] else ""
            print(f"  {a['interface']:15} ← {a['ip']:18}{dns_info}")

    if not DRY_RUN:
        print("\n⚙️  Assigning IPs to interfaces...")
        success = 0
        failed = 0

        for assignment in assignments:
            try:
                # Assign IP to interface using the ip-address-to-interface endpoint
                data = {
                    'ip_address': assignment['ip_id'],
                    'interface': assignment['interface_id']
                }
                api_request("POST", "/ipam/ip-address-to-interface/", headers, data)
                print(f"  ✅ {assignment['ip']} → {assignment['device']}/{assignment['interface']}")
                success += 1
            except Exception as e:
                print(f"  ❌ Failed to assign {assignment['ip']}: {str(e)}")
                failed += 1

        print(f"\n✅ Complete: {success} assigned, {failed} failed")
    else:
        print("\n💡 Run without --dry-run to apply changes")

if __name__ == "__main__":
    main()
