# =============================================================================
# Get-ProcessAffinityReport.ps1
# Reports the Process Priority and CPU Affinity for every running process.
# Optionally filter by name. Run as Administrator to see all processes.
# =============================================================================

#Requires -Version 5.1

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------

# Filter: leave empty ("") to show ALL processes, or enter a partial name
# e.g.  $FilterName = "LeMans"   or   $FilterName = "chrome"
$FilterName = ""

# Only show processes that differ from the "Normal" priority default
# Set to $true to hide all "Normal / all-cores" baseline entries
$HideNormal = $false

# Sort column: Name | PID | Priority | Affinity
$SortBy = "Name"

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

function Test-Admin {
    $cu = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($cu)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-CoreList {
    param([long]$Mask, [int]$TotalCores)
    if ($Mask -le 0) { return "N/A" }
    $cores = @()
    for ($i = 0; $i -lt $TotalCores; $i++) {
        if ($Mask -band ([long](1 -shl $i))) { $cores += $i }
    }
    # Compress consecutive ranges for readability  e.g. 0,1,2,3 -> 0-3
    $ranges = @()
    $start  = $cores[0]; $prev = $cores[0]
    for ($j = 1; $j -lt $cores.Count; $j++) {
        if ($cores[$j] -eq $prev + 1) {
            $prev = $cores[$j]
        } else {
            $ranges += if ($start -eq $prev) { "$start" } else { "$start-$prev" }
            $start = $cores[$j]; $prev = $cores[$j]
        }
    }
    $ranges += if ($start -eq $prev) { "$start" } else { "$start-$prev" }
    return $ranges -join ","
}

function Get-PriorityColor {
    param([string]$Priority)
    switch ($Priority) {
        "RealTime"    { return "Red"     }
        "High"        { return "Yellow"  }
        "AboveNormal" { return "Cyan"    }
        "Normal"      { return "Gray"    }
        "BelowNormal" { return "DarkGray"}
        "Idle"        { return "DarkGray"}
        default       { return "White"   }
    }
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

Clear-Host
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   Process Priority & CPU Affinity Report" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Admin)) {
    Write-Host "[WARN] Not running as Administrator — some processes will be inaccessible." -ForegroundColor Yellow
    Write-Host "       Re-run with 'Run as Administrator' for a complete report." -ForegroundColor Yellow
    Write-Host ""
}

$logicalCores  = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$allCoresMask  = [long]([Math]::Pow(2, $logicalCores) - 1)

Write-Host "[INFO] Logical CPU cores : $logicalCores   (all-cores mask: 0x$('{0:X}' -f $allCoresMask))" -ForegroundColor Gray
Write-Host "[INFO] Snapshot time     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
if ($FilterName) {
    Write-Host "[INFO] Filter           : *$FilterName*" -ForegroundColor Gray
}
Write-Host ""

# Collect data
$results   = [System.Collections.Generic.List[PSCustomObject]]::new()
$accessErr = 0

$allProcs = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { -not $FilterName -or $_.Name -like "*$FilterName*" }

foreach ($proc in $allProcs) {
    try {
        $mask     = [long]$proc.ProcessorAffinity
        $priority = $proc.PriorityClass.ToString()
        $allCores = ($mask -eq $allCoresMask) -or ($mask -eq 0)

        if ($HideNormal -and $priority -eq "Normal" -and $allCores) { continue }

        $results.Add([PSCustomObject]@{
            Name          = $proc.Name
            PID           = $proc.Id
            Priority      = $priority
            AffinityHex   = "0x$('{0:X}' -f $mask)"
            AffinityMask  = $mask
            Cores         = ConvertTo-CoreList $mask $logicalCores
            AllCores      = $allCores
            CPU_Pct       = ""   # placeholder — populated below if desired
        })
    } catch {
        $accessErr++
    }
}

# Sort
$sorted = switch ($SortBy) {
    "PID"      { $results | Sort-Object PID }
    "Priority" { $results | Sort-Object Priority, Name }
    "Affinity" { $results | Sort-Object AffinityMask, Name }
    default    { $results | Sort-Object Name }
}

# ---------------------------------------------------------------------------
# OUTPUT TABLE
# ---------------------------------------------------------------------------

$col1 = 34   # Name
$col2 =  7   # PID
$col3 = 13   # Priority
$col4 = 12   # Hex mask
$col5 = 22   # Core list

$header = ("{0,-$col1} {1,$col2}  {2,-$col3} {3,-$col4} {4,-$col5}" `
           -f "Process Name","PID","Priority","Affinity","Cores Assigned")
$divider = "-" * ($col1 + $col2 + $col3 + $col4 + $col5 + 8)

Write-Host $header    -ForegroundColor White
Write-Host $divider   -ForegroundColor DarkGray

foreach ($r in $sorted) {
    $coreDisplay = if ($r.AllCores) { "ALL ($logicalCores)" } else { $r.Cores }
    $line = ("{0,-$col1} {1,$col2}  {2,-$col3} {3,-$col4} {4,-$col5}" `
             -f $r.Name, $r.PID, $r.Priority, $r.AffinityHex, $coreDisplay)
    $color = Get-PriorityColor $r.Priority
    Write-Host $line -ForegroundColor $color
}

Write-Host $divider -ForegroundColor DarkGray
Write-Host ""

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------
$totalShown  = $sorted.Count
$nonDefault  = ($sorted | Where-Object { $_.Priority -ne "Normal" -or -not $_.AllCores }).Count
$highPlus    = ($sorted | Where-Object { $_.Priority -in @("High","RealTime") }).Count
$partialAff  = ($sorted | Where-Object { -not $_.AllCores }).Count

Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "-------" -ForegroundColor DarkGray
Write-Host ("  Processes shown         : {0,6}" -f $totalShown)
Write-Host ("  Inaccessible (skipped)  : {0,6}" -f $accessErr) -ForegroundColor $(if ($accessErr) {"Yellow"} else {"Gray"})
Write-Host ("  Non-default settings    : {0,6}" -f $nonDefault) -ForegroundColor $(if ($nonDefault) {"Cyan"} else {"Gray"})
Write-Host ("  High or RealTime prio   : {0,6}" -f $highPlus)   -ForegroundColor $(if ($highPlus)   {"Yellow"} else {"Gray"})
Write-Host ("  Custom CPU affinity     : {0,6}" -f $partialAff) -ForegroundColor $(if ($partialAff) {"Cyan"} else {"Gray"})
Write-Host ""

# ---------------------------------------------------------------------------
# PRIORITY LEGEND
# ---------------------------------------------------------------------------
Write-Host "PRIORITY LEGEND" -ForegroundColor Cyan
Write-Host "-------" -ForegroundColor DarkGray
@(
    @{ P="RealTime";    C="Red";      D="Highest possible — can starve the OS. Use with extreme care." }
    @{ P="High";        C="Yellow";   D="Recommended boost for games / latency-sensitive apps." }
    @{ P="AboveNormal"; C="Cyan";     D="Mild boost above standard applications." }
    @{ P="Normal";      C="Gray";     D="Default for most processes." }
    @{ P="BelowNormal"; C="DarkGray"; D="Slightly lower than default." }
    @{ P="Idle";        C="DarkGray"; D="Runs only when CPU is otherwise idle." }
) | ForEach-Object {
    Write-Host ("  {0,-13} " -f $_.P) -ForegroundColor $_.C -NoNewline
    Write-Host $_.D -ForegroundColor Gray
}

Write-Host ""
Write-Host "Report complete." -ForegroundColor Cyan
Write-Host ""
