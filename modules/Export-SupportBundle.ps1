<#
  Export-SupportBundle - one zip to attach to a warranty or support case.

  Contains: freeze report + ledger, analysed dumps list, drift log (every setting your OEM tool
  reverted), memory history, the minidumps themselves, and a system summary (model, serial, BIOS,
  OS build, GPU/storage/network driver versions, stability index). Review it before sending:
  it includes your device serial number on purpose, because support asks for it.

  -Out <folder>   default: your Desktop
#>
param([string]$Out = [Environment]::GetFolderPath('Desktop'))
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\Common.ps1')
$cfg = Get-SteadyConfig
$stage = Join-Path $env:TEMP ("win-steady-bundle-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $stage, (Join-Path $stage 'dumps') | Out-Null

foreach ($f in 'freeze-report.md','freeze-ledger.csv','dumps.csv','drift.log','memory.csv','alerts.log') {
    $p = Join-Path $cfg.dataDir $f; if (Test-Path $p) { Copy-Item $p $stage }
}
Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $stage 'dumps') -ErrorAction SilentlyContinue

$cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS; $os = Get-CimInstance Win32_OperatingSystem
$drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.DeviceClass -in 'DISPLAY','NET','SCSIADAPTER','HDC','SYSTEM' -and $_.DriverProviderName -ne 'Microsoft' } |
    Select-Object DeviceName, DriverProviderName, DriverVersion, @{n='DriverDate';e={ if ($_.DriverDate) { ([datetime]$_.DriverDate).ToString('yyyy-MM-dd') } }} | Sort-Object DeviceName -Unique
$stab = Get-CimInstance Win32_ReliabilityStabilityMetrics -ErrorAction SilentlyContinue | Sort-Object TimeGenerated -Descending | Select-Object -First 1
@(
    "System summary, $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "Model: $($cs.Manufacturer) $($cs.Model)",
    "Serial: $($bios.SerialNumber)",
    "BIOS: $($bios.SMBIOSBIOSVersion) ($($bios.Manufacturer), $(if ($bios.ReleaseDate) { ([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd') }))",
    "OS: $($os.Caption) build $($os.BuildNumber), installed $($os.InstallDate.ToString('yyyy-MM-dd'))",
    "RAM: $([math]::Round($cs.TotalPhysicalMemory/1GB,1)) GB",
    "Stability index: $(if ($stab) { [math]::Round($stab.SystemStabilityIndex,2) } else { 'n/a' }) of 10",
    '', 'Third-party drivers:'
) + ($drivers | ForEach-Object { "  $($_.DeviceName) | $($_.DriverProviderName) | $($_.DriverVersion) | $($_.DriverDate)" }) |
    Set-Content -Encoding utf8 (Join-Path $stage 'system-summary.txt')

$zip = Join-Path $Out ("win-steady-support-" + (Get-Date -Format 'yyyyMMdd') + ".zip")
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
Remove-Item $stage -Recurse -Force
Write-Output ("bundle: {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
