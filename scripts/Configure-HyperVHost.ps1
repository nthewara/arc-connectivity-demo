# Configure-HyperVHost.ps1
# Bootstrap script for the Hyper-V host VM
# Runs via Custom Script Extension on first boot
# 
# What it does:
#   1. Initialize and format the data disk
#   2. Install Hyper-V role
#   3. Create internal vSwitch + NAT for nested VM internet
#   4. Copy provisioning scripts to C:\ArcLab
#   5. Schedule Deploy-NestedVMs.ps1 to run after reboot

param(
    [string]$LabPath = "C:\ArcLab",
    [string]$VHDPath = "V:\VHDs",
    [string]$SwitchName = "ArcLabSwitch",
    [string]$NATName = "ArcLabNAT",
    [string]$NATSubnet = "192.168.100.0/24",
    [string]$NATGateway = "192.168.100.1"
)

$ErrorActionPreference = "Stop"
Start-Transcript -Path "$LabPath\bootstrap.log" -Append

Write-Host "=== Arc Connectivity Demo — Hyper-V Host Bootstrap ===" -ForegroundColor Cyan

# ── 1. Create lab directory ──────────────────────────────────────────
New-Item -ItemType Directory -Path $LabPath -Force | Out-Null
New-Item -ItemType Directory -Path "$LabPath\scripts" -Force | Out-Null

# ── 2. Initialize data disk (Lun 0 → drive V:) ─────────────────────
Write-Host "[1/5] Initializing data disk..."
$disk = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' -and $_.Size -gt 200GB } | Select-Object -First 1
if ($disk) {
    $disk | Initialize-Disk -PartitionStyle GPT -PassThru |
        New-Partition -DriveLetter V -UseMaximumSize |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel "VHDs" -Confirm:$false
    Write-Host "  Data disk initialized as V:\"
} else {
    Write-Host "  Data disk already initialized or not found"
}
New-Item -ItemType Directory -Path $VHDPath -Force | Out-Null

# ── 3. Install Hyper-V ──────────────────────────────────────────────
Write-Host "[2/5] Installing Hyper-V role..."
$hyperv = Get-WindowsFeature -Name Hyper-V
if (-not $hyperv.Installed) {
    Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart:$false
    Write-Host "  Hyper-V installed (reboot required)"
} else {
    Write-Host "  Hyper-V already installed"
}

# ── 4. Copy scripts to lab directory ────────────────────────────────
Write-Host "[3/5] Copying provisioning scripts..."
$scriptSource = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptSource) { $scriptSource = "." }
$scripts = @(
    "Deploy-NestedVMs.ps1",
    "Install-ArcAgent.ps1",
    "Install-ArcAgent-Linux.sh",
    "Install-ArcSQL.ps1",
    "Install-ArcK8s.sh"
)
foreach ($s in $scripts) {
    $src = Join-Path $scriptSource $s
    if (Test-Path $src) {
        Copy-Item $src "$LabPath\scripts\" -Force
        Write-Host "  Copied $s"
    }
}

# ── 5. Schedule nested VM deployment after reboot ───────────────────
Write-Host "[4/5] Scheduling nested VM deployment..."
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File $LabPath\scripts\Deploy-NestedVMs.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay (New-TimeSpan -Seconds 60)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "ArcLab-DeployVMs" `
    -Action $action -Trigger $trigger -Principal $principal `
    -Description "Deploy nested VMs for Arc demo" -Force | Out-Null
Write-Host "  Scheduled task registered"

# ── 6. Reboot to complete Hyper-V installation ──────────────────────
Write-Host "[5/5] Rebooting to complete Hyper-V installation..."
Stop-Transcript
Restart-Computer -Force
