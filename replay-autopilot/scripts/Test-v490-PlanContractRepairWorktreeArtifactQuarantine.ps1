param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-worktree-artifact-quarantine-v490-" + [guid]::NewGuid().ToString('N'))

try {
    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8

    Assert-True 'runner_defines_plan_artifact_worktree_quarantine' (
        $runLoopText.Contains('function Resolve-PlanArtifactWorktreeLeak') -and
        $runLoopText.Contains('PLAN_WORKTREE_ARTIFACT_QUARANTINE.json')
    )
    Assert-True 'plan_contract_repair_prompt_forbids_relative_cwd_writes' (
        $runLoopText.Contains('The current working directory may be the isolated worktree') -and
        $runLoopText.Contains('Every write must use an absolute path under the artifact root above')
    )
    Assert-True 'runner_quarantines_after_contract_repair_and_before_phase1_clean' (
        $runLoopText.Contains("-Stage 'PlanContractRepair'") -and
        $runLoopText.Contains("-Stage 'PrePhase1WorktreeClean'")
    )

    $functionBlock = [regex]::Match(
        $runLoopText,
        '(?s)function Resolve-PlanArtifactWorktreeLeak.+?(?=function Repair-PolicyRebuildPlanHarness)'
    ).Value
    Assert-True 'quarantine_function_extractable' (-not [string]::IsNullOrWhiteSpace($functionBlock))
    Invoke-Expression $functionBlock

    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null

    'root charter' | Set-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER.md') -Encoding UTF8
    'worktree charter' | Set-Content -LiteralPath (Join-Path $worktree 'TEST_CHARTER.md') -Encoding UTF8
    $changed = Resolve-PlanArtifactWorktreeLeak -ReplayRoot $replayRoot -Worktree $worktree -ArtifactNames @('TEST_CHARTER.md') -Stage 'unit-test-existing-root'
    Assert-True 'quarantine_returns_true_for_existing_root_duplicate' ([bool]$changed)
    Assert-True 'quarantine_removes_worktree_duplicate' (-not (Test-Path -LiteralPath (Join-Path $worktree 'TEST_CHARTER.md')))
    Assert-True 'quarantine_preserves_existing_replay_root_artifact' ((Get-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER.md') -Raw -Encoding UTF8).Trim() -eq 'root charter')

    'worktree replay plan' | Set-Content -LiteralPath (Join-Path $worktree 'REPLAY_PLAN.md') -Encoding UTF8
    $changedMissing = Resolve-PlanArtifactWorktreeLeak -ReplayRoot $replayRoot -Worktree $worktree -ArtifactNames @('REPLAY_PLAN.md') -Stage 'unit-test-missing-root'
    Assert-True 'quarantine_returns_true_for_missing_root_artifact' ([bool]$changedMissing)
    Assert-True 'quarantine_copies_missing_artifact_to_replay_root' ((Get-Content -LiteralPath (Join-Path $replayRoot 'REPLAY_PLAN.md') -Raw -Encoding UTF8).Trim() -eq 'worktree replay plan')
    Assert-True 'quarantine_removes_copied_worktree_artifact' (-not (Test-Path -LiteralPath (Join-Path $worktree 'REPLAY_PLAN.md')))

    $quarantine = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_WORKTREE_ARTIFACT_QUARANTINE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'quarantine_writes_audit_json' ($quarantine.status -eq 'QUARANTINED' -and @($quarantine.actions).Count -gt 0)

    Write-Host 'PASS: v490 plan contract repair worktree artifact quarantine'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
