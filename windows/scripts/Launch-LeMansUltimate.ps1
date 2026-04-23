# =============================================================================
# Launch-LeMansUltimate.ps1
# Launches Le Mans Ultimate via Steam with High process priority and
# a configurable CPU affinity mask.
# Run as Administrator for best results.
# =============================================================================

#Requires -Version 5.1

# ---------------------------------------------------------------------------
# CONFIGURATION — edit these values to suit your system
# ---------------------------------------------------------------------------

# Steam App ID for Le Mans Ultimate
$SteamAppId = "1537430"

# Path to Steam executable (update if Steam is installed elsewhere)
$SteamExe = "C:\Program Files (x86)\Steam\steam.exe"

# Le Mans Ultimate process name (without .exe)
$ProcessName = "LeMansUltimate"

# Process priority:  Idle | BelowNormal | Normal | AboveNormal | High | RealTime
#   !! Avoid RealTime — it can freeze your whole system !!
$TargetPriority = [System.Diagnostics.ProcessPriorityClass]::High

# CPU Affinity bitmask
#   Each bit = one logical CPU core (bit 0 = Core 0, bit 1 = Core 1, etc.)
#   Examples (hex):
#     0x0003  = Cores 0-1   (2 cores)
#     0x00FF  = Cores 0-7   (8 cores)
#     0xFFFF  = Cores 0-15  (16 cores)
#     0xFFFFFFFF = All 32 logical cores
#
#   Tip: exclude Core 0 to leave it free for Windows/background tasks:
#     0xFFFE  = Cores 1-15  (skip Core 0 on a 16-core system)
#
# Set to $null to leave affinity unchanged (OS default = all cores)
$AffinityMask = 0xFFFE   # Cores 1-15  — adjust to your CPU core count

# How long (seconds) to wait for the game process to appear after Steam launch
$WaitTimeoutSec = 90

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

function Write-Header {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  Le Mans Ultimate — Priority Launcher" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AffinityDescription {
    param([long]$Mask, [int]$TotalCores)
    $cores = @()
    for ($i = 0; $i -lt $TotalCores; $i++) {
        if ($Mask -band [long](1 -shl $i)) { $cores += $i }
    }
    return "Cores: $($cores -join ', ')  [mask: 0x$('{0:X}' -f $Mask)]"
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

Write-Header

# Admin check
if (-not (Test-Admin)) {
    Write-Host "[WARN] Not running as Administrator." -ForegroundColor Yellow
    Write-Host "       Priority/affinity changes may be silently ignored." -ForegroundColor Yellow
    Write-Host "       Right-click the script and choose 'Run as Administrator'." -ForegroundColor Yellow
    Write-Host ""
}

# Validate Steam
if (-not (Test-Path $SteamExe)) {
    Write-Host "[ERROR] Steam not found at: $SteamExe" -ForegroundColor Red
    Write-Host "        Update the `$SteamExe variable at the top of this script." -ForegroundColor Red
    exit 1
}

# System CPU info
$logicalCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
Write-Host "[INFO] Logical CPU cores detected : $logicalCores" -ForegroundColor Gray

if ($null -ne $AffinityMask) {
    $maxMask = [long]([Math]::Pow(2, $logicalCores) - 1)
    if (($AffinityMask -band $maxMask) -eq 0) {
        Write-Host "[ERROR] AffinityMask 0x$('{0:X}' -f $AffinityMask) maps to no valid cores on this CPU." -ForegroundColor Red
        exit 1
    }
    $AffinityMask = $AffinityMask -band $maxMask   # clamp to available cores
    Write-Host "[INFO] Target CPU affinity        : $(Get-AffinityDescription $AffinityMask $logicalCores)" -ForegroundColor Gray
} else {
    Write-Host "[INFO] Target CPU affinity        : OS default (all cores)" -ForegroundColor Gray
}

Write-Host "[INFO] Target process priority    : $TargetPriority" -ForegroundColor Gray
Write-Host ""

# Check if game is already running
$existing = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[INFO] Le Mans Ultimate is already running (PID $($existing.Id))." -ForegroundColor Yellow
    Write-Host "       Applying settings to the existing process..." -ForegroundColor Yellow
} else {
    # Launch via Steam
    Write-Host "[INFO] Launching Le Mans Ultimate via Steam..." -ForegroundColor Green
    Start-Process -FilePath $SteamExe -ArgumentList "-applaunch $SteamAppId"

    # Wait for the game process to appear
    Write-Host "[INFO] Waiting up to $WaitTimeoutSec seconds for process '$ProcessName'..." -ForegroundColor Gray
    $elapsed = 0
    $interval = 2
    $gameProcess = $null

    while ($elapsed -lt $WaitTimeoutSec) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $gameProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($gameProcess) { break }
        Write-Host "  ... still waiting ($elapsed s)" -ForegroundColor DarkGray
    }

    if (-not $gameProcess) {
        Write-Host "[ERROR] Process '$ProcessName' did not appear within $WaitTimeoutSec seconds." -ForegroundColor Red
        Write-Host "        Check that the App ID ($SteamAppId) and process name are correct." -ForegroundColor Red
        exit 1
    }
}

# Re-fetch in case $existing was used
$gameProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
if (-not $gameProcess) {
    Write-Host "[ERROR] Could not find process '$ProcessName'." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[INFO] Found process: $ProcessName  (PID: $($gameProcess.Id))" -ForegroundColor Green

# --- Set Priority ---
try {
    $gameProcess.PriorityClass = $TargetPriority
    Write-Host "[OK]   Priority set to : $($gameProcess.PriorityClass)" -ForegroundColor Green
} catch {
    Write-Host "[WARN] Could not set priority: $_" -ForegroundColor Yellow
}

# --- Set CPU Affinity ---
if ($null -ne $AffinityMask) {
    try {
        $gameProcess.ProcessorAffinity = [IntPtr]$AffinityMask
        Write-Host "[OK]   CPU affinity set: $(Get-AffinityDescription $AffinityMask $logicalCores)" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Could not set CPU affinity: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] CPU affinity left at OS default." -ForegroundColor Gray
}

Write-Host ""
Write-Host "[DONE] Le Mans Ultimate is running with your custom settings." -ForegroundColor Cyan
Write-Host "       Close this window at any time — settings persist until the game exits." -ForegroundColor Gray
Write-Host ""
