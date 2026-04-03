# Install-ArcAgent.ps1
# Onboard a Windows VM to Azure Arc-enabled servers
#
# Adapted from Arc Jumpstart ArcBox:
#   github.com/microsoft/azure_arc — installArcAgent.ps1
#
# Run this script ON each Windows nested VM (ArcWin2025, ArcWin2022, ArcSQL)

param(
    [string]$accessToken,
    [string]$TenantId,
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$AzureLocation,
    [string]$ServicePrincipalId,
    [string]$ServicePrincipalSecret,
    [string]$Tags = "project=arc-connectivity-demo,environment=lab"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "=== Azure Arc — Connected Machine Agent Installation ===" -ForegroundColor Cyan
Write-Host "Machine: $env:COMPUTERNAME"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ── 1. Block Azure IMDS ─────────────────────────────────────────────
# Required for nested VMs: prevent Arc agent from detecting Azure
Write-Host "[1/3] Blocking Azure IMDS endpoint..."
New-NetFirewallRule -DisplayName "Block IMDS" -Direction Outbound `
    -RemoteAddress 169.254.169.254 -Action Block -ErrorAction SilentlyContinue | Out-Null
Write-Host "  IMDS blocked via Windows Firewall"

# ── 2. Download and install the agent (ArcBox pattern) ──────────────
Write-Host "[2/3] Downloading and installing Azure Connected Machine Agent..."
$agentInstaller = "$env:TEMP\AzureConnectedMachineAgent.msi"

if (-not (Test-Path "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe")) {
    Invoke-WebRequest -Uri "https://aka.ms/AzureConnectedMachineAgent" -OutFile $agentInstaller
    $exitCode = (Start-Process msiexec.exe -ArgumentList @(
        "/i", "`"$agentInstaller`"", "/l*v", "$env:TEMP\arc_install.log", "/qn"
    ) -Wait -PassThru).ExitCode
    if ($exitCode -ne 0) {
        $msg = net helpmsg $exitCode
        throw "Installation failed ($exitCode): $msg — see $env:TEMP\arc_install.log"
    }
    Write-Host "  Agent installed"
} else {
    Write-Host "  Agent already installed"
}

# ── 3. Connect to Azure Arc (ArcBox pattern) ────────────────────────
Write-Host "[3/3] Connecting to Azure Arc..."

$connectArgs = @(
    "connect"
    "--resource-group", $ResourceGroup
    "--tenant-id", $TenantId
    "--location", $AzureLocation
    "--subscription-id", $SubscriptionId
    "--tags", $Tags
    "--cloud", "AzureCloud"
    "--correlation-id", "d009f5dd-dba8-4ac7-bac9-b54ef3a6671a"
)

# Prefer access token (from managed identity), then SP, then interactive
if ($accessToken) {
    $connectArgs += "--access-token", $accessToken
    Write-Host "  Using access token authentication"
} elseif ($ServicePrincipalId -and $ServicePrincipalSecret) {
    $connectArgs += "--service-principal-id", $ServicePrincipalId
    $connectArgs += "--service-principal-secret", $ServicePrincipalSecret
    Write-Host "  Using service principal authentication"
} else {
    Write-Host "  Using interactive authentication"
}

& "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" @connectArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "SUCCESS: $env:COMPUTERNAME is now an Azure Arc-enabled server!" -ForegroundColor Green
    Write-Host "View: https://ms.portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/Microsoft.HybridCompute%2Fmachines"
} else {
    Write-Host ""
    Write-Host "FAILED: azcmagent connect exited with code $LASTEXITCODE" -ForegroundColor Red
    Write-Host "Check logs: $env:ProgramData\AzureConnectedMachineAgent\Log"
}
