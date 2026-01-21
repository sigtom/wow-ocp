# Handover Notes - January 20, 2026 (Evening Update)

## 🚀 Session Achievements
1.  **Resolved 4K Buffering:** Enabled 50GB VFS cache mapped to host disk on DUMB LXC.
2.  **Automated Token Refresh:** 15-minute rotation for TorBox links in Decypharr.
3.  **Security Hardening:** Moved all media API keys to Bitwarden/ESO/AAP and scrubbed Git history.
4.  **Stack Expansion:** Deployed Bazarr, Tautulli, and FlareSolverr via AAP.
5.  **Platform Upgrade:** Successfully upgraded **HomeLab EE** to **Ansible Core 2.20.1 (Fedora-based)**.

## 🛠️ Current Status & Blockers
*   **Proxmox Dynamic Inventory:** The sync is currently **failing** with an "Unknown Plugin" or "Dependency" error in AAP.
    *   *Root Cause:* The Seeder (`setup-aap.yml`) is still using `ansible.controller.*` module names, but the new 2.20 EE requires the **`awx.awx.*`** collection names.
    *   *Files Involved:* `automation/aap-config/setup-aap.yml`, `automation/inventory/main.proxmox.yml`.
*   **SSH Bootstrap Utility:** Ready but dependent on the inventory facts (`proxmox_vmid`) which require the sync to work first.

## 📋 Next Session Plan (The "Fix it" Prompt)
Use the following prompt to pick up where we left off:

> "Reference the **HANDOVER.md** and **PROGRESS.md** files. We are mid-way through a platform upgrade.
>
> **Goal:** Fix the Proxmox Dynamic Inventory sync in AAP.
>
> **Context:**
> 1. We just upgraded the **HomeLab EE** to Ansible 2.20.1 (based on `ghcr.io/ansible/community-ansible-dev-tools`).
> 2. The seeder (`automation/aap-config/setup-aap.yml`) needs to be refactored to use the **`awx.awx`** collection instead of `ansible.controller`.
> 3. The Proxmox inventory config is at `automation/inventory/main.proxmox.yml`.
>
> **Tasks:**
> 1. Refactor the seeder to use `awx.awx` modules.
> 2. Ensure the `Proxmox Dynamic Sync` source in the seeder points to the correct `source_project` ('HomeLab Ops') and `source_path` ('automation/inventory/main.proxmox.yml').
> 3. Update the AAP Job Template for the seeder pod if needed.
> 4. Verify the inventory sync and then run the `Util - SSH Bootstrap` playbook against 'all' hosts."

---
*End of Handover*
