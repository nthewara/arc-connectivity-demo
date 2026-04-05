# Configure-HyperVHost.ps1
# Bootstrap script for the Hyper-V host VM — runs via Custom Script Extension
#
# Adapted from Arc Jumpstart ArcBox patterns:
#   https://github.com/microsoft/azure_arc/tree/main/azure_jumpstart_arcbox
#
# What it does:
#   1. Initialize and format the data disk (drive F:)
#   2. Install Hyper-V + DHCP roles
#   3. Create internal vSwitch + NAT + DHCP scope for nested VM internet
#   4. Install azcopy, Azure CLI, and other prerequisites
#   5. Copy provisioning scripts to C:\ArcLab
#   6. Schedule Deploy-NestedVMs.ps1 to run after reboot

param(
    [string]$LabPath       = "C:\ArcLab",
    [string]$VMDir         = "F:\Virtual Machines",
    [string]$SwitchName    = "ArcLabSwitch",
    [string]$NATName       = "ArcLabNAT",
    [string]$NATSubnet     = "10.10.1.0/24",
    [string]$NATGateway    = "10.10.1.1",
    [string]$DHCPStart     = "10.10.1.100",
    [string]$DHCPEnd       = "10.10.1.200",
    [string]$DHCPMask      = "255.255.255.0"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

New-Item -ItemType Directory -Path $LabPath -Force | Out-Null
New-Item -ItemType Directory -Path "$LabPath\Logs" -Force | Out-Null

Start-Transcript -Path "$LabPath\Logs\Configure-HyperVHost.log" -Append

Write-Host "=== Arc Connectivity Demo — Hyper-V Host Bootstrap ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"

# ── 1. Format data disk ─────────────────────────────────────────────
# Pattern from ArcBox Bootstrap.ps1 — raw disk → drive F:
Write-Host "[1/7] Initializing data disk..."
$disk = (Get-Disk | Where-Object PartitionStyle -eq 'raw')[0]
if ($disk) {
    $disk | Initialize-Disk -PartitionStyle MBR -PassThru |
        New-Partition -UseMaximumSize -DriveLetter F |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel "VMsDisk" -Confirm:$false -Force
    Write-Host "  Data disk formatted as F:\"
} else {
    Write-Host "  Data disk already formatted or not found"
}
New-Item -ItemType Directory -Path $VMDir -Force | Out-Null

# ── 2. Install required roles ───────────────────────────────────────
Write-Host "[2/7] Installing Hyper-V + DHCP roles..."
$features = @('Hyper-V', 'DHCP', 'RSAT-Hyper-V-Tools', 'RSAT-DHCP')
$rebootNeeded = $false
foreach ($f in $features) {
    $feat = Get-WindowsFeature -Name $f
    if (-not $feat.Installed) {
        $result = Install-WindowsFeature -Name $f -IncludeManagementTools
        Write-Host "  Installed: $f"
        if ($result.RestartNeeded -eq 'Yes') {
            $rebootNeeded = $true
        }
    } else {
        Write-Host "  Already installed: $f"
    }
}

if ($rebootNeeded) {
    Write-Host "  Windows reports reboot required for role installation"
}

# ── 3. Install Azure CLI + azcopy ───────────────────────────────────
# Needed for downloading VHDs from Jumpstart storage + Arc onboarding
Write-Host "[3/7] Installing Azure CLI and azcopy..."
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Invoke-WebRequest -Uri "https://aka.ms/installazurecliwindowsx64" -OutFile "$env:TEMP\AzureCLI.msi"
    Start-Process msiexec.exe -ArgumentList "/i `"$env:TEMP\AzureCLI.msi`" /qn /norestart" -Wait
    $env:PATH += ";C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin"
    Write-Host "  Azure CLI installed"
} else {
    Write-Host "  Azure CLI already installed"
}

if (-not (Get-Command azcopy -ErrorAction SilentlyContinue)) {
    Invoke-WebRequest -Uri "https://aka.ms/downloadazcopy-v10-windows" -OutFile "$env:TEMP\azcopy.zip"
    Expand-Archive -Path "$env:TEMP\azcopy.zip" -DestinationPath "$env:TEMP\azcopy" -Force
    $azcopyExe = Get-ChildItem "$env:TEMP\azcopy" -Recurse -Filter "azcopy.exe" | Select-Object -First 1
    Copy-Item $azcopyExe.FullName "C:\Windows\System32\azcopy.exe" -Force
    Write-Host "  azcopy installed"
} else {
    Write-Host "  azcopy already installed"
}

# ── 4. Create internal vSwitch + NAT ────────────────────────────────
# Pattern from ArcBox ArcServersLogonScript.ps1 — DHCP + NAT for nested VMs
Write-Host "[4/7] Configuring networking (vSwitch + DHCP + NAT)..."

$sw = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $sw) {
    New-VMSwitch -Name $SwitchName -SwitchType Internal
    Write-Host "  Created vSwitch: $SwitchName"
}

$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
$existingIP = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $NATGateway }
if (-not $existingIP) {
    New-NetIPAddress -IPAddress $NATGateway -PrefixLength 24 -InterfaceIndex $adapter.ifIndex
    Write-Host "  Assigned $NATGateway to vSwitch adapter"
}

$nat = Get-NetNat -Name $NATName -ErrorAction SilentlyContinue
if (-not $nat) {
    New-NetNat -Name $NATName -InternalIPInterfaceAddressPrefix $NATSubnet
    Write-Host "  Created NAT: $NATName ($NATSubnet)"
}

# Configure DHCP scope (from ArcBox pattern)
$dhcpScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
if (-not ($dhcpScope | Where-Object Name -eq 'ArcLab')) {
    Add-DhcpServerv4Scope -Name 'ArcLab' `
        -StartRange $DHCPStart -EndRange $DHCPEnd `
        -SubnetMask $DHCPMask -LeaseDuration 1.00:00:00 -State Active
    Set-DhcpServerv4OptionValue -ComputerName localhost `
        -DnsServer 168.63.129.16 `
        -Router $NATGateway -Force
    Write-Host "  DHCP scope configured ($DHCPStart - $DHCPEnd)"
}

# ── 5. Copy scripts to lab directory ────────────────────────────────
Write-Host "[5/7] Copying provisioning scripts..."
$scriptDir = "$LabPath\scripts"
New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
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
        Copy-Item $src "$scriptDir\" -Force
        Write-Host "  Copied $s"
    }
}

# ── 6. Create Hyper-V Manager desktop shortcut ──────────────────────
Write-Host "[6/7] Creating desktop shortcuts..."
$hypervLink = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Administrative Tools\Hyper-V Manager.lnk'
if (Test-Path $hypervLink) {
    Copy-Item -Path $hypervLink -Destination 'C:\Users\Public\Desktop\Hyper-V Manager.lnk' -Force
}

# ── 7. Schedule nested VM deployment after reboot ───────────────────
Write-Host "[7/7] Scheduling nested VM deployment..."
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File $scriptDir\Deploy-NestedVMs.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay (New-TimeSpan -Seconds 30)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "ArcLab-DeployVMs" `
    -Action $action -Trigger $trigger -Principal $principal `
    -Description "Deploy nested VMs for Arc connectivity demo" -Force | Out-Null
Write-Host "  Scheduled task registered"

Write-Host ""
Write-Host "Bootstrap complete. Rebooting to finish Hyper-V installation..." -ForegroundColor Green
Stop-Transcript
Restart-Computer -Force
exit 0
