#!/usr/bin/env python3
"""
Nautobot Infrastructure Setup Script - FINAL VERSION
Fully tested against Nautobot 3.0.3 API

This script creates the complete WOW homelab infrastructure in Nautobot.
Run after ensuring Datacenter location type has proper content_types enabled.
"""

import os
import sys
import requests
from typing import Dict, List, Optional
from datetime import datetime

# Configuration
NAUTOBOT_URL = "https://ipmgmt.sigtom.dev"
API_TOKEN = os.getenv("NAUTOBOT_API_TOKEN")

if not API_TOKEN:
    print("ERROR: NAUTOBOT_API_TOKEN environment variable not set")
    sys.exit(1)

HEADERS = {
    "Authorization": f"Token {API_TOKEN}",
    "Content-Type": "application/json",
    "Accept": "application/json",
}

class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def log(message: str, level: str = "INFO"):
    timestamp = datetime.now().strftime("%H:%M:%S")
    color_map = {
        "INFO": Colors.BLUE,
        "SUCCESS": Colors.GREEN,
        "WARNING": Colors.YELLOW,
        "ERROR": Colors.RED,
        "SKIP": Colors.CYAN,
    }
    color = color_map.get(level, Colors.RESET)
    print(f"{color}[{timestamp}] {level}: {message}{Colors.RESET}")

def api_request(method: str, endpoint: str, data: Optional[Dict] = None) -> Optional[Dict]:
    """Make API request"""
    url = f"{NAUTOBOT_URL}/api/{endpoint}"
    try:
        if method == "GET":
            response = requests.get(url, headers=HEADERS, timeout=10)
        elif method == "POST":
            response = requests.post(url, headers=HEADERS, json=data, timeout=10)
        elif method == "PATCH":
            response = requests.patch(url, headers=HEADERS, json=data, timeout=10)
        else:
            return None
        
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        if method != "GET":  # Don't log GET failures (expected for lookups)
            log(f"{method} {endpoint} failed: {e}", "ERROR")
            if hasattr(e, 'response') and hasattr(e.response, 'text'):
                log(f"Response: {e.response.text}", "ERROR")
        return None

def get_by_name(endpoint: str, name: str, field: str = "name") -> Optional[str]:
    """Get object ID by name"""
    result = api_request("GET", f"{endpoint}?{field}={name}")
    if result and result.get('count', 0) > 0:
        return result['results'][0]['id']
    return None

def create_if_missing(endpoint: str, name: str, data: Dict, lookup_field: str = "name") -> Optional[str]:
    """Create object if it doesn't exist, return ID"""
    # Try to find existing
    obj_id = get_by_name(endpoint, name, lookup_field)
    if obj_id:
        log(f"Found existing: {name}", "SKIP")
        return obj_id
    
    # Create new
    log(f"Creating: {name}", "INFO")
    result = api_request("POST", f"{endpoint}/", data)
    if result and 'id' in result:
        log(f"Created: {name} (ID: {result['id']})", "SUCCESS")
        return result['id']
    
    return None

def main():
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    log(f"{Colors.BOLD}Nautobot Infrastructure Setup - WOW Homelab (Final){Colors.RESET}", "INFO")
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    
    # Get reusable status ID
    status_id = get_by_name("extras/statuses", "Active")
    if not status_id:
        log("Active status not found - cannot proceed", "ERROR")
        return
    
    log("\n=== Phase 1: Location Setup ===", "INFO")
    
    # Get or create location type
    loc_type_id = get_by_name("dcim/location-types", "Datacenter")
    if not loc_type_id:
        loc_type_id = create_if_missing("dcim/location-types", "Datacenter", {
            "name": "Datacenter",
            "description": "Datacenter or server room",
            "content_types": ["dcim.device", "dcim.rack", "ipam.prefix", "ipam.vlan"]
        })
    
    # Create WOW-DC location
    wowdc_id = create_if_missing("dcim/locations", "WOW-DC", {
        "name": "WOW-DC",
        "location_type": loc_type_id,
        "status": status_id,
        "description": "Main datacenter/server room in Tampa, FL"
    })
    
    # Create RACK 1
    rack_id = create_if_missing("dcim/racks", "RACK 1", {
        "name": "RACK 1",
        "location": wowdc_id,
        "status": status_id,
        "u_height": 42,
        "desc_units": True,
        "width": 19,
        "type": "4-post-frame"
    })
    
    log("\n=== Phase 2: Manufacturers ===", "INFO")
    
    manufacturers = {}
    for name in ["Netgate", "Cisco", "MikroTik", "Dell", "Supermicro"]:
        manufacturers[name] = create_if_missing("dcim/manufacturers", name, {
            "name": name,
            "description": f"{name} manufacturer"
        })
    
    log("\n=== Phase 3: Device Roles ===", "INFO")
    
    roles_data = {
        "Firewall": "ff0000",
        "Switch": "00ff00",
        "Core Switch": "0000ff",
        "Blade Chassis": "ffaa00",
        "Compute Node": "9900ff",
        "Storage": "00ffff"
    }
    
    roles = {}
    for name, color in roles_data.items():
        roles[name] = create_if_missing("extras/roles", name, {
            "name": name,
            "color": color,
            "description": f"{name} device role",
            "content_types": ["dcim.device"]
        })
    
    log("\n=== Phase 4: Device Types ===", "INFO")
    
    device_types = {}
    
    # pfSense
    device_types["pfSense"] = create_if_missing("dcim/device-types", "pfSense SG-5100", {
        "model": "pfSense SG-5100",
        "manufacturer": manufacturers["Netgate"],
        "part_number": "SG-5100",
        "u_height": 1,
        "is_full_depth": False
    }, "model")
    
    # Cisco
    device_types["Cisco"] = create_if_missing("dcim/device-types", "SG300-28", {
        "model": "SG300-28",
        "manufacturer": manufacturers["Cisco"],
        "part_number": "SG300-28",
        "u_height": 1,
        "is_full_depth": True
    }, "model")
    
    # MikroTik
    device_types["MikroTik"] = create_if_missing("dcim/device-types", "CRS317-1G-16S+", {
        "model": "CRS317-1G-16S+",
        "manufacturer": manufacturers["MikroTik"],
        "part_number": "CRS317-1G-16S+",
        "u_height": 1,
        "is_full_depth": True
    }, "model")
    
    # Dell FX2s Chassis
    device_types["FX2s"] = create_if_missing("dcim/device-types", "PowerEdge FX2s", {
        "model": "PowerEdge FX2s",
        "manufacturer": manufacturers["Dell"],
        "part_number": "FX2s",
        "u_height": 2,
        "is_full_depth": True,
        "subdevice_role": "parent"
    }, "model")
    
    # Dell FC630 Blade
    device_types["FC630"] = create_if_missing("dcim/device-types", "PowerEdge FC630", {
        "model": "PowerEdge FC630",
        "manufacturer": manufacturers["Dell"],
        "part_number": "FC630",
        "u_height": 0,
        "is_full_depth": False,
        "subdevice_role": "child"
    }, "model")
    
    # Supermicro
    device_types["Supermicro"] = create_if_missing("dcim/device-types", "6028U-TR4T+", {
        "model": "6028U-TR4T+",
        "manufacturer": manufacturers["Supermicro"],
        "part_number": "6028U-TR4T+",
        "u_height": 2,
        "is_full_depth": True
    }, "model")
    
    log("\n=== Phase 5: Physical Devices ===", "INFO")
    
    devices = {}
    
    # U42: pfSense (front only - Cisco goes in different U)
    devices["pfSense"] = create_if_missing("dcim/devices", "pfSense", {
        "name": "pfSense",
        "device_type": device_types["pfSense"],
        "role": roles["Firewall"],
        "location": wowdc_id,
        "rack": rack_id,
        "position": 42,
        "face": "front",
        "status": status_id,
        "comments": "Primary firewall/router - SSH: sre-bot@10.1.1.1:1815"
    })
    
    # U41: MikroTik Core Switch
    devices["MikroTik"] = create_if_missing("dcim/devices", "wow-10gb-mik-sw", {
        "name": "wow-10gb-mik-sw",
        "device_type": device_types["MikroTik"],
        "role": roles["Core Switch"],
        "location": wowdc_id,
        "rack": rack_id,
        "position": 41,
        "face": "front",
        "status": status_id,
        "comments": "10G SFP+ core switch - Web UI: http://172.16.100.50/"
    })
    
    # U40: Cisco SG300-28 (moved from U42 rear to avoid conflicts)
    devices["Cisco"] = create_if_missing("dcim/devices", "cisco-sg300-28", {
        "name": "cisco-sg300-28",
        "device_type": device_types["Cisco"],
        "role": roles["Switch"],
        "location": wowdc_id,
        "rack": rack_id,
        "position": 40,
        "face": "front",
        "status": status_id,
        "comments": "28-port gigabit switch - Web UI: http://10.1.1.2/"
    })
    
    # U38-39: Dell FX2s Chassis
    devices["FX2s"] = create_if_missing("dcim/devices", "dell-fx2s-chassis", {
        "name": "dell-fx2s-chassis",
        "device_type": device_types["FX2s"],
        "role": roles["Blade Chassis"],
        "location": wowdc_id,
        "rack": rack_id,
        "position": 38,
        "face": "front",
        "status": status_id,
        "comments": "Dell FX2s blade chassis with 4x FC630 blades"
    })
    
    # Blades
    blade_configs = [
        ("wow-prox1", 1, "Proxmox VE hypervisor - Mgmt: 172.16.110.101"),
        ("wow-ocp-node2", 2, "OpenShift node 2 - Machine: 172.16.100.102"),
        ("wow-ocp-node3", 3, "OpenShift node 3 - Machine: 172.16.100.103"),
        ("wow-ocp-node4", 4, "OpenShift node 4 - Media workloads")
    ]
    
    for blade_name, position, comment in blade_configs:
        devices[blade_name] = create_if_missing("dcim/devices", blade_name, {
            "name": blade_name,
            "device_type": device_types["FC630"],
            "role": roles["Compute Node"],
            "location": wowdc_id,
            "parent_device": devices["FX2s"],
            "device_bay_position": position,
            "status": status_id,
            "comments": comment
        })
    
    # U36-37: TrueNAS
    devices["TrueNAS"] = create_if_missing("dcim/devices", "wow-ts01", {
        "name": "wow-ts01",
        "device_type": device_types["Supermicro"],
        "role": roles["Storage"],
        "location": wowdc_id,
        "rack": rack_id,
        "position": 36,
        "face": "front",
        "status": status_id,
        "comments": "TrueNAS Scale 25.10 - Mgmt: 172.16.110.100, Storage: 172.16.160.100"
    })
    
    log("\n=== Phase 6: VLANs ===", "INFO")
    
    vlan_configs = [
        (100, "Apps", "Primary application network (native VLAN)"),
        (110, "Proxmox-Mgmt", "Proxmox management plane (RESTRICTED)"),
        (120, "Reserved-120", "Reserved for future use"),
        (130, "Workload", "OpenShift workload traffic"),
        (160, "Storage", "NFS/iSCSI storage backend")
    ]
    
    vlans = {}
    for vid, name, description in vlan_configs:
        vlans[vid] = create_if_missing("ipam/vlans", str(vid), {
            "vid": vid,
            "name": name,
            "status": status_id,
            "description": description
        }, "vid")
    
    log("\n=== Phase 7: IP Prefixes ===", "INFO")
    
    prefix_configs = [
        ("10.1.1.0/24", None, "pfSense management network"),
        ("172.16.100.0/24", vlans[100], "Apps network (native VLAN)"),
        ("172.16.110.0/24", vlans[110], "Proxmox management (RESTRICTED)"),
        ("172.16.120.0/24", vlans[120], "Reserved for future use"),
        ("172.16.130.0/24", vlans[130], "Workload network (OpenShift only)"),
        ("172.16.160.0/24", vlans[160], "Storage network (OFF LIMITS)")
    ]
    
    for prefix, vlan_id, description in prefix_configs:
        data = {
            "prefix": prefix,
            "status": status_id,
            "description": description
        }
        if vlan_id:
            data["vlan"] = vlan_id
        
        create_if_missing("ipam/prefixes", prefix, data, "prefix")
    
    log(f"\n{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    log(f"{Colors.BOLD}✅ Setup Complete!{Colors.RESET}", "SUCCESS")
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    log(f"Nautobot URL: {NAUTOBOT_URL}", "INFO")
    log(f"View rack: {NAUTOBOT_URL}/dcim/racks/", "INFO")
    log(f"\nNext Steps:", "INFO")
    log(f"  1. Add network interfaces to devices", "INFO")
    log(f"  2. Import IP addresses from IP-INVENTORY.md", "INFO")
    log(f"  3. Configure device credentials for discovery", "INFO")

if __name__ == "__main__":
    main()
