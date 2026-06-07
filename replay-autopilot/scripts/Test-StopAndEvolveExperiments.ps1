param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonObject {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Copy-IfExists {
    param([string]$Source, [string]$Destination)
    if (Test-Path -LiteralPath $Source) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktree = Join-Path $replayRootFull 'worktree'
if (-not (Test-Path -LiteralPath $worktree)) {
    throw "Replay worktree not found: $worktree"
}

$tempRoot = Join-Path $scriptRoot ('.tmp\stop-evolve-experiments-{0}' -f $PID)
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[string]
$evidence = [ordered]@{}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-ReplayDryRunAndRouter.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Carrier authorization dry-run tests failed.' }
$cases.Add('carrier_authorization_dry_run_fail_closed') | Out-Null
$evidence.carrier_authorization = 'PASS'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-VerifierContracts.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Verifier fail-closed contract tests failed.' }
$cases.Add('verifier_fail_closed_contracts') | Out-Null
$evidence.verifier_contracts = 'PASS'

$sampleSlices = @(9, 12)
foreach ($slice in $sampleSlices) {
    $sliceResult = Join-Path $replayRootFull ('SLICE_RESULT_{0:D2}.json' -f $slice)
    if (-not (Test-Path -LiteralPath $sliceResult)) { continue }

    $caseRoot = Join-Path $tempRoot ('slice{0:D2}' -f $slice)
    New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
    Copy-Item -LiteralPath $sliceResult -Destination (Join-Path $caseRoot ('SLICE_RESULT_{0:D2}.json' -f $slice)) -Force
    foreach ($prefix in @('CARRIER_AUTHORIZATION', 'EXACT_CONTRACT_ASSERTION_MATRIX', 'SIDE_EFFECT_EVIDENCE')) {
        Copy-IfExists -Source (Join-Path $replayRootFull ('{0}_{1:D2}.json' -f $prefix, $slice)) -Destination (Join-Path $caseRoot ('{0}_{1:D2}.json' -f $prefix, $slice))
    }
    Copy-IfExists -Source (Join-Path $replayRootFull 'FAMILY_CONTRACT.json') -Destination (Join-Path $caseRoot 'FAMILY_CONTRACT.json')

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1') `
        -ReplayRoot $caseRoot `
        -Worktree $worktree `
        -SliceResult (Join-Path $caseRoot ('SLICE_RESULT_{0:D2}.json' -f $slice)) `
        -SliceIndex $slice | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Verifier failed for copied slice $slice." }
    $verify = Read-JsonObject (Join-Path $caseRoot ('SLICE_VERIFY_{0:D2}.json' -f $slice))
    if ([bool]$verify.authorized_for_synthesis) { throw "Slice $slice should fail closed for synthesis." }
    if ($slice -eq 9 -and [int]$verify.adjusted_coverage_delta -ne 0) { throw 'S9 exact contract gap should have adjusted delta 0.' }
    $cases.Add(('current_slice_{0:D2}_fails_closed_under_new_verifier' -f $slice)) | Out-Null
    $evidence[('slice_{0:D2}' -f $slice)] = [ordered]@{
        verification_status = [string]$verify.verification_status
        adjusted_coverage_delta = [int]$verify.adjusted_coverage_delta
        coverage_cap = [int]$verify.coverage_cap
        authorized_for_next_slice = [bool]$verify.authorized_for_next_slice
        authorized_for_synthesis = [bool]$verify.authorized_for_synthesis
        authorization_blockers = @($verify.authorization_blockers)
    }
}

$router = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'FamilyRouterAndCap.ps1') -ReplayRoot $replayRootFull -ValidateOnly | ConvertFrom-Json
if ([string]$router.selected_family -ne 'core_entry') { throw "Expected router to return to core_entry, got $($router.selected_family)." }
if ([int]$router.coverage_cap_from_ledger -gt 25) { throw "Expected ledger cap <=25, got $($router.coverage_cap_from_ledger)." }
if ([bool]$router.final_pass_allowed) { throw 'Expected final_pass_allowed=false while required families remain open/partial.' }
$cases.Add('router_ledger_cap_current_evidence') | Out-Null
$evidence.router = $router

$result = [ordered]@{
    status = 'PASS'
    replay_root = $replayRootFull
    cases = @($cases)
    evidence = $evidence
    temp_root = $tempRoot
}

$resultPath = Join-Path $replayRootFull 'EXPERIMENT_VALIDATION.json'
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$mdPath = Join-Path $replayRootFull 'EXPERIMENT_VALIDATION.md'
@(
    '# Stop-And-Evolve Experiment Validation',
    '',
    "- status: PASS",
    "- replay_root: $replayRootFull",
    "- validation_json: $resultPath",
    '',
    '## Cases',
    (@($cases) | ForEach-Object { "- $_" }) -join "`n"
) -join "`n" | Set-Content -LiteralPath $mdPath -Encoding UTF8

$result | ConvertTo-Json -Depth 12

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
