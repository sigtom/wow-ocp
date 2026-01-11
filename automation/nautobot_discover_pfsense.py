#!/usr/bin/env python3
"""
Nautobot pfSense Discovery Script

Discovers network devices via pfSense DHCP leases and ARP table.
Creates/updates IP addresses in Nautobot with proper tagging.

Usage:
  export NAUTOBOT_API_TOKEN="your-token"
  python3 nautobot_discover_pfsense.py [--dry-run]
"""

import os
import sys
import re
import argparse
import paramiko
import requests
from typing import Dict, List, Optional
from datetime import datetime

# Configuration
NAUTOBOT_URL = "https://ipmgmt.sigtom.dev"
API_TOKEN = os.getenv("NAUTOBOT_API_TOKEN")

# pfSense credentials
PFSENSE_HOST = "10.1.1.1"
PFSENSE_PORT = 1815
PFSENSE_USER = "sre-bot"
PFSENSE_KEY = os.path.expanduser("~/.ssh/id_pfsense_sre")

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
    Returns: {mac: {ip, hostname, type, source}}
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
                mac = current_lease['mac']
                devices[mac] = {
                    'ip': current_lease.get('ip'),
                    'hostname': current_lease.get('hostname', 'unknown'),
                    'source': 'dhcp',
                    'type': 'dhcp-client'
                }
                current_lease = {}
        
        # Get ARP table
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

def update_nautobot(devices: Dict[str, Dict]):
    """
    Update Nautobot with discovered devices
    Creates IP addresses with proper tagging
    """
    log("Updating Nautobot with discovered devices...", "INFO")
    
    # Get Active status
    status_result = api_request("GET", "extras/statuses?name=Active")
    if not status_result or status_result.get('count', 0) == 0:
        log("Active status not found", "ERROR")
        return
    status_id = status_result['results'][0]['id']
    
    # Get prefix IDs
    prefixes = {}
    for prefix_cidr in ["10.1.1.0/24", "172.16.100.0/24", "172.16.110.0/24", "172.16.130.0/24", "172.16.160.0/24"]:
        result = api_request("GET", f"ipam/prefixes?prefix={prefix_cidr}")
        if result and result.get('count', 0) > 0:
            prefixes[prefix_cidr] = result['results'][0]['id']
    
    stats = {'created': 0, 'skipped': 0, 'errors': 0}
    
    for mac, device in devices.items():
        ip = device.get('ip')
        hostname = device.get('hostname', 'unknown')
        device_type = device.get('type', 'unknown')
        source = device.get('source', 'unknown')
        
        if not ip:
            continue
        
        # Determine prefix
        prefix_id = None
        if ip.startswith('10.1.1.'):
            prefix_id = prefixes.get('10.1.1.0/24')
        elif ip.startswith('172.16.100.'):
            prefix_id = prefixes.get('172.16.100.0/24')
        elif ip.startswith('172.16.110.'):
            prefix_id = prefixes.get('172.16.110.0/24')
        elif ip.startswith('172.16.130.'):
            prefix_id = prefixes.get('172.16.130.0/24')
        elif ip.startswith('172.16.160.'):
            prefix_id = prefixes.get('172.16.160.0/24')
        
        if not prefix_id:
            log(f"Skipping {ip} - no matching prefix", "SKIP")
            stats['skipped'] += 1
            continue
        
        # Check if IP already exists
        result = api_request("GET", f"ipam/ip-addresses?address={ip}")
        if result and result.get('count', 0) > 0:
            stats['skipped'] += 1
            continue
        
        # Create IP address
        description = f"Discovered via pfSense {source} - MAC: {mac}"
        
        data = {
            "address": f"{ip}/32" if '/' not in ip else ip,
            "status": status_id,
            "parent": prefix_id,
            "dns_name": hostname if hostname != 'unknown' else "",
            "description": description
        }
        
        result = api_request("POST", "ipam/ip-addresses/", data)
        if result:
            log(f"Created IP: {ip} ({hostname})", "SUCCESS")
            stats['created'] += 1
        else:
            log(f"Failed to create IP: {ip}", "ERROR")
            stats['errors'] += 1
    
    log(f"Stats: Created={stats['created']}, Skipped={stats['skipped']}, Errors={stats['errors']}", "INFO")

def generate_report(devices: Dict[str, Dict]):
    """Generate discovery report"""
    print(f"\n{Colors.BOLD}{'='*80}{Colors.RESET}")
    print(f"{Colors.BOLD}pfSense Network Discovery Report{Colors.RESET}")
    print(f"{Colors.BOLD}{'='*80}{Colors.RESET}\n")
    
    # Group by type
    dhcp_clients = {mac: dev for mac, dev in devices.items() if dev.get('type') == 'dhcp-client'}
    static_devices = {mac: dev for mac, dev in devices.items() if dev.get('type') == 'static'}
    
    print(f"{Colors.GREEN}DHCP Clients: {len(dhcp_clients)}{Colors.RESET}")
    for i, (mac, device) in enumerate(sorted(dhcp_clients.items(), key=lambda x: x[1]['ip'])):
        if i < 15:
            print(f"  • {device['ip']:16s} {device['hostname']:30s} {mac}")
    
    if len(dhcp_clients) > 15:
        print(f"  ... and {len(dhcp_clients) - 15} more")
    
    print(f"\n{Colors.CYAN}Static/ARP Devices: {len(static_devices)}{Colors.RESET}")
    for i, (mac, device) in enumerate(sorted(static_devices.items(), key=lambda x: x[1]['ip'])):
        if i < 15:
            print(f"  • {device['ip']:16s} {device['hostname']:30s} {mac}")
    
    if len(static_devices) > 15:
        print(f"  ... and {len(static_devices) - 15} more")
    
    print(f"\n{Colors.BOLD}{'='*80}{Colors.RESET}")
    print(f"{Colors.BOLD}Total Devices: {len(devices)}{Colors.RESET}")
    print(f"{Colors.BOLD}{'='*80}{Colors.RESET}\n")

def main():
    global DRY_RUN
    
    parser = argparse.ArgumentParser(description='Discover network devices from pfSense and update Nautobot')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without making changes')
    args = parser.parse_args()
    
    DRY_RUN = args.dry_run
    
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    log(f"{Colors.BOLD}pfSense Network Discovery for Nautobot{Colors.RESET}", "INFO")
    if DRY_RUN:
        log(f"{Colors.BOLD}🔍 DRY RUN MODE - No changes will be made{Colors.RESET}", "WARNING")
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    
    # Discover from pfSense
    devices = discover_pfsense()
    
    # Generate report
    generate_report(devices)
    
    # Update Nautobot
    if not DRY_RUN:
        update_nautobot(devices)
    else:
        log("Dry run complete - no changes made to Nautobot", "INFO")
    
    log(f"\n{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")
    if DRY_RUN:
        log(f"{Colors.BOLD}✅ Dry run complete{Colors.RESET}", "SUCCESS")
        log(f"Run without --dry-run to import devices into Nautobot", "INFO")
    else:
        log(f"{Colors.BOLD}✅ Discovery complete!{Colors.RESET}", "SUCCESS")
        log(f"View IPs: {NAUTOBOT_URL}/ipam/ip-addresses/", "INFO")
    log(f"{Colors.BOLD}{'='*70}{Colors.RESET}", "INFO")

if __name__ == "__main__":
    main()
