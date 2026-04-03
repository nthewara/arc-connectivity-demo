# Deploy-NestedVMs.ps1
# Runs after reboot (scheduled task) to create nested VMs
#
# Creates:
#   - ArcWin2025  (Windows Server 2025, Arc-enabled server)
#   - ArcWin2022  (Windows Server 2022, Arc-enabled server)
#   - ArcUbuntu   (Ubuntu 22.04, Arc-enabled server)
#   - ArcSQL      (Windows Server 2022 + SQL Server 2022)
#   - ArcK3s      (Ubuntu 22.04 + K3s)

param(
    [string]$LabPath = "C:\ArcLab",
    [string]$VHDPath = "V:\VHDs",
    [string]$SwitchName = "ArcLabSwitch",
    [string]$NATName = "ArcLabNAT",
    [string]$NATSubnet = "192.168.100.0/24",
    [string]$NATGateway = "192.168.100.1",
    [int]$NATPrefix = 24
)

$ErrorActionPreference = "Stop"
Start-Transcript -Path "$LabPath\deploy-vms.log" -Append

Write-Host "=== Arc Connectivity Demo — Deploy Nested VMs ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ── 1. Create Internal vSwitch + NAT ────────────────────────────────
Write-Host "[1/6] Configuring networking..."
$sw = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $sw) {
    New-VMSwitch -Name $SwitchName -SwitchType Internal
    Write-Host "  Created vSwitch: $SwitchName"
}

# Set IP on the host vNIC for the internal switch
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
$existingIP = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $NATGateway }
if (-not $existingIP) {
    New-NetIPAddress -IPAddress $NATGateway -PrefixLength $NATPrefix -InterfaceIndex $adapter.ifIndex
    Write-Host "  Assigned $NATGateway to vSwitch adapter"
}

# Create NAT
$nat = Get-NetNat -Name $NATName -ErrorAction SilentlyContinue
if (-not $nat) {
    New-NetNat -Name $NATName -InternalIPInterfaceAddressPrefix $NATSubnet
    Write-Host "  Created NAT: $NATName ($NATSubnet)"
}

# ── 2. Download evaluation ISOs / VHDs ──────────────────────────────
Write-Host "[2/6] Preparing VM images..."
Write-Host "  NOTE: In production, pre-stage VHDs in a storage account and download here."
Write-Host "  For this demo, we create differencing disks from the host's WinSxS or download ISOs."

# Create placeholder VHDs — in a real deployment, these would be sysprepped VHDs
# downloaded from a storage account. The script structure supports that.
$vmSpecs = @(
    @{ Name = "ArcWin2025"; RAM = 4GB; CPU = 2; DiskGB = 40; IP = "192.168.100.10"; OS = "Windows" }
    @{ Name = "ArcWin2022"; RAM = 4GB; CPU = 2; DiskGB = 40; IP = "192.168.100.11"; OS = "Windows" }
    @{ Name = "ArcUbuntu";  RAM = 4GB; CPU = 2; DiskGB = 40; IP = "192.168.100.12"; OS = "Linux" }
    @{ Name = "ArcSQL";     RAM = 8GB; CPU = 2; DiskGB = 60; IP = "192.168.100.13"; OS = "Windows" }
    @{ Name = "ArcK3s";     RAM = 8GB; CPU = 2; DiskGB = 60; IP = "192.168.100.14"; OS = "Linux" }
)

# ── 3. Create VMs ───────────────────────────────────────────────────
Write-Host "[3/6] Creating nested VMs..."
foreach ($vm in $vmSpecs) {
    $vmName = $vm.Name
    $vhdFile = Join-Path $VHDPath "$vmName.vhdx"

    $existingVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if ($existingVM) {
        Write-Host "  $vmName already exists — skipping"
        continue
    }

    # Create VHDX
    if (-not (Test-Path $vhdFile)) {
        New-VHD -Path $vhdFile -SizeBytes ($vm.DiskGB * 1GB) -Dynamic | Out-Null
        Write-Host "  Created VHDX: $vhdFile ($($vm.DiskGB)GB)"
    }

    # Create VM
    New-VM -Name $vmName `
        -MemoryStartupBytes $vm.RAM `
        -Generation 2 `
        -VHDPath $vhdFile `
        -SwitchName $SwitchName | Out-Null

    # Configure VM
    Set-VM -Name $vmName `
        -ProcessorCount $vm.CPU `
        -DynamicMemory `
        -MemoryMinimumBytes 1GB `
        -MemoryMaximumBytes $vm.RAM `
        -AutomaticStartAction Start `
        -AutomaticStopAction ShutDown

    # Enable nested virtualisation on Windows VMs (for flexibility)
    Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true

    # Disable secure boot for Linux VMs
    if ($vm.OS -eq "Linux") {
        Set-VMFirmware -VMName $vmName -EnableSecureBoot Off
    }

    Write-Host "  Created VM: $vmName ($($vm.CPU) vCPU, $($vm.RAM / 1GB)GB, $($vm.IP))"
}

# ── 4. Save VM configuration summary ────────────────────────────────
Write-Host "[4/6] Saving configuration..."
$vmSpecs | ConvertTo-Json -Depth 3 | Out-File "$LabPath\vm-config.json" -Encoding UTF8

# ── 5. Create helper scripts on desktop ─────────────────────────────
Write-Host "[5/6] Creating desktop shortcuts..."
$desktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")

# Quick-status script
@"
# Arc Lab — Quick Status
Write-Host '=== Nested VM Status ===' -ForegroundColor Cyan
Get-VM | Format-Table Name, State, CPUUsage, MemoryAssigned, Uptime -AutoSize
Write-Host ''
Write-Host '=== Arc Onboarding Status ===' -ForegroundColor Cyan
Write-Host 'Check Azure Portal > Azure Arc > Servers for onboarded machines'
Write-Host 'Check Azure Portal > Azure Arc > Kubernetes clusters for K3s'
pause
"@ | Out-File "$desktopPath\Arc-Lab-Status.ps1" -Encoding UTF8

Write-Host "[6/6] Done!"
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Green
Write-Host "Nested VMs created (VHDs need OS installation):"
foreach ($vm in $vmSpecs) {
    Write-Host "  $($vm.Name) — $($vm.IP) ($($vm.OS))"
}
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Install OS on each VM (mount ISO or use pre-built VHDs)"
Write-Host "  2. Configure static IPs (see vm-config.json)"
Write-Host "  3. Run Arc onboarding scripts from C:\ArcLab\scripts\"
Write-Host ""

# Remove the scheduled task (one-time run)
Unregister-ScheduledTask -TaskName "ArcLab-DeployVMs" -Confirm:$false -ErrorAction SilentlyContinue

Stop-Transcript
