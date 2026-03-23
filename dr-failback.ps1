##############################################################################
# DR Failback Script - Migrate from Azure back to on-prem Hyper-V
# Run this AFTER your new hardware is ready and Hyper-V is installed
#
# Prerequisites:
#   - New Hyper-V host is up with network configured
#   - Azure VM (ViseFin-Production) is running with your production data
#   - This script runs on the Hyper-V host
#
# What it does:
#   1. Downloads the Azure VM's disks to local VHDX files
#   2. Creates a new Hyper-V VM from those disks
#   3. Reconfigures networking for on-prem
#   4. Starts the VM
#   5. Deallocates the Azure VM
##############################################################################

param(
    [string]$AzureVmName = "ViseFin-Production",
    [string]$ResourceGroup = "Kanvantage",
    [string]$VmPath = "F:\HyperV\ViseFin-VM",
    [string]$ArchivePath = "D:\HyperV\ViseFin-Archive",
    [string]$VirtualSwitch = "Realtek USB GbE Family Controller - Virtual Switch",
    [int64]$MemoryGB = 48,
    [int]$CpuCount = 8,
    [switch]$SkipDownload,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$LogFile = "F:\Production\Infra\dr-failback.log"
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:PATH

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts | $msg" | Tee-Object -Append -FilePath $LogFile
}

try {
    Log "============================================"
    Log "  DR FAILBACK - Azure to On-Prem"
    Log "============================================"

    if ($DryRun) { Log "*** DRY RUN MODE - No changes will be made ***" }

    # ------------------------------------------------------------------
    # Step 1: Verify Azure VM is running
    # ------------------------------------------------------------------
    Log "Checking Azure VM status..."
    $state = az vm get-instance-view --name $AzureVmName --resource-group $ResourceGroup `
        --query "instanceView.statuses[1].displayStatus" -o tsv
    Log "Azure VM state: $state"

    if ($state -notlike "*running*") {
        Log "Starting Azure VM..."
        if (-not $DryRun) {
            az vm start --name $AzureVmName --resource-group $ResourceGroup -o none
            Start-Sleep -Seconds 30
        }
    }

    $azureIp = az network public-ip show --name ViseFin-PIP --resource-group $ResourceGroup `
        --query ipAddress -o tsv
    Log "Azure VM IP: $azureIp"

    # ------------------------------------------------------------------
    # Step 2: Stop services on Azure VM for consistent snapshot
    # ------------------------------------------------------------------
    Log "Stopping application services on Azure VM for consistent state..."
    if (-not $DryRun) {
        $env:SSH_ASKPASS = "C:\AzureUpload\sshpass.bat"
        $env:SSH_ASKPASS_REQUIRE = "force"
        $env:DISPLAY = ":0"

        # Stop app services (customize these for your workload)
        ssh -i C:\Users\Administrator\.ssh\id_rsa_drsync -o StrictHostKeyChecking=no drsync@$azureIp `
            "sudo systemctl stop postgresql nginx docker 2>/dev/null; sudo sync; echo SERVICES_STOPPED"
    }

    # ------------------------------------------------------------------
    # Step 3: Deallocate Azure VM and create snapshots
    # ------------------------------------------------------------------
    Log "Deallocating Azure VM for disk snapshot..."
    if (-not $DryRun) {
        az vm deallocate --name $AzureVmName --resource-group $ResourceGroup -o none
    }

    if (-not $SkipDownload) {
        Log "Creating disk snapshots..."
        if (-not $DryRun) {
            az snapshot create --name failback-os-snap --resource-group $ResourceGroup `
                --location centralus --source ViseFin-OS --sku Standard_LRS -o none
            az snapshot create --name failback-archive-snap --resource-group $ResourceGroup `
                --location centralus --source ViseFin-Archive --sku Standard_LRS -o none
        }

        # ------------------------------------------------------------------
        # Step 4: Get SAS URLs and download disks
        # ------------------------------------------------------------------
        Log "Generating download SAS URLs..."
        if (-not $DryRun) {
            $osSas = az snapshot grant-access --name failback-os-snap --resource-group $ResourceGroup `
                --access-level Read --duration-in-seconds 86400 --query accessSas -o tsv
            $archSas = az snapshot grant-access --name failback-archive-snap --resource-group $ResourceGroup `
                --access-level Read --duration-in-seconds 86400 --query accessSas -o tsv
        }

        # Ensure target directories exist
        New-Item -Path $VmPath -ItemType Directory -Force | Out-Null
        New-Item -Path $ArchivePath -ItemType Directory -Force | Out-Null
        New-Item -Path "C:\AzureUpload" -ItemType Directory -Force | Out-Null

        Log "Downloading OS disk from Azure (this may take a while)..."
        if (-not $DryRun) {
            & "C:\azcopy\azcopy.exe" copy $osSas "$VmPath\ViseFin-OS-Azure-download.vhd" --blob-type PageBlob
        }

        Log "Downloading Archive disk from Azure..."
        if (-not $DryRun) {
            & "C:\azcopy\azcopy.exe" copy $archSas "$ArchivePath\ViseFin-Archive-download.vhd" --blob-type PageBlob
        }

        # ------------------------------------------------------------------
        # Step 5: Convert VHD to VHDX (dynamic to save space)
        # ------------------------------------------------------------------
        Log "Converting OS VHD to dynamic VHDX..."
        if (-not $DryRun) {
            Convert-VHD -Path "$VmPath\ViseFin-OS-Azure-download.vhd" `
                -DestinationPath "$VmPath\ViseFin-OS-Azure.vhdx" -VHDType Dynamic -DeleteSource
        }

        Log "Converting Archive VHD to dynamic VHDX..."
        if (-not $DryRun) {
            Convert-VHD -Path "$ArchivePath\ViseFin-Archive-download.vhd" `
                -DestinationPath "$ArchivePath\ViseFin-Archive.vhdx" -VHDType Dynamic -DeleteSource
        }

        # Cleanup snapshots
        Log "Cleaning up Azure snapshots..."
        if (-not $DryRun) {
            az snapshot revoke-access --name failback-os-snap --resource-group $ResourceGroup -o none
            az snapshot revoke-access --name failback-archive-snap --resource-group $ResourceGroup -o none
            az snapshot delete --name failback-os-snap --resource-group $ResourceGroup -o none
            az snapshot delete --name failback-archive-snap --resource-group $ResourceGroup -o none
        }
    } else {
        Log "Skipping download (--SkipDownload flag set)"
    }

    # ------------------------------------------------------------------
    # Step 6: Remove old VM if exists, create new one
    # ------------------------------------------------------------------
    $existingVm = Get-VM -Name "ViseFin-Production" -ErrorAction SilentlyContinue
    if ($existingVm) {
        Log "Removing existing Hyper-V VM..."
        if (-not $DryRun) {
            Stop-VM -Name "ViseFin-Production" -Force -ErrorAction SilentlyContinue
            Remove-VM -Name "ViseFin-Production" -Force
        }
    }

    Log "Creating new Hyper-V VM..."
    if (-not $DryRun) {
        $vm = New-VM -Name "ViseFin-Production" `
            -MemoryStartupBytes ($MemoryGB * 1GB) `
            -Generation 2 `
            -VHDPath "$VmPath\ViseFin-OS-Azure.vhdx" `
            -SwitchName $VirtualSwitch `
            -Path "F:\HyperV"

        Set-VM -VM $vm -ProcessorCount $CpuCount -DynamicMemory -MemoryMinimumBytes 4GB -MemoryMaximumBytes ($MemoryGB * 1GB)

        # Attach archive disk
        Add-VMHardDiskDrive -VM $vm -Path "$ArchivePath\ViseFin-Archive.vhdx"

        # Disable secure boot for Linux
        Set-VMFirmware -VM $vm -EnableSecureBoot Off
    }

    # ------------------------------------------------------------------
    # Step 7: Fix network config for on-prem (remove Azure DHCP, keep static)
    # ------------------------------------------------------------------
    Log "VM created. Starting to fix network configuration..."
    if (-not $DryRun) {
        Start-VM -Name "ViseFin-Production"
        Start-Sleep -Seconds 30

        # The static netplan config (60-static.yaml) will take precedence on-prem
        # The Azure DHCP config won't interfere since there's no Azure DHCP server
        Log "VM started. Waiting for network..."
        Start-Sleep -Seconds 30

        $vmIp = (Get-VM -Name "ViseFin-Production" | Get-VMNetworkAdapter).IPAddresses |
            Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        Log "On-prem VM IP: $vmIp"
    }

    # ------------------------------------------------------------------
    # Step 8: Deallocate Azure VM to stop costs
    # ------------------------------------------------------------------
    Log "Failback complete. Azure VM remains deallocated to save costs."
    Log "Once you verify on-prem is working, you can delete Azure resources with:"
    Log "  az vm delete --name $AzureVmName --resource-group $ResourceGroup --yes"
    Log "  az disk delete --name ViseFin-OS --resource-group $ResourceGroup"
    Log "  az disk delete --name ViseFin-Archive --resource-group $ResourceGroup"

    Log "============================================"
    Log "  FAILBACK COMPLETED SUCCESSFULLY"
    Log "============================================"
    Log ""
    Log "NEXT STEPS:"
    Log "  1. Verify your applications are working on-prem"
    Log "  2. Update DNS records back to on-prem IP"
    Log "  3. Re-enable the DR-Sync-Azure scheduled task for future protection"
    Log "  4. Keep Azure resources for 48 hours as safety net, then delete"
}
catch {
    Log "ERROR: $_"
    Log "Failback failed. Azure VM is still deallocated with your data intact."
    Log "Fix the issue and re-run this script."
    exit 1
}
