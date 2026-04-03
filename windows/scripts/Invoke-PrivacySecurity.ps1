#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies registry-based privacy and security hardening to Windows 11.
.DESCRIPTION
    Targets telemetry, advertising, activity tracking, remote access exposure, and AutoPlay.
    Does NOT disable Windows Defender, SmartScreen, UAC, or Windows Firewall.
    Backs up all modified registry values for accurate Revert.
.PARAMETER Mode
    Check  — Report current state vs target. No changes made.
    Apply  — Apply registry tweaks and save backup.json.
    Revert — Restore previous registry values from backup.json.
.EXAMPLE
    .\Invoke-PrivacySecurity.ps1 -Mode Check
    .\Invoke-PrivacySecurity.ps1 -Mode Apply
    .\Invoke-PrivacySecurity.ps1 -Mode Revert
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
# Each entry: Path, Name, DesiredValue, Type, Label
# Type: DWord (default), String, QWord

$RegistryTweaks = @(

    # ── Telemetry ──────────────────────────────────────────────────────────
    @{
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        Name  = 'AllowTelemetry'
        Value = 0
        Type  = 'DWord'
        Label = 'Telemetry level — set to 0 (Security)'
    }
    @{
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        Name  = 'DisableEnterpriseAuthProxy'
        Value = 1
        Type  = 'DWord'
        Label = 'Telemetry — disable enterprise auth proxy'
    }

    # ── Advertising ID ────────────────────────────────────────────────────
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
        Name  = 'Enabled'
        Value = 0
        Type  = 'DWord'
        Label = 'Advertising ID — disabled'
    }

    # ── Activity History / Timeline ───────────────────────────────────────
    @{
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        Name  = 'EnableActivityFeed'
        Value = 0
        Type  = 'DWord'
        Label = 'Activity History — feed disabled'
    }
    @{
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        Name  = 'PublishUserActivities'
        Value = 0
        Type  = 'DWord'
        Label = 'Activity History — publish disabled'
    }
    @{
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        Name  = 'UploadUserActivities'
        Value = 0
        Type  = 'DWord'
        Label = 'Activity History — upload disabled'
    }

    # ── Cortana & Search ──────────────────────────────────────────────────
    @{
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
        Name  = 'AllowCortana'
        Value = 0
        Type  = 'DWord'
        Label = 'Cortana — disabled via policy'
    }
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'
        Name  = 'BingSearchEnabled'
        Value = 0
        Type  = 'DWord'
        Label = 'Bing search in Start menu — disabled'
    }
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'
        Name  = 'CortanaConsent'
        Value = 0
        Type  = 'DWord'
        Label = 'Cortana consent — removed'
    }

    # ── Feedback ──────────────────────────────────────────────────────────
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules'
        Name  = 'NumberOfSIUFInPeriod'
        Value = 0
        Type  = 'DWord'
        Label = 'Feedback requests — disabled'
    }
    @{
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        Name  = 'DoNotShowFeedbackNotifications'
        Value = 1
        Type  = 'DWord'
        Label = 'Feedback notifications — suppressed'
    }

    # ── App tracking ──────────────────────────────────────────────────────
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Name  = 'Start_TrackProgs'
        Value = 0
        Type  = 'DWord'
        Label = 'App launch tracking — disabled'
    }

    # ── Tailored experiences ──────────────────────────────────────────────
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'
        Name  = 'TailoredExperiencesWithDiagnosticDataEnabled'
        Value = 0
        Type  = 'DWord'
        Label = 'Tailored experiences — disabled'
    }

    # ── Content Delivery Manager (ads/suggestions) ────────────────────────
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Name  = 'SubscribedContent-338393Enabled'
        Value = 0
        Type  = 'DWord'
        Label = 'Suggested content in Settings — disabled'
    }
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Name  = 'SubscribedContent-353694Enabled'
        Value = 0
        Type  = 'DWord'
        Label = 'Start menu suggestions — disabled'
    }
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Name  = 'SubscribedContent-353696Enabled'
        Value = 0
        Type  = 'DWord'
        Label = 'Lock screen ads — disabled'
    }
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Name  = 'SilentInstalledAppsEnabled'
        Value = 0
        Type  = 'DWord'
        Label = 'Silent app installs — disabled'
    }
    @{
        Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        Name  = 'DisableWindowsConsumerFeatures'
        Value = 1
        Type  = 'DWord'
        Label = 'Windows consumer features (OEM bloat) — disabled'
    }

    # ── Remote Assistance ─────────────────────────────────────────────────
    @{
        Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'
        Name  = 'fAllowToGetHelp'
        Value = 0
        Type  = 'DWord'
        Label = 'Remote Assistance — disabled'
    }

    # ── AutoPlay / AutoRun ────────────────────────────────────────────────
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        Name  = 'NoDriveTypeAutoRun'
        Value = 255
        Type  = 'DWord'
        Label = 'AutoPlay — disabled for all drive types'
    }
    @{
        Path  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        Name  = 'NoAutorun'
        Value = 1
        Type  = 'DWord'
        Label = 'AutoRun — disabled'
    }
)

# ── Helper: read registry value (returns $null if missing) ──────────────────

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch {
        return $null
    }
}

# ── Helper: ensure registry path exists ────────────────────────────────────

function Ensure-RegPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

# ── CHECK ───────────────────────────────────────────────────────────────────

function Invoke-Check {
    Write-Host "`n=== Privacy & Security — Check ===" -ForegroundColor White
    $driftFound = $false

    Write-Host "`n-- Registry Tweaks --" -ForegroundColor White
    foreach ($tweak in $RegistryTweaks) {
        $current = Get-RegValue -Path $tweak.Path -Name $tweak.Name
        if ($null -ne $current -and $current -eq $tweak.Value) {
            Write-Ok "$($tweak.Label)"
        } else {
            $display = if ($null -eq $current) { '(not set)' } else { $current }
            Write-Warn "$($tweak.Label) — current: $display, desired: $($tweak.Value)"
            $driftFound = $true
        }
    }

    # SMBv1 check
    Write-Host "`n-- SMBv1 --" -ForegroundColor White
    try {
        $smb = Get-SmbServerConfiguration -ErrorAction Stop
        if ($smb.EnableSMB1Protocol -eq $false) {
            Write-Ok "SMBv1 is disabled"
        } else {
            Write-Warn "SMBv1 is enabled — should be disabled"
            $driftFound = $true
        }
    } catch {
        Write-Skip "Could not query SMB configuration: $_"
    }

    if ($driftFound) {
        Write-Host "`nDrift detected. Run with -Mode Apply to remediate.`n" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "`nAll privacy and security settings are in target state.`n" -ForegroundColor Green
        exit 0
    }
}

# ── APPLY ───────────────────────────────────────────────────────────────────

function Invoke-Apply {
    Write-Host "`n=== Privacy & Security — Apply ===" -ForegroundColor White

    $backupEntries = @()

    Write-Host "`n-- Registry Tweaks --" -ForegroundColor White
    foreach ($tweak in $RegistryTweaks) {
        $current = Get-RegValue -Path $tweak.Path -Name $tweak.Name

        # Save original value for revert
        $backupEntries += [PSCustomObject]@{
            Path            = $tweak.Path
            Name            = $tweak.Name
            OriginalValue   = $current
            OriginalType    = $tweak.Type
            KeyExistedBefore = (Test-Path $tweak.Path)
        }

        if ($null -ne $current -and $current -eq $tweak.Value) {
            Write-Skip "$($tweak.Label) — already set"
            continue
        }

        try {
            Ensure-RegPath -Path $tweak.Path
            Set-ItemProperty -Path $tweak.Path -Name $tweak.Name -Value $tweak.Value -Type $tweak.Type -Force -ErrorAction Stop
            $prev = if ($null -eq $current) { '(not set)' } else { $current }
            Write-Ok "$($tweak.Label) — set (was $prev)"
        } catch {
            Write-Err "Failed to apply $($tweak.Label): $_"
        }
    }

    # SMBv1
    Write-Host "`n-- SMBv1 --" -ForegroundColor White
    try {
        $smb = Get-SmbServerConfiguration -ErrorAction Stop
        if ($smb.EnableSMB1Protocol) {
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
            Write-Ok "SMBv1 disabled"
        } else {
            Write-Skip "SMBv1 already disabled"
        }
    } catch {
        Write-Err "Failed to configure SMBv1: $_"
    }

    # Save backup
    $backup = @{
        Timestamp = (Get-Date -Format 'o')
        Tweaks    = $backupEntries
    }
    $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupFile -Encoding UTF8
    Write-Host "`nBackup saved to $BackupFile" -ForegroundColor Cyan
    Write-Host "Apply complete.`n" -ForegroundColor Green
}

# ── REVERT ──────────────────────────────────────────────────────────────────

function Invoke-Revert {
    Write-Host "`n=== Privacy & Security — Revert ===" -ForegroundColor White

    if (-not (Test-Path $BackupFile)) {
        Write-Err "No backup found at $BackupFile. Run -Mode Apply first."
        exit 1
    }

    $backup = Get-Content $BackupFile -Raw | ConvertFrom-Json
    Write-Info "Restoring from backup taken at $($backup.Timestamp)"

    foreach ($entry in $backup.Tweaks) {
        try {
            if ($null -eq $entry.OriginalValue) {
                # Key/value didn't exist before — remove it if present
                if (Test-Path $entry.Path) {
                    Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
                    Write-Ok "Removed $($entry.Name) from $($entry.Path)"
                } else {
                    Write-Skip "$($entry.Path)\$($entry.Name) — was not present, nothing to remove"
                }
            } else {
                Ensure-RegPath -Path $entry.Path
                Set-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.OriginalValue -Type $entry.OriginalType -Force -ErrorAction Stop
                Write-Ok "Restored $($entry.Name) to $($entry.OriginalValue)"
            }
        } catch {
            Write-Err "Failed to revert $($entry.Path)\$($entry.Name): $_"
        }
    }

    # SMBv1 revert — leave disabled unless there's a specific reason
    Write-Info "SMBv1 not re-enabled during revert (no backup needed; disabled is safe default)"

    Write-Host "`nRevert complete.`n" -ForegroundColor Green
}

# ── Entry point ─────────────────────────────────────────────────────────────

switch ($Mode) {
    'Check'  { Invoke-Check }
    'Apply'  { Invoke-Apply }
    'Revert' { Invoke-Revert }
}
