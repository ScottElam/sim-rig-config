#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables or throttles Windows services with no value on a dedicated gaming/streaming PC.
.DESCRIPTION
    Services with wildcard names (e.g. CDPUserSvc_*) are matched by pattern to handle the
    per-session suffix that changes between Windows versions and reinstalls.
    The backup captures actual resolved service names and original state for accurate Revert.
.PARAMETER Mode
    Check  — Report current state vs target. No changes made.
    Apply  — Change service startup types, stop running services being disabled, save backup.json.
    Revert — Restore startup types from backup.json and restart services that were previously running.
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

$BackupFile = Join-Path $PSScriptRoot 'backup.json'

# ── Colour helpers ──────────────────────────────────────────────────────────

function Write-Ok   { param($msg) Write-Host "  [OK]      $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [CHANGE]  $msg" -ForegroundColor Yellow }
function Write-Info { param($msg) Write-Host "  [INFO]    $msg" -ForegroundColor Cyan }
function Write-Err  { param($msg) Write-Host "  [ERROR]   $msg" -ForegroundColor Red }
function Write-Skip { param($msg) Write-Host "  [SKIP]    $msg" -ForegroundColor DarkGray }

# ── Target definitions ──────────────────────────────────────────────────────

# Services to set Disabled
# Name supports wildcards; resolved to actual service names at runtime
$ToDisable = @(
    @{ Name = 'CDPSvc';            Reason = 'Connected Devices Platform (Phone Link)' }
    @{ Name = 'CDPUserSvc_*';      Reason = 'Connected Devices Platform User Service' }
    @{ Name = 'lfsvc';             Reason = 'Geolocation — no GPS hardware' }
    @{ Name = 'MapsBroker';        Reason = 'Downloaded Maps Manager — not used' }
    @{ Name = 'SysMain';           Reason = 'Superfetch — counterproductive on NVMe' }
    @{ Name = 'WSAIFabricSvc';     Reason = 'Windows AI Fabric — Copilot infrastructure' }
    @{ Name = 'whesvc';            Reason = 'Windows Health & Optimized Experiences — telemetry' }
    @{ Name = 'CMigrationService'; Reason = 'OS migration remnant — should not run perpetually' }
    @{ Name = 'TermService';       Reason = 'Remote Desktop Services — RDP not needed' }
    @{ Name = 'UmRdpService';      Reason = 'RDP UserMode Port Redirector' }
    @{ Name = 'SessionEnv';        Reason = 'Remote Desktop Configuration' }
    @{ Name = 'SCardSvr';          Reason = 'Smart Card — no reader in this build' }
    @{ Name = 'ScDeviceEnum';      Reason = 'Smart Card Device Enumeration' }
    @{ Name = 'SSDPSRV';           Reason = 'SSDP Discovery — UPnP attack surface' }
    @{ Name = 'Spooler';           Reason = 'Print Spooler — no printer on this system' }
    @{ Name = 'OneSyncSvc_*';      Reason = 'Sync Host — mail/calendar sync not used' }
)

# Services to set Manual (from Automatic)
$ToManual = @(
    @{ Name = 'brave';                         Reason = 'Brave auto-updater — on-demand sufficient' }
    @{ Name = 'edgeupdate';                    Reason = 'Edge auto-updater — on-demand sufficient' }
    @{ Name = 'GoogleUpdaterInternalService*'; Reason = 'Chrome internal updater — on-demand sufficient' }
    @{ Name = 'GoogleUpdaterService*';         Reason = 'Chrome updater — on-demand sufficient' }
    @{ Name = 'InventorySvc';                  Reason = 'Inventory & Compatibility Appraisal — telemetry-adjacent' }
    @{ Name = 'PcaSvc';                        Reason = 'Program Compatibility Assistant — not needed at startup' }
    @{ Name = 'TrkWks';                        Reason = 'Distributed Link Tracking — low value, background I/O' }
    @{ Name = 'WSearch';                       Reason = 'Windows Search indexer — I/O spikes during gaming' }
)

# ── Helper: resolve wildcard service names ──────────────────────────────────

function Resolve-Services {
    param([string]$Pattern)
    try {
        $svcs = Get-Service -Name $Pattern -ErrorAction SilentlyContinue
        return @($svcs)
    } catch {
        return @()
    }
}

# ── Helper: map StartupType string for Set-Service ──────────────────────────
# Get-Service returns DisplayName-style strings; Set-Service needs enum names

function Get-StartupTypeName {
    param($svc)
    # Query WMI for accurate StartMode (Get-Service StartType can be unreliable)
    $wmi = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue
    if ($wmi) { return $wmi.StartMode }
    return $svc.StartType.ToString()
}

# ── CHECK ───────────────────────────────────────────────────────────────────

function Invoke-Check {
    Write-Host "`n=== Services — Check ===" -ForegroundColor White
    $driftFound = $false

    Write-Host "`n-- Services to Disable --" -ForegroundColor White
    foreach ($item in $ToDisable) {
        $svcs = Resolve-Services -Pattern $item.Name
        if ($svcs.Count -eq 0) {
            Write-Skip "$($item.Name) — service not found"
            continue
        }
        foreach ($svc in $svcs) {
            $startMode = Get-StartupTypeName -svc $svc
            if ($startMode -eq 'Disabled') {
                Write-Ok "$($svc.Name) is Disabled"
            } else {
                Write-Warn "$($svc.Name) is $startMode / $($svc.Status) — should be Disabled ($($item.Reason))"
                $driftFound = $true
            }
        }
    }

    Write-Host "`n-- Services to set Manual --" -ForegroundColor White
    foreach ($item in $ToManual) {
        $svcs = Resolve-Services -Pattern $item.Name
        if ($svcs.Count -eq 0) {
            Write-Skip "$($item.Name) — service not found"
            continue
        }
        foreach ($svc in $svcs) {
            $startMode = Get-StartupTypeName -svc $svc
            if ($startMode -in @('Manual', 'Disabled')) {
                Write-Ok "$($svc.Name) is $startMode"
            } else {
                Write-Warn "$($svc.Name) is $startMode / $($svc.Status) — should be Manual ($($item.Reason))"
                $driftFound = $true
            }
        }
    }

    if ($driftFound) {
        Write-Host "`nDrift detected. Run with -Mode Apply to remediate.`n" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "`nAll services are in target state.`n" -ForegroundColor Green
        exit 0
    }
}

# ── APPLY ───────────────────────────────────────────────────────────────────

function Invoke-Apply {
    Write-Host "`n=== Services — Apply ===" -ForegroundColor White

    $backupEntries = @()

    Write-Host "`n-- Services to Disable --" -ForegroundColor White
    foreach ($item in $ToDisable) {
        $svcs = Resolve-Services -Pattern $item.Name
        if ($svcs.Count -eq 0) {
            Write-Skip "$($item.Name) — service not found"
            continue
        }
        foreach ($svc in $svcs) {
            $startMode  = Get-StartupTypeName -svc $svc
            $wasRunning = ($svc.Status -eq 'Running')

            # Save original state
            $backupEntries += [PSCustomObject]@{
                Name            = $svc.Name
                OriginalStart   = $startMode
                WasRunning      = $wasRunning
                TargetStart     = 'Disabled'
            }

            if ($startMode -eq 'Disabled') {
                Write-Skip "$($svc.Name) — already Disabled"
                continue
            }

            try {
                Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop

                if ($wasRunning) {
                    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                    Write-Ok "Disabled and stopped: $($svc.Name)"
                } else {
                    Write-Ok "Disabled: $($svc.Name) (was $startMode, not running)"
                }
            } catch {
                Write-Err "Failed to disable $($svc.Name): $_"
            }
        }
    }

    Write-Host "`n-- Services to set Manual --" -ForegroundColor White
    foreach ($item in $ToManual) {
        $svcs = Resolve-Services -Pattern $item.Name
        if ($svcs.Count -eq 0) {
            Write-Skip "$($item.Name) — service not found"
            continue
        }
        foreach ($svc in $svcs) {
            $startMode  = Get-StartupTypeName -svc $svc
            $wasRunning = ($svc.Status -eq 'Running')

            $backupEntries += [PSCustomObject]@{
                Name            = $svc.Name
                OriginalStart   = $startMode
                WasRunning      = $wasRunning
                TargetStart     = 'Manual'
            }

            if ($startMode -in @('Manual', 'Disabled')) {
                Write-Skip "$($svc.Name) — already $startMode"
                continue
            }

            try {
                Set-Service -Name $svc.Name -StartupType Manual -ErrorAction Stop
                Write-Ok "Set to Manual: $($svc.Name) (was $startMode)"
            } catch {
                Write-Err "Failed to set Manual for $($svc.Name): $_"
            }
        }
    }

    # Save backup
    $backup = @{
        Timestamp = (Get-Date -Format 'o')
        Services  = $backupEntries
    }
    $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupFile -Encoding UTF8
    Write-Host "`nBackup saved to $BackupFile" -ForegroundColor Cyan
    Write-Host "Apply complete.`n" -ForegroundColor Green
}

# ── REVERT ──────────────────────────────────────────────────────────────────

function Invoke-Revert {
    Write-Host "`n=== Services — Revert ===" -ForegroundColor White

    if (-not (Test-Path $BackupFile)) {
        Write-Err "No backup found at $BackupFile. Run -Mode Apply first."
        exit 1
    }

    $backup = Get-Content $BackupFile -Raw | ConvertFrom-Json
    Write-Info "Restoring from backup taken at $($backup.Timestamp)"

    foreach ($entry in $backup.Services) {
        $svc = Get-Service -Name $entry.Name -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Skip "$($entry.Name) — service no longer exists"
            continue
        }

        # Map WMI StartMode back to Set-Service startup type
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
            } else {
                Write-Ok "Restored $($entry.Name) to $startupType"
            }
        } catch {
            Write-Err "Failed to restore $($entry.Name): $_"
        }
    }

    Write-Host "`nRevert complete.`n" -ForegroundColor Green
}

# ── Entry point ─────────────────────────────────────────────────────────────

switch ($Mode) {
    'Check'  { Invoke-Check }
    'Apply'  { Invoke-Apply }
    'Revert' { Invoke-Revert }
}
