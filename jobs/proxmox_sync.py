from nautobot.apps.jobs import Job, register_jobs, BooleanVar, StringVar
from nautobot.virtualization.models import VirtualMachine, Cluster, ClusterType, VMInterface
from nautobot.dcim.models import Device, Interface
from nautobot.ipam.models import IPAddress
from nautobot.extras.models import Status, Tag, Relationship, RelationshipAssociation
from django.contrib.contenttypes.models import ContentType
import requests
import urllib3
import os
import ipaddress

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

name = "Infrastructure Sync Jobs"

class SyncProxmoxInventory(Job):
    # Job variables (exposed in UI/API)
    proxmox_url = StringVar(required=False, description="Proxmox API URL (e.g. https://172.16.110.101:8006)")
    proxmox_user = StringVar(required=False, description="Proxmox token user (user@realm!tokenid)")
    proxmox_token = StringVar(required=False, description="Proxmox token secret")
    commit = BooleanVar(default=False, description="Apply changes (false = dry-run)")
    mark_stale = BooleanVar(default=True, description="Tag VMs not found in Proxmox")
    include_lxc = BooleanVar(default=True, description="Include LXC containers")
    node_filter = StringVar(required=False, description="Filter by Proxmox node name")
    vmid_filter = StringVar(required=False, description="Filter by VMID")

    class Meta:
        name = "Sync Proxmox Inventory"
        description = "Sync VMs and LXCs from Proxmox to Nautobot (Safe Mode)"
        has_sensitive_variables = True

    def run(self, proxmox_url="", proxmox_user="", proxmox_token="", commit=False, mark_stale=True, include_lxc=True, node_filter="", vmid_filter=""):
        # Prioritize UI inputs, fallback to ENV
        prox_url = proxmox_url or os.environ.get("PROXMOX_URL") or os.environ.get("NAUTOBOT_PROXMOX_URL")
        prox_user = proxmox_user or os.environ.get("PROXMOX_USER") or os.environ.get("NAUTOBOT_PROXMOX_USER")
        prox_token = proxmox_token or os.environ.get("PROXMOX_TOKEN") or os.environ.get("NAUTOBOT_PROXMOX_TOKEN")
        
        if not prox_url or not prox_user or not prox_token:
            self.logger.error("Missing Proxmox credentials. Provide via UI inputs or ENV (PROXMOX_URL/USER/TOKEN).")
            return

        headers = {"Authorization": f"PVEAPIToken={prox_user}={prox_token}"}
        verify_tls = False

        self.logger.info(f"Connecting to Proxmox: {prox_url}")

        try:
            nodes_resp = requests.get(f"{prox_url}/api2/json/nodes", headers=headers, verify=verify_tls, timeout=10)
            nodes_resp.raise_for_status()
            nodes = nodes_resp.json().get("data", [])
        except Exception as e:
            self.logger.error(f"Failed to fetch nodes: {e}")
            return

        # Status mapping
        try:
            status_active = Status.objects.get(name="Active")
            status_offline = Status.objects.get(name="Offline")
            status_stale = Status.objects.get(name="Stale") if Status.objects.filter(name="Stale").exists() else status_offline
        except Exception as e:
             self.logger.error(f"Status objects missing in Nautobot: {e}")
             return

        # Ensure Cluster exists
        ctype, _ = ClusterType.objects.get_or_create(name="Proxmox")
        cluster, _ = Cluster.objects.get_or_create(name="HomeLab Proxmox", defaults={"cluster_type": ctype})

        # Relationship setup
        iface_ct = ContentType.objects.get_for_model(Interface)
        vm_iface_ct = ContentType.objects.get_for_model(VMInterface)
        ip_ct = ContentType.objects.get_for_model(IPAddress)

        iface_rel, _ = Relationship.objects.get_or_create(
            key="interface_ip",
            defaults={
                "label": "Interface IP",
                "type": "one-to-many",
                "required_on": "",
                "source_type": iface_ct,
                "destination_type": ip_ct,
                "source_label": "Interface",
                "destination_label": "IP Address",
            },
        )

        vm_iface_rel, _ = Relationship.objects.get_or_create(
            key="vm_interface_ip",
            defaults={
                "label": "VM Interface IP",
                "type": "one-to-many",
                "required_on": "",
                "source_type": vm_iface_ct,
                "destination_type": ip_ct,
                "source_label": "VM Interface",
                "destination_label": "IP Address",
            },
        )

        def netmask_to_prefix(netmask):
            try:
                return ipaddress.ip_network(f"0.0.0.0/{netmask}").prefixlen
            except Exception:
                return None

        def parse_ip_addresses(ip_list):
            for ip in ip_list or []:
                if ip.get("ip-address-type") != "ipv4":
                    continue
                ip_addr = ip.get("ip-address")
                if not ip_addr:
                    continue
                try:
                    ip_obj = ipaddress.ip_address(ip_addr)
                    if ip_obj.is_loopback or ip_obj.is_link_local:
                        continue
                except Exception:
                    continue

                prefix = ip.get("prefix")
                if prefix is None:
                    netmask = ip.get("netmask")
                    if netmask:
                        prefix = netmask_to_prefix(netmask)
                if prefix is None:
                    prefix = 32
                yield ip_addr, int(prefix)

        active_vm_names = set()

        for node_info in nodes:
            node_name = node_info.get("node")
            if node_filter and node_filter not in node_name:
                continue
                
            self.logger.info(f"Scanning Node: {node_name}")

            # ---------------------------------------------------------
            # Sync Host Interfaces (Device level)
            # ---------------------------------------------------------
            try:
                # Find the Device object for this node
                device = Device.objects.get(name=node_name)
                
                # Fetch Node Network
                net_resp = requests.get(f"{prox_url}/api2/json/nodes/{node_name}/network", headers=headers, verify=verify_tls, timeout=10)
                if net_resp.status_code == 200:
                    net_items = net_resp.json().get("data", [])
                    for net in net_items:
                        iface_name = net.get("iface")
                        if not iface_name:
                            continue
                        # Only interested in Linux Bridges (vmbr*) or VLAN subinterfaces
                        if not (iface_name.startswith("vmbr") or "." in iface_name):
                            continue

                        iface_type = "virtual" # Default fallback
                        if iface_name.startswith("vmbr"):
                            iface_type = "bridge"
                        
                        try:
                            # Upsert Interface
                            iface, created = Interface.objects.get_or_create(
                                device=device,
                                name=iface_name,
                                defaults={
                                    "type": iface_type,
                                    "enabled": True,
                                    "mtu": 1500, # Default, could parse if available
                                    "status": status_active
                                }
                            )
                            
                            if commit:
                                # Update IP if present in 'cidr'
                                cidr = net.get("cidr") # IPv4 CIDR
                                if cidr:
                                    try:
                                        ipi = ipaddress.ip_interface(cidr)
                                        ip_obj, _ = IPAddress.objects.get_or_create(
                                            host=str(ipi.ip),
                                            mask_length=int(ipi.network.prefixlen),
                                            defaults={"status": status_active}
                                        )
                                        RelationshipAssociation.objects.get_or_create(
                                            relationship=iface_rel,
                                            source_type=iface_ct,
                                            source_id=iface.id,
                                            destination_type=ip_ct,
                                            destination_id=ip_obj.id,
                                        )
                                    except Exception as ex:
                                        self.logger.warning(f"Failed to process IP {cidr}: {ex}")

                                action = "Created" if created else "Updated"
                                self.logger.info(f"{action} Host Interface: {iface_name} on {node_name}")
                            else:
                                self.logger.info(f"[Dry-Run] Would sync Interface: {iface_name} on {node_name}")
                                
                        except Exception as e:
                            self.logger.warning(f"Error syncing interface {iface_name}: {e}")
            
            except Device.DoesNotExist:
                self.logger.warning(f"Device object '{node_name}' not found in Nautobot. Skipping interface sync.")
            except Exception as e:
                self.logger.error(f"Failed host network sync for {node_name}: {e}")

            # ---------------------------------------------------------
            # VM Sync Logic
            # ---------------------------------------------------------
            vms = []
            # QEMU
            try:
                qemu = requests.get(f"{prox_url}/api2/json/nodes/{node_name}/qemu", headers=headers, verify=verify_tls, timeout=10)
                vms.extend(qemu.json().get("data", []))
            except: pass

            # LXC
            if include_lxc:
                try:
                    lxc = requests.get(f"{prox_url}/api2/json/nodes/{node_name}/lxc", headers=headers, verify=verify_tls, timeout=10)
                    vms.extend(lxc.json().get("data", []))
                except: pass

            for vm in vms:
                vmid = str(vm.get("vmid"))
                name = vm.get("name")
                status_str = vm.get("status")
                vm_type = "lxc" if "type" in vm and vm["type"] == "lxc" else "qemu"
                
                if vmid_filter and str(vmid_filter) != vmid:
                    continue

                active_vm_names.add(name)
                
                nb_status = status_active if status_str == "running" else status_offline
                
                if not name:
                    self.logger.warning(f"Skipping VMID {vmid} with no name")
                    continue

                try:
                    vm_obj, created = VirtualMachine.objects.get_or_create(
                        name=name,
                        cluster=cluster,
                        defaults={
                            "status": nb_status,
                            "vcpus": vm.get("cpus", 1),
                            "memory": int(vm.get("maxmem", 0) / 1024 / 1024),
                            "disk": int(vm.get("maxdisk", 0) / 1024 / 1024 / 1024),
                        }
                    )

                    if commit:
                        # Update fields
                        if vm_obj.status != nb_status:
                            vm_obj.status = nb_status
                        
                        # Update custom fields if they exist on the model
                        cf_updates = {}
                        if "proxmox_vmid" in vm_obj.custom_field_data:
                            cf_updates["proxmox_vmid"] = vmid
                        if "proxmox_node" in vm_obj.custom_field_data:
                            cf_updates["proxmox_node"] = node_name
                        if "proxmox_vmtype" in vm_obj.custom_field_data:
                            cf_updates["proxmox_vmtype"] = vm_type
                        
                        if cf_updates:
                            vm_obj.custom_field_data.update(cf_updates)
                        
                        vm_obj.save()
                        
                        action = "Created" if created else "Updated"
                        self.logger.info(f"{action} VM: {name} (VMID: {vmid}, Node: {node_name})")

                        # -------------------------------------------------
                        # VM/LXC Interface & IP Sync (guest agent)
                        # -------------------------------------------------
                        try:
                            iface_data = []
                            if vm_type == "qemu":
                                resp = requests.get(f"{prox_url}/api2/json/nodes/{node_name}/qemu/{vmid}/agent/network-get-interfaces", headers=headers, verify=verify_tls, timeout=10)
                                if resp.status_code == 200:
                                    payload = resp.json().get("data", {})
                                    iface_data = payload.get("result", payload) if isinstance(payload, dict) else payload
                            else:
                                resp = requests.get(f"{prox_url}/api2/json/nodes/{node_name}/lxc/{vmid}/interfaces", headers=headers, verify=verify_tls, timeout=10)
                                if resp.status_code == 200:
                                    payload = resp.json().get("data", {})
                                    iface_data = payload.get("result", payload) if isinstance(payload, dict) else payload

                            if isinstance(iface_data, list):
                                for iface in iface_data:
                                    iface_name = iface.get("name") or iface.get("iface") or "eth0"
                                    vm_iface, _ = VMInterface.objects.get_or_create(virtual_machine=vm_obj, name=iface_name)
                                    for ip_addr, prefix in parse_ip_addresses(iface.get("ip-addresses", [])):
                                        ip_obj, _ = IPAddress.objects.get_or_create(
                                            host=ip_addr,
                                            mask_length=prefix,
                                            defaults={"status": status_active}
                                        )
                                        RelationshipAssociation.objects.get_or_create(
                                            relationship=vm_iface_rel,
                                            source_type=vm_iface_ct,
                                            source_id=vm_iface.id,
                                            destination_type=ip_ct,
                                            destination_id=ip_obj.id,
                                        )
                        except Exception as ex:
                            self.logger.warning(f"Failed guest IP sync for {name}: {ex}")
                    else:
                        self.logger.info(f"[Dry-Run] Would sync VM: {name} (VMID: {vmid}, Node: {node_name})")
                        
                except Exception as e:
                    self.logger.error(f"Error syncing {name}: {e}")

        # Stale marking
        if mark_stale and commit:
            all_vms = VirtualMachine.objects.filter(cluster=cluster)
            tag_name = "orphaned-from-proxmox"
            try:
                 tag, _ = Tag.objects.get_or_create(name=tag_name, defaults={"color": "ff0000"})
            except: 
                 tag = None

            for vm in all_vms:
                if vm.name not in active_vm_names:
                    if vm.status != status_stale:
                        if tag:
                            vm.tags.add(tag)
                        # Optional: vm.status = status_stale
                        vm.save()
                        self.logger.warning(f"Marked stale: {vm.name}")

register_jobs(SyncProxmoxInventory)
