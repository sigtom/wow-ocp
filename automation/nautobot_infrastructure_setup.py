#!/usr/bin/env python3
"""
Nautobot Infrastructure Setup Script
Automates the creation of physical infrastructure hierarchy for WOW homelab

This script creates:
1. Location Types and Locations (Tampa → WOW-DC)
2. Manufacturers and Device Types
3. Device Roles
4. Rack and physical device layout
5. Network interfaces on all devices
6. VLANs and IP Prefixes
7. IP Address assignments

Author: SigTom
Date: 2026-01-10
Nautobot Version: 3.0.3
"""

import os
import sys
import json
import requests
from typing import Dict, List, Optional, Any
from datetime import datetime

# Configuration
NAUTOBOT_URL = "https://ipmgmt.sigtom.dev"
API_TOKEN = os.getenv("NAUTOBOT_API_TOKEN")

if not API_TOKEN:
    print("ERROR: NAUTOBOT_API_TOKEN environment variable not set")
    sys.exit(1)

# API Headers
HEADERS = {
    "Authorization": f"Token {API_TOKEN}",
    "Content-Type": "application/json",
    "Accept": "application/json",
}

# Color codes for output
class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def log(message: str, level: str = "INFO"):
    """Pretty print log messages"""
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

def api_get(endpoint: str) -> Optional[Dict]:
    """Make GET request to Nautobot API"""
    url = f"{NAUTOBOT_URL}/api/{endpoint}"
    try:
        response = requests.get(url, headers=HEADERS, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        log(f"GET {endpoint} failed: {e}", "ERROR")
        return None

def api_post(endpoint: str, data: Dict) -> Optional[Dict]:
    """Make POST request to Nautobot API"""
    url = f"{NAUTOBOT_URL}/api/{endpoint}"
    try:
        response = requests.post(url, headers=HEADERS, json=data, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        log(f"POST {endpoint} failed: {e}", "ERROR")
        if hasattr(e.response, 'text'):
            log(f"Response: {e.response.text}", "ERROR")
        return None

def get_or_create(endpoint: str, lookup_key: str, lookup_value: str, create_data: Dict) -> Optional[str]:
    """Get existing object or create new one, return UUID"""
    # Try to find existing
    result = api_get(f"{endpoint}?{lookup_key}={lookup_value}")
    if result and result.get('count', 0) > 0:
        obj_id = result['results'][0]['id']
        log(f"Found existing {endpoint} '{lookup_value}' (ID: {obj_id})", "SKIP")
        return obj_id
    
    # Create new
    log(f"Creating {endpoint}: {lookup_value}", "INFO")
    result = api_post(f"{endpoint}/", create_data)
    if result:
        obj_id = result.get('id')
        log(f"Created {endpoint} '{lookup_value}' (ID: {obj_id})", "SUCCESS")
        return obj_id
    else:
        # If creation failed, try one more lookup in case it exists with slightly different query
        result = api_get(f"{endpoint}")
        if result and 'results' in result:
            for item in result['results']:
                if item.get(lookup_key) == lookup_value or item.get('name') == lookup_value or item.get('model') == lookup_value:
                    obj_id = item['id']
                    log(f"Found existing {endpoint} on retry '{lookup_value}' (ID: {obj_id})", "SKIP")
                    return obj_id
    return None

def create_statuses():
    """Ensure required statuses exist"""
    log("Checking statuses...", "INFO")
    
    statuses = [
        {"name": "Active", "color": "4caf50", "description": "Unit is active"},
        {"name": "Planned", "color": "2196f3", "description": "Unit is planned"},
        {"name": "Staged", "color": "ffc107", "description": "Unit is staged"},
        {"name": "Failed", "color": "f44336", "description": "Unit has failed"},
        {"name": "Inventory", "color": "9e9e9e", "description": "Unit is in inventory"},
        {"name": "Decommissioning", "color": "ff9800", "description": "Unit is being decommissioned"},
    ]
    
    for status in statuses:
        get_or_create("extras/statuses", "name", status["name"], {
            "name": status["name"],
            "color": status["color"],
            "description": status["description"],
            "content_types": ["dcim.location", "dcim.rack", "dcim.device"]
        })

def create_location_types():
    """Create location type hierarchy"""
    log("Setting up location types...", "INFO")
    
    # In Nautobot 3.x, we just need one location type for the datacenter
    # Tampa will be a location without strict typing
    datacenter_id = get_or_create("dcim/location-types", "name", "Datacenter", {
        "name": "Datacenter",
        "description": "Datacenter or server room",
        "content_types": ["dcim.device", "dcim.rack", "ipam.prefix", "ipam.vlan"]
    })
    
    return {"datacenter": datacenter_id}

def create_locations(location_types: Dict[str, str]):
    """Create physical locations"""
    log("Setting up locations...", "INFO")
    
    # Get Active status
    status_result = api_get("extras/statuses?name=Active")
    if not status_result or status_result.get('count', 0) == 0:
        log("Active status not found", "ERROR")
        return None
    status_id = status_result['results'][0]['id']
    
    # WOW-DC (Main location - no parent needed)
    wowdc_id = get_or_create("dcim/locations", "name", "WOW-DC", {
        "name": "WOW-DC",
        "location_type": location_types["datacenter"],
        "status": status_id,
        "description": "Main datacenter/server room in Tampa, FL"
    })
    
    return {"wowdc": wowdc_id}

def create_rack(location_id: str):
    """Create RACK 1"""
    log("Setting up rack...", "INFO")
    
    # Get Active status
    status_result = api_get("extras/statuses?name=Active")
    status_id = status_result['results'][0]['id']
    
    rack_id = get_or_create("dcim/racks", "name", "RACK 1", {
        "name": "RACK 1",
        "location": location_id,
        "status": status_id,
        "u_height": 42,
        "desc_units": True,  # U42 at top
        "width": 19,  # 19 inches
        "type": "4-post-frame",
        "comments": "Main 42U rack housing all WOW homelab equipment"
    })
    
    return rack_id

def create_manufacturers():
    """Create device manufacturers"""
    log("Setting up manufacturers...", "INFO")
    
    manufacturers = {
        "Netgate": "Netgate (pfSense)",
        "Cisco": "Cisco Systems",
        "MikroTik": "MikroTik",
        "Dell": "Dell EMC",
        "Supermicro": "Super Micro Computer, Inc."
    }
    
    result = {}
    for name, description in manufacturers.items():
        mfg_id = get_or_create("dcim/manufacturers", "name", name, {
            "name": name,
            "description": description
        })
        result[name.lower()] = mfg_id
    
    return result

def create_device_roles():
    """Create device roles using Nautobot 3.x extras/roles API"""
    log("Setting up device roles...", "INFO")
    
    roles = {
        "Firewall": "ff0000",
        "Switch": "00ff00",
        "Core Switch": "0000ff",
        "Blade Chassis": "ffaa00",
        "Compute Node": "9900ff",
        "Storage": "00ffff"
    }
    
    result = {}
    for name, color in roles.items():
        role_id = get_or_create("extras/roles", "name", name, {
            "name": name,
            "color": color,
            "description": f"{name} device role",
            "content_types": ["dcim.device"]
        })
        result[name.lower().replace(" ", "_")] = role_id
    
    return result

def create_device_types(manufacturers: Dict[str, str]):
    """Create device types"""
    log("Setting up device types...", "INFO")
    
    device_types = [
        {
            "model": "pfSense SG-5100",
            "manufacturer": manufacturers["netgate"],
            "part_number": "SG-5100",
            "u_height": 1,
            "is_full_depth": False,
            "comments": "Netgate pfSense firewall appliance"
        },
        {
            "model": "SG300-28",
            "manufacturer": manufacturers["cisco"],
            "part_number": "SG300-28",
            "u_height": 1,
            "is_full_depth": True,
            "comments": "28-port gigabit managed switch"
        },
        {
            "model": "CRS317-1G-16S+",
            "manufacturer": manufacturers["mikrotik"],
            "part_number": "CRS317-1G-16S+",
            "u_height": 1,
            "is_full_depth": True,
            "comments": "16-port 10G SFP+ core switch with 1 gigabit management port"
        },
        {
            "model": "PowerEdge FX2s",
            "manufacturer": manufacturers["dell"],
            "part_number": "FX2s",
            "u_height": 2,
            "is_full_depth": True,
            "subdevice_role": "parent",
            "comments": "Dell FX2s blade chassis (holds 4x FC630 blades)"
        },
        {
            "model": "PowerEdge FC630",
            "manufacturer": manufacturers["dell"],
            "part_number": "FC630",
            "u_height": 0,  # Blades have no U height
            "is_full_depth": False,
            "subdevice_role": "child",
            "comments": "Dell PowerEdge FC630 blade server"
        },
        {
            "model": "6028U-TR4T+",
            "manufacturer": manufacturers["supermicro"],
            "part_number": "6028U-TR4T+",
            "u_height": 2,
            "is_full_depth": True,
            "comments": "Supermicro 2U TwinPro server"
        }
    ]
    
    result = {}
    for dt in device_types:
        dt_id = get_or_create("dcim/device-types", "model", dt["model"], dt)
        result[dt["model"].lower().replace(" ", "_").replace("-", "_")] = dt_id
    
    return result

def create_devices(location_id: str, rack_id: str, device_types: Dict[str, str], 
                   device_roles: Dict[str, str]):
    """Create all physical devices"""
    log("Setting up devices...", "INFO")
    
    # Get Active status
    status_result = api_get("extras/statuses?name=Active")
    status_id = status_result['results'][0]['id']
    
    devices = []
    
    # U42 Front: pfSense
    pfsense_id = get_or_create("dcim/devices", "name", "pfSense", {
        "name": "pfSense",
        "device_type": device_types["pfsense_sg_5100"],
        "role": device_roles["firewall"],
        "location": location_id,
        "rack": rack_id,
        "position": 42,
        "face": "front",
        "status": status_id,
        "comments": "Primary firewall/router - Management IP: 10.1.1.1:1815 (SSH)"
    })
    devices.append({"name": "pfSense", "id": pfsense_id})
    
    # U42 Rear: Cisco SG300-28
    cisco_id = get_or_create("dcim/devices", "name", "cisco-sg300-28", {
        "name": "cisco-sg300-28",
        "device_type": device_types["sg300_28"],
        "role": device_roles["switch"],
        "location": location_id,
        "rack": rack_id,
        "position": 42,
        "face": "rear",
        "status": status_id,
        "comments": "28-port gigabit switch - Web UI: http://10.1.1.2/"
    })
    devices.append({"name": "cisco-sg300-28", "id": cisco_id})
    
    # U41: MikroTik Core Switch
    mikrotik_id = get_or_create("dcim/devices", "name", "wow-10gb-mik-sw", {
        "name": "wow-10gb-mik-sw",
        "device_type": device_types["crs317_1g_16s+"],
        "role": device_roles["core_switch"],
        "location": location_id,
        "rack": rack_id,
        "position": 41,
        "face": "front",
        "status": status_id,
        "comments": "10G SFP+ core/backbone switch - Web UI: http://172.16.100.50/"
    })
    devices.append({"name": "wow-10gb-mik-sw", "id": mikrotik_id})
    
    # U38-39: Dell FX2s Chassis
    chassis_id = get_or_create("dcim/devices", "name", "dell-fx2s-chassis", {
        "name": "dell-fx2s-chassis",
        "device_type": device_types["poweredge_fx2s"],
        "role": device_roles["blade_chassis"],
        "location": location_id,
        "rack": rack_id,
        "position": 38,
        "face": "front",
        "status": status_id,
        "comments": "Dell FX2s blade chassis housing 4x FC630 blades"
    })
    devices.append({"name": "dell-fx2s-chassis", "id": chassis_id})
    
    # Blades in chassis
    blades = [
        {"name": "wow-prox1", "position": 1, "comments": "Proxmox VE hypervisor - Mgmt: 172.16.110.101"},
        {"name": "wow-ocp-node2", "position": 2, "comments": "OpenShift node 2 - Machine: 172.16.100.102"},
        {"name": "wow-ocp-node3", "position": 3, "comments": "OpenShift node 3 - Machine: 172.16.100.103"},
        {"name": "wow-ocp-node4", "position": 4, "comments": "OpenShift node 4 - Media workloads"}
    ]
    
    for blade in blades:
        blade_id = get_or_create("dcim/devices", "name", blade["name"], {
            "name": blade["name"],
            "device_type": device_types["poweredge_fc630"],
            "role": device_roles["compute_node"],
            "location": location_id,
            "parent_device": chassis_id,
            "device_bay_position": blade["position"],
            "status": status_id,
            "comments": blade["comments"]
        })
        devices.append({"name": blade["name"], "id": blade_id})
    
    # U36-37: TrueNAS
    truenas_id = get_or_create("dcim/devices", "name", "wow-ts01", {
        "name": "wow-ts01",
        "device_type": device_types["6028u_tr4t+"],
        "role": device_roles["storage"],
        "location": location_id,
        "rack": rack_id,
        "position": 36,
        "face": "front",
        "status": status_id,
        "comments": "TrueNAS Scale 25.10 - Mgmt: 172.16.110.100, Storage: 172.16.160.100"
    })
    devices.append({"name": "wow-ts01", "id": truenas_id})
    
    return devices

def create_interfaces(devices: List[Dict[str, str]]):
    """Create network interfaces on all devices"""
    log("Creating network interfaces...", "INFO")
    
    # Get Active status for interfaces
    status_result = api_get("extras/statuses?name=Active")
    if not status_result or status_result.get('count', 0) == 0:
        log("Active status not found", "ERROR")
        return
    status_id = status_result['results'][0]['id']
    
    # Helper to create interface
    def add_interface(device_id: str, name: str, type: str, description: str = ""):
        if not device_id:  # Skip if device wasn't created
            return None
        return get_or_create("dcim/interfaces", "name", f"{device_id}_{name}", {
            "device": device_id,
            "name": name,
            "type": type,
            "status": status_id,
            "description": description,
            "enabled": True
        })
    
    # Get device IDs by name
    device_map = {d["name"]: d["id"] for d in devices}
    
    # pfSense interfaces
    log("Adding pfSense interfaces...", "INFO")
    add_interface(device_map["pfSense"], "em0", "1000base-t", "WAN interface")
    add_interface(device_map["pfSense"], "em1", "1000base-t", "LAN interface (172.16.100.1)")
    add_interface(device_map["pfSense"], "vlan110", "virtual", "Proxmox Mgmt (172.16.110.1)")
    add_interface(device_map["pfSense"], "vlan130", "virtual", "Workload (172.16.130.1)")
    add_interface(device_map["pfSense"], "vlan160", "virtual", "Storage (172.16.160.1)")
    
    # Cisco SG300-28 interfaces (28 gigabit ports)
    log("Adding Cisco SG300-28 interfaces...", "INFO")
    for i in range(1, 29):
        add_interface(device_map["cisco-sg300-28"], f"gi{i}", "1000base-t", 
                     f"Gigabit Ethernet port {i}")
    
    # MikroTik CRS317 interfaces
    log("Adding MikroTik interfaces...", "INFO")
    add_interface(device_map["wow-10gb-mik-sw"], "ether1", "1000base-t", 
                 "Management port (172.16.100.50)")
    for i in range(1, 17):
        add_interface(device_map["wow-10gb-mik-sw"], f"sfp-plus{i}", "10gbase-x-sfpp", 
                     f"10G SFP+ port {i}")
    
    # Dell blades (FC630)
    log("Adding blade interfaces...", "INFO")
    for blade_name in ["wow-prox1", "wow-ocp-node2", "wow-ocp-node3", "wow-ocp-node4"]:
        add_interface(device_map[blade_name], "eno1", "10gbase-x-sfpp", "Machine/Primary network")
        add_interface(device_map[blade_name], "eno2", "10gbase-x-sfpp", "Storage network (VLAN 160)")
        if blade_name in ["wow-ocp-node2", "wow-ocp-node3"]:
            add_interface(device_map[blade_name], "eno3", "10gbase-x-sfpp", "Workload network (VLAN 130)")
    
    # TrueNAS interfaces
    log("Adding TrueNAS interfaces...", "INFO")
    add_interface(device_map["wow-ts01"], "eno1", "1000base-t", "Management (172.16.110.100)")
    add_interface(device_map["wow-ts01"], "eno2", "10gbase-x-sfpp", "Storage (172.16.160.100)")
    
    log("All interfaces created successfully", "SUCCESS")

def create_vlans():
    """Create VLANs"""
    log("Setting up VLANs...", "INFO")
    
    # Get Active status
    status_result = api_get("extras/statuses?name=Active")
    status_id = status_result['results'][0]['id']
    
    vlans = [
        {"vid": 100, "name": "Apps", "description": "Primary application network (native VLAN)"},
        {"vid": 110, "name": "Proxmox-Mgmt", "description": "Proxmox management plane (RESTRICTED)"},
        {"vid": 120, "name": "Reserved-120", "description": "Reserved for future use"},
        {"vid": 130, "name": "Workload", "description": "OpenShift workload traffic (OpenShift only)"},
        {"vid": 160, "name": "Storage", "description": "NFS/iSCSI storage backend (OFF LIMITS)"}
    ]
    
    result = {}
    for vlan in vlans:
        vlan_id = get_or_create("ipam/vlans", "vid", str(vlan["vid"]), {
            "vid": vlan["vid"],
            "name": vlan["name"],
            "status": status_id,
            "description": vlan["description"]
        })
        result[vlan["vid"]] = vlan_id
    
    return result

def create_prefixes(vlans: Dict[int, str]):
    """Create IP prefixes"""
    log("Setting up IP prefixes...", "INFO")
    
    # Get Active status
    status_result = api_get("extras/statuses?name=Active")
    status_id = status_result['results'][0]['id']
    
    prefixes = [
        {"prefix": "10.1.1.0/24", "vlan": None, "description": "pfSense management network"},
        {"prefix": "172.16.100.0/24", "vlan": vlans[100], "description": "Apps network (native VLAN on vmbr0)"},
        {"prefix": "172.16.110.0/24", "vlan": vlans[110], "description": "Proxmox management (VLAN 110)"},
        {"prefix": "172.16.120.0/24", "vlan": vlans[120], "description": "Reserved (VLAN 120)"},
        {"prefix": "172.16.130.0/24", "vlan": vlans[130], "description": "Workload network (VLAN 130 - OpenShift only)"},
        {"prefix": "172.16.160.0/24", "vlan": vlans[160], "description": "Storage network (VLAN 160 - OFF LIMITS)"}
    ]
    
    result = {}
    for pfx in prefixes:
        prefix_data = {
            "prefix": pfx["prefix"],
            "status": status_id,
            "description": pfx["description"]
        }
        if pfx["vlan"]:
            prefix_data["vlan"] = pfx["vlan"]
        
        prefix_id = get_or_create("ipam/prefixes", "prefix", pfx["prefix"], prefix_data)
        result[pfx["prefix"]] = prefix_id
    
    return result

def main():
    """Main execution"""
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    log(f"{Colors.BOLD}Nautobot Infrastructure Setup - WOW Homelab{Colors.RESET}", "INFO")
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    
    # Phase 1: Statuses
    log(f"\n{Colors.BOLD}Phase 1: Statuses{Colors.RESET}", "INFO")
    create_statuses()
    
    # Phase 2: Location Hierarchy
    log(f"\n{Colors.BOLD}Phase 2: Location Hierarchy{Colors.RESET}", "INFO")
    location_types = create_location_types()
    locations = create_locations(location_types)
    rack_id = create_rack(locations["wowdc"])
    
    # Phase 3: Device Setup
    log(f"\n{Colors.BOLD}Phase 3: Device Infrastructure{Colors.RESET}", "INFO")
    manufacturers = create_manufacturers()
    device_roles = create_device_roles()
    device_types = create_device_types(manufacturers)
    
    # Phase 4: Physical Devices
    log(f"\n{Colors.BOLD}Phase 4: Physical Devices{Colors.RESET}", "INFO")
    devices = create_devices(locations["wowdc"], rack_id, device_types, device_roles)
    
    # Phase 5: Network Interfaces
    log(f"\n{Colors.BOLD}Phase 5: Network Interfaces{Colors.RESET}", "INFO")
    create_interfaces(devices)
    
    # Phase 6: VLANs and Prefixes
    log(f"\n{Colors.BOLD}Phase 6: VLANs and IP Prefixes{Colors.RESET}", "INFO")
    vlans = create_vlans()
    prefixes = create_prefixes(vlans)
    
    # Summary
    log(f"\n{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    log(f"{Colors.BOLD}Setup Complete!{Colors.RESET}", "SUCCESS")
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    log(f"Next Steps:", "INFO")
    log(f"  1. Visit {NAUTOBOT_URL}/dcim/racks/ to view RACK 1 elevation", "INFO")
    log(f"  2. Run IP import script to populate IP addresses from IP-INVENTORY.md", "INFO")
    log(f"  3. Configure network device API access (MikroTik sre-bot user)", "INFO")
    log(f"  4. Set up automated discovery via pfSense SSH", "INFO")
    
if __name__ == "__main__":
    main()
