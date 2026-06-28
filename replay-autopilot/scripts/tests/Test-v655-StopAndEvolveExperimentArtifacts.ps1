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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v655-experiment-artifacts-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'src\main\java\demo') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>demo-root</artifactId><version>1</version></project>'

    $command = "mvn --% -f $(Join-Path $worktree 'pom.xml') -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test"
    @{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = 'demo.RealEntry.handle(String): String'
        selected_carrier = 'demo.RealEntry.handle(String): String'
        production_boundary = 'demo.RealEntry.handle(String): String'
        downstream_side_effect_or_output = 'returned payload value'
        red_expectation = 'business assertion fails before mapping is fixed'
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    @{
        gate = 'callable_carrier_authorization'
        slice_index = 1
        authorization = 'ALLOW'
        can_proceed = $true
        selected_carrier = 'demo.RealEntry.handle(String): String'
        selected_real_entry = 'demo.RealEntry.handle(String): String'
        resolved_signature = @{ selected_carrier = @{ class_name = 'demo.RealEntry'; visibility = 'public'; formatted = 'String demo.RealEntry.handle(String)' } }
        blockers = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    @{
        carrier_candidates = @(@{ signature = 'demo.RealEntry.handle(String): String' })
        real_entry_candidates = @(@{ signature = 'demo.RealEntry.handle(String): String' })
        callable_carriers = @(@{ signature = 'demo.RealEntry.handle(String): String' })
        failed_carrier_authorizations = @(@{ signature = 'demo.BadEntry.handle()'; reason = 'synthetic_carrier' })
        test_harness_modules = @('demo-harness')
        valid_maven_command_templates = @(@{ module = 'demo-harness'; command = $command })
        forbidden_proof_types_by_family = @{ core_entry = @('mock_only', 'static_only', 'helper_only', 'file_presence') }
        side_effect_probe_examples = @(@{ family = 'core_entry'; probe = 'returned payload value' })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'replay-context-index.json') -Encoding UTF8
    @{
        families = @(@{ id = 'core_entry'; required = $true; proof_required = 'real_entry_behavior' })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
- selected_carrier: demo.RealEntry.handle(String): String
- selected_real_entry: demo.RealEntry.handle(String): String
- first_red_test: RealEntryContractTest#returnsMappedPayload
- red_command: $command
- green_command: $command
- expected_red_failure: assertEquals("mapped", result) fails before mapping is fixed
- expected_green_assertion: assertEquals("mapped", result) passes through the existing entry
- red_assertion: assertEquals("mapped", result)
- downstream_output_or_side_effect: returned payload value
- production_boundary: demo.RealEntry.handle(String): String
- must_not_behavior: must not use helper-only or mock-only closure
- green_change_boundary: RealEntry.handle return mapping
- validation_command: $command
- entry_invocation_method: new RealEntry().handle("input")
"@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType real_entry_behavior | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'pre-slice experiment contract generator should pass valid first-slice plan'

    $sliceExecutionContract = Join-Path $replayRoot 'SLICE_EXECUTION_CONTRACT_01.json'
    $carrierInvocationContract = Join-Path $replayRoot 'CARRIER_INVOCATION_CONTRACT_01.json'
    Assert-True (Test-Path -LiteralPath $sliceExecutionContract) 'SLICE_EXECUTION_CONTRACT_01.json must be generated'
    Assert-True (Test-Path -LiteralPath $carrierInvocationContract) 'CARRIER_INVOCATION_CONTRACT_01.json must be generated'

    $execution = Get-Content -LiteralPath $sliceExecutionContract -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$execution.family_id -eq 'core_entry') 'slice execution contract must bind family_id'
    Assert-True ([string]$execution.production_entry_qn -match 'demo\.RealEntry') 'slice execution contract must bind production entry'
    Assert-True ([string]$execution.red_command -match '-f') 'slice execution contract must contain exact RED command'
    Assert-True ([string]$execution.green_command -match '-f') 'slice execution contract must contain exact GREEN command'

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'verify_first_slice_runnable_contract.ps1') `
        -Contract $sliceExecutionContract `
        -ReplayRoot $replayRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'first-slice runnable verifier must accept valid canonical contract'

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'verify_carrier_invocation_contract.ps1') `
        -Contract $sliceExecutionContract `
        -CarrierIndex (Join-Path $replayRoot 'replay-context-index.json') `
        -OutputPath $carrierInvocationContract | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'carrier invocation verifier must accept existing production carrier'
    $carrierInvocation = Get-Content -LiteralPath $carrierInvocationContract -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$carrierInvocation.resolved) 'carrier invocation contract must report resolved=true'
    Assert-True ([bool]$carrierInvocation.signature_match) 'carrier invocation contract must report signature_match=true'
    Assert-True ([bool]$carrierInvocation.test_invokes_entry) 'carrier invocation contract must report test_invokes_entry=true'
    Assert-True ([string]$carrierInvocation.carrier_origin -eq 'existing_production') 'carrier invocation contract must report existing_production origin'

    @{
        slice_index = 1
        slice_status = 'DONE'
        proof_kind = 'real_entry_behavior'
        production_boundary = 'demo.RealEntry.handle(String): String'
        side_effect_evidence = @{
            status = 'CLOSED'
            entry_call = 'new RealEntry().handle("input")'
            expected_writes_or_outputs = @('returned payload value')
        }
        behavior_test_charter = @{
            proof_kind = 'real_entry_behavior'
            production_entry = 'demo.RealEntry.handle(String): String'
            state_or_output = 'returned payload value'
            must_not = 'must not use helper-only or mock-only closure'
        }
        must_not_assertions = @('must not use helper-only or mock-only closure')
        gap_flags = @()
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'verify_family_proof_ledger.ps1') `
        -FamilyLedger (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') `
        -SliceContract $sliceExecutionContract `
        -SliceResult (Join-Path $replayRoot 'SLICE_RESULT_01.json') | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'family proof ledger must accept real-entry output proof'
    $familyProof = Get-Content -LiteralPath (Join-Path $replayRoot 'FAMILY_PROOF_LEDGER_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$familyProof.coverage_credit_authorized) 'family proof ledger must authorize coverage credit only after accepted proof'

    @(
        @{
            id = 'config_policy_threshold'
            required = $true
            proof_required = @('persist_free_review_amount', 'clear_updates_database', 'reject_invalid_amounts', 'auto_flow_gate_reads_config')
        }
    ) | ForEach-Object {
        @{ families = @($_) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8
    }
    @{
        schema = 'slice_execution_contract.v1'
        family_id = 'config_policy_threshold'
        production_entry_qn = 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl.save'
        side_effect_or_output_probe = 'persist_free_review_amount; clear_updates_database; reject_invalid_amounts; auto_flow_gate_reads_config'
        must_not_assertion = 'do not insert invalid zero-threshold config'
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sliceExecutionContract -Encoding UTF8
    @{
        slice_index = 1
        slice_status = 'DONE'
        proof_kind = 'real_entry_behavior'
        production_boundary = 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl.save'
        side_effect_evidence = @{
            status = 'CLOSED'
            entry_call = 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl.save'
            expected_writes_or_outputs = @('persist_free_review_amount', 'clear_updates_database', 'reject_invalid_amounts', 'auto_flow_gate_reads_config')
        }
        must_not_assertions = @('invalid zero-threshold request must not call mapper.insertSelective')
        gap_flags = @()
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'verify_family_proof_ledger.ps1') `
        -FamilyLedger (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') `
        -SliceContract $sliceExecutionContract `
        -SliceResult (Join-Path $replayRoot 'SLICE_RESULT_01.json') | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'family proof ledger must accept config real-entry behavior proof with config outputs'
    $configFamilyProof = Get-Content -LiteralPath (Join-Path $replayRoot 'FAMILY_PROOF_LEDGER_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$configFamilyProof.proof_family -eq 'config_policy_threshold') 'config family proof ledger must keep config proof family'
    Assert-True ([bool]$configFamilyProof.coverage_credit_authorized) 'config family proof ledger must authorize coverage credit after accepted config proof'

    @{
        families = @(@{ id = 'core_entry'; required = $true; proof_required = 'real_entry_behavior' })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8
    $execution | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sliceExecutionContract -Encoding UTF8
    @{
        slice_index = 1
        slice_status = 'DONE'
        proof_kind = 'helper_only'
        production_boundary = 'helper_only'
        side_effect_evidence = @{ status = 'CLOSED'; entry_call = 'helper_only'; expected_writes_or_outputs = @('static_only') }
        behavior_test_charter = @{ proof_kind = 'helper_only'; state_or_output = 'static_only'; must_not = '' }
        gap_flags = @('wrong_test_surface')
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'verify_family_proof_ledger.ps1') `
        -FamilyLedger (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') `
        -SliceContract $sliceExecutionContract `
        -SliceResult (Join-Path $replayRoot 'SLICE_RESULT_01.json') 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'family proof ledger must reject helper/static/wrong-surface proof'

    $runSliceText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    $promptText = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $scriptsRoot) 'prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
    Assert-True ($runSliceText -match 'verify_first_slice_runnable_contract\.ps1') 'Run-SliceLoop must call verify_first_slice_runnable_contract.ps1'
    Assert-True ($runSliceText -match 'verify_carrier_invocation_contract\.ps1') 'Run-SliceLoop must call verify_carrier_invocation_contract.ps1'
    Assert-True ($runSliceText -match 'Invoke-FamilyProofLedgerGate') 'Run-SliceLoop must invoke family proof ledger gate'
    Assert-True ($runSliceText -match 'verify_family_proof_ledger\.ps1') 'Run-SliceLoop must call verify_family_proof_ledger.ps1'
    Assert-True ($promptText -match 'SLICE_EXECUTION_CONTRACT_01\.json') 'Phase1 prompt must name canonical slice execution contract'
    Assert-True ($promptText -match 'CARRIER_INVOCATION_CONTRACT_01\.json') 'Phase1 prompt must name carrier invocation contract'
    Assert-True ($promptText -match 'FAMILY_PROOF_LEDGER_01\.json') 'Phase1 prompt must name family proof ledger'

    Write-Host 'v655 Stop-And-Evolve Experiment Artifacts: PASS'
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
