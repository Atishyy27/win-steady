# win-steady

![test](https://github.com/Atishyy27/win-steady/actions/workflows/test.yml/badge.svg)

Keeps a flaky Windows laptop steady, and keeps the evidence when it isn't.

A zero-dependency PowerShell kit that does three things no single tool did for me:

1. **Re-applies the power settings Windows and OEM tools keep reverting**, and logs every revert.
2. **Keeps a history of every unexpected stop, including hard freezes that leave no crash dump.**
3. **Alerts on sustained memory pressure**, on screen and on your phone, before the machine locks up.

Built while chasing two weeks of freezes on a gaming laptop: 17 unexpected stops in 12 days, most of them freezes that left nothing behind for WhoCrashed or BlueScreenView to read.

## Why

- **Drift.** You turn off PCIe link power saving (ASPM), sleep, or a misbehaving onboard NIC. A Windows feature update, a power-mode slider, or a vendor utility (Intel IPF, Fn-key apps) quietly puts it back at the next boot or resume. You never notice until the crashes return.
- **Silent freezes.** Dump readers only see bluescreens. When you have to hold the power button, there is no dump. Windows still writes Event 6008 and Kernel-Power 41 on the next boot; win-steady turns those into a ledger you can hand to support.
- **Memory.** The screen usually dies when commit charge (RAM + page file) runs out, not when "RAM is full". One low sample is noise; several in a row is a warning.

## What you get

| Module | Runs | Writes |
|---|---|---|
| `Invoke-DriftGuard` | at boot + every 10 min (SYSTEM) | `drift.log`: every revert, with what triggered the check |
| `Update-FreezeLedger` | at logon + daily | `freeze-ledger.csv` (append-only), `freeze-report.md` |
| `Watch-Memory` | every 5 min | `memory.csv`, alert after N bad samples in a row |
| `Read-CrashDumps` | with the ledger, only for new dumps | `dumps.csv`: faulting driver + failure bucket per dump, via Microsoft's `kd.exe` (`!analyze -v`) if WinDbg is installed |
| `Export-SupportBundle` | when you ask | one zip for a warranty case: report, ledger, driver list, drift log, memory history, minidumps, system summary |

Data lives in `%LOCALAPPDATA%\win-steady`. Logs rotate at 1 MB. Alerts are capped (default 3 a day, one per kind) so they stay a signal.

## Install

```powershell
# elevated PowerShell
git clone https://github.com/<you>/win-steady
cd win-steady
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Then edit `config.json`:

- `drift.powercfg`: settings to pin (subgroup/setting aliases from `powercfg /aliases`, AC and DC values).
- `drift.keepDisabled`: devices to keep disabled, by friendly name pattern.
- `memory`: thresholds and how many bad samples in a row before alerting.
- `notify.ntfyTopic`: set a private topic name and install the free [ntfy](https://ntfy.sh) app to get phone pushes. Leave empty for desktop toasts only.

Try any module by hand first:

```powershell
.\modules\Invoke-DriftGuard.ps1 -WhatIf     # show drift, change nothing
.\modules\Update-FreezeLedger.ps1
.\modules\Watch-Memory.ps1
```

Remove with `.\uninstall.ps1` (your settings and data stay).

## Talking to support

```powershell
.\modules\Export-SupportBundle.ps1          # writes win-steady-support-<date>.zip to your Desktop
```

The bundle is what support asks for anyway, in one file: how many stops, which were silent freezes,
which driver each crash dump names, every setting your OEM tool reverted, and your BIOS and driver
versions. It includes your device serial on purpose (support needs it); review before sending.

## How it compares

| | win-steady | Dump readers (WhoCrashed, BlueScreenView) | Power-plan tools | Memory reporters | Sensor apps (LibreHardwareMonitor) |
|---|---|---|---|---|---|
| Silent freezes (no dump) | yes, with history | no | no | no | no |
| Faulting driver from dumps | yes (via kd, if installed) | yes, with a GUI | no | no | no |
| Re-applies reverted settings + audit log | yes | no | set once | no | no |
| Sustained memory alerts + phone push | yes | no | no | report only | no |
| Warranty support bundle | yes | no | no | no | no |
| Temperatures, fans, sensors | no, use LibreHardwareMonitor | no | no | no | yes |
| GUI | no (CLI + markdown report) | yes | yes | some | yes |

Use win-steady next to those tools, not instead of them.

## Limits

- It does not fix hardware. If the ledger shows freezes on every power transition, that is warranty evidence, not a script problem.
- Disabling a wedged device can hang Windows' device manager; the guard runs it with a 60-second timeout and tells you to use the BIOS instead.
- Windows only (PowerShell 5.1+, Windows 10/11).

## License

MIT
