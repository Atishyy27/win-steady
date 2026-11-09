# Shared helpers for win-steady. Dot-sourced by every module.

$script:Root = Split-Path -Parent $PSScriptRoot

function Get-SteadyConfig {
    $path = Join-Path $script:Root 'config.json'
    if (-not (Test-Path $path)) { $path = Join-Path $script:Root 'config.example.json' }
    $cfg = Get-Content $path -Raw | ConvertFrom-Json
    $cfg.dataDir = [Environment]::ExpandEnvironmentVariables($cfg.dataDir)
    New-Item -ItemType Directory -Force $cfg.dataDir | Out-Null
    return $cfg
}

function Write-SteadyLog([string]$Name, [string]$Line) {
    $cfg = Get-SteadyConfig
    $file = Join-Path $cfg.dataDir "$Name.log"
    $stamped = "{0}  {1}" -f (Get-Date -Format s), $Line
    # Logs rotate at 1 MB so nothing grows forever.
    if ((Test-Path $file) -and (Get-Item $file).Length -gt 1MB) { Move-Item $file "$file.1" -Force }
    for ($i = 0; $i -lt 10; $i++) {
        try { [IO.File]::AppendAllText($file, $stamped + [Environment]::NewLine); return } catch { Start-Sleep -Milliseconds 150 }
    }
}

function Send-SteadyAlert([string]$Kind, [string]$Title, [string]$Message) {
    $cfg = Get-SteadyConfig
    # Max N pushes a day, one per kind per day, so alerts stay a signal.
    $stateF = Join-Path $cfg.dataDir 'alert-state.json'
    $today = Get-Date -Format 'yyyy-MM-dd'
    $state = if (Test-Path $stateF) { Get-Content $stateF -Raw | ConvertFrom-Json } else { $null }
    if (-not $state -or $state.day -ne $today) { $state = [pscustomobject]@{ day = $today; sent = @() } }
    $sent = @($state.sent)
    if ($sent -contains $Kind -or $sent.Count -ge [int]$cfg.notify.maxPushesPerDay) { return }

    if ($cfg.notify.toast) {
        try {
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
            $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
            $t = $xml.GetElementsByTagName('text')
            $null = $t.Item(0).AppendChild($xml.CreateTextNode($Title))
            $null = $t.Item(1).AppendChild($xml.CreateTextNode($Message))
            $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
        } catch { Write-SteadyLog 'alerts' "toast failed: $_" }
    }
    if ($cfg.notify.ntfyTopic) {
        try {
            Invoke-RestMethod -Method Post -Uri ("{0}/{1}" -f $cfg.notify.ntfyServer.TrimEnd('/'), $cfg.notify.ntfyTopic) `
                -Headers @{ Title = $Title; Tags = 'warning' } -Body $Message -TimeoutSec 15 | Out-Null
        } catch { Write-SteadyLog 'alerts' "ntfy failed: $_" }
    }
    $state.sent = $sent + $Kind
    $state | ConvertTo-Json | Set-Content -Encoding utf8 $stateF
    Write-SteadyLog 'alerts' "SENT $Kind :: $Title :: $Message"
}
