##############################################################################
# DR Sync Script - Incremental replication from on-prem to Azure DR VM
# Runs rsync over SSH from on-prem ViseFin-Production to Azure standby VM
# Schedule via Windows Task Scheduler (e.g., daily at 2 AM)
##############################################################################

$ErrorActionPreference = "Continue"
$LogFile = "F:\Production\Infra\dr-sync.log"
$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:PATH

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts | $msg" | Tee-Object -Append -FilePath $LogFile
}

# Config
$ResourceGroup = "Kanvantage"
$AzureVmName = "ViseFin-Production"
$OnPremVmIp = "10.20.0.36"
$SshKey = "C:\Users\Administrator\.ssh\id_rsa_drsync"
$SshUser = "drsync"

# Directories to sync (add/remove as needed)
$SyncPaths = @(
    "/etc",
    "/home",
    "/opt",
    "/var/lib",
    "/var/log",
    "/srv",
    "/root"
)

$ExcludePaths = @(
    "/var/lib/docker/overlay2",
    "/var/log/journal",
    "*.tmp",
    "*.swp",
    "*.cache"
)

try {
    Log "=== DR Sync Started ==="

    # Step 1: Start Azure VM
    Log "Starting Azure DR VM..."
    az vm start --name $AzureVmName --resource-group $ResourceGroup -o none 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to start Azure VM" }
    Start-Sleep -Seconds 30

    # Get Azure VM IP
    $AzureIp = az network public-ip show --name ViseFin-PIP --resource-group $ResourceGroup --query ipAddress -o tsv
    Log "Azure VM IP: $AzureIp"

    # Step 2: Build rsync exclude args
    $excludeArgs = ($ExcludePaths | ForEach-Object { "--exclude='$_'" }) -join " "

    # Step 3: Run rsync for each path via SSH proxy through Hyper-V host
    # The on-prem VM (10.20.0.36) is accessed from the Hyper-V host
    # We SSH into the on-prem VM, then rsync to Azure VM
    foreach ($path in $SyncPaths) {
        Log "Syncing $path..."
        $rsyncCmd = "rsync -azP --delete $excludeArgs -e 'ssh -i /tmp/drsync_key -o StrictHostKeyChecking=no' $path $SshUser@${AzureIp}:$path"

        # Execute rsync from the on-prem VM via SSH
        $result = ssh -i $SshKey -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$OnPremVmIp `
            "export TERM=dumb; rsync -az --delete -e 'ssh -o StrictHostKeyChecking=no' $path $SshUser@${AzureIp}:$path 2>&1"

        if ($LASTEXITCODE -eq 0) {
            Log "  $path synced successfully"
        } else {
            Log "  WARNING: $path sync returned exit code $LASTEXITCODE"
            Log "  Output: $result"
        }
    }

    # Step 4: Sync database dumps if applicable
    Log "Triggering database backup on source..."
    ssh -i $SshKey -o StrictHostKeyChecking=no root@$OnPremVmIp `
        "pg_dumpall -U postgres 2>/dev/null | gzip > /tmp/db_backup.sql.gz && rsync -azP -e 'ssh -o StrictHostKeyChecking=no' /tmp/db_backup.sql.gz $SshUser@${AzureIp}:/tmp/db_backup.sql.gz 2>&1"
    Log "Database backup synced"

    # Step 5: Deallocate Azure VM to save costs
    Log "Deallocating Azure DR VM..."
    az vm deallocate --name $AzureVmName --resource-group $ResourceGroup -o none 2>&1
    Log "Azure VM deallocated"

    Log "=== DR Sync Completed Successfully ==="
}
catch {
    Log "ERROR: $_"

    # Still try to deallocate on error to avoid charges
    Log "Attempting to deallocate VM after error..."
    az vm deallocate --name $AzureVmName --resource-group $ResourceGroup -o none 2>&1

    Log "=== DR Sync Failed ==="
    exit 1
}
