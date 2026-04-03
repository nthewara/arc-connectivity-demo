# Install-ArcSQL.ps1
# Onboard SQL Server to Azure Arc-enabled SQL Server
#
# Run this script ON the ArcSQL nested VM (after SQL Server is installed)
# Prerequisites: SQL Server 2022 installed, internet access, Arc agent already connected

param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$Location,

    [string]$ServicePrincipalId,
    [string]$ServicePrincipalSecret,
    [string]$LicenseType = "PAYG"  # PAYG, Paid, or LicenseOnly
)

$ErrorActionPreference = "Stop"

Write-Host "=== Azure Arc — SQL Server Onboarding ===" -ForegroundColor Cyan
Write-Host "Machine: $env:COMPUTERNAME"

# ── 1. Verify Arc agent is connected ────────────────────────────────
Write-Host "[1/3] Checking Arc agent status..."
$agentStatus = & "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" show --json | ConvertFrom-Json
if ($agentStatus.status -ne "Connected") {
    Write-Host "ERROR: Arc agent is not connected. Run Install-ArcAgent.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Host "  Arc agent connected as: $($agentStatus.resourceName)"

# ── 2. Verify SQL Server is running ─────────────────────────────────
Write-Host "[2/3] Checking SQL Server..."
$sqlService = Get-Service -Name "MSSQLSERVER" -ErrorAction SilentlyContinue
if (-not $sqlService -or $sqlService.Status -ne "Running") {
    Write-Host "ERROR: SQL Server service not found or not running." -ForegroundColor Red
    exit 1
}
Write-Host "  SQL Server is running"

# ── 3. Install Arc SQL Server extension ──────────────────────────────
Write-Host "[3/3] Installing Arc SQL Server extension..."
Write-Host "  This deploys the SQL Server extension on the Arc-enabled server"
Write-Host "  which registers the SQL instance with Azure Arc."
Write-Host ""
Write-Host "  In the Azure Portal:"
Write-Host "    1. Go to Azure Arc > SQL Server"
Write-Host "    2. Click + Add"
Write-Host "    3. Select the Arc-enabled server ($($agentStatus.resourceName))"
Write-Host "    4. Configure license type: $LicenseType"
Write-Host ""
Write-Host "  Or use Azure CLI:"
Write-Host "    az connectedmachine extension create \"
Write-Host "      --machine-name $($agentStatus.resourceName) \"
Write-Host "      --resource-group $ResourceGroup \"
Write-Host "      --name WindowsAgent.SqlServer \"
Write-Host "      --type WindowsAgent.SqlServer \"
Write-Host "      --publisher Microsoft.AzureData \"
Write-Host "      --settings '{\"LicenseType\":\"$LicenseType\"}'"
Write-Host ""
Write-Host "After extension installation, SQL Server will appear in Azure Arc > SQL Server." -ForegroundColor Green
