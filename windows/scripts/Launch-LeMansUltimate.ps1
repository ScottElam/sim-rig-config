# =============================================================================
# Launch-LeMansUltimate.ps1
#
# Launches Le Mans Ultimate via Steam with:
#   - High Performance power plan (restores previous plan on exit)
#   - High process priority and configurable CPU affinity
#   - Helper apps launched before the game, closed when it exits
#   - Monitoring loop that cleans up when the game exits
#
# Run as Administrator for best results.
# =============================================================================

#Requires -Version 5.1

# ---------------------------------------------------------------------------
# CONFIGURATION - edit these values to suit your system
# ---------------------------------------------------------------------------

# --- Steam / Game ---

$SteamAppId     = "2399420"
$SteamExe       = "D:\Steam\steam.exe"
$ProcessName    = "Le Mans Ultimate"
$WaitTimeoutSec = 90

# --- Process priority and CPU affinity ---

# Priority: Idle | BelowNormal | Normal | AboveNormal | High | RealTime
#   !! Avoid RealTime — it can freeze the whole system !!
$TargetPriority = [System.Diagnostics.ProcessPriorityClass]::High

# CPU Affinity bitmask — each bit = one logical processor (LP 0 = bit 0, etc.)
#   The 9850X3D has 8 cores / 16 logical processors (SMT enabled).
#
#   NOTE: The 9850X3D is a SINGLE-CCD chip. There is no second CCD to offload
#   OBS or helpers to. This mask only reserves LP 0 for the OS/background tasks.
#   AMD CPPC Preferred Cores handles the scheduling from there.
#
#   0xFFFE = LPs 1-15  (reserves LP 0 for OS — recommended for 9850X3D)
#   0xFFFF = LPs 0-15  (all 16 logical processors)
#   $null  = OS default — no affinity change applied
$AffinityMask = 0xFFFE

# --- Power plan ---

# High Performance plan GUID (built-in Windows — do not change)
$HighPerfPlanGuid  = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

# Restore the previous power plan when the game exits
$RestorePowerPlanOnExit = $true

# --- Helper applications ---
# Enable  : $true to launch this app, $false to skip
# Path    : Full path to the executable
# Process : Process name (without .exe) used to check if already running

$HelperApps = @(
    @{
        Name    = 'CrewChief'
        Enable  = $true
        Path    = 'C:\Program Files (x86)\CrewChiefV4\CrewChiefV4.exe'
        Process = 'CrewChiefV4'
    },
    @{
        Name    = 'TinyPedal'
        Enable  = $true
        Path    = 'D:\TinyPedal\TinyPedal.exe'
        Process = 'TinyPedal'
    },
    @{
        Name    = 'Coach Dave Academy'
        Enable  = $true
        Path    = 'C:\Program Files\Coach Dave Academy\CoachDaveAcademy.exe'
        Process = 'CoachDaveAcademy'
    },
    @{
        Name    = 'OBS'
        Enable  = $false   # Set to $true to include OBS in the launch sequence
        Path    = 'C:\Program Files\obs-studio\bin\64bit\obs64.exe'
        Process = 'obs64'
    }
)

# Close helper apps that THIS script launched when the game exits
# Apps that were already running before the script started are never closed
$CloseHelpersOnExit = $true

# How often (seconds) to poll for the game process after launch
$MonitorPollIntervalSec = 5

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

function Write-Header {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  Le Mans Ultimate - Session Launcher" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-Admin {
    $cu = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($cu)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AffinityDescription {
    param([long]$Mask, [int]$TotalLPs)
    $lps = @()
    for ($i = 0; $i -lt $TotalLPs; $i++) {
        if ($Mask -band [long](1 -shl $i)) { $lps += $i }
    }
    return ("LPs: {0}  [mask: 0x{1:X}]" -f ($lps -join ", "), $Mask)
}

function Get-ActivePowerPlanGuid {
    $output = powercfg /getactivescheme 2>&1
    if ($output -match 'GUID:\s+([\w-]+)') { return $matches[1] }
    return $null
}

function Set-PowerPlan {
    param([string]$Guid, [string]$Label)
    powercfg /setactive $Guid 2>&1 | Out-Null
    Write-Host "[OK]   Power plan set    : $Label" -ForegroundColor Green
}

function Start-HelperApp {
    param($App)
    if (-not $App.Enable) { return $false }

    $alreadyRunning = Get-Process -Name $App.Process -ErrorAction SilentlyContinue
    if ($alreadyRunning) {
        Write-Host "[INFO] $($App.Name) is already running — skipping launch." -ForegroundColor Gray
        return $false   # did not launch it — do not close it on exit
    }

    if (-not (Test-Path $App.Path)) {
        Write-Host "[WARN] $($App.Name) not found at: $($App.Path)" -ForegroundColor Yellow
        return $false
    }

    try {
        Start-Process -FilePath $App.Path
        Write-Host "[OK]   Launched          : $($App.Name)" -ForegroundColor Green
        return $true    # launched by this script — eligible for close on exit
    }
    catch {
        Write-Host "[WARN] Could not launch $($App.Name): $_" -ForegroundColor Yellow
        return $false
    }
}

function Stop-HelperApp {
    param($App)
    $proc = Get-Process -Name $App.Process -ErrorAction SilentlyContinue
    if ($proc) {
        try {
            $proc | Stop-Process -Force
            Write-Host "[OK]   Closed            : $($App.Name)" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Could not close $($App.Name): $_" -ForegroundColor Yellow
        }
    }
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

# --- Power plan ---
$previousPlanGuid = Get-ActivePowerPlanGuid
Write-Host "[INFO] Current power plan : $previousPlanGuid" -ForegroundColor Gray
Set-PowerPlan -Guid $HighPerfPlanGuid -Label "High Performance ($HighPerfPlanGuid)"
Write-Host ""

# --- Helper apps ---
Write-Host "[INFO] Starting helper applications..." -ForegroundColor Cyan
$launchedHelpers = @()
foreach ($app in $HelperApps) {
    $wasLaunched = Start-HelperApp -App $app
    if ($wasLaunched) { $launchedHelpers += $app }
}
Write-Host ""

# --- System CPU info ---
$logicalCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
Write-Host "[INFO] Logical processors detected : $logicalCores" -ForegroundColor Gray

if ($null -ne $AffinityMask) {
    $maxMask = [long]([Math]::Pow(2, $logicalCores) - 1)
    if (($AffinityMask -band $maxMask) -eq 0) {
        Write-Host ("[ERROR] AffinityMask 0x{0:X} maps to no valid LPs on this CPU." -f $AffinityMask) -ForegroundColor Red
        exit 1
    }
    $AffinityMask = $AffinityMask -band $maxMask
    Write-Host "[INFO] Target CPU affinity         : $(Get-AffinityDescription $AffinityMask $logicalCores)" -ForegroundColor Gray
} else {
    Write-Host "[INFO] Target CPU affinity         : OS default (all LPs)" -ForegroundColor Gray
}

Write-Host "[INFO] Target process priority     : $TargetPriority" -ForegroundColor Gray
Write-Host ""

# --- Launch or attach to game ---
$existing = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[INFO] Le Mans Ultimate is already running (PID $($existing.Id))." -ForegroundColor Yellow
    Write-Host "       Applying settings to the existing process..." -ForegroundColor Yellow
} else {
    Write-Host "[INFO] Launching Le Mans Ultimate via Steam..." -ForegroundColor Green
    Start-Process -FilePath $SteamExe -ArgumentList "-applaunch $SteamAppId"

    Write-Host "[INFO] Waiting up to $WaitTimeoutSec seconds for process '$ProcessName'..." -ForegroundColor Gray
    $elapsed     = 0
    $interval    = 2
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

$gameProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
if (-not $gameProcess) {
    Write-Host "[ERROR] Could not find process '$ProcessName'." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[INFO] Found process: $ProcessName  (PID: $($gameProcess.Id))" -ForegroundColor Green

# --- Priority ---
try {
    $gameProcess.PriorityClass = $TargetPriority
    Write-Host "[OK]   Priority set to   : $($gameProcess.PriorityClass)" -ForegroundColor Green
} catch {
    Write-Host "[WARN] Could not set priority: $_" -ForegroundColor Yellow
}

# --- Affinity ---
if ($null -ne $AffinityMask) {
    try {
        $gameProcess.ProcessorAffinity = [IntPtr]$AffinityMask
        Write-Host "[OK]   CPU affinity set  : $(Get-AffinityDescription $AffinityMask $logicalCores)" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Could not set CPU affinity: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] CPU affinity left at OS default." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# MONITOR — stay alive until LMU exits, then clean up
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "[INFO] Monitoring session. This window will clean up when LMU exits." -ForegroundColor Cyan
Write-Host "       Close this window early to skip cleanup." -ForegroundColor Gray
Write-Host ""

while ($true) {
    Start-Sleep -Seconds $MonitorPollIntervalSec
    $stillRunning = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if (-not $stillRunning) { break }
}

Write-Host ""
Write-Host "[INFO] Le Mans Ultimate has exited. Running cleanup..." -ForegroundColor Yellow
Write-Host ""

# --- Restore power plan ---
if ($RestorePowerPlanOnExit -and $previousPlanGuid) {
    Set-PowerPlan -Guid $previousPlanGuid -Label "Previous plan ($previousPlanGuid)"
} else {
    Write-Host "[INFO] Power plan left at High Performance." -ForegroundColor Gray
}

# --- Close helpers that this script launched ---
if ($CloseHelpersOnExit -and $launchedHelpers.Count -gt 0) {
    Write-Host "[INFO] Closing helper applications..." -ForegroundColor Cyan
    foreach ($app in $launchedHelpers) {
        Stop-HelperApp -App $app
    }
} elseif ($launchedHelpers.Count -eq 0) {
    Write-Host "[INFO] No helper apps to close (none were launched by this script)." -ForegroundColor Gray
}

Write-Host ""
Write-Host "[DONE] Session ended cleanly." -ForegroundColor Cyan
Write-Host ""
