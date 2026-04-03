#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Audits installed software and disables NVIDIA telemetry scheduled tasks.
.DESCRIPTION
    Checks for NVIDIA telemetry scheduled tasks and disables them.
    Reports on NVIDIA components that require manual removal via the NVIDIA App.
    Audits browser proliferation and reports recommendations.
    Supports Check and Apply only — no Revert mode.
.PARAMETER Mode
    Check — Report current state. No changes made.
    Apply — Disable NVIDIA telemetry tasks and report what was done.
.EXAMPLE
    .\Invoke-InstalledPrograms.ps1 -Mode Check
    .\Invoke-InstalledPrograms.ps1 -Mode Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Check', 'Apply')]
    [string]$Mode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Colour helpers ──────────────────────────────────────────────────────────

function Write-Ok      { param($msg) Write-Host "  [OK]      $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "  [CHANGE]  $msg" -ForegroundColor Yellow }
function Write-Info    { param($msg) Write-Host "  [INFO]    $msg" -ForegroundColor Cyan }
function Write-Action  { param($msg) Write-Host "  [ACTION]  $msg" -ForegroundColor Magenta }
function Write-Err     { param($msg) Write-Host "  [ERROR]   $msg" -ForegroundColor Red }
function Write-Skip    { param($msg) Write-Host "  [SKIP]    $msg" -ForegroundColor DarkGray }

# ── NVIDIA telemetry task patterns ─────────────────────────────────────────

$NvidiaTelemetryTaskPatterns = @(
    '\NVIDIA Corporation\NvTmMon*'
    '\NVIDIA Corporation\NvTmRep*'
    '\NVIDIA Corporation\NvProfileUpdaterOnLogon*'
    '\NVIDIA Corporation\NvDriverUpdateCheckDaily*'
    '\NvTmRepOnLogon*'
)

# ── Chromium-based browsers ────────────────────────────────────────────────

$ChromiumBrowsers = @(
    @{ Name = 'Brave';          Match = 'Brave' }
    @{ Name = 'Google Chrome';  Match = 'Google Chrome' }
    @{ Name = 'Microsoft Edge'; Match = 'Microsoft Edge' }
)

# NVIDIA components that need manual action
$NvidiaManualComponents = @(
    @{ Name = 'NVIDIA ShadowPlay*';       Label = 'NVIDIA ShadowPlay';       Action = 'Disable via NVIDIA App → Settings → In-Game Overlay' }
    @{ Name = 'NVIDIA Telemetry Client*'; Label = 'NVIDIA Telemetry Client'; Action = 'Remove via NVIDIA App Custom Install — deselect Telemetry' }
    @{ Name = 'NVIDIA Virtual Audio*';    Label = 'NVIDIA Virtual Audio';    Action = 'Remove via NVIDIA App Custom Install — deselect HD Audio Driver' }
)

# ── Helper: get all tasks matching a wildcard path ──────────────────────────

function Get-ScheduledTasksByPattern {
    param([string]$Pattern)

    # Split folder from task name pattern
    $lastSlash = $Pattern.LastIndexOf('\')
    $folder    = $Pattern.Substring(0, $lastSlash)
    $taskPat   = $Pattern.Substring($lastSlash + 1)

    Get-ScheduledTask -TaskPath "$folder\" -TaskName $taskPat -ErrorAction SilentlyContinue
}

# ── Helper: check installed program by display name ─────────────────────────

function Get-InstalledProgram {
    param([string]$NamePattern)

    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $paths) {
        $result = Get-ItemProperty $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $NamePattern } |
            Select-Object -First 1
        if ($result) { return $result }
    }
    return $null
}

# ── CHECK ───────────────────────────────────────────────────────────────────

function Invoke-Check {
    Write-Host "`n=== Installed Programs — Check ===" -ForegroundColor White
    $driftFound = $false

    # NVIDIA telemetry scheduled tasks
    Write-Host "`n-- NVIDIA Telemetry Scheduled Tasks --" -ForegroundColor White
    foreach ($pattern in $NvidiaTelemetryTaskPatterns) {
        $tasks = Get-ScheduledTasksByPattern -Pattern $pattern
        if ($tasks) {
            foreach ($task in $tasks) {
                if ($task.State -ne 'Disabled') {
                    Write-Warn "$($task.TaskPath)$($task.TaskName) is $($task.State) — should be Disabled"
                    $driftFound = $true
                } else {
                    Write-Ok "$($task.TaskPath)$($task.TaskName) is Disabled"
                }
            }
        } else {
            Write-Skip "No tasks found matching: $pattern"
        }
    }

    # NVIDIA components requiring manual action
    Write-Host "`n-- NVIDIA Components (manual action required) --" -ForegroundColor White
    foreach ($item in $NvidiaManualComponents) {
        $prog = Get-InstalledProgram -NamePattern $item.Name
        if ($prog) {
            Write-Warn "$($item.Label) is installed"
            Write-Info "    Recommended action: $($item.Action)"
        } else {
            Write-Ok "$($item.Label) not found / already removed"
        }
    }

    # Browser audit
    Write-Host "`n-- Browser Audit --" -ForegroundColor White
    $installedChromium = @()
    foreach ($browser in $ChromiumBrowsers) {
        $prog = Get-InstalledProgram -NamePattern "*$($browser.Match)*"
        if ($prog) {
            Write-Info "$($browser.Name) is installed (each installs its own updater service)"
            $installedChromium += $browser.Name
        }
    }
    $firefoxProg = Get-InstalledProgram -NamePattern "*Firefox*"
    if ($firefoxProg) { Write-Info "Mozilla Firefox is installed" }

    if ($installedChromium.Count -ge 3) {
        Write-Warn "$($installedChromium.Count) Chromium-based browsers installed ($($installedChromium -join ', '))"
        Write-Info "    Recommendation: consolidate to 2 browsers (e.g. Brave + Firefox) to reduce updater services"
        $driftFound = $true
    } else {
        Write-Ok "Browser count is within acceptable range"
    }

    if ($driftFound) {
        Write-Host "`nAction items found. Run with -Mode Apply to remediate automated items.`n" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "`nAll automated checks passed.`n" -ForegroundColor Green
        exit 0
    }
}

# ── APPLY ───────────────────────────────────────────────────────────────────

function Invoke-Apply {
    Write-Host "`n=== Installed Programs — Apply ===" -ForegroundColor White

    # Disable NVIDIA telemetry scheduled tasks
    Write-Host "`n-- NVIDIA Telemetry Scheduled Tasks --" -ForegroundColor White
    foreach ($pattern in $NvidiaTelemetryTaskPatterns) {
        $tasks = Get-ScheduledTasksByPattern -Pattern $pattern
        if ($tasks) {
            foreach ($task in $tasks) {
                if ($task.State -ne 'Disabled') {
                    try {
                        Disable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop | Out-Null
                        Write-Ok "Disabled: $($task.TaskPath)$($task.TaskName)"
                    } catch {
                        Write-Err "Failed to disable $($task.TaskName): $_"
                    }
                } else {
                    Write-Skip "$($task.TaskName) — already Disabled"
                }
            }
        } else {
            Write-Skip "No tasks found matching: $pattern"
        }
    }

    # NVIDIA manual components
    Write-Host "`n-- NVIDIA Components (manual action required) --" -ForegroundColor White
    foreach ($item in $NvidiaManualComponents) {
        $prog = Get-InstalledProgram -NamePattern $item.Name
        if ($prog) {
            Write-Action "$($item.Label) detected — manual step required:"
            Write-Host "         $($item.Action)" -ForegroundColor Magenta
        } else {
            Write-Ok "$($item.Label) not found"
        }
    }

    # Browser report
    Write-Host "`n-- Browser Audit --" -ForegroundColor White
    $installedChromium = @()
    foreach ($browser in $ChromiumBrowsers) {
        $prog = Get-InstalledProgram -NamePattern "*$($browser.Match)*"
        if ($prog) { $installedChromium += $browser.Name }
    }
    if ($installedChromium.Count -ge 3) {
        Write-Action "Consider removing one or more Chromium-based browsers: $($installedChromium -join ', ')"
        Write-Host "         Each browser installs background updater services (brave, edgeupdate, GoogleUpdater*)." -ForegroundColor Magenta
        Write-Host "         The Services script sets these updaters to Manual start regardless." -ForegroundColor Magenta
    } else {
        Write-Ok "Browser count is within acceptable range"
    }

    Write-Host "`nApply complete. NVIDIA scheduled telemetry tasks disabled.`n" -ForegroundColor Green
    Write-Host "Revert is not available for this script. Re-enable tasks via Task Scheduler if needed.`n" -ForegroundColor DarkGray
}

# ── Entry point ─────────────────────────────────────────────────────────────

switch ($Mode) {
    'Check' { Invoke-Check }
    'Apply' { Invoke-Apply }
}
