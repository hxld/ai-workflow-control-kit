param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )
    if (-not $Condition) {
        throw "ASSERT FAILED: $Name"
    }
    Write-Host "PASS: $Name"
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($sliceLoop, [ref]$tokens, [ref]$errors)
Assert-True 'Run-SliceLoop parses after v516' (-not $errors -or $errors.Count -eq 0)

$text = Get-Content -LiteralPath $sliceLoop -Raw -Encoding UTF8
$repairStart = $text.IndexOf('function Invoke-TestCharterRepairGate')
$repairEnd = $text.IndexOf('function Invoke-LayerValidationGate')
Assert-True 'test charter repair function boundaries found' ($repairStart -ge 0 -and $repairEnd -gt $repairStart)
$repairText = $text.Substring($repairStart, $repairEnd - $repairStart)

$repairExitIndex = $repairText.IndexOf('$repairExit = Invoke-SliceExecutorWithRetry')
$recheckIndex = $repairText.IndexOf('$recheck = Invoke-TestCharterPrevalidatorGate')
$failedGateReturnIndex = $repairText.IndexOf('return $FailedGate', $recheckIndex)
$passedRecheckReturnIndex = $repairText.IndexOf('return $recheck', $recheckIndex)

Assert-True 'repair executor is invoked' ($repairExitIndex -ge 0)
Assert-True 'prevalidator recheck is invoked after repair executor' ($recheckIndex -gt $repairExitIndex)
Assert-True 'failed gate fallback happens only after recheck' ($failedGateReturnIndex -gt $recheckIndex)
Assert-True 'passed recheck returns before failed gate fallback' ($passedRecheckReturnIndex -gt $recheckIndex -and $passedRecheckReturnIndex -lt $failedGateReturnIndex)
Assert-True 'nonzero executor with passed recheck is recorded' ($repairText.Contains('test charter repair executor nonzero ignored'))

Write-Host 'v516 test charter repair recheck ordering regression passed.'
