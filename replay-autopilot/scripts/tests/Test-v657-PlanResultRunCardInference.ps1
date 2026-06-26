#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v657-plan-result-run-card-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-server') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'

    @{
        families = @(@{
            id = 'core_entry'
            required = $true
            proof_required = @(
                'real_processor_entry_invoked',
                'successful_ai_apply_claim_response_reaches_auto_flow_orchestration',
                'manual_trigger_is_not_accepted_as_auto_flow_proof'
            )
            forbidden_proof = @('helper_only', 'static_only', 'mock_only', 'dto_only')
        })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8

    @{
        plan_status = 'PROCEED'
        expected_test_class = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessorAutoFlowTest'
        expected_test_method = 'handleTaskResponse_successAiApplyClaimResult_triggersAutoFlow'
        side_effects = @(
            'real processor entry invokes the auto-flow owner with caseId/task/result context',
            'completion log side effect is retained'
        )
        expected_assertions = @(
            'verify(aiAutoClaimFlowService).executeAutoFlow(eq(caseId), same(task), same(result))',
            'verify(caseExamineLogService).saveExamineLog(...)'
        )
        test_infrastructure_check = @{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = "mvn -f $worktree\pom.xml -pl claim-server -am test-compile"
            blocker_reason = 'none'
        }
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $replayRoot 'PLAN_RESULT.json') -Encoding UTF8

    @{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        selected_carrier = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse(AiApplyClaimApiTask,AiApplyClaimApiTaskResponse)'
        production_boundary = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        downstream_side_effect_or_output = 'real processor entry invokes the auto-flow owner with caseId/task/result context'
        red_expectation = 'business assertion fails before the auto-flow owner is invoked'
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    @{
        gate = 'callable_carrier_authorization'
        slice_index = 1
        authorization = 'ALLOW'
        can_proceed = $true
        selected_carrier = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse(AiApplyClaimApiTask,AiApplyClaimApiTaskResponse)'
        selected_real_entry = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        resolved_signature = @{ selected_carrier = @{ class_name = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor'; visibility = 'public'; formatted = 'void com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse(AiApplyClaimApiTask,AiApplyClaimApiTaskResponse)' } }
        blockers = @()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
selected_carrier: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse(AiApplyClaimApiTask,AiApplyClaimApiTaskResponse)
selected_real_entry: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse
first_red_test: claim-server/src/test/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessorAutoFlowTest.java#handleTaskResponse_successAiApplyClaimResult_triggersAutoFlow
downstream_output_or_side_effect: real processor entry invokes the auto-flow owner with caseId/task/result context
production_boundary: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse
red_assertion: business assertion fails before the auto-flow owner is invoked
expected_green_assertion: auto-flow owner receives caseId/task/result context
must_not_behavior: do not use helper/static/mock/dto-only proof as closure
green_change_boundary: real task processor invokes production auto-flow owner
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType exact_contract_slice | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'PLAN_RESULT.json-only runnable fields should authorize first slice'

    $runCard = Get-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_RUN_CARD.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $runnable = Get-Content -LiteralPath (Join-Path $replayRoot 'RUNNABLE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $preGate = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_SLICE_AUTHORIZATION_GATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $proofGate = Get-Content -LiteralPath (Join-Path $replayRoot 'PROOF_TYPE_POLICY_GATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $contextGate = Get-Content -LiteralPath (Join-Path $replayRoot 'REPLAY_CONTEXT_INDEX_CONTRACT_CHECK.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    Assert-True ([string]$runCard.status -eq 'ALLOW') 'run card must be ALLOW after command inference'
    Assert-True ([string]$runCard.existing_test_harness_module -eq 'claim-server') 'run card must infer claim-server harness from PLAN_RESULT.json'
    Assert-True ([string]$runCard.red_command -match '-f\s+"?.*worktree\\pom\.xml"?\s+-pl\s+claim-server\s+-am') 'run card red command must use isolated root POM and claim-server -am'
    Assert-True ([string]$runCard.red_command -match '-Dtest=com\.huize\.claim\.core\.ai\.task\.AiApplyClaimApiTaskProcessorAutoFlowTest#handleTaskResponse_successAiApplyClaimResult_triggersAutoFlow') 'run card red command must target expected class and method'
    Assert-True ([string]$runnable.status -eq 'AUTHORIZED') 'runnable authorization must pass after command inference'
    Assert-True ([string]$runnable.test_harness_module -eq 'claim-server') 'runnable authorization must expose inferred harness module'
    Assert-True ([string]$preGate.status -eq 'PASS') 'pre-slice authorization gate must pass inferred run card'
    Assert-True ([string]$proofGate.status -eq 'PASS') 'proof-type gate must not compare proof_required assertions as proof_type'
    Assert-True ([string]$proofGate.proof_type -eq 'real_entry_behavior') 'core_entry forced exact_contract_slice must normalize to real_entry_behavior'
    Assert-True ([string]$contextGate.status -eq 'PASS') 'context index contract check must pass with generated context index'
    Assert-True (Test-Path -LiteralPath (Join-Path $replayRoot 'replay-context-index.json')) 'pre-slice gate must generate minimal replay context index when missing'

    Write-Host 'v657 PLAN_RESULT run-card inference: PASS'
    exit 0
} catch {
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
