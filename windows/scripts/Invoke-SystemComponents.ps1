#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes unused Windows Optional Features, Capabilities, and AppX packages.
.DESCRIPTION
    Targets components with no value for a dedicated sim-racing and streaming PC.
    Does not touch gaming infrastructure (Xbox runtime DLLs, DirectX, etc.).
.PARAMETER Mode
    Check  — Report current state vs target. No changes made.
    Apply  — Remove components and save backup.json for Revert.
    Revert — Restore Capabilities and Optional Features from backup.json.
             AppX packages must be reinstalled manually from the Microsoft Store.
.EXAMPLE
    .\Invoke-SystemComponents.ps1 -Mode Check
    .\Invoke-SystemComponents.ps1 -Mode Apply
    .\Invoke-SystemComponents.ps1 -Mode Revert
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

# AppX packages to remove (supports partial name matching)
$TargetAppX = @(
    @{ Match = 'Microsoft.XboxGamingOverlay';          Label = 'Xbox Game Bar' }
    @{ Match = 'Microsoft.YourPhone';                  Label = 'Phone Link' }
    @{ Match = 'MicrosoftCorporationII.YourPhone';     Label = 'Phone Link (alt package)' }
    @{ Match = 'Microsoft.Windows.DevHome';            Label = 'Dev Home' }
    @{ Match = 'Microsoft.549981C3F5F10';              Label = 'Cortana App' }
    @{ Match = 'Microsoft.WindowsMaps';                Label = 'Windows Maps' }
    @{ Match = 'Microsoft.BingNews';                   Label = 'News' }
    @{ Match = 'Microsoft.BingWeather';                Label = 'Weather' }
    @{ Match = 'Microsoft.XboxIdentityProvider';       Label = 'Xbox Identity Provider' }
    @{ Match = 'Microsoft.XboxSpeechToTextOverlay';    Label = 'Xbox Speech To Text Overlay' }
)

# Windows Capabilities to remove
$TargetCapabilities = @(
    @{ Name = 'App.StepsRecorder~~~~0.0.1.0';                   Label = 'Steps Recorder' }
    @{ Name = 'Microsoft.Windows.WordPad~~~~0.0.1.0';           Label = 'WordPad' }
    @{ Name = 'Browser.InternetExplorer~~~~0.0.11.0';           Label = 'Internet Explorer Mode' }
)

# Optional Features to disable
$TargetFeatures = @(
    @{ Name = 'WindowsMediaPlayer';  Label = 'Windows Media Player (Legacy)' }
    @{ Name = 'WorkFolders-Client';  Label = 'Work Folders Client' }
)

# ── Helper functions ────────────────────────────────────────────────────────

function Get-InstalledAppX {
    param([string]$Match)
    Get-AppxPackage -AllUsers -Name $Match -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Get-CapabilityState {
    param([string]$Name)
    Get-WindowsCapability -Online -Name $Name -ErrorAction SilentlyContinue
}

function Get-FeatureState {
    param([string]$Name)
    Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction SilentlyContinue
}

# ── CHECK ───────────────────────────────────────────────────────────────────

function Invoke-Check {
    Write-Host "`n=== System Components — Check ===" -ForegroundColor White
    $driftFound = $false

    Write-Host "`n-- AppX Packages --" -ForegroundColor White
    foreach ($item in $TargetAppX) {
        $pkg = Get-InstalledAppX -Match $item.Match
        if ($pkg) {
            Write-Warn "$($item.Label) is installed — should be removed"
            $driftFound = $true
        } else {
            Write-Ok "$($item.Label) is not installed"
        }
    }

    Write-Host "`n-- Windows Capabilities --" -ForegroundColor White
    foreach ($item in $TargetCapabilities) {
        $cap = Get-CapabilityState -Name $item.Name
        if ($null -eq $cap) {
            Write-Skip "$($item.Label) — not present on this Windows version"
        } elseif ($cap.State -eq 'Installed') {
            Write-Warn "$($item.Label) is Installed — should be removed"
            $driftFound = $true
        } else {
            Write-Ok "$($item.Label) is $($cap.State)"
        }
    }

    Write-Host "`n-- Optional Features --" -ForegroundColor White
    foreach ($item in $TargetFeatures) {
        $feat = Get-FeatureState -Name $item.Name
        if ($null -eq $feat) {
            Write-Skip "$($item.Label) — feature not present on this Windows version"
        } elseif ($feat.State -eq 'Enabled') {
            Write-Warn "$($item.Label) is Enabled — should be disabled"
            $driftFound = $true
        } else {
            Write-Ok "$($item.Label) is $($feat.State)"
        }
    }

    if ($driftFound) {
        Write-Host "`nDrift detected. Run with -Mode Apply to remediate.`n" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "`nAll components are in target state.`n" -ForegroundColor Green
        exit 0
    }
}

# ── APPLY ───────────────────────────────────────────────────────────────────

function Invoke-Apply {
    Write-Host "`n=== System Components — Apply ===" -ForegroundColor White

    $backup = @{
        RemovedAppX        = @()
        RemovedCapabilities = @()
        DisabledFeatures   = @()
        Timestamp          = (Get-Date -Format 'o')
    }

    Write-Host "`n-- AppX Packages --" -ForegroundColor White
    foreach ($item in $TargetAppX) {
        $pkg = Get-InstalledAppX -Match $item.Match
        if ($pkg) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Ok "Removed $($item.Label) ($($pkg.PackageFullName))"
                $backup.RemovedAppX += @{ Match = $item.Match; Label = $item.Label; FullName = $pkg.PackageFullName }
            } catch {
                Write-Err "Failed to remove $($item.Label): $_"
            }
        } else {
            Write-Skip "$($item.Label) — not installed, skipping"
        }
    }

    Write-Host "`n-- Windows Capabilities --" -ForegroundColor White
    foreach ($item in $TargetCapabilities) {
        $cap = Get-CapabilityState -Name $item.Name
        if ($null -eq $cap) {
            Write-Skip "$($item.Label) — not present on this Windows version"
        } elseif ($cap.State -eq 'Installed') {
            try {
                Remove-WindowsCapability -Online -Name $item.Name -ErrorAction Stop | Out-Null
                Write-Ok "Removed capability: $($item.Label)"
                $backup.RemovedCapabilities += @{ Name = $item.Name; Label = $item.Label }
            } catch {
                Write-Err "Failed to remove $($item.Label): $_"
            }
        } else {
            Write-Skip "$($item.Label) — already $($cap.State)"
        }
    }

    Write-Host "`n-- Optional Features --" -ForegroundColor White
    foreach ($item in $TargetFeatures) {
        $feat = Get-FeatureState -Name $item.Name
        if ($null -eq $feat) {
            Write-Skip "$($item.Label) — feature not present on this Windows version"
        } elseif ($feat.State -eq 'Enabled') {
            try {
                Disable-WindowsOptionalFeature -Online -FeatureName $item.Name -NoRestart -ErrorAction Stop | Out-Null
                Write-Ok "Disabled feature: $($item.Label)"
                $backup.DisabledFeatures += @{ Name = $item.Name; Label = $item.Label }
            } catch {
                Write-Err "Failed to disable $($item.Label): $_"
            }
        } else {
            Write-Skip "$($item.Label) — already $($feat.State)"
        }
    }

    # Save backup
    $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupFile -Encoding UTF8
    Write-Host "`nBackup saved to $BackupFile" -ForegroundColor Cyan
    Write-Host "Apply complete. A reboot may be required for feature changes.`n" -ForegroundColor Green
}

# ── REVERT ──────────────────────────────────────────────────────────────────

function Invoke-Revert {
    Write-Host "`n=== System Components — Revert ===" -ForegroundColor White

    if (-not (Test-Path $BackupFile)) {
        Write-Err "No backup found at $BackupFile. Run -Mode Apply first."
        exit 1
    }

    $backup = Get-Content $BackupFile -Raw | ConvertFrom-Json

    Write-Host "`n-- AppX Packages --" -ForegroundColor White
    if ($backup.RemovedAppX.Count -gt 0) {
        Write-Info "AppX packages cannot be automatically restored."
        Write-Info "The following were removed — reinstall from the Microsoft Store if needed:"
        foreach ($item in $backup.RemovedAppX) {
            Write-Host "    $($item.Label)  ($($item.Match))" -ForegroundColor Yellow
        }
    } else {
        Write-Ok "No AppX packages were removed in the last Apply"
    }

    Write-Host "`n-- Windows Capabilities --" -ForegroundColor White
    foreach ($item in $backup.RemovedCapabilities) {
        try {
            Add-WindowsCapability -Online -Name $item.Name -ErrorAction Stop | Out-Null
            Write-Ok "Restored capability: $($item.Label)"
        } catch {
            Write-Err "Failed to restore $($item.Label): $_"
        }
    }
    if ($backup.RemovedCapabilities.Count -eq 0) {
        Write-Ok "No capabilities were removed in the last Apply"
    }

    Write-Host "`n-- Optional Features --" -ForegroundColor White
    foreach ($item in $backup.DisabledFeatures) {
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName $item.Name -NoRestart -ErrorAction Stop | Out-Null
            Write-Ok "Re-enabled feature: $($item.Label)"
        } catch {
            Write-Err "Failed to re-enable $($item.Label): $_"
        }
    }
    if ($backup.DisabledFeatures.Count -eq 0) {
        Write-Ok "No features were disabled in the last Apply"
    }

    Write-Host "`nRevert complete. A reboot may be required for feature changes.`n" -ForegroundColor Green
}

# ── Entry point ─────────────────────────────────────────────────────────────

switch ($Mode) {
    'Check'  { Invoke-Check }
    'Apply'  { Invoke-Apply }
    'Revert' { Invoke-Revert }
}
