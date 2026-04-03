# Install-ArcAgent.ps1
# Onboard a Windows VM to Azure Arc-enabled servers
#
# Run this script ON each Windows nested VM (ArcWin2025, ArcWin2022, ArcSQL)
# Prerequisites: Internet access from the nested VM via NAT

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
    [string]$Tags = "project=arc-connectivity-demo,environment=lab"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Azure Arc — Connected Machine Agent Installation ===" -ForegroundColor Cyan
Write-Host "Machine: $env:COMPUTERNAME"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ── 1. Download the Connected Machine Agent ─────────────────────────
Write-Host "[1/3] Downloading Azure Connected Machine Agent..."
$agentInstaller = "$env:TEMP\AzureConnectedMachineAgent.msi"

if (-not (Test-Path $agentInstaller)) {
    Invoke-WebRequest `
        -Uri "https://aka.ms/AzureConnectedMachineAgent" `
        -OutFile $agentInstaller `
        -UseBasicParsing
    Write-Host "  Downloaded to $agentInstaller"
} else {
    Write-Host "  Installer already downloaded"
}

# ── 2. Install the agent ────────────────────────────────────────────
Write-Host "[2/3] Installing agent..."
$installed = Get-Service -Name "himds" -ErrorAction SilentlyContinue
if (-not $installed) {
    Start-Process msiexec.exe -ArgumentList "/i `"$agentInstaller`" /qn /norestart" -Wait -NoNewWindow
    Write-Host "  Agent installed"
} else {
    Write-Host "  Agent already installed"
}

# ── 3. Connect to Azure Arc ─────────────────────────────────────────
Write-Host "[3/3] Connecting to Azure Arc..."
$connectArgs = @(
    "connect"
    "--resource-group", $ResourceGroup
    "--tenant-id", $TenantId
    "--location", $Location
    "--subscription-id", $SubscriptionId
    "--tags", $Tags
)

if ($ServicePrincipalId -and $ServicePrincipalSecret) {
    $connectArgs += "--service-principal-id", $ServicePrincipalId
    $connectArgs += "--service-principal-secret", $ServicePrincipalSecret
    Write-Host "  Using service principal authentication"
} else {
    Write-Host "  Using interactive authentication (browser-based)"
}

& "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" @connectArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "SUCCESS: $env:COMPUTERNAME is now an Azure Arc-enabled server!" -ForegroundColor Green
    Write-Host "Check: Azure Portal > Azure Arc > Servers"
} else {
    Write-Host ""
    Write-Host "FAILED: azcmagent connect exited with code $LASTEXITCODE" -ForegroundColor Red
    Write-Host "Check logs at: $env:ProgramData\AzureConnectedMachineAgent\Log"
}
