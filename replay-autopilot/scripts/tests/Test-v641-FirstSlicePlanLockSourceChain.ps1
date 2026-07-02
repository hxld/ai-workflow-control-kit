param()

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$runSlicePath = Join-Path $repoRoot 'scripts\Run-SliceLoop.ps1'
$preparePath = Join-Path $repoRoot 'scripts\Prepare-SliceEvidenceContracts.ps1'
$callableGatePath = Join-Path $repoRoot 'scripts\Invoke-CallableCarrierAuthorization.ps1'

$runSliceText = Get-Content -LiteralPath $runSlicePath -Raw -Encoding UTF8
$prepareText = Get-Content -LiteralPath $preparePath -Raw -Encoding UTF8
$callableGateText = Get-Content -LiteralPath $callableGatePath -Raw -Encoding UTF8

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

Assert-Contains `
    -Text $runSliceText `
    -Pattern 'function Get-PlanField' `
    -Message 'Run-SliceLoop.ps1 must parse first-slice plan-lock fields before applying source-chain override.'

Assert-Contains `
    -Text $runSliceText `
    -Pattern 'first_red_test' `
    -Message 'Run-SliceLoop.ps1 plan-lock guard must inspect first_red_test.'

Assert-Contains `
    -Text $runSliceText `
    -Pattern 'source-chain override skipped' `
    -Message 'Run-SliceLoop.ps1 must emit evidence when source-chain override is skipped.'

Assert-Contains `
    -Text $prepareText `
    -Pattern 'firstSlicePlanLocksNonSourceCarrier' `
    -Message 'Prepare-SliceEvidenceContracts.ps1 must keep S1 core_entry carrier/test locked to the plan when source-chain is a different later slice.'

Assert-Contains `
    -Text $prepareText `
    -Pattern 'source_chain_contract_preserved_for_later_slice_plan_lock_kept' `
    -Message 'Prepare-SliceEvidenceContracts.ps1 must write a warning when it preserves source-chain for later slices instead of overriding S1.'

Assert-Contains `
    -Text $runSliceText `
    -Pattern 'Invoke-CallableCarrierAuthorizationGate' `
    -Message 'Run-SliceLoop.ps1 must hard-gate callable carrier authorization before executor.'

Assert-Contains `
    -Text $callableGateText `
    -Pattern 'verify_carrier_signature.py' `
    -Message 'Callable carrier authorization gate must call the signature verifier.'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v641-plan-lock-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    $worktree = Join-Path $tempRoot 'worktree'
    $sourceDir = Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task'
    New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

    @'
package com.example.project.core.ai.task;

public class ExampleApplyClaimApiTaskProcessor {
    private ExampleApplyClaimTaskData rebuildTaskData(Long caseId) {
        return null;
    }

    public void doIt() {
    }

    public void handleTaskResponse(ExampleApplyClaimApiTask example-featureApiTask, ExampleApplyClaimApiTaskResponse taskResponse) {
    }
}
'@ | Set-Content -LiteralPath (Join-Path $sourceDir 'ExampleApplyClaimApiTaskProcessor.java') -Encoding UTF8

    @'
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorAutoFlowTest.java#eligibleSystemTriggeredAiResultStartsAutoFlow
selected_carrier: com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.handleTaskResponse(ExampleApplyClaimApiTask,ExampleApplyClaimApiTaskResponse)
selected_real_entry: com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.doIt
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    @'
plan_status: PROCEED
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorAutoFlowTest.java#eligibleSystemTriggeredAiResultStartsAutoFlow
selected_carrier: com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.handleTaskResponse(ExampleApplyClaimApiTask,ExampleApplyClaimApiTaskResponse)
selected_real_entry: com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.doIt
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'IMPLEMENTATION_CONTRACT.md') -Encoding UTF8

    $sourceChain = [pscustomobject]@{
        required_source_chain = $true
        next_required_slice = [pscustomobject]@{
            carrier = 'TaskProcessor rebuildTaskData -> source.caseId -> InputData.case_id'
            entry = 'AbstractExampleApiTaskProcessor.rebuildTaskData(Long caseId)'
            test_name = 'AbstractExampleApiTaskProcessorTest.testRebuildTaskData_PreservesSourceFields'
            slice_type = 'exact_contract_slice'
        }
    }

    $forced = [pscustomobject]@{
        family_id = 'core_entry'
        slice_type = 'tracer_bullet'
        target_sibling_surface = 'com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.doIt'
        reason = 'rank1 core entry'
    }

    $planParts = New-Object System.Collections.Generic.List[string]
    $planParts.Add((Get-Content -LiteralPath (Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md') -Raw -Encoding UTF8)) | Out-Null
    $planParts.Add((Get-Content -LiteralPath (Join-Path $tempRoot 'IMPLEMENTATION_CONTRACT.md') -Raw -Encoding UTF8)) | Out-Null
    $planText = @($planParts) -join "`n"
    $plannedCarrier = if ($planText -match '(?m)^\s*selected_carrier\s*:\s*(.+?)\s*$') { $matches[1].Trim() } else { '' }
    $plannedFirstRedTest = if ($planText -match '(?m)^\s*first_red_test\s*:\s*(.+?)\s*$') { $matches[1].Trim() } else { '' }
    $sourceText = @($sourceChain.next_required_slice.carrier, $sourceChain.next_required_slice.entry, $sourceChain.next_required_slice.test_name) -join "`n"
    $plannedText = @($plannedCarrier, $plannedFirstRedTest) -join "`n"

    $firstSlicePlanLocksNonSourceCarrier = (
        -not [string]::IsNullOrWhiteSpace($plannedCarrier) -and
        -not [string]::IsNullOrWhiteSpace($sourceText) -and
        $sourceText -notmatch [regex]::Escape($plannedCarrier) -and
        $plannedText -notmatch '(?i)\b(rebuildTaskData|source_chain|source[-_\s]?chain|source field|wire field|input_data)\b'
    )
    if (-not $firstSlicePlanLocksNonSourceCarrier) {
        throw 'Fixture should reproduce S1 plan-lock conflict: plan carrier handleTaskResponse differs from source-chain rebuildTaskData.'
    }

    $selectedCarrier = $plannedCarrier
    $sourceApplies = (
        -not $firstSlicePlanLocksNonSourceCarrier -and
        [string]$sourceChain.next_required_slice.slice_type -eq 'exact_contract_slice' -and
        (
            [string]$forced.target_sibling_surface -eq [string]$sourceChain.next_required_slice.carrier -or
            [string]$forced.target_sibling_surface -match '(?i)CaseRoute|Insure|RequestBuildContext|ExampleBaseRequest|source' -or
            [string]$forced.family_id -eq 'core_entry'
        )
    )
    if ($sourceApplies) {
        $selectedCarrier = [string]$sourceChain.next_required_slice.entry
    }

    if ($selectedCarrier -ne $plannedCarrier) {
        throw "S1 selected carrier was overwritten by source-chain contract: $selectedCarrier"
    }

    $carrierObject = [ordered]@{
        selected_carrier = 'com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.handleTaskResponse(ExampleApplyClaimApiTask,ExampleApplyClaimApiTaskResponse)'
        real_entry = 'com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.handleTaskResponse(ExampleApplyClaimApiTask,ExampleApplyClaimApiTaskResponse)'
        downstream_side_effect_or_output = 'auto flow side effect'
    }
    $carrierObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $callableGatePath -ReplayRoot $tempRoot -Worktree $worktree -SliceIndex 1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $publicResult = Get-Content -LiteralPath (Join-Path $tempRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Raw -Encoding UTF8
        throw "Public handleTaskResponse carrier should be authorized: $publicResult"
    }

    @'
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/AbstractExampleApiTaskProcessorTest.java#testRebuildTaskData_PreservesSourceFields
selected_carrier: com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long)
selected_real_entry: com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.handleTaskResponse(ExampleApplyClaimApiTask,ExampleApplyClaimApiTaskResponse)
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $carrierObject.selected_carrier = 'com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long)'
    $carrierObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $callableGatePath -ReplayRoot $tempRoot -Worktree $worktree -SliceIndex 1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        throw 'Private rebuildTaskData carrier should be blocked before RED.'
    }
    $privateResult = Get-Content -LiteralPath (Join-Path $tempRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($privateResult.blockers) -notcontains 'carrier_private') {
        throw "Private rebuildTaskData should report carrier_private blocker: $($privateResult | ConvertTo-Json -Depth 8)"
    }
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'v641 first-slice plan-lock source-chain guard test passed.'
