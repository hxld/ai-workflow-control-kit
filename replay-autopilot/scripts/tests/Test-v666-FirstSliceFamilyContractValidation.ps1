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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v666-first-slice-family-contract-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-server') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'

    @{
        families = @(
            @{
                id = 'core_entry'
                required = $true
                status = 'OPEN'
                weight = 100
                recommended_slice_type = 'tracer_bullet'
                touched_count = 0
                first_executable_carrier = 'demo.CoreFacade.batchQuery'
                proof_required = @('invoke_existing_facade_entry')
                forbidden_proof = @('helper_only', 'static_only', 'mock_only')
                coverage_cap_if_open = 80
                open_sibling_surfaces = @('demo.CoreFacade.batchQuery')
                open_sibling_count = 1
            },
            @{
                id = 'stateful_side_effect'
                required = $true
                status = 'OPEN'
                weight = 95
                recommended_slice_type = 'stateful_success_slice'
                touched_count = 0
                first_executable_carrier = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
                proof_required = @('processor_entry_invocation', 'persisted_compensation_or_status_effect')
                forbidden_proof = @('helper_only', 'static_only', 'mock_only')
                coverage_cap_if_open = 40
                open_sibling_surfaces = @('com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse')
                open_sibling_count = 1
            }
        )
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8

    @{
        plan_status = 'PROCEED'
        expected_test_class = 'AiApplyClaimApiTaskProcessorTest'
        expected_test_method = 'handleTaskResponsePersistsBusinessRowsAndAiLog'
        test_infrastructure_check = @{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            blocker_reason = 'none'
        }
        expected_side_effects = @(
            'insert_or_update t_ai_claim_review_material',
            'insert case_examine_log with AI_ACCEPT_LOG_TAG'
        )
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $replayRoot 'PLAN_RESULT.json') -Encoding UTF8

    @{
        schema_version = 1
        slice_index = 1
        forced_requirement_family = 'stateful_side_effect'
        forced_slice_type = 'stateful_success_slice'
        authorization = 'ALLOW'
        real_entry = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        selected_carrier = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        production_boundary = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        downstream_side_effect_or_output = 'real processor invocation stores AI business result tables and writes AI processing log'
        red_expectation = 'business assertion fails before handleTaskResponse reaches all required persistence/log boundaries'
        issues = @()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    @{
        gate = 'callable_carrier_authorization'
        slice_index = 1
        authorization = 'ALLOW'
        can_proceed = $true
        selected_carrier = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        selected_real_entry = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        resolved_signature = @{
            selected_carrier = @{
                class_name = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor'
                visibility = 'public'
                formatted = 'void com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse(AiApplyClaimApiTask, AiApplyClaimApiTaskResponse)'
            }
        }
        blockers = @()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1-core-stateful-ai-apply-response
highest_weight_open_gate: stateful_side_effect
first_slice_family: stateful_side_effect
first_red_test: claim-server/src/test/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessorTest.java#handleTaskResponsePersistsBusinessRowsAndAiLog
selected_real_entry: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse
selected_carrier: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse
minimum_side_effect_or_blocker: real processor invocation stores AI business result tables through persistence boundaries and writes AI processing log
production_boundary: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java:handleTaskResponse, saveOrUpdateReviewMaterial, CaseExamineLogService.saveExamineLog
red_expectation: RED fails before implementation if handleTaskResponse does not reach all required AI business persistence boundaries and AI log side effect
expected_green_assertion: real processor invocation stores AI business result tables and writes AI processing log
proof_kind: stateful_side_effect
must_not_behavior: do not use helper/static/mock/dto-only proof as closure
'@

    $runnerSubset = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    $start = $runnerSubset.IndexOf('function Read-TextIfExists')
    $end = $runnerSubset.IndexOf('function Test-RequiredFamilyOpenInLedger')
    Assert-True ($start -ge 0 -and $end -gt $start) 'Run-SliceLoop function extraction anchors must exist'
    $functionText = @'
function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}
'@ + "`n" + $runnerSubset.Substring($start, $end - $start)
    $extractPath = Join-Path $tempRoot 'run-slice-functions.ps1'
    Write-Utf8 $extractPath $functionText
    . $extractPath

    $ledger = Get-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $forced = Get-ForcedFamilyDecision -Ledger $ledger -SliceIndex 1 -ReplayRoot $replayRoot
    Assert-True ([string]$forced.family_id -eq 'stateful_side_effect') 'S1 router must preserve FIRST_SLICE_PROOF_PLAN first_slice_family'

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily stateful_side_effect `
        -ForcedSliceType stateful_success_slice | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'pre-slice experiment contracts must pass stateful first-slice plan'

    $charter = Get-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $proofGate = Get-Content -LiteralPath (Join-Path $replayRoot 'PROOF_TYPE_POLICY_GATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $runCard = Get-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_RUN_CARD.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $firstContract = Get-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_EXECUTABLE_CONTRACT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $slicePlan = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_PLAN_CONTRACT_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    Assert-True ([string]$charter.family_id -eq 'stateful_side_effect') 'test charter must bind selected stateful family'
    Assert-True ([string]$charter.proof_type -eq 'stateful_side_effect') 'test charter proof_type must match selected stateful family'
    Assert-True ([string]$slicePlan.required_proof_type -eq 'stateful_side_effect') 'slice plan required proof type must remain stateful'
    Assert-True ([string]$runCard.required_proof_type -eq 'stateful_side_effect') 'run card required proof type must remain stateful'
    Assert-True ([string]$firstContract.required_proof_type -eq 'stateful_side_effect') 'first executable contract required proof type must remain stateful'
    Assert-True ([string]$proofGate.status -eq 'PASS') 'proof-type gate must use contract fallback when ledger lacks required_proof_type'
    Assert-True ([string]$proofGate.required_proof_type -eq 'stateful_side_effect') 'proof-type gate must expose fallback required proof type'
    Assert-True ([string]$firstContract.red_command -match '(?i)^mvn\s+--%') 'generated RED command must include PowerShell stop-parsing marker'
    Assert-True ([string]$firstContract.red_command -match '-pl claim-server -am') 'generated RED command must include reactor -am with module'
    Assert-True ([string]$firstContract.red_command -match '-Dtest=AiApplyClaimApiTaskProcessorTest#handleTaskResponsePersistsBusinessRowsAndAiLog') 'generated RED command must target inferred test selector'

    $contractBefore = Get-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_EXECUTABLE_CONTRACT.json') -Raw -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'validate-first-slice-contract.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -Slice 1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'first-slice contract validation must pass without regenerating artifacts'
    $contractAfter = Get-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_EXECUTABLE_CONTRACT.json') -Raw -Encoding UTF8
    Assert-True ($contractBefore -eq $contractAfter) 'first-slice validation must not rewrite pre-generated contract by default'

    Write-Host 'v666 first-slice family and contract validation: PASS'
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
