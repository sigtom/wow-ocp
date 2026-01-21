from .discovery import DiscoverPhysicalCables
from nautobot.apps.jobs import register_jobs

name = "Network Discovery Jobs"
register_jobs(DiscoverPhysicalCables)
