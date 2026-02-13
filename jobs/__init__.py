from .discovery import DiscoverPhysicalCables
from .proxmox_sync import SyncProxmoxInventory
from nautobot.apps.jobs import register_jobs

name = "Network Discovery Jobs"
register_jobs(DiscoverPhysicalCables, SyncProxmoxInventory)
