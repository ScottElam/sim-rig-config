#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Audits installed software and disables NVIDIA telemetry scheduled tasks.
.DESCRIPTION
    Logs every run to .\logs\YYYY-MM-DD_HH-mm-ss_Mode.log
    No backup file -- uninstall actions are not reversible.
.PARAMETER Mode
    Check - Report current state. No changes made.
    Apply - Disable NVIDIA telemetry tasks and report manual actions required.
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

# ---------------------------------------------------------------------------
# Logging paths
# ---------------------------------------------------------------------------

$LogDir  = Join-Path $PSScriptRoot 'logs'
$LogFile = Join-Path $LogDir "$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')_$Mode.log"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

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

function Write-Ok     { param([string]$msg) Write-Log -Level 'OK'     -Message $msg -Color Green }
function Write-Warn   { param([string]$msg) Write-Log -Level 'CHANGE' -Message $msg -Color Yellow }
function Write-Info   { param([string]$msg) Write-Log -Level 'INFO'   -Message $msg -Color Cyan }
function Write-Action { param([string]$msg) Write-Log -Level 'ACTION' -Message $msg -Color Magenta }
function Write-Err    { param([string]$msg) Write-Log -Level 'ERROR'  -Message $msg -Color Red }
function Write-Skip   { param([string]$msg) Write-Log -Level 'SKIP'   -Message $msg -Color DarkGray }

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
# Target definitions
# ---------------------------------------------------------------------------

$NvidiaTelemetryTaskPatterns = @(
    '\NVIDIA Corporation\NvTmMon*',
    '\NVIDIA Corporation\NvTmRep*',
#    '\NVIDIA Corporation\NvProfileUpdaterOnLogon*',
#    '\NVIDIA Corporation\NvDriverUpdateCheckDaily*',
    '\NvTmRepOnLogon*'
)

$ChromiumBrowsers = @(
    @{ Name = 'Brave';          Match = 'Brave' },
    @{ Name = 'Google Chrome';  Match = 'Google Chrome' },
    @{ Name = 'Microsoft Edge'; Match = 'Microsoft Edge' }
)

$NvidiaManualComponents = @(
    @{ Name = 'NVIDIA ShadowPlay*';       Label = 'NVIDIA ShadowPlay';       Action = 'Disable via NVIDIA App --> Settings --> In-Game Overlay' },
    @{ Name = 'NVIDIA Telemetry Client*'; Label = 'NVIDIA Telemetry Client'; Action = 'Remove via NVIDIA App Custom Install -- deselect Telemetry' },
    @{ Name = 'NVIDIA Virtual Audio*';    Label = 'NVIDIA Virtual Audio';    Action = 'Remove via NVIDIA App Custom Install -- deselect HD Audio Driver' }
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function Get-ScheduledTasksByPattern {
    param([string]$Pattern)
    $lastSlash = $Pattern.LastIndexOf('\')
    $folder    = $Pattern.Substring(0, $lastSlash)
    $taskPat   = $Pattern.Substring($lastSlash + 1)
    Get-ScheduledTask -TaskPath "$folder\" -TaskName $taskPat -ErrorAction SilentlyContinue
}

function Get-InstalledProgram {
    param([string]$NamePattern)
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
	
	foreach ($path in $paths) {
		Set-StrictMode -Off # jse
		$result = Get-ItemProperty $path -ErrorAction SilentlyContinue |
			Where-Object { $_.DisplayName -like $NamePattern } |
			Select-Object -First 1
		Set-StrictMode -Version Latest # Or the specific version used at the top of your file
    
		if ($result) { return $result }
	}
#    foreach ($path in $paths) {
#        $result = Get-ItemProperty $path -ErrorAction SilentlyContinue |
#            Where-Object { $_.DisplayName -like $NamePattern } |
#            Select-Object -First 1
#        if ($result) { return $result }
#    }
    return $null
}

# ---------------------------------------------------------------------------
# CHECK
# ---------------------------------------------------------------------------

function Invoke-Check {
    Write-Header -Title 'Installed Programs -- Check'
    $driftFound = $false

    Write-Section 'NVIDIA Telemetry Scheduled Tasks'
    foreach ($pattern in $NvidiaTelemetryTaskPatterns) {
        $tasks = Get-ScheduledTasksByPattern -Pattern $pattern
        if ($tasks) {
            foreach ($task in $tasks) {
                if ($task.State -ne 'Disabled') {
                    Write-Warn "$($task.TaskPath)$($task.TaskName) is $($task.State) -- should be Disabled"
                    $driftFound = $true
                }
                else {
                    Write-Ok "$($task.TaskPath)$($task.TaskName) is Disabled"
                }
            }
        }
        else {
            Write-Skip "No tasks found matching: $pattern"
        }
    }

    Write-Section 'NVIDIA Components (manual action required)'
    foreach ($item in $NvidiaManualComponents) {
        $prog = Get-InstalledProgram -NamePattern $item.Name
        if ($prog) {
            Write-Warn "$($item.Label) is installed"
            Write-Info "    Recommended action: $($item.Action)"
        }
        else {
            Write-Ok "$($item.Label) not found"
        }
    }

    Write-Section 'Browser Audit'
    $installedChromium = [System.Collections.Generic.List[string]]::new()
    foreach ($browser in $ChromiumBrowsers) {
        $prog = Get-InstalledProgram -NamePattern "*$($browser.Match)*"
        if ($prog) {
            Write-Info "$($browser.Name) installed"
            $installedChromium.Add($browser.Name)
        }
    }
    if ($installedChromium.Count -ge 3) {
        Write-Warn "$($installedChromium.Count) Chromium-based browsers: $($installedChromium -join ', ')"
        Write-Info "    Recommendation: consolidate to 2 (e.g. Brave + Firefox) to reduce updater surface"
        $driftFound = $true
    }
    else {
        Write-Ok "Browser count within acceptable range"
    }

    Write-Info "Log saved to $LogFile"
    if ($driftFound) {
        Add-Content -Path $LogFile -Value "`nRESULT: DRIFT DETECTED" -Encoding UTF8
        Write-Host "`nAction items found. Run with -Mode Apply to remediate automated items.`n" -ForegroundColor Yellow
        exit 1
    }
    else {
        Add-Content -Path $LogFile -Value "`nRESULT: PASS" -Encoding UTF8
        Write-Host "`nAll automated checks passed.`n" -ForegroundColor Green
        exit 0
    }
}

# ---------------------------------------------------------------------------
# APPLY
# ---------------------------------------------------------------------------

function Invoke-Apply {
    Write-Header -Title 'Installed Programs -- Apply'

    Write-Section 'NVIDIA Telemetry Scheduled Tasks'
    foreach ($pattern in $NvidiaTelemetryTaskPatterns) {
        $tasks = Get-ScheduledTasksByPattern -Pattern $pattern
        if ($tasks) {
            foreach ($task in $tasks) {
                if ($task.State -ne 'Disabled') {
                    try {
                        Disable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction Stop | Out-Null
                        Write-Ok "Disabled: $($task.TaskPath)$($task.TaskName)"
                    }
                    catch {
                        Write-Err "Failed to disable $($task.TaskName): $_"
                    }
                }
                else {
                    Write-Skip "$($task.TaskName) -- already Disabled"
                }
            }
        }
        else {
            Write-Skip "No tasks found matching: $pattern"
        }
    }

    Write-Section 'NVIDIA Components (manual action required)'
    foreach ($item in $NvidiaManualComponents) {
        $prog = Get-InstalledProgram -NamePattern $item.Name
        if ($prog) {
            Write-Action "$($item.Label) detected -- manual step required:"
            Write-Action "    $($item.Action)"
        }
        else {
            Write-Ok "$($item.Label) not found"
        }
    }

    Write-Section 'Browser Audit'
    $installedChromium = [System.Collections.Generic.List[string]]::new()
    foreach ($browser in $ChromiumBrowsers) {
        $prog = Get-InstalledProgram -NamePattern "*$($browser.Match)*"
        if ($prog) { $installedChromium.Add($browser.Name) }
    }
    if ($installedChromium.Count -ge 3) {
        Write-Action "Consider removing one or more Chromium-based browsers: $($installedChromium -join ', ')"
        Write-Info "    Each browser installs background updater services."
        Write-Info "    The Services script sets these updaters to Manual start regardless."
    }
    else {
        Write-Ok "Browser count within acceptable range"
    }

    Write-Info "Log saved to $LogFile"
    Write-Info "No backup file for this script -- uninstall actions are not reversible."
    Add-Content -Path $LogFile -Value "`nRESULT: APPLIED" -Encoding UTF8
    Write-Host "`nApply complete.`n" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

switch ($Mode) {
    'Check' { Invoke-Check }
    'Apply' { Invoke-Apply }
}
