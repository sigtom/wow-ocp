#!/usr/bin/env python3
"""
Nautobot Network Discovery Script

Discovers network devices and topology using multiple sources:
1. pfSense - DHCP leases and ARP table (IP + hostname + MAC)
2. Cisco SG300-28 - SNMP MAC table and port status
3. MikroTik CRS317 - SNMP MAC table and interface stats

Combines data to create/update devices and IPs in Nautobot.

Usage:
  export NAUTOBOT_API_TOKEN="your-token"
  python3 nautobot_discover_network.py [--dry-run] [--source pfsense|cisco|mikrotik|all]
"""

import os
import sys
import re
import argparse
import paramiko
import requests
from pysnmp.hlapi import (
    SnmpEngine, CommunityData, UdpTransportTarget, ContextData,
    ObjectType, ObjectIdentity, nextCmd
)
from typing import Dict, List, Optional, Tuple
from datetime import datetime
from collections import defaultdict

# Configuration
NAUTOBOT_URL = "https://ipmgmt.sigtom.dev"
API_TOKEN = os.getenv("NAUTOBOT_API_TOKEN")

# Device credentials
PFSENSE_HOST = "10.1.1.1"
PFSENSE_PORT = 1815
PFSENSE_USER = "sre-bot"
PFSENSE_KEY = os.path.expanduser("~/.ssh/id_pfsense_sre")

# SNMP configuration
SNMP_COMMUNITY = "rohomelab"
CISCO_IP = "10.1.1.2"
MIKROTIK_IP = "172.16.100.50"

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
    """Make API request to Nautobot"""
    url = f"{NAUTOBOT_URL}/api/{endpoint}"
    try:
        if method == "GET":
            response = requests.get(url, headers=HEADERS, timeout=10)
        elif method == "POST":
            if DRY_RUN:
                log(f"Would create: {endpoint}", "DRYRUN")
                return {"id": "dry-run-id"}
            response = requests.post(url, headers=HEADERS, json=data, timeout=10)
        elif method == "PATCH":
            if DRY_RUN:
                log(f"Would update: {endpoint}", "DRYRUN")
                return {"id": "dry-run-id"}
            response = requests.patch(url, headers=HEADERS, json=data, timeout=10)
        else:
            return None
        
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        if method != "GET":
            log(f"{method} {endpoint} failed: {e}", "ERROR")
        return None

def discover_pfsense() -> Dict[str, Dict]:
    """
    Discover devices via pfSense DHCP leases and ARP table
    Returns: {mac: {ip, hostname, type}}
    """
    log("Discovering devices from pfSense...", "INFO")
    
    devices = {}
    
    try:
        # SSH to pfSense
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(
            PFSENSE_HOST,
            port=PFSENSE_PORT,
            username=PFSENSE_USER,
            key_filename=PFSENSE_KEY,
            timeout=10
        )
        
        # Get DHCP leases
        log("Pulling DHCP leases...", "INFO")
        stdin, stdout, stderr = ssh.exec_command("cat /var/dhcpd/var/db/dhcpd.leases")
        dhcp_output = stdout.read().decode()
        
        # Parse DHCP leases
        current_lease = {}
        for line in dhcp_output.split('\n'):
            line = line.strip()
            
            if line.startswith('lease '):
                # New lease block
                ip = line.split()[1]
                current_lease = {'ip': ip}
            
            elif 'hardware ethernet' in line:
                mac = line.split()[-1].rstrip(';').upper()
                if current_lease:
                    current_lease['mac'] = mac
            
            elif 'client-hostname' in line:
                hostname = line.split('"')[1] if '"' in line else ''
                if current_lease:
                    current_lease['hostname'] = hostname
            
            elif line == '}' and current_lease.get('mac'):
                # End of lease block
                mac = current_lease['mac']
                devices[mac] = {
                    'ip': current_lease.get('ip'),
                    'hostname': current_lease.get('hostname', 'unknown'),
                    'source': 'dhcp',
                    'type': 'dhcp-client'
                }
                current_lease = {}
        
        # Get ARP table for additional devices
        log("Pulling ARP table...", "INFO")
        stdin, stdout, stderr = ssh.exec_command("arp -an")
        arp_output = stdout.read().decode()
        
        # Parse ARP table
        for line in arp_output.split('\n'):
            # Format: ? (172.16.100.50) at aa:bb:cc:dd:ee:ff on em1
            match = re.search(r'\(([0-9.]+)\)\s+at\s+([0-9a-fA-F:]+)', line)
            if match:
                ip = match.group(1)
                mac = match.group(2).upper()
                
                # Add if not already in DHCP leases
                if mac not in devices:
                    devices[mac] = {
                        'ip': ip,
                        'hostname': f'device-{mac.replace(":", "")}',
                        'source': 'arp',
                        'type': 'static'
                    }
        
        ssh.close()
        log(f"Found {len(devices)} devices from pfSense", "SUCCESS")
        
    except Exception as e:
        log(f"pfSense discovery failed: {e}", "ERROR")
    
    return devices

def snmp_walk(host: str, oid: str) -> List[Tuple]:
    """
    Perform SNMP walk on device
    Returns list of (oid, value) tuples
    """
    results = []
    
    try:
        for (errorIndication, errorStatus, errorIndex, varBinds) in nextCmd(
            SnmpEngine(),
            CommunityData(SNMP_COMMUNITY, mpModel=1),  # SNMPv2c
            UdpTransportTarget((host, 161), timeout=5, retries=2),
            ContextData(),
            ObjectType(ObjectIdentity(oid)),
            lexicographicMode=False
        ):
            if errorIndication:
                log(f"SNMP error: {errorIndication}", "ERROR")
                break
            elif errorStatus:
                log(f"SNMP error: {errorStatus.prettyPrint()}", "ERROR")
                break
            else:
                for varBind in varBinds:
                    results.append((str(varBind[0]), str(varBind[1])))
        
    except Exception as e:
        log(f"SNMP walk failed for {host}: {e}", "ERROR")
    
    return results

def discover_cisco_snmp() -> Dict[str, Dict]:
    """
    Discover Cisco SG300-28 via SNMP
    Returns: {mac: {port, vlan, status}}
    """
    log("Discovering Cisco SG300-28 via SNMP...", "INFO")
    
    mac_table = {}
    
    try:
        # MAC address table (BRIDGE-MIB)
        # OID: 1.3.6.1.2.1.17.7.1.2.2.1.2 (dot1qTpFdbPort)
        log("Querying MAC address table...", "INFO")
        results = snmp_walk(CISCO_IP, '1.3.6.1.2.1.17.7.1.2.2.1.2')
        
        for oid, port in results:
            # Extract MAC from OID (last 6 octets)
            oid_parts = oid.split('.')
            if len(oid_parts) >= 6:
                mac_octets = oid_parts[-6:]
                mac = ':'.join([f"{int(x):02X}" for x in mac_octets])
                
                mac_table[mac] = {
                    'port': int(port),
                    'device': 'cisco-sg300-28',
                    'source': 'snmp'
                }
        
        # Get port names/descriptions
        log("Querying interface names...", "INFO")
        port_names = {}
        results = snmp_walk(CISCO_IP, '1.3.6.1.2.1.31.1.1.1.1')  # ifName
        for oid, name in results:
            port_idx = oid.split('.')[-1]
            port_names[int(port_idx)] = name
        
        # Add port names to MAC table
        for mac, info in mac_table.items():
            port_idx = info['port']
            if port_idx in port_names:
                info['port_name'] = port_names[port_idx]
        
        log(f"Found {len(mac_table)} MACs on Cisco switch", "SUCCESS")
        
    except Exception as e:
        log(f"Cisco SNMP discovery failed: {e}", "ERROR")
    
    return mac_table

def discover_mikrotik_snmp() -> Dict[str, Dict]:
    """
    Discover MikroTik CRS317 via SNMP
    Returns: {mac: {port, interface}}
    """
    log("Discovering MikroTik CRS317 via SNMP...", "INFO")
    
    mac_table = {}
    
    try:
        # MAC address table
        log("Querying MAC address table...", "INFO")
        results = snmp_walk(MIKROTIK_IP, '1.3.6.1.2.1.17.7.1.2.2.1.2')
        
        for oid, port in results:
            oid_parts = oid.split('.')
            if len(oid_parts) >= 6:
                mac_octets = oid_parts[-6:]
                mac = ':'.join([f"{int(x):02X}" for x in mac_octets])
                
                mac_table[mac] = {
                    'port': int(port),
                    'device': 'wow-10gb-mik-sw',
                    'source': 'snmp'
                }
        
        # Get interface names
        log("Querying interface names...", "INFO")
        port_names = {}
        results = snmp_walk(MIKROTIK_IP, '1.3.6.1.2.1.31.1.1.1.1')
        for oid, name in results:
            port_idx = oid.split('.')[-1]
            port_names[int(port_idx)] = name
        
        for mac, info in mac_table.items():
            port_idx = info['port']
            if port_idx in port_names:
                info['interface'] = port_names[port_idx]
        
        log(f"Found {len(mac_table)} MACs on MikroTik switch", "SUCCESS")
        
    except Exception as e:
        log(f"MikroTik SNMP discovery failed: {e}", "ERROR")
    
    return mac_table

def correlate_data(pfsense_devices: Dict, cisco_macs: Dict, mikrotik_macs: Dict) -> List[Dict]:
    """
    Correlate data from all sources
    Returns list of discovered devices with all available info
    """
    log("Correlating data from all sources...", "INFO")
    
    discovered = []
    
    for mac, device_info in pfsense_devices.items():
        device = {
            'mac': mac,
            'ip': device_info.get('ip'),
            'hostname': device_info.get('hostname'),
            'type': device_info.get('type'),
            'source': device_info.get('source')
        }
        
        # Check if MAC seen on Cisco
        if mac in cisco_macs:
            device['cisco_port'] = cisco_macs[mac].get('port_name', f"port-{cisco_macs[mac]['port']}")
            device['connected_to'] = 'cisco-sg300-28'
        
        # Check if MAC seen on MikroTik
        if mac in mikrotik_macs:
            device['mikrotik_interface'] = mikrotik_macs[mac].get('interface', f"port-{mikrotik_macs[mac]['port']}")
            device['connected_to'] = 'wow-10gb-mik-sw'
        
        discovered.append(device)
    
    log(f"Correlated {len(discovered)} devices", "SUCCESS")
    return discovered

def update_nautobot(devices: List[Dict]):
    """
    Update Nautobot with discovered devices
    Creates IPs and optionally device objects
    """
    log("Updating Nautobot with discovered devices...", "INFO")
    
    # Get Active status
    status_result = api_request("GET", "extras/statuses?name=Active")
    if not status_result or status_result.get('count', 0) == 0:
        log("Active status not found", "ERROR")
        return
    status_id = status_result['results'][0]['id']
    
    # Get prefix IDs
    prefix_100 = None
    prefix_result = api_request("GET", "ipam/prefixes?prefix=172.16.100.0/24")
    if prefix_result and prefix_result.get('count', 0) > 0:
        prefix_100 = prefix_result['results'][0]['id']
    
    for device in devices:
        ip = device.get('ip')
        mac = device.get('mac')
        hostname = device.get('hostname', f"device-{mac.replace(':', '')}")
        device_type = device.get('type', 'unknown')
        
        if not ip:
            continue
        
        # Determine prefix
        prefix_id = None
        if ip.startswith('172.16.100.'):
            prefix_id = prefix_100
        
        if not prefix_id:
            log(f"Skipping {ip} - no matching prefix", "SKIP")
            continue
        
        # Check if IP already exists
        result = api_request("GET", f"ipam/ip-addresses?address={ip}")
        if result and result.get('count', 0) > 0:
            log(f"IP {ip} already exists ({hostname})", "SKIP")
            continue
        
        # Create IP address
        description = f"Discovered via {device.get('source', 'unknown')}"
        if device.get('connected_to'):
            description += f" - Connected to {device['connected_to']}"
            if device.get('cisco_port'):
                description += f" port {device['cisco_port']}"
            if device.get('mikrotik_interface'):
                description += f" interface {device['mikrotik_interface']}"
        
        data = {
            "address": f"{ip}/32" if '/' not in ip else ip,
            "status": status_id,
            "parent": prefix_id,
            "dns_name": hostname if hostname != 'unknown' else "",
            "description": description
        }
        
        log(f"Creating IP: {ip} ({hostname})", "INFO")
        result = api_request("POST", "ipam/ip-addresses/", data)
        if result:
            log(f"Created IP: {ip} ({hostname})", "SUCCESS")

def generate_report(devices: List[Dict]):
    """Generate discovery report"""
    print(f"\n{Colors.BOLD}{'='*80}{Colors.RESET}")
    print(f"{Colors.BOLD}Network Discovery Report{Colors.RESET}")
    print(f"{Colors.BOLD}{'='*80}{Colors.RESET}\n")
    
    # Group by type
    dhcp_clients = [d for d in devices if d.get('type') == 'dhcp-client']
    static_devices = [d for d in devices if d.get('type') == 'static']
    
    print(f"{Colors.GREEN}DHCP Clients: {len(dhcp_clients)}{Colors.RESET}")
    for device in dhcp_clients[:10]:
        port_info = ""
        if device.get('cisco_port'):
            port_info = f" → Cisco {device['cisco_port']}"
        elif device.get('mikrotik_interface'):
            port_info = f" → MikroTik {device['mikrotik_interface']}"
        
        print(f"  • {device['ip']:16s} {device['hostname']:30s} {device['mac']}{port_info}")
    
    if len(dhcp_clients) > 10:
        print(f"  ... and {len(dhcp_clients) - 10} more")
    
    print(f"\n{Colors.CYAN}Static/ARP Devices: {len(static_devices)}{Colors.RESET}")
    for device in static_devices[:10]:
        port_info = ""
        if device.get('cisco_port'):
            port_info = f" → Cisco {device['cisco_port']}"
        elif device.get('mikrotik_interface'):
            port_info = f" → MikroTik {device['mikrotik_interface']}"
        
        print(f"  • {device['ip']:16s} {device['hostname']:30s} {device['mac']}{port_info}")
    
    if len(static_devices) > 10:
        print(f"  ... and {len(static_devices) - 10} more")
    
    print(f"\n{Colors.BOLD}{'='*80}{Colors.RESET}")

def main():
    global DRY_RUN
    
    parser = argparse.ArgumentParser(description='Discover network devices and update Nautobot')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without making changes')
    parser.add_argument('--source', choices=['pfsense', 'cisco', 'mikrotik', 'all'], default='all',
                       help='Which sources to query (default: all)')
    args = parser.parse_args()
    
    DRY_RUN = args.dry_run
    
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    log(f"{Colors.BOLD}Nautobot Network Discovery{Colors.RESET}", "INFO")
    if DRY_RUN:
        log(f"{Colors.BOLD}🔍 DRY RUN MODE - No changes will be made{Colors.RESET}", "WARNING")
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    
    # Discover from sources
    pfsense_devices = {}
    cisco_macs = {}
    mikrotik_macs = {}
    
    if args.source in ['pfsense', 'all']:
        pfsense_devices = discover_pfsense()
    
    if args.source in ['cisco', 'all']:
        cisco_macs = discover_cisco_snmp()
    
    if args.source in ['mikrotik', 'all']:
        mikrotik_macs = discover_mikrotik_snmp()
    
    # Correlate data
    discovered = correlate_data(pfsense_devices, cisco_macs, mikrotik_macs)
    
    # Generate report
    generate_report(discovered)
    
    # Update Nautobot
    if not DRY_RUN:
        update_nautobot(discovered)
    
    log(f"\n{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    if DRY_RUN:
        log(f"{Colors.BOLD}✅ Dry run complete - no changes made{Colors.RESET}", "SUCCESS")
    else:
        log(f"{Colors.BOLD}✅ Discovery complete!{Colors.RESET}", "SUCCESS")
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")

if __name__ == "__main__":
    main()
