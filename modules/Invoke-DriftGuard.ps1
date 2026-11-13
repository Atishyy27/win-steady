<#
  Invoke-DriftGuard - re-applies power settings and disabled devices that Windows or OEM tools
  keep reverting, and logs every revert with what triggered the check.

  Why: Windows feature updates, power-mode sliders and OEM utilities (Intel IPF, vendor Fn-key
  apps, etc.) silently rewrite the active power scheme. A setting you fixed once is gone after
  the next boot, resume or mode change. This puts it back and leaves an audit trail, which is
  also evidence for a warranty or support case.

  -Trigger BOOT|RESUME|INTERVAL|MANUAL   recorded in drift.log
  -WhatIf                                report drift only, change nothing
#>
param([ValidateSet('BOOT','RESUME','INTERVAL','MANUAL')][string]$Trigger = 'MANUAL', [switch]$WhatIf)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\Common.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\Parsers.ps1')
$cfg = Get-SteadyConfig
$changed = @()

function Get-Index($sub, $set, $kind) { ConvertFrom-PowerCfgIndex ((powercfg /q SCHEME_CURRENT $sub $set 2>$null) -join "`n") $kind }

foreach ($p in $cfg.drift.powercfg) {
    foreach ($kind in 'AC','DC') {
        $want = [int]$p.($kind.ToLower())
        $have = Get-Index $p.subgroup $p.setting $kind
        if ($null -eq $have) { continue }          # setting not present on this machine
        if ($have -ne $want) {
            $changed += "$($p.name) $kind $have->$want"
            if (-not $WhatIf) {
                if ($kind -eq 'AC') { powercfg /setacvalueindex SCHEME_CURRENT $p.subgroup $p.setting $want 2>$null | Out-Null }
                else                { powercfg /setdcvalueindex SCHEME_CURRENT $p.subgroup $p.setting $want 2>$null | Out-Null }
            }
        }
    }
}
if ($changed.Count -and -not $WhatIf) { powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null }   # commit to the live policy

foreach ($d in $cfg.drift.keepDisabled) {
    $dev = Get-PnpDevice -FriendlyName $d.friendlyNameLike -PresentOnly -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($dev -and $dev.Status -eq 'OK') {
        $changed += "$($d.name) re-enabled"
        # Disable in a background job with a timeout: a wedged device can hang PnP calls for minutes.
        if (-not $WhatIf) {
            $j = Start-Job { param($id) Disable-PnpDevice -InstanceId $id -Confirm:$false } -ArgumentList $dev.InstanceId
            if (-not (Wait-Job $j -Timeout 60)) { Stop-Job $j; $changed += "(disable of $($d.name) timed out; check BIOS)" }
            Remove-Job $j -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($changed.Count) {
    $verb = if ($WhatIf) { 'DRIFT (not fixed, -WhatIf)' } else { 'REVERTED, re-applied' }
    Write-SteadyLog 'drift' "trigger=$Trigger $verb :: $($changed -join '; ')"
    Write-Output "$verb :: $($changed -join '; ')"
} else {
    # One heartbeat per day for INTERVAL runs; every BOOT/RESUME run is logged (that's the pattern that matters).
    $log = Join-Path $cfg.dataDir 'drift.log'
    $today = Get-Date -Format 'yyyy-MM-dd'
    $hb = (Test-Path $log) -and (Select-String -Path $log -Pattern "^$today.*trigger=INTERVAL ok" -Quiet)
    # logEveryCheck: one line per run, so a freeze can be matched to the last known state.
    if ($Trigger -ne 'INTERVAL' -or -not $hb -or $cfg.drift.logEveryCheck) { Write-SteadyLog 'drift' "trigger=$Trigger ok" }
    Write-Output 'ok: no drift'
}
