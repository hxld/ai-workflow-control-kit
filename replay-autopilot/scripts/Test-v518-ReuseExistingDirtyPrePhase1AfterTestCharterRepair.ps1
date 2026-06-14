param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'

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
[void][System.Management.Automation.Language.Parser]::ParseFile($runLoop, [ref]$tokens, [ref]$errors)
Assert-True 'Run-ReplayLoop parses after v518' (-not $errors -or $errors.Count -eq 0)

$text = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8

Assert-True 'reuse dirty helper exists' ($text.Contains('function Get-ReuseExistingPrePhase1DirtyDecision'))
Assert-True 'helper scans slice result artifacts' ($text.Contains("-Filter 'SLICE_RESULT_*.json'"))
Assert-True 'helper can allow dirty files from authorized existing slice' (
    $text.Contains('reuse_existing_dirty_matches_authorized_slice_files') -and
    $text.Contains('dirty_entries_not_covered_by_authorized_slice') -and
    $text.Contains('Get-DeclaredSliceFiles')
)
Assert-True 'helper matches stale test charter blocker' (
    $text.Contains("[string]`$sliceResult.slice_status -eq 'BLOCKED'") -and
    $text.Contains("[string]`$sliceResult.blocker -match 'test charter'") -and
    $text.Contains("[string]`$sliceResult.slice_title -match 'test charter'")
)
Assert-True 'helper requires passed repair result' (
    $text.Contains('TEST_CHARTER_REPAIR_RESULT_{0}.md') -and
    $text.Contains('validation_status:\s*PASSED') -and
    $text.Contains('can_proceed:\s*true')
)
Assert-True 'dirty reuse is gated by ReuseExisting switch' (
    $text.Contains('$prePhase1DirtyEntries.Count -gt 0 -and [bool]$ReuseExisting') -and
    $text.Contains('Get-ReuseExistingPrePhase1DirtyDecision -ReplayRoot $replayRoot')
)
Assert-True 'dirty block remains fail closed without allowed reuse decision' (
    $text.Contains('$prePhase1DirtyEntries.Count -gt 0 -and (-not $prePhase1DirtyReuseDecision -or -not [bool]$prePhase1DirtyReuseDecision.allow)')
)
Assert-True 'allowed reuse writes explicit warning evidence' (
    $text.Contains("status = 'WARN'") -and
    $text.Contains("decision = 'ALLOW_REUSE_EXISTING_DIRTY'") -and
    $text.Contains('because a reuse decision passed') -and
    $text.Contains('slice resume will re-evaluate implementation artifacts')
)

Write-Host 'v518 reuse-existing dirty pre-phase1 regression passed.'
