<#
  install.ps1 - registers the win-steady scheduled tasks. Run once from an elevated PowerShell:
      powershell -ExecutionPolicy Bypass -File .\install.ps1
  Re-running is safe (tasks are replaced). Remove everything with .\uninstall.ps1.

  Tasks:
    win-steady drift (boot)     SYSTEM, at startup             Invoke-DriftGuard -Trigger BOOT
    win-steady drift (interval) SYSTEM, every N min (config)    Invoke-DriftGuard -Trigger INTERVAL
    win-steady memory           you, every N min (config)       Watch-Memory  (toasts need your session)
    win-steady freeze ledger    you, at logon + daily 09:00     Update-FreezeLedger
#>
$ErrorActionPreference = 'Stop'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run install.ps1 from an elevated (Administrator) PowerShell.'
}
$root = $PSScriptRoot
if (-not (Test-Path (Join-Path $root 'config.json'))) { Copy-Item (Join-Path $root 'config.example.json') (Join-Path $root 'config.json'); Write-Output 'created config.json from config.example.json; edit it to taste.' }
$cfg = Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
# SYSTEM tasks would expand %LOCALAPPDATA% to the system profile; pin the installing user's path instead.
if ($cfg.dataDir -match '%') {
    $cfg.dataDir = [Environment]::ExpandEnvironmentVariables($cfg.dataDir)
    $cfg | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $root 'config.json')
}

function Act($script, $extra = '') {
    New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"{0}`" {1}" -f (Join-Path $root "modules\$script"), $extra)
}
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
$sys = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$me  = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$every = { param($min) $t = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $min); $t }

Register-ScheduledTask -TaskName 'win-steady drift (boot)'     -Action (Act 'Invoke-DriftGuard.ps1' '-Trigger BOOT')     -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $sys -Settings $set -Force | Out-Null
Register-ScheduledTask -TaskName 'win-steady drift (interval)' -Action (Act 'Invoke-DriftGuard.ps1' '-Trigger INTERVAL') -Trigger (& $every ([int]$cfg.drift.intervalMinutes)) -Principal $sys -Settings $set -Force | Out-Null
$long = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'win-steady drift (watch)'    -Action (Act 'Watch-PowerDrift.ps1')                     -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $sys -Settings $long -Force | Out-Null
Register-ScheduledTask -TaskName 'win-steady memory'          -Action (Act 'Watch-Memory.ps1')                         -Trigger (& $every ([int]$cfg.memory.intervalMinutes)) -Principal $me -Settings $set -Force | Out-Null
Register-ScheduledTask -TaskName 'win-steady freeze ledger'    -Action (Act 'Update-FreezeLedger.ps1')                  -Trigger @((New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"), (New-ScheduledTaskTrigger -Daily -At 9am)) -Principal $me -Settings $set -Force | Out-Null

Get-ScheduledTask -TaskName 'win-steady*' | ForEach-Object { "{0,-30} {1}" -f $_.TaskName, $_.State }
Write-Output ("data and logs: " + [Environment]::ExpandEnvironmentVariables($cfg.dataDir))
