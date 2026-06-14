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
Assert-True 'Run-SliceLoop parses after v517' (-not $errors -or $errors.Count -eq 0)

$text = Get-Content -LiteralPath $sliceLoop -Raw -Encoding UTF8

Assert-True 'stale test charter repair result path is checked' ($text.Contains('TEST_CHARTER_REPAIR_RESULT_{0:D2}.md'))
Assert-True 'stale blocker requires blocked slice status' ($text.Contains("[string]`$existingSliceResult.slice_status -eq 'BLOCKED'"))
Assert-True 'stale blocker requires test charter blocker text' ($text.Contains("[string]`$existingSliceResult.blocker -match 'test charter'"))
Assert-True 'stale blocker requires passed repair validation' ($text.Contains('validation_status:\s*PASSED'))
Assert-True 'stale blocker requires can_proceed true' ($text.Contains('can_proceed:\s*true'))
Assert-True 'stale slice artifacts are archived' ($text.Contains('logs\stale-slice-results') -and $text.Contains('Move-Item -LiteralPath $sliceResult') -and $text.Contains('Move-Item -LiteralPath $sliceVerify'))
Assert-True 'stale result disables reuse' ($text.Contains('$hasExistingResult = $false') -and $text.Contains('$hasExistingVerify = $false'))
Assert-True 'runner contract records stale invalidation' ($text.Contains('stale test charter blocker invalidated'))

Write-Host 'v517 stale test charter blocker invalidation regression passed.'
