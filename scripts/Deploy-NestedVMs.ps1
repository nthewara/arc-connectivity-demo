# Deploy-NestedVMs.ps1
# Runs after reboot via scheduled task — downloads pre-built VHDs from
# Arc Jumpstart's public storage and creates nested VMs.
#
# VHD source: https://jumpstartprodsg.blob.core.windows.net/arcbox/prod/
# This uses the same pre-sysprepped images that ArcBox IT Pro uses:
#   - ArcBox-Win2K22.vhdx  (Windows Server 2022 Datacenter)
#   - ArcBox-Win2K25.vhdx  (Windows Server 2025 Datacenter)
#   - ArcBox-Ubuntu-01.vhdx (Ubuntu 22.04 LTS)
#   - ArcBox-SQL-DEV.vhdx   (Windows Server 2022 + SQL Server 2022 Developer)
#
# Reference: github.com/microsoft/azure_arc — ArcServersLogonScript.ps1

param(
    [string]$LabPath     = "C:\ArcLab",
    [string]$VMDir       = "F:\Virtual Machines",
    [string]$SwitchName  = "ArcLabSwitch",
    [string]$Prefix      = "Arc"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Start-Transcript -Path "$LabPath\Logs\Deploy-NestedVMs.log" -Append

Write-Host "=== Arc Connectivity Demo — Deploy Nested VMs ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"

# ── VHD source (same as Arc Jumpstart ArcBox) ───────────────────────
$vhdSourceBase = "https://jumpstartprodsg.blob.core.windows.net/arcbox/prod"

$vmSpecs = @(
    @{
        Name    = "${Prefix}-Win2K25"
        VHD     = "ArcBox-Win2K25.vhdx"
        RAM     = 4GB
        CPU     = 2
        OS      = "Windows"
        Purpose = "Arc-enabled server (Windows Server 2025)"
    }
    @{
        Name    = "${Prefix}-Win2K22"
        VHD     = "ArcBox-Win2K22.vhdx"
        RAM     = 4GB
        CPU     = 2
        OS      = "Windows"
        Purpose = "Arc-enabled server (Windows Server 2022)"
    }
    @{
        Name    = "${Prefix}-Ubuntu"
        VHD     = "ArcBox-Ubuntu-01.vhdx"
        RAM     = 4GB
        CPU     = 2
        OS      = "Linux"
        Purpose = "Arc-enabled server (Ubuntu 22.04)"
    }
    @{
        Name    = "${Prefix}-SQL"
        VHD     = "ArcBox-SQL-DEV.vhdx"
        RAM     = 8GB
        CPU     = 2
        OS      = "Windows"
        Purpose = "Arc-enabled SQL Server (SQL 2022 Developer)"
    }
    @{
        Name    = "${Prefix}-K3s"
        VHD     = "ArcBox-Ubuntu-01.vhdx"
        RAM     = 8GB
        CPU     = 2
        OS      = "Linux"
        Purpose = "Arc-enabled Kubernetes (K3s on Ubuntu)"
    }
)

# ── 1. Download VHDs using azcopy ────────────────────────────────────
# Pattern from ArcBox: azcopy cp with --include-pattern for selective download
Write-Host "[1/4] Downloading VHDs from Arc Jumpstart storage..."
Write-Host "  Source: $vhdSourceBase"
Write-Host "  This can take 10-15 minutes depending on bandwidth..."

New-Item -ItemType Directory -Path $VMDir -Force | Out-Null

# Build unique VHD list (Ubuntu image is shared by two VMs)
$uniqueVHDs = $vmSpecs | Select-Object -ExpandProperty VHD -Unique

foreach ($vhd in $uniqueVHDs) {
    $destPath = Join-Path $VMDir $vhd
    if (Test-Path $destPath) {
        Write-Host "  $vhd already downloaded — skipping"
        continue
    }
    Write-Host "  Downloading $vhd..."
    $srcUrl = "$vhdSourceBase/$vhd"
    # azcopy supports anonymous access to public blobs
    & azcopy cp $srcUrl $destPath --check-length=false --log-level=ERROR
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: azcopy failed for $vhd — trying Invoke-WebRequest fallback..."
        Invoke-WebRequest -Uri $srcUrl -OutFile $destPath -UseBasicParsing
    }
    Write-Host "  Downloaded: $vhd ($('{0:N1}' -f ((Get-Item $destPath).Length / 1GB)) GB)"
}

# ── 2. Create VMs ───────────────────────────────────────────────────
Write-Host "[2/4] Creating nested VMs..."

# Nested VM credentials (same as ArcBox defaults)
$nestedWindowsUser = "Administrator"
$nestedWindowsPass = "ArcDemo123!!"
$nestedLinuxUser   = "jumpstart"
$nestedLinuxPass   = "JS123!!"

foreach ($vm in $vmSpecs) {
    $vmName = $vm.Name

    $existing = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  $vmName already exists — skipping"
        continue
    }

    # Each VM gets its own copy of the VHD (so they can diverge)
    $srcVHD  = Join-Path $VMDir $vm.VHD
    $destVHD = Join-Path $VMDir "$vmName.vhdx"

    if (-not (Test-Path $destVHD)) {
        Write-Host "  Copying VHD for $vmName..."
        Copy-Item $srcVHD $destVHD -Force
    }

    # Create Gen2 VM
    New-VM -Name $vmName `
        -MemoryStartupBytes $vm.RAM `
        -Generation 2 `
        -VHDPath $destVHD `
        -SwitchName $SwitchName | Out-Null

    # Configure resources
    Set-VM -Name $vmName `
        -ProcessorCount $vm.CPU `
        -DynamicMemory `
        -MemoryMinimumBytes 1GB `
        -MemoryMaximumBytes $vm.RAM `
        -AutomaticStartAction Start `
        -AutomaticStopAction ShutDown

    # Enable nested virtualisation extensions
    Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true

    # Disable secure boot for Linux VMs
    if ($vm.OS -eq "Linux") {
        Set-VMFirmware -VMName $vmName -EnableSecureBoot Off
    }

    Start-VM -Name $vmName
    Write-Host "  Created and started: $vmName ($($vm.Purpose))"
}

# ── 3. Wait for VMs to get DHCP addresses ───────────────────────────
Write-Host "[3/4] Waiting for VMs to obtain IP addresses..."
Start-Sleep -Seconds 30
foreach ($vm in $vmSpecs) {
    $vmName = $vm.Name
    $ip = Get-VM -Name $vmName | Select-Object -ExpandProperty NetworkAdapters |
        Select-Object -ExpandProperty IPAddresses | Select-Object -First 1
    Write-Host "  $vmName → $ip"
}

# ── 4. Save config + clean up ───────────────────────────────────────
Write-Host "[4/4] Saving configuration..."

$vmSpecs | ConvertTo-Json -Depth 3 | Out-File "$LabPath\vm-config.json" -Encoding UTF8

# Create desktop status script
$desktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
@"
# Arc Lab — Quick Status
Write-Host '=== Nested VM Status ===' -ForegroundColor Cyan
Get-VM | Format-Table Name, State, CPUUsage, @{N='Memory(MB)';E={[math]::Round(`$_.MemoryAssigned/1MB)}}, Uptime -AutoSize
Write-Host ''
Write-Host '=== IP Addresses ===' -ForegroundColor Cyan
Get-VM | ForEach-Object {
    `$ip = `$_ | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Select-Object -First 1
    Write-Host "  `$(`$_.Name) → `$ip"
}
Write-Host ''
Write-Host '=== Default Credentials ===' -ForegroundColor Yellow
Write-Host '  Windows: Administrator / ArcDemo123!!'
Write-Host '  Linux:   jumpstart / JS123!!'
Write-Host ''
Write-Host 'Onboarding scripts: C:\ArcLab\scripts\' -ForegroundColor Green
pause
"@ | Out-File "$desktopPath\Arc-Lab-Status.ps1" -Encoding UTF8

# Remove the scheduled task (one-time run)
Unregister-ScheduledTask -TaskName "ArcLab-DeployVMs" -Confirm:$false -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== All 5 nested VMs deployed ===" -ForegroundColor Green
Write-Host "Next steps:"
Write-Host "  1. Check IPs: run Arc-Lab-Status.ps1 on the desktop"
Write-Host "  2. Windows VMs: RDP or Hyper-V console (Administrator / ArcDemo123!!)"
Write-Host "  3. Linux VMs: SSH from host (jumpstart / JS123!!)"
Write-Host "  4. Onboard to Arc: scripts in C:\ArcLab\scripts\"
Write-Host ""

Stop-Transcript
