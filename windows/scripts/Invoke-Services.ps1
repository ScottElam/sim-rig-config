#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables or throttles Windows services with no value on a dedicated gaming/streaming PC.
.DESCRIPTION
    Logs every run to .\logs\YYYY-MM-DD_HH-mm-ss_Mode.log
    Backups written to .\backups\backup-YYYY-MM-DD.json (Apply overwrites same-day backup)
    Revert uses the most recent backup in .\backups\
.PARAMETER Mode
    Check  - Report current state vs target. No changes made.
    Apply  - Change service startup types and save dated backup.
    Revert - Restore startup types from most recent backup.
.EXAMPLE
    .\Invoke-Services.ps1 -Mode Check
    .\Invoke-Services.ps1 -Mode Apply
    .\Invoke-Services.ps1 -Mode Revert
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Check', 'Apply', 'Revert')]
    [string]$Mode
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
# Target definitions
# ---------------------------------------------------------------------------

$ToDisable = @(
    @{ Name = 'CDPSvc';            Reason = 'Connected Devices Platform (Phone Link)' },
    @{ Name = 'CDPUserSvc_*';      Reason = 'Connected Devices Platform User Service' },
    @{ Name = 'lfsvc';             Reason = 'Geolocation -- no GPS hardware' },
    @{ Name = 'MapsBroker';        Reason = 'Downloaded Maps Manager -- not used' },
    @{ Name = 'SysMain';           Reason = 'Superfetch -- counterproductive on NVMe' },
    @{ Name = 'WSAIFabricSvc';     Reason = 'Windows AI Fabric -- Copilot infrastructure' },
    @{ Name = 'whesvc';            Reason = 'Windows Health & Optimized Experiences -- telemetry' },
    @{ Name = 'CMigrationService'; Reason = 'OS migration remnant -- should not run perpetually' },
    @{ Name = 'SCardSvr';          Reason = 'Smart Card -- no reader in this build' },
    @{ Name = 'ScDeviceEnum';      Reason = 'Smart Card Device Enumeration' },
    @{ Name = 'SSDPSRV';           Reason = 'SSDP Discovery -- UPnP attack surface' },
    @{ Name = 'Spooler';           Reason = 'Print Spooler -- no printer on this system' },
    @{ Name = 'OneSyncSvc_*';      Reason = 'Sync Host -- mail/calendar sync not used' }
)

$ToManual = @(
    @{ Name = 'brave';                         Reason = 'Brave auto-updater -- on-demand sufficient' },
    @{ Name = 'edgeupdate';                    Reason = 'Edge auto-updater -- on-demand sufficient' },
    @{ Name = 'GoogleUpdaterInternalService*'; Reason = 'Chrome internal updater -- on-demand sufficient' },
    @{ Name = 'GoogleUpdaterService*';         Reason = 'Chrome updater -- on-demand sufficient' },
    @{ Name = 'InventorySvc';                  Reason = 'Inventory & Compatibility Appraisal -- telemetry-adjacent' },
    @{ Name = 'PcaSvc';                        Reason = 'Program Compatibility Assistant -- not needed at startup' },
    @{ Name = 'TrkWks';                        Reason = 'Distributed Link Tracking -- low value, background I/O' },
    @{ Name = 'WSearch';                       Reason = 'Windows Search indexer -- I/O spikes during gaming' }
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function Resolve-Services {
    param([string]$Pattern)
    try {
        return @(Get-Service -Name $Pattern -ErrorAction SilentlyContinue)
    }
    catch {
        return @()
    }
}

function Get-StartupTypeName {
    param($svc)
    $wmi = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue
    if ($wmi) { return $wmi.StartMode }
    return $svc.StartType.ToString()
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
    Write-Header -Title 'Services -- Check'
    $driftFound = $false

    Write-Section 'Services to Disable'
    foreach ($item in $ToDisable) {
		Set-StrictMode -Off # jse added
        $svcs = Resolve-Services -Pattern $item.Name
        if ($svcs.Count -eq 0) {
            Write-Skip "$($item.Name) -- service not found"
            continue
        }
        foreach ($svc in $svcs) {
            $startMode = Get-StartupTypeName -svc $svc
            if ($startMode -eq 'Disabled') {
                Write-Ok "$($svc.Name) is Disabled"
            }
            else {
                Write-Warn "$($svc.Name) is $startMode / $($svc.Status) -- should be Disabled ($($item.Reason))"
                $driftFound = $true
            }
        }
		Set-StrictMode -Version Latest # Or the specific version used at the top of your file
    }

    Write-Section 'Services to set Manual'
    foreach ($item in $ToManual) {
		Set-StrictMode -Off # jse added
        $svcs = Resolve-Services -Pattern $item.Name
        if ($svcs.Count -eq 0) {
            Write-Skip "$($item.Name) -- service not found"
            continue
        }
        foreach ($svc in $svcs) {
            $startMode = Get-StartupTypeName -svc $svc
            if ($startMode -in @('Manual', 'Disabled')) {
                Write-Ok "$($svc.Name) is $startMode"
            }
            else {
                Write-Warn "$($svc.Name) is $startMode / $($svc.Status) -- should be Manual ($($item.Reason))"
                $driftFound = $true
            }
        }
		Set-StrictMode -Version Latest # Or the specific version used at the top of your file
    }

    Write-Info "Log saved to $LogFile"
    if ($driftFound) {
        Add-Content -Path $LogFile -Value "`nRESULT: DRIFT DETECTED" -Encoding UTF8
        Write-Host "`nDrift detected. Run with -Mode Apply to remediate.`n" -ForegroundColor Yellow
        exit 1
    }
    else {
        Add-Content -Path $LogFile -Value "`nRESULT: PASS" -Encoding UTF8
        Write-Host "`nAll services are in target state.`n" -ForegroundColor Green
        exit 0
    }
}

# ---------------------------------------------------------------------------
# APPLY
# ---------------------------------------------------------------------------

function Invoke-Apply {
    Write-Header -Title 'Services -- Apply'

    $backupEntries = [System.Collections.Generic.List[object]]::new()

    Write-Section 'Services to Disable'
    foreach ($item in $ToDisable) {
		Set-StrictMode -Off # jse added
        $svcs = Resolve-Services -Pattern $item.Name
        if ($svcs.Count -eq 0) {
            Write-Skip "$($item.Name) -- service not found"
            continue
        }
        foreach ($svc in $svcs) {
            $startMode  = Get-StartupTypeName -svc $svc
            $wasRunning = ($svc.Status -eq 'Running')

            $backupEntries.Add([PSCustomObject]@{
                Name          = $svc.Name
                OriginalStart = $startMode
                WasRunning    = $wasRunning
                TargetStart   = 'Disabled'
            })

            if ($startMode -eq 'Disabled') {
                Write-Skip "$($svc.Name) -- already Disabled"
                continue
            }

            try {
                Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
                if ($wasRunning) {
                    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                    Write-Ok "Disabled and stopped: $($svc.Name) (was $startMode)"
                }
                else {
                    Write-Ok "Disabled: $($svc.Name) (was $startMode, not running)"
                }
            }
            catch {
                Write-Err "Failed to disable $($svc.Name): $_"
            }
        }
		Set-StrictMode -Version Latest # Or the specific version used at the top of your file
    }

    Write-Section 'Services to set Manual'
    foreach ($item in $ToManual) {
		Set-StrictMode -Off # jse added
        $svcs = Resolve-Services -Pattern $item.Name
        if ($svcs.Count -eq 0) {
            Write-Skip "$($item.Name) -- service not found"
            continue
        }
        foreach ($svc in $svcs) {
            $startMode  = Get-StartupTypeName -svc $svc
            $wasRunning = ($svc.Status -eq 'Running')

            $backupEntries.Add([PSCustomObject]@{
                Name          = $svc.Name
                OriginalStart = $startMode
                WasRunning    = $wasRunning
                TargetStart   = 'Manual'
            })

            if ($startMode -in @('Manual', 'Disabled')) {
                Write-Skip "$($svc.Name) -- already $startMode"
                continue
            }

            try {
                Set-Service -Name $svc.Name -StartupType Manual -ErrorAction Stop
                Write-Ok "Set to Manual: $($svc.Name) (was $startMode)"
            }
            catch {
                Write-Err "Failed to set Manual for $($svc.Name): $_"
            }
        }
		Set-StrictMode -Version Latest # Or the specific version used at the top of your file
    }

    $backup = [PSCustomObject]@{
        Timestamp = (Get-Date -Format 'o')
        Services  = $backupEntries
    }
    $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupFile -Encoding UTF8

    Write-Info "Backup saved to $BackupFile"
    Write-Info "Log saved to $LogFile"
    Add-Content -Path $LogFile -Value "`nRESULT: APPLIED" -Encoding UTF8
    Write-Host "`nApply complete.`n" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# REVERT
# ---------------------------------------------------------------------------

function Invoke-Revert {
    Write-Header -Title 'Services -- Revert'

    $latestBackup = Get-LatestBackup
    if (-not $latestBackup) {
        Write-Err "No backup files found in $BackupDir. Run -Mode Apply first."
        Add-Content -Path $LogFile -Value "`nRESULT: FAILED -- no backup found" -Encoding UTF8
        exit 1
    }

    Write-Info "Using backup: $($latestBackup.Name)"
    $backup = Get-Content $latestBackup.FullName -Raw | ConvertFrom-Json

    foreach ($entry in $backup.Services) {
        $svc = Get-Service -Name $entry.Name -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Skip "$($entry.Name) -- service no longer exists"
            continue
        }

        $startupType = switch ($entry.OriginalStart) {
            'Auto'     { 'Automatic' }
            'Manual'   { 'Manual' }
            'Disabled' { 'Disabled' }
            default    { $entry.OriginalStart }
        }

        try {
            Set-Service -Name $entry.Name -StartupType $startupType -ErrorAction Stop
            if ($entry.WasRunning -and $startupType -ne 'Disabled') {
                Start-Service -Name $entry.Name -ErrorAction SilentlyContinue
                Write-Ok "Restored $($entry.Name) to $startupType and started"
            }
            else {
                Write-Ok "Restored $($entry.Name) to $startupType"
            }
        }
        catch {
            Write-Err "Failed to restore $($entry.Name): $_"
        }
    }

    Write-Info "Log saved to $LogFile"
    Add-Content -Path $LogFile -Value "`nRESULT: REVERTED" -Encoding UTF8
    Write-Host "`nRevert complete.`n" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

switch ($Mode) {
    'Check'  { Invoke-Check }
    'Apply'  { Invoke-Apply }
    'Revert' { Invoke-Revert }
}
