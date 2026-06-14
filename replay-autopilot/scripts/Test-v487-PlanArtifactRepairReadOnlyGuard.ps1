param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-artifact-repair-guard-v487-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8

    Assert-True 'repair_prompt_marks_existing_plan_result_read_only' (
        $runLoopText.Contains('``PLAN_RESULT.json`` and ``IMPLEMENTATION_CONTRACT.md`` are read-only when they already exist') -and
        $runLoopText.Contains('preserve their existing ``test_infrastructure_check`` exactly')
    )
    Assert-True 'repair_prompt_only_creates_plan_result_when_missing' (
        $runLoopText.Contains('PLAN_RESULT.json: create this only if it is listed under Missing Artifacts') -and
        $runLoopText.Contains('If it already exists, it is read-only')
    )
    Assert-True 'runner_snapshots_existing_plan_artifacts_before_repair' (
        $runLoopText.Contains('$repairGuardDir') -and
        $runLoopText.Contains('$repairGuardedArtifacts') -and
        $runLoopText.Contains('before_hash')
    )
    Assert-True 'runner_restores_unauthorized_repair_changes' (
        $runLoopText.Contains('RESTORED_UNAUTHORIZED_MODIFICATIONS') -and
        $runLoopText.Contains('PLAN_ARTIFACT_REPAIR_GUARD.json') -and
        $runLoopText.Contains('RESTORE_AND_CONTINUE')
    )
    Assert-True 'runner_guard_does_not_snapshot_missing_artifacts' (
        $runLoopText.Contains('if ($missingPlanArtifacts -contains $artifact)') -and
        $runLoopText.Contains('continue')
    )

    Write-Host 'PASS: v487 plan artifact repair read-only guard'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
