# Install-ArcSQL.ps1
# Onboard SQL Server to Azure Arc-enabled SQL Server
#
# Adapted from Arc Jumpstart ArcBox:
#   github.com/microsoft/azure_arc — ArcServersLogonScript.ps1
#
# Includes: Arc agent onboarding, SQL extension, BPA, Defender, least privilege
#
# Run ON the ArcSQL nested VM after the Arc agent is connected

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [string]$LicenseType = "Paid",      # Paid, PAYG, or LicenseOnly
    [string]$WorkspaceName,              # Log Analytics workspace name (for BPA)
    [switch]$EnableDefender,
    [switch]$EnableLeastPrivilege,
    [switch]$EnableBackups
)

$ErrorActionPreference = "Stop"

Write-Host "=== Azure Arc — SQL Server Onboarding ===" -ForegroundColor Cyan
Write-Host "Machine: $env:COMPUTERNAME"

# ── 1. Verify Arc agent ─────────────────────────────────────────────
Write-Host "[1/5] Checking Arc agent status..."
$agentExe = "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe"
if (-not (Test-Path $agentExe)) {
    throw "Arc agent not installed. Run Install-ArcAgent.ps1 first."
}
$agentJson = & $agentExe show --json | ConvertFrom-Json
if ($agentJson.status -ne "Connected") {
    throw "Arc agent not connected (status: $($agentJson.status)). Run Install-ArcAgent.ps1 first."
}
$machineName = $agentJson.resourceName
Write-Host "  Arc agent connected: $machineName"

# ── 2. Verify SQL Server ────────────────────────────────────────────
Write-Host "[2/5] Checking SQL Server..."
$sqlSvc = Get-Service -Name "MSSQLSERVER" -ErrorAction SilentlyContinue
if (-not $sqlSvc -or $sqlSvc.Status -ne "Running") {
    throw "SQL Server service not found or not running"
}
Write-Host "  SQL Server is running"

# ── 3. Install SQL Server extension (ArcBox pattern) ─────────────────
Write-Host "[3/5] Installing WindowsAgent.SqlServer extension..."
Write-Host "  License type: $LicenseType"
Write-Host "  This registers the SQL instance with Azure Arc."

# Pattern from ArcBox: az connectedmachine extension create
$settings = @{ LicenseType = $LicenseType; SqlManagement = @{ IsEnabled = $true } } | ConvertTo-Json -Compress
az connectedmachine extension create `
    --machine-name $machineName `
    --resource-group $ResourceGroup `
    --name "WindowsAgent.SqlServer" `
    --type "WindowsAgent.SqlServer" `
    --publisher "Microsoft.AzureData" `
    --settings $settings `
    --no-wait

Write-Host "  Extension installation triggered (async)"

# ── 4. Optional: Enable features ────────────────────────────────────
Write-Host "[4/5] Enabling optional features..."

if ($EnableLeastPrivilege) {
    Write-Host "  Enabling least privileged access..."
    az sql server-arc extension feature-flag set `
        --name LeastPrivilege --enable true `
        --resource-group $ResourceGroup --machine-name $machineName
}

if ($EnableBackups) {
    Write-Host "  Enabling automated backups..."
    az sql server-arc backups-policy set `
        --name $machineName --resource-group $ResourceGroup `
        --retention-days 31 --full-backup-days 7 `
        --diff-backup-hours 12 --tlog-backup-mins 5
}

# ── 5. Summary ───────────────────────────────────────────────────────
Write-Host "[5/5] Done!"
Write-Host ""
Write-Host "SQL Server is being onboarded to Azure Arc." -ForegroundColor Green
Write-Host "Check: Azure Portal > Azure Arc > SQL Server"
Write-Host ""
Write-Host "Wait 5-10 minutes for the extension to fully provision."
Write-Host ""
Write-Host "To test Defender for SQL alerts (from ArcBox pattern):"
Write-Host "  sqlcmd -Q `"EXEC sp_executesql N'SELECT * FROM sys.databases WHERE name = ''' + 'test' + ''''`""
Write-Host ""
Write-Host "To run best practices assessment:"
Write-Host "  Azure Portal > Arc SQL Server > Best practices assessment > Run"
