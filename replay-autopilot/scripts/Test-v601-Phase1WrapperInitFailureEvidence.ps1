param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runReplayLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$runSliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'

$replayText = Get-Content -LiteralPath $runReplayLoop -Raw -Encoding UTF8
$sliceText = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8

Assert-True ($replayText -match 'phase1-wrapper') 'Run-ReplayLoop must capture Phase1 wrapper stdout/stderr logs.'
Assert-True ($replayText -match 'phase1_wrapper_exec\.v1') 'Run-ReplayLoop must write Phase1 wrapper exec metadata.'
Assert-True ($replayText.Contains('$oldPhase1ErrorActionPreference = $ErrorActionPreference')) 'Run-ReplayLoop must preserve parent ErrorActionPreference around Phase1 native invocation.'
Assert-True ($replayText.Contains('$ErrorActionPreference = ''Continue''')) 'Run-ReplayLoop must prevent native stderr from aborting before phase1.exec.json is written.'
Assert-True ($replayText -match 'invocation_error') 'Run-ReplayLoop must persist wrapper invocation errors in phase1.exec.json.'
Assert-True ($replayText -match 'wrapper_invocation_error') 'Run-ReplayLoop must copy wrapper invocation exceptions into the Phase1 stderr log.'
Assert-True ($replayText.Contains('failure_category = if ($phase1ExitCode -eq 95)')) 'Run-ReplayLoop must record exit 95 in wrapper metadata.'
Assert-True ($replayText.Contains('elseif ($phase1ExitCode -eq 95) { "phase1_init_failure" }')) 'Run-ReplayLoop must classify exit 95 as phase1_init_failure.'
Assert-True ($replayText -match 'PHASE1_INIT_FAILURE\.json') 'Run-ReplayLoop must read PHASE1_INIT_FAILURE evidence.'
Assert-True ($replayText -match 'Phase1 Init Blocker') 'Run-ReplayLoop must expose a specific Phase1 init blocker.'

Assert-True ($sliceText -match 'function Write-Phase1InitFailure') 'Run-SliceLoop must define init failure writer.'
Assert-True ($sliceText -match 'phase1_init_failure\.v1') 'Run-SliceLoop must persist structured init failure JSON.'
Assert-True ($sliceText.Contains('$phase1InitGateActive = $true')) 'Run-SliceLoop must enable a bounded init failure trap before initialization.'
Assert-True ($sliceText.Contains('$phase1InitGateActive = $false')) 'Run-SliceLoop must disable the init failure trap before normal slice execution.'
Assert-True ($sliceText -match 'PHASE1_INIT_EXCEPTION\.txt') 'Run-SliceLoop must persist unexpected init exceptions.'
Assert-True ($sliceText -match 'phase1_init_exception') 'Run-SliceLoop must classify unexpected init exceptions.'
Assert-True ($sliceText -match 'exit 95') 'Run-SliceLoop must use a stable nonzero exit for init gate failures.'
Assert-True ($sliceText -match 'required_path_missing') 'Run-SliceLoop must classify missing required paths before generic throw.'
Assert-True ($sliceText -match 'plan_schema_validation_failed') 'Run-SliceLoop must classify plan schema init gate failures.'
Assert-True ($sliceText -match 'pre_execution_constraint_check_failed') 'Run-SliceLoop must classify pre-execution init gate failures.'
Assert-True ($sliceText -match 'first_slice_dry_run_denied') 'Run-SliceLoop must classify first-slice dry-run init gate failures.'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($runReplayLoop, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-True (-not $parseErrors -or $parseErrors.Count -eq 0) ('Run-ReplayLoop parse errors: ' + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-True (-not $parseErrors -or $parseErrors.Count -eq 0) ('Run-SliceLoop parse errors: ' + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v601-' + [guid]::NewGuid().ToString('N'))
try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null

    $requirementSource = Join-Path $tempRoot 'requirement.md'
    $baselineIndex = Join-Path $tempRoot 'BASELINE_INDEX.md'
    $missingContextManifest = Join-Path $tempRoot 'MISSING_CONTEXT_MANIFEST.md'
    Set-Content -LiteralPath $requirementSource -Encoding UTF8 -Value '# Requirement'
    Set-Content -LiteralPath $baselineIndex -Encoding UTF8 -Value '# Baseline'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $runSliceLoop `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -ProjectRoot $worktree `
        -FeatureName 'phase1-init-test' `
        -RequirementSource $requirementSource `
        -OracleBranch 'oracle' `
        -OracleCommit 'oracle-commit' `
        -BaseCommit 'base-commit' `
        -BaselineIndex $baselineIndex `
        -ContextManifest $missingContextManifest `
        -Executor 'claude' `
        -RequireExecutor 'claude' `
        -MaxSlices 1 *> (Join-Path $tempRoot 'run-slice-loop.out.log')
    $sliceExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }

    Assert-True ($sliceExitCode -eq 95) "Run-SliceLoop missing required path should exit 95, got $sliceExitCode."

    $initFailurePath = Join-Path $replayRoot 'PHASE1_INIT_FAILURE.json'
    Assert-True (Test-Path -LiteralPath $initFailurePath) 'Run-SliceLoop must write PHASE1_INIT_FAILURE.json for init failures.'
    $initFailure = Get-Content -LiteralPath $initFailurePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$initFailure.reason -match 'required_path_missing') 'PHASE1_INIT_FAILURE.json must classify the missing required path.'

    $progressPath = Join-Path $replayRoot 'SLICE_PROGRESS.json'
    Assert-True (Test-Path -LiteralPath $progressPath) 'Run-SliceLoop must write SLICE_PROGRESS.json on init failure.'
    $progress = Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$progress.stopped) 'SLICE_PROGRESS.json must be stopped on init failure.'
    Assert-True ([string]$progress.stop_reason -match 'phase1_init_failure') 'SLICE_PROGRESS.json must include phase1_init_failure stop reason.'

    $contractPath = Join-Path $replayRoot 'RUNNER_ENFORCEMENT_CONTRACT.md'
    Assert-True (Test-Path -LiteralPath $contractPath) 'Run-SliceLoop must append runner contract evidence on init failure.'
    Assert-True ((Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8) -match 'phase1 init failure') 'RUNNER_ENFORCEMENT_CONTRACT.md must include init failure evidence.'
} finally {
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot) -and $tempRoot.StartsWith([System.IO.Path]::GetTempPath(), [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'Test-v601-Phase1WrapperInitFailureEvidence PASS'
