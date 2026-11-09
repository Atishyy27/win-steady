<#
  Read-CrashDumps - names the faulting driver for each new crash dump, using Microsoft's own
  kernel debugger (kd.exe from WinDbg or the Windows SDK). Skips quietly if kd is not installed.

  Each dump is analysed once (tracked in dumps.csv). Symbols are cached under <dataDir>\symbols;
  the first run downloads a few hundred MB of public symbols from Microsoft, later runs are quick.
  Output: <dataDir>\dumps.csv  (DumpFile, Written, BugCheckCode, Module, Image, FailureBucket, Process)
#>
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\Common.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\Parsers.ps1')
$cfg = Get-SteadyConfig

function Find-Kd {
    $c = @(
        (Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.WinDbg_*\amd64\kd.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1).FullName,
        "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\kd.exe",
        "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\kd.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }
    return ($c | Select-Object -First 1)
}

$kd = Find-Kd
if (-not $kd) { Write-Output 'kd.exe not found: install WinDbg from the Microsoft Store to get driver names. Skipping.'; return }

$csv = Join-Path $cfg.dataDir 'dumps.csv'
$done = @{}; if (Test-Path $csv) { Import-Csv $csv | ForEach-Object { $done[$_.DumpFile] = $true } }
$dumps = @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp", "$env:SystemRoot\MEMORY.DMP" -ErrorAction SilentlyContinue)
$sym = Join-Path $cfg.dataDir 'symbols'; New-Item -ItemType Directory -Force $sym | Out-Null
$new = 0
foreach ($d in $dumps) {
    $key = "$($d.Name)|$($d.LastWriteTime.ToString('s'))"
    if ($done.ContainsKey($key)) { continue }
    # One crash writes both MEMORY.DMP and a minidump; analyse it once, from the minidump.
    if ($d.Name -eq 'MEMORY.DMP' -and ($dumps | Where-Object { $_.Name -ne 'MEMORY.DMP' -and [math]::Abs(($_.LastWriteTime - $d.LastWriteTime).TotalMinutes) -lt 5 })) { continue }
    $job = Start-Job { param($kd, $dump, $sym) & $kd -z $dump -y "srv*$sym*https://msdl.microsoft.com/download/symbols" -c '!analyze -v; q' 2>&1 | Out-String } -ArgumentList $kd, $d.FullName, $sym
    $text = if (Wait-Job $job -Timeout 600) { Receive-Job $job } else { Stop-Job $job; '' }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    $r = ConvertFrom-KdAnalysis $text
    [pscustomobject]@{ DumpFile = $key; Written = $d.LastWriteTime.ToString('s'); BugCheckCode = $r.BugCheckCode; Module = $r.Module; Image = $r.Image; FailureBucket = $r.FailureBucket; Process = $r.Process } |
        Export-Csv $csv -Append -NoTypeInformation
    Write-SteadyLog 'dumps' "analysed $($d.Name): $($r.Image) / $($r.FailureBucket)"
    $new++
}
Write-Output "dumps analysed this run: $new (of $($dumps.Count) on disk)"
