# Disaster Recovery Runbook — ViseFin Production

## Overview

This DR solution replicates the on-prem Hyper-V VM `ViseFin-Production` to an Azure standby VM in **Central US** using incremental rsync over SSH. The Azure VM stays deallocated (stopped) to minimize costs and is only started during sync or failover.

This approach was chosen after Azure Site Recovery (ASR) failed due to a persistent Azure-side AAD service principal provisioning bug (error 499 / AADSTS500011) that Microsoft could not resolve.

## Architecture

```
On-Prem (Hyper-V Host: MAIN_SERVER01)          Azure (Central US)
┌──────────────────────────┐                   ┌──────────────────────────┐
│ VM: ViseFin-Production   │   rsync/SSH       │ VM: ViseFin-Production   │
│ IP: 10.20.0.36           │ ──────────────►   │ IP: 20.12.203.14 (PIP)  │
│ OS Disk: 700GB (VHDX)    │   Daily 8 AM      │ OS Disk: 700GB (Managed) │
│ Archive: 500GB (VHDX)    │                   │ Archive: 500GB (Managed) │
│ RAM: 32GB                │                   │ Size: Standard_D2s_v3    │
│ State: Running           │                   │ State: Deallocated       │
└──────────────────────────┘                   └──────────────────────────┘
```

## Azure Resources

| Resource | Type | Location | Notes |
|---|---|---|---|
| ViseFin-Production | VM (Standard_D2s_v3) | Central US | Deallocated when idle |
| ViseFin-OS-v2 | Managed Disk 700GB Standard_LRS | Central US | OS disk |
| ViseFin-Archive | Managed Disk 500GB Standard_LRS | Central US | Data disk (mounted /mnt/archive) |
| Production-VNet | VNet 10.0.0.0/16 | Central US | |
| ViseFin-NIC | NIC | Central US | |
| ViseFin-PIP | Static Public IP | Central US | 20.12.203.14 |
| ViseFin-NSG | NSG | Central US | SSH(22), HTTPS(443) allowed |
| visefin (storage) | Storage Account | East US | Production data (not DR) |

## Monthly Cost (Standby)

| Component | Cost |
|---|---|
| Managed Disks (700GB + 500GB Standard HDD) | ~$20 |
| Static Public IP | ~$3.60 |
| VM compute (~15min/day during sync) | ~$2 |
| **Total** | **~$26/month** |

## Scripts

All scripts are in `F:\Production\Infra\` and backed up to GitHub at `https://github.com/Aminak1990/infra.git`.

### dr-sync.ps1 — Daily Incremental Sync

**Scheduled:** Daily at 2:00 AM via Windows Task Scheduler (`DR-Sync-Azure`)

**What it does:**
1. Authenticates to Azure using service principal (`C:\AzureUpload\dr-sp-creds.json`)
2. Starts the Azure VM
3. Rsyncs `/etc`, `/home`, `/opt`, `/var/lib`, `/var/log`, `/srv`, `/root` from on-prem to Azure
4. Creates and syncs a PostgreSQL database dump
5. Deallocates the Azure VM

**Runtime:** ~14 minutes

**Log:** `F:\Production\Infra\dr-sync.log`

**Manual run:** `powershell -ExecutionPolicy Bypass -File F:\Production\Infra\dr-sync.ps1`

**Trigger via task:** `Start-ScheduledTask -TaskName 'DR-Sync-Azure'`

### dr-failover.ps1 — Emergency Failover

**When to use:** On-prem hardware is down, need to run from Azure immediately.

**What it does:**
1. Starts the Azure VM
2. Displays the public IP and SSH connection info

**Run:** `powershell -File F:\Production\Infra\dr-failover.ps1`

**Post-failover steps:**
1. Update DNS records to point to Azure IP (20.12.203.14)
2. Verify applications are working
3. Communicate to users

### dr-failback.ps1 — Migrate Back to On-Prem

**When to use:** New on-prem hardware is ready, need to move back from Azure.

**What it does:**
1. Stops application services on Azure VM
2. Creates disk snapshots and downloads via azcopy
3. Converts VHD to VHDX
4. Creates new Hyper-V VM with correct settings
5. Starts the VM

**Run:** `powershell -File F:\Production\Infra\dr-failback.ps1`

**Dry run:** `powershell -File F:\Production\Infra\dr-failback.ps1 -DryRun`

**Parameters:**
- `-VmPath` — Path for OS VHDX (default: `F:\HyperV\ViseFin-VM`)
- `-ArchivePath` — Path for archive VHDX (default: `D:\HyperV\ViseFin-Archive`)
- `-VirtualSwitch` — Hyper-V switch name
- `-MemoryGB` — RAM allocation (default: 48)
- `-CpuCount` — vCPUs (default: 8)
- `-SkipDownload` — Skip disk download if already done

## SSH Access

| From | To | Method |
|---|---|---|
| Hyper-V Host → On-prem VM | `visefin@10.20.0.36` | Password (via SSH_ASKPASS) |
| Hyper-V Host → Azure VM | `visefin@20.12.203.14` | Key (`~/.ssh/id_rsa_drsync`) |
| On-prem VM → Azure VM | `visefin@20.12.203.14` | Key (`/root/.ssh/id_rsa_drsync`) |

## Network Configuration

The on-prem VM uses DHCP (`/etc/netplan/01-network.yaml`), which works in both environments:
- **On-prem:** DHCP server assigns 10.20.0.36
- **Azure:** Azure DHCP assigns 10.0.0.4 (public: 20.12.203.14)

## Credentials & Keys

| Item | Location |
|---|---|
| Azure Service Principal | `C:\AzureUpload\dr-sp-creds.json` |
| SSH key (private) | `C:\Users\Administrator\.ssh\id_rsa_drsync` |
| SSH key (public) | `C:\Users\Administrator\.ssh\id_rsa_drsync.pub` |
| SSH key on on-prem VM | `/root/.ssh/id_rsa_drsync` |
| Azure CLI login | Service principal auto-login in scripts |

## Troubleshooting

### Sync fails with "Failed to start Azure VM"
- Check Azure CLI auth: `az login --service-principal -u <appId> -p <password> --tenant <tenant>`
- Check VM state: `az vm get-instance-view --name ViseFin-Production --resource-group Kanvantage`

### Sync fails with rsync permission errors
- Ensure sudoers is configured on Azure VM: `visefin ALL=(ALL) NOPASSWD: /usr/bin/rsync` in `/etc/sudoers.d/dr-sync`
- Re-apply via: `az vm run-command invoke --name ViseFin-Production --resource-group Kanvantage --command-id RunShellScript --scripts @F:\Production\Infra\fix-azure-sudo.sh`

### Can't SSH to Azure VM
- Check NSG rules: `az network nsg rule list --nsg-name ViseFin-NSG --resource-group Kanvantage -o table`
- Check VM is running: `az vm start --name ViseFin-Production --resource-group Kanvantage`
- Check SSH key: `ssh -i C:\Users\Administrator\.ssh\id_rsa_drsync visefin@20.12.203.14`

### Azure VM has no network after boot
- The netplan must be DHCP: check `/etc/netplan/01-network.yaml` contains `dhcp4: true`
- Fix via: `az vm run-command invoke --scripts @F:\Production\Infra\fix-azure-netplan.sh`

## Change History

| Date | Change |
|---|---|
| 2026-03-23 | Initial DR setup: VHD upload, VM creation, sync scripts |
| 2026-03-24 | Fixed sync auth (service principal), sudo rsync, tested end-to-end |
| 2026-03-24 | Fixed SSH readiness check (TCP port test instead of SSH binary) |
| 2026-03-24 | Schedule confirmed at 2:00 AM daily, manually tested and verified |
