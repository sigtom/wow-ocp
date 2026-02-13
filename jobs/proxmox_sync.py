from nautobot.apps.jobs import Job, register_jobs
from nautobot.virtualization.models import VirtualMachine, Cluster, ClusterType
from nautobot.extras.models import Status, Tag
import requests
import urllib3
import os

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

name = "Infrastructure Sync Jobs"

class SyncProxmoxInventory(Job):
    class Meta:
        name = "Sync Proxmox Inventory"
        description = "Sync VMs and LXCs from Proxmox to Nautobot (Safe Mode)"
        has_sensitive_variables = False

    def run(self, commit=False, mark_stale=True, include_lxc=True, node_filter="", vmid_filter=""):
        prox_url = os.environ.get("PROXMOX_URL") or os.environ.get("NAUTOBOT_PROXMOX_URL")
        prox_user = os.environ.get("PROXMOX_USER") or os.environ.get("NAUTOBOT_PROXMOX_USER")
        prox_token = os.environ.get("PROXMOX_TOKEN") or os.environ.get("NAUTOBOT_PROXMOX_TOKEN")
        
        if not prox_url or not prox_user or not prox_token:
            self.logger.error("Missing Proxmox credentials (PROXMOX_URL/USER/TOKEN) in environment.")
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
        cluster, _ = Cluster.objects.get_or_create(name="HomeLab Proxmox", defaults={"type": ctype})

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
                        # Only interested in Linux Bridges (vmbr*) or VLAN subinterfaces
                        # Filter as needed to avoid noise
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
                                # Update IP if present in 'cidr' or 'address'/'netmask'
                                cidr = net.get("cidr") # IPv4 CIDR
                                if cidr:
                                    # Create IP Address and assign
                                    try:
                                        ip_obj, ip_created = IPAddress.objects.get_or_create(
                                            address=cidr,
                                            defaults={"status": status_active}
                                        )
                                        # Assign to interface
                                        if ip_obj.assigned_object != iface:
                                            ip_obj.assigned_object = iface
                                            ip_obj.save()
                                            self.logger.info(f"Assigned IP {cidr} to {iface_name}")
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
            # VM Sync Logic (Existing)
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
                # vm_type logic: check 'type' key if present, else infer
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
