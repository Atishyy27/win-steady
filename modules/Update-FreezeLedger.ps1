<#
  Update-FreezeLedger - keeps a history of every unexpected stop, including silent freezes that
  leave no crash dump, and writes a short report.

  Why: dump readers (WhoCrashed, BlueScreenView, WinDbg) only see bluescreens. A hard freeze that
  you end with the power button leaves no dump at all, so those tools show nothing. Windows still
  records it: Event 6008 (unexpected shutdown) and Kernel-Power 41 on the next boot. This joins
  those with bugchecks (1001), corrected hardware errors (WHEA 17) and the Reliability stability
  index, and appends one row per stop to freeze-ledger.csv (append-only, so history never rewrites).

  Output: <dataDir>\freeze-ledger.csv, <dataDir>\freeze-report.md
#>
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\Common.ps1')
$cfg = Get-SteadyConfig
$since = (Get-Date).AddDays(-[int]$cfg.freeze.historyDays)
$csv = Join-Path $cfg.dataDir 'freeze-ledger.csv'
$known = @{}
if (Test-Path $csv) { Import-Csv $csv | ForEach-Object { $known[$_.BootTime] = $true } }

$boots = @(Get-WinEvent -FilterHashtable @{ LogName='System'; Id=6008; StartTime=$since } -ErrorAction SilentlyContinue)
$bugs  = @(Get-WinEvent -FilterHashtable @{ LogName='System'; Id=1001; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=$since } -ErrorAction SilentlyContinue)
$kp41  = @(Get-WinEvent -FilterHashtable @{ LogName='System'; Id=41; StartTime=$since } -ErrorAction SilentlyContinue)
$whea  = @(Get-WinEvent -FilterHashtable @{ LogName='System'; Id=17; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$since } -ErrorAction SilentlyContinue)

$new = 0
foreach ($b in ($boots | Sort-Object TimeCreated)) {
    $key = $b.TimeCreated.ToString('s')
    if ($known.ContainsKey($key)) { continue }
    $win = { param($e) [math]::Abs(($e.TimeCreated - $b.TimeCreated).TotalMinutes) -lt 5 }
    $bug = $bugs | Where-Object { & $win $_ } | Select-Object -First 1
    $k   = $kp41 | Where-Object { & $win $_ } | Select-Object -First 1
    $kd = @{}; if ($k) { ([xml]$k.ToXml()).Event.EventData.Data | ForEach-Object { $kd[$_.Name] = $_.'#text' } }
    $code = if ($bug -and $bug.Message -match 'bugcheck was: (0x[0-9a-f]+)') { $Matches[1] -replace '0x0+', '0x' } else { '' }
    $lastAlive = if ($b.Message -match 'at (.+?) on (.+?) was unexpected') { ($Matches[2] -replace '[^\d/]','') + ' ' + $Matches[1] } else { '' }
    [pscustomobject]@{
        BootTime        = $key
        Type            = if ($code) { 'bluescreen' } else { 'freeze-or-power-loss' }
        BugCheck        = $code
        LastAlive       = $lastAlive
        DuringSleep     = if ($kd.SleepInProgress -and $kd.SleepInProgress -ne '0') { 'yes' } else { 'no' }
        PowerButtonHeld = if ($kd.LongPowerButtonPressDetected -eq 'true') { 'yes' } else { 'unknown' }
        WheaWithin1h    = @($whea | Where-Object { [math]::Abs(($_.TimeCreated - $b.TimeCreated).TotalMinutes) -lt 60 }).Count
    } | Export-Csv $csv -Append -NoTypeInformation
    $new++
}

$rows = if (Test-Path $csv) { @(Import-Csv $csv | Where-Object { [datetime]$_.BootTime -ge $since }) } else { @() }
$stab = Get-CimInstance Win32_ReliabilityStabilityMetrics -ErrorAction SilentlyContinue | Sort-Object TimeGenerated -Descending | Select-Object -First 1
$md = @(
    "# Freeze ledger, last $($cfg.freeze.historyDays) days ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))",
    '',
    "Unexpected stops: $($rows.Count) (bluescreens $(@($rows | ? Type -eq 'bluescreen').Count), freezes or power loss $(@($rows | ? Type -ne 'bluescreen').Count)).",
    "During sleep: $(@($rows | ? DuringSleep -eq 'yes').Count). Corrected hardware errors (WHEA) in the window: $($whea.Count).",
    "Reliability stability index now: $(if ($stab) { [math]::Round($stab.SystemStabilityIndex,2) } else { 'n/a' }) of 10.",
    '',
    '| Boot after stop | Type | Bug check | Last alive | During sleep | WHEA +-1h |',
    '|---|---|---|---|---|---|'
) + ($rows | Sort-Object BootTime -Descending | ForEach-Object { "| $($_.BootTime) | $($_.Type) | $($_.BugCheck) | $($_.LastAlive) | $($_.DuringSleep) | $($_.WheaWithin1h) |" })
$md | Set-Content -Encoding utf8 (Join-Path $cfg.dataDir 'freeze-report.md')
Write-SteadyLog 'freeze' "ledger updated: $new new stop(s), $($rows.Count) in window"
if ($new -gt 0) { Send-SteadyAlert 'freeze' 'Laptop had an unexpected stop' "$new new since last check. See freeze-report.md." }
Write-Output "new stops: $new | in window: $($rows.Count)"
