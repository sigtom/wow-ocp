#!/usr/bin/env python3
"""
Nautobot IP Address Import Script

Imports IP addresses from IP-INVENTORY.md and assigns them to device interfaces.
Creates IP address objects with proper status, DNS names, and descriptions.

Usage:
  export NAUTOBOT_API_TOKEN="your-token-here"
  python3 nautobot_import_ips.py [--dry-run]
"""

import os
import sys
import requests
import argparse
from typing import Dict, List, Optional, Tuple
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
}

class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    MAGENTA = '\033[95m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

DRY_RUN = False

def log(message: str, level: str = "INFO"):
    timestamp = datetime.now().strftime("%H:%M:%S")
    color_map = {
        "INFO": Colors.BLUE,
        "SUCCESS": Colors.GREEN,
        "WARNING": Colors.YELLOW,
        "ERROR": Colors.RED,
        "SKIP": Colors.CYAN,
        "DRYRUN": Colors.MAGENTA,
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
            if DRY_RUN:
                log(f"Would create: {endpoint} with data: {data}", "DRYRUN")
                return {"id": "dry-run-id"}
            response = requests.post(url, headers=HEADERS, json=data, timeout=10)
        elif method == "PATCH":
            if DRY_RUN:
                log(f"Would update: {endpoint} with data: {data}", "DRYRUN")
                return {"id": "dry-run-id"}
            response = requests.patch(url, headers=HEADERS, json=data, timeout=10)
        else:
            return None

        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        if method != "GET":
            log(f"{method} {endpoint} failed: {e}", "ERROR")
            if hasattr(e, 'response') and hasattr(e.response, 'text'):
                log(f"Response: {e.response.text}", "ERROR")
        return None

def get_status_id(name: str = "Active") -> Optional[str]:
    """Get status ID by name"""
    result = api_request("GET", f"extras/statuses?name={name}")
    if result and result.get('count', 0) > 0:
        return result['results'][0]['id']
    return None

def get_prefix_id(prefix: str) -> Optional[str]:
    """Get prefix ID"""
    result = api_request("GET", f"ipam/prefixes?prefix={prefix}")
    if result and result.get('count', 0) > 0:
        return result['results'][0]['id']
    return None

def get_device_interface_id(device_name: str, interface_name: str) -> Optional[str]:
    """Get interface ID for a device"""
    # First get device ID
    result = api_request("GET", f"dcim/devices?name={device_name}")
    if not result or result.get('count', 0) == 0:
        return None
    device_id = result['results'][0]['id']

    # Then get interface
    result = api_request("GET", f"dcim/interfaces?device_id={device_id}&name={interface_name}")
    if result and result.get('count', 0) > 0:
        return result['results'][0]['id']
    return None

def get_or_create_ip(address: str, prefix_id: str, status_id: str,
                     dns_name: str = "", description: str = "",
                     tags: List[str] = None) -> Optional[str]:
    """Get existing IP or create new one"""
    # Check if IP exists
    result = api_request("GET", f"ipam/ip-addresses?address={address}")
    if result and result.get('count', 0) > 0:
        ip_id = result['results'][0]['id']
        log(f"IP {address} already exists", "SKIP")
        return ip_id

    # Create new IP
    data = {
        "address": address,
        "status": status_id,
        "parent": prefix_id,
        "dns_name": dns_name,
        "description": description
    }

    if tags:
        # Get tag IDs
        tag_ids = []
        for tag_name in tags:
            tag_result = api_request("GET", f"extras/tags?name={tag_name}")
            if tag_result and tag_result.get('count', 0) > 0:
                tag_ids.append(tag_result['results'][0]['id'])
            else:
                # Create tag if it doesn't exist (Nautobot 3.x requires content_types)
                tag_data = {
                    "name": tag_name,
                    "color": "9e9e9e",
                    "content_types": ["ipam.ipaddress", "ipam.prefix", "dcim.device"]
                }
                tag_create = api_request("POST", "extras/tags/", tag_data)
                if tag_create:
                    tag_ids.append(tag_create['id'])

        if tag_ids:
            data["tags"] = tag_ids

    result = api_request("POST", "ipam/ip-addresses/", data)
    if result:
        log(f"Created IP: {address} ({dns_name or description})", "SUCCESS")
        return result.get('id')
    return None

def assign_ip_to_interface(ip_id: str, interface_id: str) -> bool:
    """Assign IP address to an interface"""
    if DRY_RUN:
        log(f"Would assign IP {ip_id} to interface {interface_id}", "DRYRUN")
        return True

    # Update the IP address to link it to the interface
    data = {"assigned_object_id": interface_id, "assigned_object_type": "dcim.interface"}
    result = api_request("PATCH", f"ipam/ip-addresses/{ip_id}/", data)
    return result is not None

def create_ip_range(start: str, end: str, description: str, tags: List[str] = None) -> Optional[str]:
    """Create an IP range for reserved/pool addresses"""
    # Check if range exists
    result = api_request("GET", f"ipam/ip-ranges?start_address={start}")
    if result and result.get('count', 0) > 0:
        log(f"IP range {start}-{end} already exists", "SKIP")
        return result['results'][0]['id']

    # Get status
    status_id = get_status_id("Reserved")
    if not status_id:
        status_id = get_status_id("Active")

    data = {
        "start_address": start,
        "end_address": end,
        "status": status_id,
        "description": description
    }

    if tags:
        tag_ids = []
        for tag_name in tags:
            tag_result = api_request("GET", f"extras/tags?name={tag_name}")
            if tag_result and tag_result.get('count', 0) > 0:
                tag_ids.append(tag_result['results'][0]['id'])
        if tag_ids:
            data["tags"] = tag_ids

    result = api_request("POST", "ipam/ip-ranges/", data)
    if result:
        log(f"Created IP range: {start}-{end} ({description})", "SUCCESS")
        return result.get('id')
    return None

def main():
    global DRY_RUN

    parser = argparse.ArgumentParser(description='Import IPs from inventory to Nautobot')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without making changes')
    args = parser.parse_args()

    DRY_RUN = args.dry_run

    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    log(f"{Colors.BOLD}Nautobot IP Address Import{Colors.RESET}", "INFO")
    if DRY_RUN:
        log(f"{Colors.BOLD}🔍 DRY RUN MODE - No changes will be made{Colors.RESET}", "WARNING")
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")

    # Get common IDs
    active_status = get_status_id("Active")
    reserved_status = get_status_id("Reserved")
    if not reserved_status:
        reserved_status = active_status

    # Get prefix IDs
    prefix_100 = get_prefix_id("172.16.100.0/24")
    prefix_110 = get_prefix_id("172.16.110.0/24")
    prefix_130 = get_prefix_id("172.16.130.0/24")
    prefix_160 = get_prefix_id("172.16.160.0/24")
    prefix_10 = get_prefix_id("10.1.1.0/24")

    log("\n=== Phase 1: Infrastructure Gateways ===", "INFO")

    # 10.1.1.1 - pfSense WAN/Management
    pfsense_wan_int = get_device_interface_id("pfSense", "em0")
    ip_id = get_or_create_ip("10.1.1.1/32", prefix_10, active_status,
                             dns_name="pfsense.mgmt.sigtom.dev",
                             description="pfSense management interface, NTP server",
                             tags=["infrastructure", "gateway"])
    if ip_id and pfsense_wan_int:
        assign_ip_to_interface(ip_id, pfsense_wan_int)

    # 172.16.100.1 - pfSense LAN
    pfsense_lan_int = get_device_interface_id("pfSense", "em1")
    ip_id = get_or_create_ip("172.16.100.1/24", prefix_100, active_status,
                             dns_name="gw.sigtom.dev",
                             description="Apps network gateway, DNS, DHCP, NTP",
                             tags=["infrastructure", "gateway"])
    if ip_id and pfsense_lan_int:
        assign_ip_to_interface(ip_id, pfsense_lan_int)

    # 172.16.110.1 - pfSense VLAN 110
    pfsense_110_int = get_device_interface_id("pfSense", "em1.110")
    ip_id = get_or_create_ip("172.16.110.1/24", prefix_110, active_status,
                             description="Proxmox management gateway (VLAN 110)",
                             tags=["infrastructure", "gateway"])
    if ip_id and pfsense_110_int:
        assign_ip_to_interface(ip_id, pfsense_110_int)

    # 172.16.130.1 - pfSense VLAN 130
    pfsense_130_int = get_device_interface_id("pfSense", "em1.130")
    ip_id = get_or_create_ip("172.16.130.1/24", prefix_130, active_status,
                             description="OpenShift workload gateway (VLAN 130)",
                             tags=["infrastructure", "gateway", "openshift"])
    if ip_id and pfsense_130_int:
        assign_ip_to_interface(ip_id, pfsense_130_int)

    # 172.16.160.1 - pfSense VLAN 160
    pfsense_160_int = get_device_interface_id("pfSense", "em1.160")
    ip_id = get_or_create_ip("172.16.160.1/24", prefix_160, active_status,
                             description="Storage network gateway (VLAN 160)",
                             tags=["infrastructure", "gateway", "storage"])
    if ip_id and pfsense_160_int:
        assign_ip_to_interface(ip_id, pfsense_160_int)

    log("\n=== Phase 2: Network Devices ===", "INFO")

    # 172.16.100.50 - MikroTik Core Switch
    mikrotik_int = get_device_interface_id("wow-10gb-mik-sw", "ether1")
    ip_id = get_or_create_ip("172.16.100.50/24", prefix_100, active_status,
                             dns_name="sw-core.sigtom.dev",
                             description="MikroTik CRS317 10G core switch",
                             tags=["network", "switch", "dhcp"])
    if ip_id and mikrotik_int:
        assign_ip_to_interface(ip_id, mikrotik_int)

    # 10.1.1.2 - Cisco SG300-28 (primary management)
    # Note: Device doesn't have interface in Nautobot yet for this IP
    get_or_create_ip("10.1.1.2/32", prefix_10, active_status,
                     dns_name="sw-access.sigtom.dev",
                     description="Cisco SG300-28 management interface",
                     tags=["network", "switch"])

    log("\n=== Phase 3: Compute Nodes ===", "INFO")

    # wow-prox1
    prox1_mgmt_int = get_device_interface_id("wow-prox1", "eno1")
    ip_id = get_or_create_ip("172.16.110.101/24", prefix_110, active_status,
                             dns_name="wow-prox1.mgmt.sigtom.dev",
                             description="Proxmox VE hypervisor management",
                             tags=["compute", "proxmox"])
    if ip_id and prox1_mgmt_int:
        assign_ip_to_interface(ip_id, prox1_mgmt_int)

    prox1_storage_int = get_device_interface_id("wow-prox1", "eno2")
    ip_id = get_or_create_ip("172.16.160.101/24", prefix_160, active_status,
                             description="Proxmox storage interface",
                             tags=["compute", "proxmox", "storage"])
    if ip_id and prox1_storage_int:
        assign_ip_to_interface(ip_id, prox1_storage_int)

    # wow-ocp-node2
    node2_machine_int = get_device_interface_id("wow-ocp-node2", "eno1")
    ip_id = get_or_create_ip("172.16.100.102/24", prefix_100, active_status,
                             dns_name="wow-ocp-node2.ossus.sigtomtech.com",
                             description="OpenShift node 2 machine network",
                             tags=["compute", "openshift"])
    if ip_id and node2_machine_int:
        assign_ip_to_interface(ip_id, node2_machine_int)

    node2_storage_int = get_device_interface_id("wow-ocp-node2", "eno2")
    ip_id = get_or_create_ip("172.16.160.102/24", prefix_160, active_status,
                             description="OpenShift node 2 storage network",
                             tags=["compute", "openshift", "storage"])
    if ip_id and node2_storage_int:
        assign_ip_to_interface(ip_id, node2_storage_int)

    node2_workload_int = get_device_interface_id("wow-ocp-node2", "eno3")
    ip_id = get_or_create_ip("172.16.130.102/24", prefix_130, active_status,
                             description="OpenShift node 2 workload network",
                             tags=["compute", "openshift", "workload"])
    if ip_id and node2_workload_int:
        assign_ip_to_interface(ip_id, node2_workload_int)

    # wow-ocp-node3
    node3_machine_int = get_device_interface_id("wow-ocp-node3", "eno1")
    ip_id = get_or_create_ip("172.16.100.103/24", prefix_100, active_status,
                             dns_name="wow-ocp-node3.ossus.sigtomtech.com",
                             description="OpenShift node 3 machine network",
                             tags=["compute", "openshift"])
    if ip_id and node3_machine_int:
        assign_ip_to_interface(ip_id, node3_machine_int)

    node3_storage_int = get_device_interface_id("wow-ocp-node3", "eno2")
    ip_id = get_or_create_ip("172.16.160.103/24", prefix_160, active_status,
                             description="OpenShift node 3 storage network",
                             tags=["compute", "openshift", "storage"])
    if ip_id and node3_storage_int:
        assign_ip_to_interface(ip_id, node3_storage_int)

    node3_workload_int = get_device_interface_id("wow-ocp-node3", "eno3")
    ip_id = get_or_create_ip("172.16.130.103/24", prefix_130, active_status,
                             description="OpenShift node 3 workload network",
                             tags=["compute", "openshift", "workload"])
    if ip_id and node3_workload_int:
        assign_ip_to_interface(ip_id, node3_workload_int)

    log("\n=== Phase 4: Storage ===", "INFO")

    # wow-ts01
    truenas_mgmt_int = get_device_interface_id("wow-ts01", "eno1")
    ip_id = get_or_create_ip("172.16.110.100/24", prefix_110, active_status,
                             dns_name="wow-ts01.mgmt.sigtom.dev",
                             description="TrueNAS Scale 25.10 management interface",
                             tags=["storage", "truenas"])
    if ip_id and truenas_mgmt_int:
        assign_ip_to_interface(ip_id, truenas_mgmt_int)

    truenas_storage_int = get_device_interface_id("wow-ts01", "eno2")
    ip_id = get_or_create_ip("172.16.160.100/24", prefix_160, active_status,
                             description="TrueNAS storage interface (Democratic CSI)",
                             tags=["storage", "truenas", "nfs"])
    if ip_id and truenas_storage_int:
        assign_ip_to_interface(ip_id, truenas_storage_int)

    log("\n=== Phase 5: OpenShift VIPs ===", "INFO")

    get_or_create_ip("172.16.100.104/32", prefix_100, active_status,
                     dns_name="api-int.ossus.sigtomtech.com",
                     description="OpenShift internal API VIP",
                     tags=["openshift", "vip", "api"])

    get_or_create_ip("172.16.100.105/32", prefix_100, active_status,
                     dns_name="api.ossus.sigtomtech.com",
                     description="OpenShift external API VIP",
                     tags=["openshift", "vip", "api"])

    get_or_create_ip("172.16.100.106/32", prefix_100, active_status,
                     dns_name="apps.ossus.sigtomtech.com",
                     description="OpenShift apps ingress VIP (*.apps wildcard)",
                     tags=["openshift", "vip", "ingress"])

    log("\n=== Phase 6: Key Infrastructure Services ===", "INFO")

    # DNS/Infrastructure VMs
    get_or_create_ip("172.16.100.2/24", prefix_100, active_status,
                     dns_name="wow-pihole1.sigtom.dev",
                     description="Pi-hole DNS server (LXC 101)",
                     tags=["dns", "lxc"])

    get_or_create_ip("172.16.100.110/24", prefix_100, active_status,
                     dns_name="iventoy.sigtom.dev",
                     description="iVentoy PXE boot server (LXC 102)",
                     tags=["pxe", "lxc"])

    get_or_create_ip("172.16.110.211/24", prefix_110, active_status,
                     dns_name="dns2.sigtom.dev",
                     description="Technitium DNS server (VM 211)",
                     tags=["dns", "vm", "migrate-to-apps"])

    get_or_create_ip("172.16.110.213/24", prefix_110, active_status,
                     dns_name="ipmgmt.sigtom.dev",
                     description="Nautobot IPAM server (VM 212)",
                     tags=["ipam", "vm", "migrate-to-apps"])

    log("\n=== Phase 7: MetalLB Pools (IP Ranges) ===", "INFO")
    log("Note: IP ranges not supported in Nautobot 3.x - use prefix tags instead", "WARNING")

    # Note: Nautobot 3.x doesn't have ipam/ip-ranges endpoint
    # MetalLB pools are documented via prefix descriptions and tags
    # Individual IPs from pools are created as needed (e.g., plex.sigtom.dev below)

    log("\n=== Phase 8: Known MetalLB Services ===", "INFO")

    get_or_create_ip("172.16.100.200/32", prefix_100, active_status,
                     dns_name="plex.sigtom.dev",
                     description="Plex Media Server (MetalLB service)",
                     tags=["metallb", "media", "openshift"])

    log(f"\n{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    if DRY_RUN:
        log(f"{Colors.BOLD}✅ Dry run complete - no changes made{Colors.RESET}", "SUCCESS")
        log(f"{Colors.BOLD}Run without --dry-run to apply changes{Colors.RESET}", "INFO")
    else:
        log(f"{Colors.BOLD}✅ IP import complete!{Colors.RESET}", "SUCCESS")
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    log(f"View IPs: {NAUTOBOT_URL}/ipam/ip-addresses/", "INFO")

if __name__ == "__main__":
    main()
