##############################################################################
# DR Failover Script - Starts the Azure DR VM and outputs connection info
# Run this in an emergency when on-prem is down
##############################################################################

$env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;" + $env:PATH
$ResourceGroup = "Kanvantage"
$VmName = "ViseFin-Production"

Write-Host "======================================" -ForegroundColor Red
Write-Host "  DISASTER RECOVERY FAILOVER" -ForegroundColor Red
Write-Host "======================================" -ForegroundColor Red
Write-Host ""

Write-Host "Starting Azure DR VM..." -ForegroundColor Yellow
az vm start --name $VmName --resource-group $ResourceGroup -o none 2>&1

if ($LASTEXITCODE -eq 0) {
    Start-Sleep -Seconds 10
    $ip = az network public-ip show --name ViseFin-PIP --resource-group $ResourceGroup --query ipAddress -o tsv
    $status = az vm get-instance-view --name $VmName --resource-group $ResourceGroup --query "instanceView.statuses[1].displayStatus" -o tsv

    Write-Host ""
    Write-Host "VM Status: $status" -ForegroundColor Green
    Write-Host "Public IP: $ip" -ForegroundColor Green
    Write-Host ""
    Write-Host "Connect via SSH: ssh drsync@$ip" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To update DNS, point your records to: $ip" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To stop DR VM after failback:" -ForegroundColor Yellow
    Write-Host "  az vm deallocate --name $VmName --resource-group $ResourceGroup" -ForegroundColor Yellow
} else {
    Write-Host "FAILED to start VM!" -ForegroundColor Red
    exit 1
}
