<#
  Watch-PowerDrift - a light, always-on loop that puts pinned power settings back within seconds.

  Why: some OEM utilities rewrite the power plan whenever they start or you change a mode with an
  Fn key (seen with Clevo's FnKey.exe, which writes PCIe ASPM back to "maximum saving" within
  3 seconds of starting). A guard that runs every few minutes leaves the machine on the bad value
  for that whole gap. This reads the values through the Windows power API (no powercfg process per
  check), so a 5-second loop costs almost nothing. It only writes when something drifted, and logs
  each fix to drift.log as trigger=WATCH.

  -Seconds N    check interval (default from config drift.watchSeconds, else 5)
  -Once         one pass and exit (for testing)
#>
param([int]$Seconds = 0, [switch]$Once)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\Common.ps1')
$cfg = Get-SteadyConfig
if ($Seconds -le 0) { $Seconds = if ($cfg.drift.watchSeconds) { [int]$cfg.drift.watchSeconds } else { 5 } }

Add-Type -Namespace WinSteady -Name Power -MemberDefinition @'
[DllImport("powrprof.dll")] public static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
[DllImport("powrprof.dll")] public static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid sub, ref Guid setting, out uint value);
[DllImport("powrprof.dll")] public static extern uint PowerReadDCValueIndex(IntPtr root, ref Guid scheme, ref Guid sub, ref Guid setting, out uint value);
[DllImport("powrprof.dll")] public static extern uint PowerWriteACValueIndex(IntPtr root, ref Guid scheme, ref Guid sub, ref Guid setting, uint value);
[DllImport("powrprof.dll")] public static extern uint PowerWriteDCValueIndex(IntPtr root, ref Guid scheme, ref Guid sub, ref Guid setting, uint value);
[DllImport("powrprof.dll")] public static extern uint PowerSetActiveScheme(IntPtr root, ref Guid scheme);
[DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr p);
'@

# Resolve powercfg aliases (SUB_PCIEXPRESS / ASPM) to GUIDs once, from powercfg's own output.
$pins = foreach ($p in $cfg.drift.powercfg) {
    $q = (powercfg /q SCHEME_CURRENT $p.subgroup $p.setting 2>$null) -join "`n"
    $sub = [regex]::Match($q, 'Subgroup GUID: ([0-9a-f-]{36})').Groups[1].Value
    $set = [regex]::Match($q, 'Power Setting GUID: ([0-9a-f-]{36})').Groups[1].Value
    if ($sub -and $set) { [pscustomobject]@{ Name = $p.name; Sub = [guid]$sub; Set = [guid]$set; AC = [uint32]$p.ac; DC = [uint32]$p.dc } }
}
if (-not $pins) { Write-SteadyLog 'drift' 'trigger=WATCH no pinned settings found on this machine; exiting'; return }

function Get-ActiveScheme { $ptr = [IntPtr]::Zero; [void][WinSteady.Power]::PowerGetActiveScheme([IntPtr]::Zero, [ref]$ptr); $g = [Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][guid]); [void][WinSteady.Power]::LocalFree($ptr); $g }

do {
    $scheme = Get-ActiveScheme
    $fixed = @()
    foreach ($p in $pins) {
        $sub = $p.Sub; $set = $p.Set; $ac = [uint32]0; $dc = [uint32]0
        if ([WinSteady.Power]::PowerReadACValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$sub, [ref]$set, [ref]$ac) -ne 0) { continue }
        [void][WinSteady.Power]::PowerReadDCValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$sub, [ref]$set, [ref]$dc)
        if ($ac -ne $p.AC) { [void][WinSteady.Power]::PowerWriteACValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$sub, [ref]$set, $p.AC); $fixed += "$($p.Name) AC $ac->$($p.AC)" }
        if ($dc -ne $p.DC) { [void][WinSteady.Power]::PowerWriteDCValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$sub, [ref]$set, $p.DC); $fixed += "$($p.Name) DC $dc->$($p.DC)" }
    }
    if ($fixed) {
        [void][WinSteady.Power]::PowerSetActiveScheme([IntPtr]::Zero, [ref]$scheme)   # make the new values live
        Write-SteadyLog 'drift' "trigger=WATCH REVERTED, re-applied :: $($fixed -join '; ')"
    }
    if (-not $Once) { Start-Sleep -Seconds $Seconds }
} while (-not $Once)
