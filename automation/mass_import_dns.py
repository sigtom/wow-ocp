import sys
import requests
import re
import json

# Configuration
API_URL = "http://172.16.130.210:5380/api"
CATALOG = "cluster-catalog.sigtom.dev"
DNS_LIST_FILE = "pihole1-dns.list"

def get_token():
    with open(".env", "r") as f:
        for line in f:
            if line.startswith("TECHNITIUM_API_TOKEN_DNS1="):
                return line.split("=")[1].strip()
    return None

def ensure_zone(token, zone):
    print(f"Ensuring zone: {zone}")
    # Try to create it
    url = f"{API_URL}/zones/create"
    params = {"token": token, "zone": zone, "catalog": CATALOG}
    r = requests.get(url, params=params)
    data = r.json()
    
    if data.get("status") == "ok":
        print(f"  Zone {zone} created and linked to catalog.")
    elif "already exists" in data.get("error", {}).get("message", ""):
        print(f"  Zone {zone} already exists, updating catalog link...")
        url = f"{API_URL}/zones/options/set"
        params = {"token": token, "zone": zone, "catalog": CATALOG}
        r = requests.get(url, params=params)
        if r.json().get("status") == "ok":
            print(f"    Catalog link updated.")
        else:
            print(f"    Error updating catalog: {r.json().get('error', {}).get('message')}")
    else:
        print(f"  Error: {data.get('status')} - {data.get('error', {}).get('message')}")

def add_record(token, zone, domain, ip):
    print(f"  Adding: {domain} -> {ip}")
    url = f"{API_URL}/zones/records/add"
    params = {
        "token": token,
        "zone": zone,
        "domain": domain,
        "type": "A",
        "ipAddress": ip,
        "overwrite": "true"
    }
    r = requests.get(url, params=params)
    res = r.json()
    if res.get("status") != "ok":
        print(f"    Error: {res.get('status')} - {res.get('error', {}).get('message')}")
    else:
        print(f"    Result: OK")

def main():
    token = get_token()
    if not token:
        print("Error: Could not find TECHNITIUM_API_TOKEN_DNS1 in .env")
        return

    # List of target zones
    target_zones = ["sigtomtech.com", "ahchto.sigtomtech.com", "sigtom.info", "sigtom.dev"]
    for z in target_zones:
        ensure_zone(token, z)

    with open(DNS_LIST_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            
            parts = line.split()
            if len(parts) < 2:
                continue
                
            ip = parts[0]
            for domain in parts[1:]:
                found_zone = None
                clean_domain = None
                
                sorted_zones = sorted(target_zones, key=len, reverse=True)
                
                for z in sorted_zones:
                    if z in domain:
                        # Normalize domain: ensure it matches the full FQDN but belongs to the zone
                        # Example: 'overseerr.sigtom.dev' matches zone 'sigtom.dev'
                        if domain.endswith("." + z) or domain == z:
                             # Extract potential subdomain part
                             subdomain = domain.replace(f".{z}", "")
                             if subdomain == z: subdomain = "@"
                             
                             # Cleanup squashed IP bug
                             subdomain = re.sub(r"\d{1,3}\..*", "", subdomain).strip()
                             
                             if subdomain == domain: 
                                 clean_domain = "@"
                             else:
                                 clean_domain = subdomain
                             
                             found_zone = z
                             break
                
                if found_zone and clean_domain:
                    # Technitium 'domain' param can be '@' for zone root or subdomain name
                    add_record(token, found_zone, clean_domain, ip)

if __name__ == "__main__":
    main()
