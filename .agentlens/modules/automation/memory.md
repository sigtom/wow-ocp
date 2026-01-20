# Memory

[← Back to MODULE](MODULE.md) | [← Back to INDEX](../../INDEX.md)

## Summary

| High 🔴 | Medium 🟡 | Low 🟢 |
| 5 | 0 | 2 |

## 🔴 High Priority

### `RULE` (automation/nautobot_assign_ips_to_interfaces.py:84)

> 1: pfSense interfaces

### `RULE` (automation/nautobot_assign_ips_to_interfaces.py:93)

> 2: OpenShift nodes (machine network on eno1, storage on eno2, workload on eno3)

### `RULE` (automation/nautobot_assign_ips_to_interfaces.py:112)

> 3: Proxmox (mgmt on vmbr0, storage on vmbr0.160)

### `RULE` (automation/nautobot_assign_ips_to_interfaces.py:118)

> 4: TrueNAS (mgmt on eno1, storage on eno2)

### `RULE` (automation/nautobot_assign_ips_to_interfaces.py:124)

> 5: Network devices (single interface or management)

## 🟢 Low Priority

### `NOTE` (automation/nautobot_import_ips.py:291)

> Device doesn't have interface in Nautobot yet for this IP

### `NOTE` (automation/nautobot_import_ips.py:422)

> Nautobot 3.x doesn't have ipam/ip-ranges endpoint

