#!/usr/bin/env python3
"""
Add network interfaces to all devices in Nautobot
"""

import os
import sys
import requests
from typing import Dict, Optional

NAUTOBOT_URL = "https://ipmgmt.sigtom.dev"
API_TOKEN = os.getenv("NAUTOBOT_API_TOKEN")

if not API_TOKEN:
    print("ERROR: NAUTOBOT_API_TOKEN environment variable not set")
    sys.exit(1)

HEADERS = {
    "Authorization": f"Token {API_TOKEN}",
    "Content-Type": "application/json",
}

def api_request(method: str, endpoint: str, data: Optional[Dict] = None) -> Optional[Dict]:
    url = f"{NAUTOBOT_URL}/api/{endpoint}"
    try:
        if method == "GET":
            response = requests.get(url, headers=HEADERS, timeout=10)
        elif method == "POST":
            response = requests.post(url, headers=HEADERS, json=data, timeout=10)
        
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        if method == "POST":
            print(f"ERROR: {method} {endpoint} - {e}")
        return None

def get_device_id(name: str) -> Optional[str]:
    result = api_request("GET", f"dcim/devices?name={name}")
    if result and result.get('count', 0) > 0:
        return result['results'][0]['id']
    return None

def get_status_id() -> Optional[str]:
    result = api_request("GET", "extras/statuses?name=Active")
    if result and result.get('count', 0) > 0:
        return result['results'][0]['id']
    return None

def add_interface(device_id: str, name: str, itype: str, description: str = "") -> bool:
    # Check if exists
    result = api_request("GET", f"dcim/interfaces?device_id={device_id}&name={name}")
    if result and result.get('count', 0) > 0:
        print(f"  ✓ {name} (exists)")
        return True
    
    # Create
    status_id = get_status_id()
    data = {
        "device": device_id,
        "name": name,
        "type": itype,
        "status": status_id,
        "description": description,
        "enabled": True
    }
    
    result = api_request("POST", "dcim/interfaces/", data)
    if result:
        print(f"  ✓ {name} (created)")
        return True
    else:
        print(f"  ✗ {name} (failed)")
        return False

def main():
    print("="*70)
    print("Adding Network Interfaces to Nautobot Devices")
    print("="*70)
    
    # pfSense
    print("\n[pfSense]")
    device_id = get_device_id("pfSense")
    if device_id:
        add_interface(device_id, "em0", "1000base-t", "WAN interface")
        add_interface(device_id, "em1", "1000base-t", "LAN - 172.16.100.1")
        add_interface(device_id, "em1.110", "virtual", "Proxmox Mgmt - 172.16.110.1")
        add_interface(device_id, "em1.130", "virtual", "Workload - 172.16.130.1")
        add_interface(device_id, "em1.160", "virtual", "Storage - 172.16.160.1")
    
    # Cisco SG300-28
    print("\n[Cisco SG300-28]")
    device_id = get_device_id("cisco-sg300-28")
    if device_id:
        for i in range(1, 29):
            add_interface(device_id, f"gi{i}", "1000base-t", f"Gigabit Ethernet {i}")
    
    # MikroTik CRS317
    print("\n[MikroTik CRS317]")
    device_id = get_device_id("wow-10gb-mik-sw")
    if device_id:
        add_interface(device_id, "ether1", "1000base-t", "Management - 172.16.100.50")
        for i in range(1, 17):
            add_interface(device_id, f"sfp-plus{i}", "10gbase-x-sfpp", f"10G SFP+ port {i}")
    
    # Proxmox blade
    print("\n[wow-prox1]")
    device_id = get_device_id("wow-prox1")
    if device_id:
        add_interface(device_id, "eno1", "10gbase-x-sfpp", "Machine network - 172.16.110.101")
        add_interface(device_id, "eno2", "10gbase-x-sfpp", "Storage network - 172.16.160.101")
    
    # OpenShift node2
    print("\n[wow-ocp-node2]")
    device_id = get_device_id("wow-ocp-node2")
    if device_id:
        add_interface(device_id, "eno1", "10gbase-x-sfpp", "Machine network - 172.16.100.102")
        add_interface(device_id, "eno2", "10gbase-x-sfpp", "Storage network - 172.16.160.102")
        add_interface(device_id, "eno3", "10gbase-x-sfpp", "Workload network - 172.16.130.102")
    
    # OpenShift node3
    print("\n[wow-ocp-node3]")
    device_id = get_device_id("wow-ocp-node3")
    if device_id:
        add_interface(device_id, "eno1", "10gbase-x-sfpp", "Machine network - 172.16.100.103")
        add_interface(device_id, "eno2", "10gbase-x-sfpp", "Storage network - 172.16.160.103")
        add_interface(device_id, "eno3", "10gbase-x-sfpp", "Workload network - 172.16.130.103")
    
    # OpenShift node4
    print("\n[wow-ocp-node4]")
    device_id = get_device_id("wow-ocp-node4")
    if device_id:
        add_interface(device_id, "eno1", "10gbase-x-sfpp", "Machine network")
        add_interface(device_id, "eno2", "10gbase-x-sfpp", "Storage network")
    
    # TrueNAS
    print("\n[wow-ts01]")
    device_id = get_device_id("wow-ts01")
    if device_id:
        add_interface(device_id, "eno1", "1000base-t", "Management - 172.16.110.100")
        add_interface(device_id, "eno2", "10gbase-x-sfpp", "Storage - 172.16.160.100")
    
    print("\n" + "="*70)
    print("✅ Interface creation complete!")
    print("="*70)

if __name__ == "__main__":
    main()
