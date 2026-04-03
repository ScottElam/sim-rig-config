#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies power plan selection and system performance tweaks for sim-racing and streaming.
.DESCRIPTION
    Manages power plan (High Performance or Balanced), visual effects, GameDVR, HAGS,
    display timeouts, startup delay, and hibernation state.
    Supports Check, Apply, and Revert. PowerPlan only applies in Apply mode.
.PARAMETER Mode
    Check  — Report current state vs target. No changes made.
    Apply  — Apply all tweaks and save backup.json.
    Revert — Restore previous state from backup.json.
.PARAMETER PowerPlan
    Performance — Sets High Performance power plan (default; recommended for 9850X3D).
    Eco         — Sets Balanced power plan.
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

$BackupFile = Join-Path $PSScriptRoot 'backup.json'

# ── Known power plan GUIDs ──────────────────────────────────────────────────

$PlanGuids = @{
    Balanced        = '381b4222-f694-41f0-9685-ff5bb260df2e'
    HighPerformance = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
}

$DesiredPlanGuid = if ($PowerPlan -eq 'Performance') { $PlanGuids.HighPerformance } else { $PlanGuids.Balanced }
$DesiredMonitorTimeout = if ($PowerPlan -eq 'Performance') { 0 } else { 15 }

# ── Colour helpers ──────────────────────────────────────────────────────────

function Write-Ok   { param($msg) Write-Host "  [OK]      $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [CHANGE]  $msg" -ForegroundColor Yellow }
function Write-Info { param($msg) Write-Host "  [INFO]    $msg" -ForegroundColor Cyan }
function Write-Err  { param($msg) Write-Host "  [ERROR]   $msg" -ForegroundColor Red }
function Write-Skip { param($msg) Write-Host "  [SKIP]    $msg" -ForegroundColor DarkGray }

# ── Registry tweaks ─────────────────────────────────────────────────────────

$RegistryTweaks = @(

    # Visual Effects — best performance
    @{
        Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        Name  = 'VisualFXSetting'
        Value = 2
        Type  = 'DWord'
        Label = 'Visual effects — Adjust for best performance'
    }
    @{
        Path  = 'HKCU:\Control Panel\Desktop'
        Name  = 'AnimateWindows'
        Value = 0
        Type  = 'DWord'
        Label = 'Animate windows — disabled'
    }
    @{
        Path  = 'HKCU:\Control Panel\Desktop'
        Name  = 'MenuShowDelay'
        Value = 0
        Type  = 'String'
        Label = 'Menu show delay — 0ms'
    }
    @{
        Path  = 'HKCU:\Control Panel\Desktop\WindowMetrics'
        Name  = 'MinAnimate'
        Value = '0'
        Type  = 'String'
        Label = 'Minimise/maximise animations — disabled'
    }
    @{
        Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Name  = 'TaskbarAnimations'
        Value = 0
        Type  = 'DWord'
        Label = 'Taskbar animations — disabled'
    }
    @{
        Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Name  = 'ListviewAlphaSelect'
        Value = 0
        Type  = 'DWord'
        Label = 'Listview alpha selection — disabled'
    }
    @{
        Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Name  = 'ListviewShadow'
        Value = 0
        Type  = 'DWord'
        Label = 'Icon shadows on desktop — disabled'
    }

    # GameDVR
    @{
        Path  = 'HKCU:\System\GameConfigStore'
        Name  = 'GameDVR_Enabled'
        Value = 0
        Type  = 'DWord'
        Label = 'GameDVR — disabled'
    }
    @{
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
        Name  = 'AllowGameDVR'
        Value = 0
        Type  = 'DWord'
        Label = 'GameDVR policy — disabled'
    }

    # Hardware-Accelerated GPU Scheduling
    @{
        Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        Name  = 'HwSchMode'
        Value = 2
        Type  = 'DWord'
        Label = 'Hardware-Accelerated GPU Scheduling (HAGS) — enabled'
    }

    # Startup delay
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize'
        Name  = 'StartupDelayInMSec'
        Value = 0
        Type  = 'DWord'
        Label = 'Startup delay — 0ms'
    }

    # Processor scheduling — Programs (foreground)
    @{
        Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
        Name  = 'Win32PrioritySeparation'
        Value = 38   # 0x26 — short variable intervals, prioritise foreground
        Type  = 'DWord'
        Label = 'Processor scheduling — optimised for foreground programs'
    }
)

# ── Helper: read registry value ─────────────────────────────────────────────

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try {
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        return $null
    }
}

function Ensure-RegPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
}

# ── Helper: get active power plan ──────────────────────────────────────────

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

# ── Helper: hibernation state ───────────────────────────────────────────────

function Get-HibernationState {
    $hiberFile = "$env:SystemDrive\hiberfil.sys"
    return (Test-Path $hiberFile)
}

# ── Helper: monitor timeout (AC) ────────────────────────────────────────────

function Get-MonitorTimeout {
    $output = & powercfg /query $DesiredPlanGuid 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 2>$null
    if ($output -match 'Current AC Power Setting Index:\s+0x([0-9a-f]+)') {
        return [Convert]::ToInt32($Matches[1], 16) / 60  # convert seconds to minutes
    }
    return $null
}

# ── CHECK ───────────────────────────────────────────────────────────────────

function Invoke-Check {
    Write-Host "`n=== Performance — Check (target plan: $PowerPlan) ===" -ForegroundColor White
    $driftFound = $false

    # Power plan
    Write-Host "`n-- Power Plan --" -ForegroundColor White
    $activePlan = Get-ActivePlanGuid
    $activeName = Get-PlanName -Guid $activePlan
    $desiredName = Get-PlanName -Guid $DesiredPlanGuid
    if ($activePlan -eq $DesiredPlanGuid) {
        Write-Ok "Active plan: $activeName"
    } else {
        Write-Warn "Active plan: $activeName — desired: $desiredName"
        $driftFound = $true
    }

    # Hibernation
    Write-Host "`n-- Hibernation --" -ForegroundColor White
    $hibEnabled = Get-HibernationState
    if ($PowerPlan -eq 'Performance') {
        if (-not $hibEnabled) {
            Write-Ok "Hibernation is disabled"
        } else {
            Write-Warn "Hibernation is enabled — should be disabled in Performance mode"
            $driftFound = $true
        }
    } else {
        Write-Info "Eco mode — hibernation state left as-is (currently: $(if ($hibEnabled) {'enabled'} else {'disabled'}))"
    }

    # Registry tweaks
    Write-Host "`n-- Registry Tweaks --" -ForegroundColor White
    foreach ($tweak in $RegistryTweaks) {
        $current = Get-RegValue -Path $tweak.Path -Name $tweak.Name
        # Compare as string to handle mixed types
        if ($null -ne $current -and "$current" -eq "$($tweak.Value)") {
            Write-Ok "$($tweak.Label)"
        } else {
            $display = if ($null -eq $current) { '(not set)' } else { $current }
            Write-Warn "$($tweak.Label) — current: $display, desired: $($tweak.Value)"
            $driftFound = $true
        }
    }

    # HAGS note
    Write-Host "`n-- HAGS Note --" -ForegroundColor White
    Write-Info "HAGS registry change takes effect after a reboot and requires a supported driver."
    Write-Info "Verify in: NVIDIA App → Settings → Gaming → Hardware-Accelerated GPU Scheduling"

    if ($driftFound) {
        Write-Host "`nDrift detected. Run with -Mode Apply to remediate.`n" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "`nAll performance settings are in target state.`n" -ForegroundColor Green
        exit 0
    }
}

# ── APPLY ───────────────────────────────────────────────────────────────────

function Invoke-Apply {
    Write-Host "`n=== Performance — Apply (plan: $PowerPlan) ===" -ForegroundColor White

    $backupEntries = @()
    $activePlanBefore = Get-ActivePlanGuid
    $hibBefore = Get-HibernationState

    # Power plan
    Write-Host "`n-- Power Plan --" -ForegroundColor White
    $currentPlanName = Get-PlanName -Guid $activePlanBefore
    $desiredName = Get-PlanName -Guid $DesiredPlanGuid

    # Ensure High Performance plan exists (it can be hidden on some editions)
    if ($PowerPlan -eq 'Performance') {
        $existingPlans = & powercfg /list 2>$null
        if ($existingPlans -notmatch $PlanGuids.HighPerformance) {
            Write-Info "High Performance plan not visible — making it available..."
            & powercfg /duplicatescheme $PlanGuids.HighPerformance | Out-Null
        }
    }

    if ($activePlanBefore -eq $DesiredPlanGuid) {
        Write-Skip "Power plan is already $desiredName"
    } else {
        & powercfg /setactive $DesiredPlanGuid 2>$null
        Write-Ok "Power plan set to $desiredName (was $currentPlanName)"
    }

    # Monitor timeout
    Write-Host "`n-- Monitor Timeout --" -ForegroundColor White
    $timeoutSeconds = $DesiredMonitorTimeout * 60
    & powercfg /change monitor-timeout-ac $DesiredMonitorTimeout 2>$null
    $timeoutLabel = if ($DesiredMonitorTimeout -eq 0) { 'never' } else { "$($DesiredMonitorTimeout) minutes" }
    Write-Ok "AC monitor timeout set to $timeoutLabel"

    # Hibernation
    Write-Host "`n-- Hibernation --" -ForegroundColor White
    if ($PowerPlan -eq 'Performance') {
        if ($hibBefore) {
            & powercfg /h off 2>$null
            Write-Ok "Hibernation disabled (freed ~16 GB hiberfil.sys)"
        } else {
            Write-Skip "Hibernation already disabled"
        }
    } else {
        Write-Skip "Eco mode — hibernation state not modified"
    }

    # Registry tweaks
    Write-Host "`n-- Registry Tweaks --" -ForegroundColor White
    foreach ($tweak in $RegistryTweaks) {
        $current = Get-RegValue -Path $tweak.Path -Name $tweak.Name

        $backupEntries += [PSCustomObject]@{
            Path            = $tweak.Path
            Name            = $tweak.Name
            OriginalValue   = $current
            OriginalType    = $tweak.Type
        }

        if ($null -ne $current -and "$current" -eq "$($tweak.Value)") {
            Write-Skip "$($tweak.Label) — already set"
            continue
        }

        try {
            Ensure-RegPath -Path $tweak.Path
            Set-ItemProperty -Path $tweak.Path -Name $tweak.Name -Value $tweak.Value -Type $tweak.Type -Force -ErrorAction Stop
            $prev = if ($null -eq $current) { '(not set)' } else { $current }
            Write-Ok "$($tweak.Label) — applied (was $prev)"
        } catch {
            Write-Err "Failed: $($tweak.Label) — $_"
        }
    }

    # Save backup
    $backup = @{
        Timestamp         = (Get-Date -Format 'o')
        PowerPlanApplied  = $PowerPlan
        PreviousPlanGuid  = $activePlanBefore
        HibernationBefore = $hibBefore
        Tweaks            = $backupEntries
    }
    $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupFile -Encoding UTF8

    Write-Host "`nBackup saved to $BackupFile" -ForegroundColor Cyan
    Write-Host "Apply complete. HAGS change and visual effects require a reboot to fully take effect.`n" -ForegroundColor Green
}

# ── REVERT ──────────────────────────────────────────────────────────────────

function Invoke-Revert {
    Write-Host "`n=== Performance — Revert ===" -ForegroundColor White

    if (-not (Test-Path $BackupFile)) {
        Write-Err "No backup found at $BackupFile. Run -Mode Apply first."
        exit 1
    }

    $backup = Get-Content $BackupFile -Raw | ConvertFrom-Json
    Write-Info "Restoring from backup taken at $($backup.Timestamp)"

    # Restore power plan
    Write-Host "`n-- Power Plan --" -ForegroundColor White
    if ($backup.PreviousPlanGuid) {
        & powercfg /setactive $backup.PreviousPlanGuid 2>$null
        Write-Ok "Power plan restored to $(Get-PlanName -Guid $backup.PreviousPlanGuid)"
    }

    # Hibernation — note only, not auto-restored
    Write-Host "`n-- Hibernation --" -ForegroundColor White
    if ($backup.HibernationBefore -eq $true) {
        Write-Info "Hibernation was enabled before Apply. Re-enable manually if desired:"
        Write-Host "         powercfg /h on" -ForegroundColor DarkGray
    } else {
        Write-Skip "Hibernation was already disabled before Apply — no change needed"
    }

    # Registry tweaks
    Write-Host "`n-- Registry Tweaks --" -ForegroundColor White
    foreach ($entry in $backup.Tweaks) {
        try {
            if ($null -eq $entry.OriginalValue) {
                Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
                Write-Ok "Removed $($entry.Name) from $($entry.Path)"
            } else {
                Ensure-RegPath -Path $entry.Path
                Set-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.OriginalValue -Type $entry.OriginalType -Force -ErrorAction Stop
                Write-Ok "Restored $($entry.Name) to $($entry.OriginalValue)"
            }
        } catch {
            Write-Err "Failed to revert $($entry.Path)\$($entry.Name): $_"
        }
    }

    Write-Host "`nRevert complete. A reboot may be needed for visual effect and HAGS changes.`n" -ForegroundColor Green
}

# ── Entry point ─────────────────────────────────────────────────────────────

switch ($Mode) {
    'Check'  { Invoke-Check }
    'Apply'  { Invoke-Apply }
    'Revert' { Invoke-Revert }
}
