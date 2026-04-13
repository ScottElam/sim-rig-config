# Invoke-Performance.ps1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies power plan selection and system performance tweaks for sim-racing and streaming.
.DESCRIPTION
    Logs every run to .\logs\YYYY-MM-DD_HH-mm-ss_Mode.log
    Backups written to .\backups\backup-YYYY-MM-DD.json (Apply overwrites same-day backup)
    Revert uses the most recent backup in .\backups\
.PARAMETER Mode
    Check  - Report current state vs target. No changes made.
    Apply  - Apply all tweaks and save dated backup.
    Revert - Restore previous state from most recent backup.
.PARAMETER PowerPlan
    Performance - Sets High Performance power plan (default; recommended for 9850X3D).
    Eco         - Sets Balanced power plan.
.EXAMPLE
    .\Invoke-Performance.ps1 -Mode Check
    .\Invoke-Performance.ps1 -Mode Apply -PowerPlan Performance
    .\Invoke-Performance.ps1 -Mode Apply -PowerPlan Eco
    .\Invoke-Performance.ps1 -Mode Revert
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Check', 'Apply', 'Revert')]
    [string]$Mode,

    [ValidateSet('Performance', 'Eco')]
    [string]$PowerPlan = 'Performance'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Logging and backup paths
# ---------------------------------------------------------------------------

$LogDir    = Join-Path $PSScriptRoot 'logs'
$BackupDir = Join-Path $PSScriptRoot 'backups'

$LogFile    = Join-Path $LogDir    "$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')_$Mode.log"
$BackupFile = Join-Path $BackupDir "backup-$(Get-Date -Format 'yyyy-MM-dd').json"

if (-not (Test-Path $LogDir))    { New-Item -ItemType Directory -Path $LogDir    | Out-Null }
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }

# ---------------------------------------------------------------------------
# Known power plan GUIDs
# ---------------------------------------------------------------------------

$PlanGuids = @{
    Balanced        = '381b4222-f694-41f0-9685-ff5bb260df2e'
    HighPerformance = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
}

$DesiredPlanGuid       = if ($PowerPlan -eq 'Performance') { $PlanGuids.HighPerformance } else { $PlanGuids.Balanced }
$DesiredMonitorTimeout = if ($PowerPlan -eq 'Performance') { 0 } else { 15 }

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

function Write-Log {
    param([string]$Level, [string]$Message, [System.ConsoleColor]$Color)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $consoleLine = "  [$Level]".PadRight(12) + $Message
    $logLine     = "[$timestamp] [$Level]".PadRight(32) + $Message
    Write-Host $consoleLine -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $logLine -Encoding UTF8
}

function Write-Ok   { param([string]$msg) Write-Log -Level 'OK'     -Message $msg -Color Green }
function Write-Warn { param([string]$msg) Write-Log -Level 'CHANGE' -Message $msg -Color Yellow }
function Write-Info { param([string]$msg) Write-Log -Level 'INFO'   -Message $msg -Color Cyan }
function Write-Err  { param([string]$msg) Write-Log -Level 'ERROR'  -Message $msg -Color Red }
function Write-Skip { param([string]$msg) Write-Log -Level 'SKIP'   -Message $msg -Color DarkGray }

function Write-Section {
    param([string]$Title)
    $line = "`n-- $Title --"
    Write-Host $line -ForegroundColor White
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Write-Header {
    param([string]$Title)
    $header = @(
        '',
        '=== {0} ===' -f $Title,
        'Script  : {0}' -f $PSCommandPath,
        'User    : {0}\{1}' -f $env:USERDOMAIN, $env:USERNAME,
        'Machine : {0}' -f $env:COMPUTERNAME,
        'Started : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
        ''
    )
    foreach ($line in $header) {
        Write-Host $line -ForegroundColor White
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# Registry tweaks
# ---------------------------------------------------------------------------

$RegistryTweaks = @(
    # Visual effects
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting';   Value = 2;   Type = 'DWord';  Label = 'Visual effects -- Adjust for best performance' },
    @{ Path = 'HKCU:\Control Panel\Desktop';                                            Name = 'AnimateWindows';    Value = 0;   Type = 'DWord';  Label = 'Animate windows -- disabled' },
    @{ Path = 'HKCU:\Control Panel\Desktop';                                            Name = 'MenuShowDelay';     Value = '0'; Type = 'String'; Label = 'Menu show delay -- 0ms' },
    @{ Path = 'HKCU:\Control Panel\Desktop\WindowMetrics';                              Name = 'MinAnimate';        Value = '0'; Type = 'String'; Label = 'Minimise/maximise animations -- disabled' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';     Name = 'TaskbarAnimations'; Value = 0;   Type = 'DWord';  Label = 'Taskbar animations -- disabled' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';     Name = 'ListviewAlphaSelect'; Value = 0; Type = 'DWord';  Label = 'Listview alpha selection -- disabled' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';     Name = 'ListviewShadow';    Value = 0;   Type = 'DWord';  Label = 'Icon shadows on desktop -- disabled' },
    # GameDVR
    @{ Path = 'HKCU:\System\GameConfigStore';                                           Name = 'GameDVR_Enabled';   Value = 0;   Type = 'DWord';  Label = 'GameDVR -- disabled' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR';                     Name = 'AllowGameDVR';      Value = 0;   Type = 'DWord';  Label = 'GameDVR policy -- disabled' },
    # HAGS
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers';                Name = 'HwSchMode';         Value = 2;   Type = 'DWord';  Label = 'Hardware-Accelerated GPU Scheduling (HAGS) -- enabled' },
    # Startup delay
    @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize';    Name = 'StartupDelayInMSec'; Value = 0;  Type = 'DWord';  Label = 'Startup delay -- 0ms' },
    # Processor scheduling
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl';                Name = 'Win32PrioritySeparation'; Value = 38; Type = 'DWord'; Label = 'Processor scheduling -- optimised for foreground programs' }
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try {
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    }
    catch {
        return $null
    }
}

function Set-RegPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
}

function Get-ActivePlanGuid {
    $output = & powercfg /getactivescheme 2>$null
    if ($output -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
        return $Matches[1]
    }
    return $null
}

function Get-PlanName {
    param([string]$Guid)
    switch ($Guid) {
        $PlanGuids.Balanced        { return 'Balanced' }
        $PlanGuids.HighPerformance { return 'High Performance' }
        default                    { return "Unknown ($Guid)" }
    }
}

function Get-HibernationState {
    return (Test-Path "$env:SystemDrive\hiberfil.sys")
}

function Get-LatestBackup {
    $latest = Get-ChildItem -Path $BackupDir -Filter 'backup-*.json' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    return $latest
}

# ---------------------------------------------------------------------------
# CHECK
# ---------------------------------------------------------------------------

function Invoke-Check {
    Write-Header -Title "Performance -- Check (target plan: $PowerPlan)"
    $driftFound = $false

    Write-Section 'Power Plan'
    $activePlan  = Get-ActivePlanGuid
    $activeName  = Get-PlanName -Guid $activePlan
    $desiredName = Get-PlanName -Guid $DesiredPlanGuid
    if ($activePlan -eq $DesiredPlanGuid) {
        Write-Ok "Active plan: $activeName"
    }
    else {
        Write-Warn "Active plan: $activeName -- desired: $desiredName"
        $driftFound = $true
    }

    Write-Section 'Hibernation'
    $hibEnabled = Get-HibernationState
    if ($PowerPlan -eq 'Performance') {
        if (-not $hibEnabled) {
            Write-Ok "Hibernation is disabled"
        }
        else {
            Write-Warn "Hibernation is enabled -- should be disabled in Performance mode"
            $driftFound = $true
        }
    }
    else {
        Write-Info "Eco mode -- hibernation state not checked (currently: $(if ($hibEnabled) {'enabled'} else {'disabled'}))"
    }

    Write-Section 'Registry Tweaks'
    foreach ($tweak in $RegistryTweaks) {
        $current = Get-RegValue -Path $tweak.Path -Name $tweak.Name
        if ($null -ne $current -and "$current" -eq "$($tweak.Value)") {
            Write-Ok "$($tweak.Label)"
        }
        else {
            $display = if ($null -eq $current) { '(not set)' } else { $current }
            Write-Warn "$($tweak.Label) -- current: $display, desired: $($tweak.Value)"
            $driftFound = $true
        }
    }

    Write-Info "HAGS change requires a reboot and supported driver to take effect"
    Write-Info "Log saved to $LogFile"

    if ($driftFound) {
        Add-Content -Path $LogFile -Value "`nRESULT: DRIFT DETECTED" -Encoding UTF8
        Write-Host "`nDrift detected. Run with -Mode Apply to remediate.`n" -ForegroundColor Yellow
        exit 1
    }
    else {
        Add-Content -Path $LogFile -Value "`nRESULT: PASS" -Encoding UTF8
        Write-Host "`nAll performance settings are in target state.`n" -ForegroundColor Green
        exit 0
    }
}

# ---------------------------------------------------------------------------
# APPLY
# ---------------------------------------------------------------------------

function Invoke-Apply {
    Write-Header -Title "Performance -- Apply (plan: $PowerPlan)"

    $backupEntries  = [System.Collections.Generic.List[object]]::new()
    $activePlanBefore = Get-ActivePlanGuid
    $hibBefore        = Get-HibernationState

    Write-Section 'Power Plan'
    $currentPlanName = Get-PlanName -Guid $activePlanBefore
    $desiredName     = Get-PlanName -Guid $DesiredPlanGuid

    if ($PowerPlan -eq 'Performance') {
        $existingPlans = & powercfg /list 2>$null
        if ($existingPlans -notmatch $PlanGuids.HighPerformance) {
            Write-Info "High Performance plan not visible -- making it available..."
            & powercfg /duplicatescheme $PlanGuids.HighPerformance | Out-Null
        }
    }

    if ($activePlanBefore -eq $DesiredPlanGuid) {
        Write-Skip "Power plan is already $desiredName"
    }
    else {
        & powercfg /setactive $DesiredPlanGuid 2>$null
        Write-Ok "Power plan set to $desiredName (was $currentPlanName)"
    }

    Write-Section 'Monitor Timeout'
    & powercfg /change monitor-timeout-ac $DesiredMonitorTimeout 2>$null
    $timeoutLabel = if ($DesiredMonitorTimeout -eq 0) { 'never' } else { "$($DesiredMonitorTimeout) minutes" }
    Write-Ok "AC monitor timeout set to $timeoutLabel"

    Write-Section 'Hibernation'
    if ($PowerPlan -eq 'Performance') {
        if ($hibBefore) {
            & powercfg /h off 2>$null
            Write-Ok "Hibernation disabled (freed ~16 GB hiberfil.sys)"
        }
        else {
            Write-Skip "Hibernation already disabled"
        }
    }
    else {
        Write-Skip "Eco mode -- hibernation state not modified"
    }

    Write-Section 'Registry Tweaks'
    foreach ($tweak in $RegistryTweaks) {
        $current = Get-RegValue -Path $tweak.Path -Name $tweak.Name

        $backupEntries.Add([PSCustomObject]@{
            Path          = $tweak.Path
            Name          = $tweak.Name
            OriginalValue = $current
            OriginalType  = $tweak.Type
        })

        if ($null -ne $current -and "$current" -eq "$($tweak.Value)") {
            Write-Skip "$($tweak.Label) -- already set"
            continue
        }

        try {
            Set-RegPath -Path $tweak.Path
            Set-ItemProperty -Path $tweak.Path -Name $tweak.Name -Value $tweak.Value -Type $tweak.Type -Force -ErrorAction Stop
            $prev = if ($null -eq $current) { '(not set)' } else { $current }
            Write-Ok "$($tweak.Label) -- applied (was $prev)"
        }
        catch {
            Write-Err "Failed: $($tweak.Label) -- $_"
        }
    }

    $backup = [PSCustomObject]@{
        Timestamp         = (Get-Date -Format 'o')
        PowerPlanApplied  = $PowerPlan
        PreviousPlanGuid  = $activePlanBefore
        HibernationBefore = $hibBefore
        Tweaks            = $backupEntries
    }
    $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupFile -Encoding UTF8

    Write-Info "Backup saved to $BackupFile"
    Write-Info "Log saved to $LogFile"
    Add-Content -Path $LogFile -Value "`nRESULT: APPLIED" -Encoding UTF8
    Write-Host "`nApply complete. HAGS and visual effect changes require a reboot.`n" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# REVERT
# ---------------------------------------------------------------------------

function Invoke-Revert {
    Write-Header -Title 'Performance -- Revert'

    $latestBackup = Get-LatestBackup
    if (-not $latestBackup) {
        Write-Err "No backup files found in $BackupDir. Run -Mode Apply first."
        Add-Content -Path $LogFile -Value "`nRESULT: FAILED -- no backup found" -Encoding UTF8
        exit 1
    }

    Write-Info "Using backup: $($latestBackup.Name)"
    $backup = Get-Content $latestBackup.FullName -Raw | ConvertFrom-Json

    Write-Section 'Power Plan'
    if ($backup.PreviousPlanGuid) {
        & powercfg /setactive $backup.PreviousPlanGuid 2>$null
        Write-Ok "Power plan restored to $(Get-PlanName -Guid $backup.PreviousPlanGuid)"
    }

    Write-Section 'Hibernation'
    if ($backup.HibernationBefore -eq $true) {
        Write-Info "Hibernation was enabled before Apply. Re-enable manually if desired:"
        Write-Info "    powercfg /h on"
    }
    else {
        Write-Skip "Hibernation was already disabled before Apply -- no change needed"
    }

    Write-Section 'Registry Tweaks'
    foreach ($entry in $backup.Tweaks) {
        try {
            if ($null -eq $entry.OriginalValue) {
                Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
                Write-Ok "Removed $($entry.Name) from $($entry.Path)"
            }
            else {
                Set-RegPath -Path $entry.Path
                Set-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.OriginalValue -Type $entry.OriginalType -Force -ErrorAction Stop
                Write-Ok "Restored $($entry.Name) to $($entry.OriginalValue)"
            }
        }
        catch {
            Write-Err "Failed to revert $($entry.Path)\$($entry.Name): $_"
        }
    }

    Write-Info "Log saved to $LogFile"
    Add-Content -Path $LogFile -Value "`nRESULT: REVERTED" -Encoding UTF8
    Write-Host "`nRevert complete. A reboot may be needed for visual effect and HAGS changes.`n" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

switch ($Mode) {
    'Check'  { Invoke-Check }
    'Apply'  { Invoke-Apply }
    'Revert' { Invoke-Revert }
}
