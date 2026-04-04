#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes unused Windows Optional Features, Capabilities, and AppX packages.
.DESCRIPTION
    Targets components with no value for a dedicated sim-racing and streaming PC.
    Logs every run to .\logs\YYYY-MM-DD_HH-mm-ss_Mode.log
    Backups written to .\backups\backup-YYYY-MM-DD.json (Apply overwrites same-day backup)
    Revert uses the most recent backup in .\backups\
.PARAMETER Mode
    Check  - Report current state vs target. No changes made.
    Apply  - Remove components and save dated backup.
    Revert - Restore Capabilities and Optional Features from most recent backup.
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

$TargetAppX = @(
    @{ Match = 'Microsoft.XboxGamingOverlay';       Label = 'Xbox Game Bar' },
    @{ Match = 'Microsoft.YourPhone';               Label = 'Phone Link' },
    @{ Match = 'MicrosoftCorporationII.YourPhone';  Label = 'Phone Link (alt package)' },
    @{ Match = 'Microsoft.Windows.DevHome';         Label = 'Dev Home' },
    @{ Match = 'Microsoft.549981C3F5F10';           Label = 'Cortana App' },
    @{ Match = 'Microsoft.WindowsMaps';             Label = 'Windows Maps' },
    @{ Match = 'Microsoft.BingNews';                Label = 'News' },
    @{ Match = 'Microsoft.BingWeather';             Label = 'Weather' },
    @{ Match = 'Microsoft.XboxIdentityProvider';    Label = 'Xbox Identity Provider' },
    @{ Match = 'Microsoft.XboxSpeechToTextOverlay'; Label = 'Xbox Speech To Text Overlay' }
)

$TargetCapabilities = @(
    @{ Name = 'App.StepsRecorder~~~~0.0.1.0';         Label = 'Steps Recorder' },
    @{ Name = 'Microsoft.Windows.WordPad~~~~0.0.1.0'; Label = 'WordPad' },
    @{ Name = 'Browser.InternetExplorer~~~~0.0.11.0'; Label = 'Internet Explorer Mode' }
)

$TargetFeatures = @(
    @{ Name = 'WindowsMediaPlayer'; Label = 'Windows Media Player (Legacy)' },
    @{ Name = 'WorkFolders-Client'; Label = 'Work Folders Client' }
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

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
    Write-Header -Title 'System Components -- Check'
    $driftFound = $false

    Write-Section 'AppX Packages'
    foreach ($item in $TargetAppX) {
        $pkg = Get-InstalledAppX -Match $item.Match
        if ($pkg) {
            Write-Warn "$($item.Label) is installed -- should be removed"
            $driftFound = $true
        }
        else {
            Write-Ok "$($item.Label) is not installed"
        }
    }

    Write-Section 'Windows Capabilities'
    foreach ($item in $TargetCapabilities) {
        $cap = Get-CapabilityState -Name $item.Name
        if ($null -eq $cap) {
            Write-Skip "$($item.Label) -- not present on this Windows version"
        }
        elseif ($cap.State -eq 'Installed') {
            Write-Warn "$($item.Label) is Installed -- should be removed"
            $driftFound = $true
        }
        else {
            Write-Ok "$($item.Label) is $($cap.State)"
        }
    }

    Write-Section 'Optional Features'
    foreach ($item in $TargetFeatures) {
        $feat = Get-FeatureState -Name $item.Name
        if ($null -eq $feat) {
            Write-Skip "$($item.Label) -- feature not present on this Windows version"
        }
        elseif ($feat.State -eq 'Enabled') {
            Write-Warn "$($item.Label) is Enabled -- should be disabled"
            $driftFound = $true
        }
        else {
            Write-Ok "$($item.Label) is $($feat.State)"
        }
    }

    if ($driftFound) {
        Write-Info "Log saved to $LogFile"
        Write-Host "`nDrift detected. Run with -Mode Apply to remediate.`n" -ForegroundColor Yellow
        Add-Content -Path $LogFile -Value "`nRESULT: DRIFT DETECTED" -Encoding UTF8
        exit 1
    }
    else {
        Write-Info "Log saved to $LogFile"
        Write-Host "`nAll components are in target state.`n" -ForegroundColor Green
        Add-Content -Path $LogFile -Value "`nRESULT: PASS" -Encoding UTF8
        exit 0
    }
}

# ---------------------------------------------------------------------------
# APPLY
# ---------------------------------------------------------------------------

function Invoke-Apply {
    Write-Header -Title 'System Components -- Apply'

    $removedAppX         = [System.Collections.Generic.List[object]]::new()
    $removedCapabilities = [System.Collections.Generic.List[object]]::new()
    $disabledFeatures    = [System.Collections.Generic.List[object]]::new()

    Write-Section 'AppX Packages'
    foreach ($item in $TargetAppX) {
        $pkg = Get-InstalledAppX -Match $item.Match
        if ($pkg) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Ok "Removed $($item.Label) ($($pkg.PackageFullName))"
                $removedAppX.Add([PSCustomObject]@{
                    Match    = $item.Match
                    Label    = $item.Label
                    FullName = $pkg.PackageFullName
                })
            }
            catch {
                Write-Err "Failed to remove $($item.Label): $_"
            }
        }
        else {
            Write-Skip "$($item.Label) -- not installed"
        }
    }

    Write-Section 'Windows Capabilities'
    foreach ($item in $TargetCapabilities) {
        $cap = Get-CapabilityState -Name $item.Name
        if ($null -eq $cap) {
            Write-Skip "$($item.Label) -- not present on this Windows version"
        }
        elseif ($cap.State -eq 'Installed') {
            try {
                Remove-WindowsCapability -Online -Name $item.Name -ErrorAction Stop | Out-Null
                Write-Ok "Removed capability: $($item.Label)"
                $removedCapabilities.Add([PSCustomObject]@{
                    Name  = $item.Name
                    Label = $item.Label
                })
            }
            catch {
                Write-Err "Failed to remove $($item.Label): $_"
            }
        }
        else {
            Write-Skip "$($item.Label) -- already $($cap.State)"
        }
    }

    Write-Section 'Optional Features'
    foreach ($item in $TargetFeatures) {
        $feat = Get-FeatureState -Name $item.Name
        if ($null -eq $feat) {
            Write-Skip "$($item.Label) -- feature not present on this Windows version"
        }
        elseif ($feat.State -eq 'Enabled') {
            try {
                Disable-WindowsOptionalFeature -Online -FeatureName $item.Name -NoRestart -ErrorAction Stop | Out-Null
                Write-Ok "Disabled feature: $($item.Label)"
                $disabledFeatures.Add([PSCustomObject]@{
                    Name  = $item.Name
                    Label = $item.Label
                })
            }
            catch {
                Write-Err "Failed to disable $($item.Label): $_"
            }
        }
        else {
            Write-Skip "$($item.Label) -- already $($feat.State)"
        }
    }

    $backup = [PSCustomObject]@{
        Timestamp           = (Get-Date -Format 'o')
        RemovedAppX         = $removedAppX
        RemovedCapabilities = $removedCapabilities
        DisabledFeatures    = $disabledFeatures
    }
    $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupFile -Encoding UTF8

    Write-Info "Backup saved to $BackupFile"
    Write-Info "Log saved to $LogFile"
    Add-Content -Path $LogFile -Value "`nRESULT: APPLIED" -Encoding UTF8
    Write-Host "`nApply complete. A reboot may be required for feature changes.`n" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# REVERT
# ---------------------------------------------------------------------------

function Invoke-Revert {
    Write-Header -Title 'System Components -- Revert'

    $latestBackup = Get-LatestBackup
    if (-not $latestBackup) {
        Write-Err "No backup files found in $BackupDir. Run -Mode Apply first."
        Add-Content -Path $LogFile -Value "`nRESULT: FAILED -- no backup found" -Encoding UTF8
        exit 1
    }

    Write-Info "Using backup: $($latestBackup.Name)"
    $backup = Get-Content $latestBackup.FullName -Raw | ConvertFrom-Json

    Write-Section 'AppX Packages'
    if ($backup.RemovedAppX.Count -gt 0) {
        Write-Info "AppX packages cannot be automatically restored."
        Write-Info "The following were removed -- reinstall from the Microsoft Store if needed:"
        foreach ($item in $backup.RemovedAppX) {
            Write-Warn "$($item.Label)  ($($item.Match))"
        }
    }
    else {
        Write-Ok "No AppX packages were removed in the source backup"
    }

    Write-Section 'Windows Capabilities'
    if ($backup.RemovedCapabilities.Count -gt 0) {
        foreach ($item in $backup.RemovedCapabilities) {
            try {
                Add-WindowsCapability -Online -Name $item.Name -ErrorAction Stop | Out-Null
                Write-Ok "Restored capability: $($item.Label)"
            }
            catch {
                Write-Err "Failed to restore $($item.Label): $_"
            }
        }
    }
    else {
        Write-Ok "No capabilities were removed in the source backup"
    }

    Write-Section 'Optional Features'
    if ($backup.DisabledFeatures.Count -gt 0) {
        foreach ($item in $backup.DisabledFeatures) {
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName $item.Name -NoRestart -ErrorAction Stop | Out-Null
                Write-Ok "Re-enabled feature: $($item.Label)"
            }
            catch {
                Write-Err "Failed to re-enable $($item.Label): $_"
            }
        }
    }
    else {
        Write-Ok "No features were disabled in the source backup"
    }

    Write-Info "Log saved to $LogFile"
    Add-Content -Path $LogFile -Value "`nRESULT: REVERTED" -Encoding UTF8
    Write-Host "`nRevert complete. A reboot may be required for feature changes.`n" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

switch ($Mode) {
    'Check'  { Invoke-Check }
    'Apply'  { Invoke-Apply }
    'Revert' { Invoke-Revert }
}
