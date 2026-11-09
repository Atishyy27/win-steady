# uninstall.ps1 - removes the win-steady scheduled tasks. Your data folder and settings are left as they are.
Get-ScheduledTask -TaskName 'win-steady*' -ErrorAction SilentlyContinue | ForEach-Object {
    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
    "removed: $($_.TaskName)"
}
"Settings you pinned stay as they are now. To restore Windows defaults: powercfg /restoredefaultschemes"
