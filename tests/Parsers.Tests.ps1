BeforeAll { . (Join-Path $PSScriptRoot '..\lib\Parsers.ps1') }

Describe 'ConvertFrom-PowerCfgIndex' {
    BeforeAll { $sample = @"
    Power Setting GUID: ee12f906-d277-404b-b6da-e5fa1a576df5  (Link State Power Management)
    Current AC Power Setting Index: 0x00000000
    Current DC Power Setting Index: 0x00000002
"@ }
    It 'reads AC' { ConvertFrom-PowerCfgIndex $sample 'AC' | Should -Be 0 }
    It 'reads DC' { ConvertFrom-PowerCfgIndex $sample 'DC' | Should -Be 2 }
    It 'returns null when absent' { ConvertFrom-PowerCfgIndex 'nothing here' 'AC' | Should -BeNullOrEmpty }
}

Describe 'ConvertFrom-UnexpectedShutdownMessage' {
    It 'extracts the last-alive time' {
        $m = 'The previous system shutdown at 3:09:12 PM on 11/9/2026 was unexpected.'
        ConvertFrom-UnexpectedShutdownMessage $m | Should -Be '11/9/2026 3:09:12 PM'
    }
    It 'strips invisible direction marks' {
        $m = "The previous system shutdown at 1:19:03 AM on $([char]0x200e)11/$([char]0x200e)8/$([char]0x200e)2026 was unexpected."
        ConvertFrom-UnexpectedShutdownMessage $m | Should -Be '11/8/2026 1:19:03 AM'
    }
    It 'returns empty on other text' { ConvertFrom-UnexpectedShutdownMessage 'hello' | Should -Be '' }
}

Describe 'ConvertFrom-BugcheckMessage' {
    It 'shortens the code' {
        $m = 'The computer has rebooted from a bugcheck. The bugcheck was: 0x0000013a (0x0000000000000017, ...).'
        ConvertFrom-BugcheckMessage $m | Should -Be '0x13a'
    }
    It 'returns empty when no bugcheck' { ConvertFrom-BugcheckMessage 'clean shutdown' | Should -Be '' }
}

Describe 'ConvertFrom-KdAnalysis' {
    BeforeAll { $kd = @"
BUGCHECK_CODE:  13a
PROCESS_NAME:  dwm.exe
MODULE_NAME: dxgmms2
IMAGE_NAME:  dxgmms2.sys
FAILURE_BUCKET_ID:  0x13a_17_dxgmms2!AllocateElements
"@ }
    It 'parses all fields' {
        $r = ConvertFrom-KdAnalysis $kd
        $r.BugCheckCode  | Should -Be '13a'
        $r.Image         | Should -Be 'dxgmms2.sys'
        $r.Module        | Should -Be 'dxgmms2'
        $r.Process       | Should -Be 'dwm.exe'
        $r.FailureBucket | Should -Be '0x13a_17_dxgmms2!AllocateElements'
    }
    It 'handles empty output' { (ConvertFrom-KdAnalysis '').Image | Should -Be '' }
}
