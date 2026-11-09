# Pure text parsers, kept separate so they can be unit-tested without a real machine state.

function ConvertFrom-PowerCfgIndex([string]$Text, [ValidateSet('AC','DC')][string]$Kind) {
    # powercfg /q output -> integer index, or $null when the setting is absent.
    if ($Text -match "Current $Kind Power Setting Index:\s*(0x[0-9a-fA-F]+)") { return [convert]::ToInt32($Matches[1], 16) }
    return $null
}

function ConvertFrom-UnexpectedShutdownMessage([string]$Message) {
    # Event 6008 text -> last-alive time as text (format varies with locale, so it is kept verbatim).
    if ($Message -match 'at (.+?) on (.+?) was unexpected') { return (($Matches[2] -replace '[^\d/.\-]', '') + ' ' + $Matches[1]).Trim() }
    return ''
}

function ConvertFrom-BugcheckMessage([string]$Message) {
    # Event 1001 (WER-SystemErrorReporting) text -> short bug check code like 0x9f.
    if ($Message -match 'bugcheck was: (0x[0-9a-fA-F]+)') { return ($Matches[1].ToLower() -replace '^0x0+', '0x') }
    return ''
}

function ConvertFrom-KdAnalysis([string]$Text) {
    # Output of `kd -z <dump> -c "!analyze -v; q"` -> the fields that matter for triage.
    $get = { param($key) if ($Text -match "(?m)^\s*$key\s*:\s*(.+?)\s*$") { $Matches[1] } else { '' } }
    [pscustomobject]@{
        BugCheckCode  = & $get 'BUGCHECK_CODE'
        Module        = & $get 'MODULE_NAME'
        Image         = & $get 'IMAGE_NAME'
        FailureBucket = & $get 'FAILURE_BUCKET_ID'
        Process       = & $get 'PROCESS_NAME'
    }
}
