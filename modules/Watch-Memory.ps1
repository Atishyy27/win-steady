<#
  Watch-Memory - alerts when memory pressure is SUSTAINED, not on a single spike.

  Why: a laptop rarely freezes from low RAM alone; it freezes when commit charge (RAM + page file)
  runs out and the compositor or a driver cannot allocate. A single low sample is noise. This
  alerts after N consecutive samples over the threshold, names the top processes by committed
  memory, and can push to your phone through ntfy.sh (free, no account).

  Output: <dataDir>\memory.csv (one row per run), alerts via toast and/or ntfy.
#>
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\Common.ps1')
$cfg = Get-SteadyConfig
$os = Get-CimInstance Win32_OperatingSystem
$free = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$commitPct = [math]::Round(100 * ($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / $os.TotalVirtualMemorySize, 0)
$over = ($free -lt [double]$cfg.memory.freeGbBelow) -or ($commitPct -ge [int]$cfg.memory.commitPercentAbove)

$csv = Join-Path $cfg.dataDir 'memory.csv'
[pscustomobject]@{ Timestamp = (Get-Date).ToString('s'); FreeGB = $free; CommitPct = $commitPct; Over = $over } |
    Export-Csv $csv -Append -NoTypeInformation

$n = [int]$cfg.memory.sustainedSamples
$recent = @(Import-Csv $csv | Select-Object -Last $n)
if ($recent.Count -ge $n -and -not ($recent | Where-Object { $_.Over -ne 'True' })) {
    $top = Get-Process | Group-Object ProcessName | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; MB = [math]::Round(($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum / 1MB) } } |
        Sort-Object MB -Descending | Select-Object -First ([int]$cfg.memory.topProcesses)
    $topText = ($top | Select-Object -First 3 | ForEach-Object { "$($_.Name) $($_.MB) MB" }) -join ', '
    Write-SteadyLog 'memory' ("SUSTAINED: free $free GB, commit $commitPct% :: " + (($top | ForEach-Object { "$($_.Name)=$($_.MB)MB" }) -join ' '))
    Send-SteadyAlert 'memory' 'Memory pressure' "Free $free GB, commit $commitPct% for $n checks. Top: $topText"
}
Write-Output "free $free GB, commit $commitPct%, over=$over"
