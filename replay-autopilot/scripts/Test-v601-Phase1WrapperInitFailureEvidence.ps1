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
Assert-True ($replayText.Contains('failure_category = if ($phase1ExitCode -eq 95)')) 'Run-ReplayLoop must record exit 95 in wrapper metadata.'
Assert-True ($replayText.Contains('elseif ($phase1ExitCode -eq 95) { "phase1_init_failure" }')) 'Run-ReplayLoop must classify exit 95 as phase1_init_failure.'
Assert-True ($replayText -match 'PHASE1_INIT_FAILURE\.json') 'Run-ReplayLoop must read PHASE1_INIT_FAILURE evidence.'
Assert-True ($replayText -match 'Phase1 Init Blocker') 'Run-ReplayLoop must expose a specific Phase1 init blocker.'

Assert-True ($sliceText -match 'function Write-Phase1InitFailure') 'Run-SliceLoop must define init failure writer.'
Assert-True ($sliceText -match 'phase1_init_failure\.v1') 'Run-SliceLoop must persist structured init failure JSON.'
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

Write-Host 'Test-v601-Phase1WrapperInitFailureEvidence PASS'
