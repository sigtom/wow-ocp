from nautobot.apps.jobs import Job, register_jobs
from nautobot.dcim.models import Device, Interface, Cable
from nautobot.extras.models import Status
from nautobot.virtualization.models import VirtualMachine
import subprocess
import re

name = "Network Discovery Jobs"

class DiscoverPhysicalCables(Job):
    class Meta:
        name = "Discover Physical Cables (SNMP)"
        description = "Read-Only SNMP scan of pfSense and MikroTik to map physical topology."
        has_sensitive_variables = False

    def snmp_walk(self, host, community, oid):
        results = {}
        try:
            # Note: This requires snmpwalk to be installed on the Nautobot worker
            cmd = ["snmpwalk", "-On", "-v2c", "-c", community, host, oid]
            output = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode()
            for line in output.splitlines():
                if " = " in line:
                    key, val = line.split(" = ", 1)
                    suffix = key.replace(oid, "").strip(".")
                    results[suffix] = val.split(": ", 1)[-1].strip('" ')
        except Exception as e:
            self.logger.error(f"SNMP Walk failed for {host}: {e}")
        return results

    def format_mac(self, raw):
        parts = re.split(r'[:\-\s]', raw.strip())
        if len(parts) == 6:
            return ":".join([f"{int(p, 16):02X}" for p in parts if p]).upper()
        return raw.upper()

    def run(self):
        pfsense_ip = "10.1.1.1"
        pfsense_comm = "jntinfraro1815"
        mik_ip = "172.16.100.50"
        mik_comm = "rohomelab"

        self.logger.info("Gathering pfSense ARP Table...")
        arp_res = self.snmp_walk(pfsense_ip, pfsense_comm, ".1.3.6.1.2.1.4.22.1.2")
        arp = {}
        for k, v in arp_res.items():
            ip = ".".join(k.split(".")[-4:])
            try: arp[ip] = self.format_mac(v)
            except: pass

        self.logger.info("Gathering MikroTik MAC Table...")
        # Hardcoded mapping from our discovery
        mik_mapping = {
            "130": "SFP13",
            "131": "SFP14",
            "132": "SFP15",
            "10": "TrueNAS MGMT",
            "16": "UPLINK TO FW",
            "17": "MGMT/UPLINK"
        }
        fdb = self.snmp_walk(mik_ip, mik_comm, ".1.3.6.1.2.1.17.4.3.1.2")
        mac_to_port = {}
        for m_oid, bport in fdb.items():
            m_parts = m_oid.split(".")
            if len(m_parts) == 6:
                mac = ":".join([f"{int(x):02X}" for x in m_parts])
                port_name = mik_mapping.get(bport)
                if port_name: mac_to_port[mac] = port_name

        # Targets to link
        targets = [
            ("wow-ts01", "172.16.110.100", "eno1"),
            ("wow-ts01", "172.16.160.100", "eno2"),
            ("wow-prox1", "172.16.110.101", "eno1"),
            ("wow-ocp-node2", "172.16.100.102", "eno1"),
            ("wow-ocp-node3", "172.16.100.103", "eno1"),
            ("wow-ocp-node4", "172.16.100.104", "eno1"),
        ]

        mik_switch = Device.objects.get(name="wow-10gb-mik-sw")
        status_connected = Status.objects.get(name="Connected")

        for name, ip, if_name in targets:
            mac = arp.get(ip)
            port_name = mac_to_port.get(mac)
            if not port_name: continue

            self.logger.info(f"Processing: {name} on port {port_name}")

            try:
                device = Device.objects.get(name=name)
                # Standardize port name for lookup
                nb_port = port_name.lower().replace("sfp", "sfp-plus")
                if "TrueNAS" in port_name or "UPLINK" in port_name: nb_port = port_name

                side_a = Interface.objects.get(device=device, name=if_name)
                side_b = Interface.objects.get(device=mik_switch, name=nb_port)

                if not side_a.cable and not side_b.cable:
                    Cable.objects.create(
                        termination_a=side_a,
                        termination_b=side_b,
                        status=status_connected
                    )
                    self.logger.success(f"Created cable for {name} -> {port_name}")
                else:
                    self.logger.info(f"Cable already exists for {name}")

            except Exception as e:
                self.logger.error(f"Failed to create cable for {name}: {e}")
