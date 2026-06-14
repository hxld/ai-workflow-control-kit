param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$classifyScript = Join-Path $scriptRoot 'Classify-Feature.ps1'
$horizontalScript = Join-Path $scriptRoot 'verify-horizontal-slice.ps1'
$familyRouterScript = Join-Path $scriptRoot 'FamilyRouterAndCap.ps1'
$closureScript = Join-Path $scriptRoot 'Verify-SliceClosure.ps1'
$sliceVerifierScript = Join-Path $scriptRoot 'SliceVerifier.ps1'

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

function Write-JsonFile {
    param(
        [string]$Path,
        $Value,
        [int]$Depth = 12
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function New-TextFile {
    param(
        [string]$Path,
        [string]$Content
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

$tempRoot = Join-Path $env:TEMP ("replay-autopilot-v519-" + [System.Guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $tempRoot 'replay'
$worktree = Join-Path $tempRoot 'worktree'
New-Item -ItemType Directory -Path $replayRoot, $worktree -Force | Out-Null

try {
    & git -C $worktree init | Out-Null
    & git -C $worktree config user.email "replay-autopilot@example.invalid" | Out-Null
    & git -C $worktree config user.name "Replay Autopilot Eval" | Out-Null

    $prodFile1 = 'claim-core/src/main/java/com/acme/claim/core/task/ApplyTaskProcessor.java'
    $prodFile2 = 'claim-core/src/main/java/com/acme/claim/core/task/CalculateTaskProcessor.java'
    $testFile = 'claim-server/src/test/java/com/acme/claim/core/task/TaskProcessorRebuildTest.java'

    New-TextFile -Path (Join-Path $worktree $prodFile1) -Content @'
package com.acme.claim.core.task;

public class ApplyTaskProcessor {
    public String rebuildRequest(String sourceId, String existingValue) {
        if (existingValue != null && !existingValue.isEmpty()) {
            return existingValue;
        }
        return sourceId;
    }
}
'@
    New-TextFile -Path (Join-Path $worktree $prodFile2) -Content @'
package com.acme.claim.core.task;

public class CalculateTaskProcessor {
    public String rebuildRequest(String sourceId, String existingValue) {
        if (existingValue != null && !existingValue.isEmpty()) {
            return existingValue;
        }
        return sourceId;
    }
}
'@
    New-TextFile -Path (Join-Path $worktree $testFile) -Content @'
package com.acme.claim.core.task;

import org.junit.Test;
import static org.junit.Assert.assertEquals;

public class TaskProcessorRebuildTest {
    @Test
    public void rebuildRequestPreservesAndPropagatesFieldIntoInputDataPayload() {
        ApplyTaskProcessor processor = new ApplyTaskProcessor();
        assertEquals("P001", processor.rebuildRequest("P001", null));
    }
}
'@
    & git -C $worktree add $prodFile1 $prodFile2 $testFile | Out-Null

    $requirementPath = Join-Path $replayRoot 'requirement.md'
    New-TextFile -Path $requirementPath -Content @'
# Requirement

When a backend task processor rebuilds a downstream request, preserve and propagate the existing business identifier into the final input_data payload.

Must not add or change database schema.
Must not change frontend pages.
Must not introduce a new config switch.
Nullable compatibility proof must show no new mandatory validation/schema/frontend dependency is introduced.
'@

    Write-JsonFile -Path (Join-Path $replayRoot 'AUTOPILOT_RUN.json') -Value ([ordered]@{
        replay_root = $replayRoot
        worktree = $worktree
        requirement_source = $requirementPath
    })
    Write-JsonFile -Path (Join-Path $replayRoot 'ORACLE_DIFF_ANALYSIS.json') -Value ([ordered]@{
        total_additions = 4
        total_deletions = 0
        files = @(
            [ordered]@{ path = $prodFile1; is_production = $true; is_test = $false; additions = 2; deletions = 0 },
            [ordered]@{ path = $prodFile2; is_production = $true; is_test = $false; additions = 2; deletions = 0 }
        )
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $classifyScript -ReplayRoot $replayRoot -Worktree $worktree -RequirementSource $requirementPath | Out-Null
    $classification = Read-JsonFile (Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json')
    Assert-True 'classifier selects narrow backend read-only fix' ([string]$classification.classification -eq 'narrow_backend_read_only_fix')
    Assert-True 'classifier keeps payload family applicable when requirement names input_data payload' (
        @(($classification.verifier_adjustments.non_applicable_families) | Where-Object { [string]$_ -eq 'wire_payload_api_contract' }).Count -eq 0
    )
    Assert-True 'classifier lowers horizontal minimum to backend plus test' (
        [int]$classification.verifier_adjustments.horizontal_minimum -eq 2 -and
        @(($classification.verifier_adjustments.horizontal_required_categories) | Where-Object { @('Backend', 'Test') -contains [string]$_ }).Count -eq 2
    )
    Assert-True 'classifier marks stateful side effect not applicable' (
        @(($classification.verifier_adjustments.non_applicable_families) | Where-Object { [string]$_ -eq 'stateful_side_effect' }).Count -eq 1
    )
    Assert-True 'classifier ignores no-new schema/frontend dependency as a positive UI/schema signal' (
        -not [bool]$classification.evidence.positive_write_signal -and
        -not [bool]$classification.evidence.ui_requirement_signal
    )

    Write-JsonFile -Path (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Value ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'exact_contract_slice'
        coverage_delta = 60
        target_subsurface_or_carrier = 'ApplyTaskProcessor.rebuildRequest'
        production_boundary = 'backend task processor rebuilds downstream request input_data payload'
        proof_kind = 'api_contract'
        red_expectation = 'GREEN-only accepted for read-only field propagation after feature classification'
        implemented_files = @($prodFile1, $prodFile2, $testFile)
        current_slice_changed_files = @($prodFile1, $prodFile2, $testFile)
        touched_requirement_families = @('core_entry', 'automation_test_interface')
        closed_requirement_families = @('core_entry', 'automation_test_interface')
        gap_flags = @(
            'tdd_red_not_replayed',
            'red_phase_missing',
            'wrong_test_surface',
            'side_effect_evidence_missing',
            'side_effect_red_not_business_assertion',
            'side_effect_ledger_gap',
            'family_sibling_gap',
            'tooling_enforcement_stop'
        )
        tests = @(
            [ordered]@{
                phase = 'GREEN'
                command = 'mvn -pl claim-server -Dtest=TaskProcessorRebuildTest test'
                result = 'pass'
                evidence = 'BUILD SUCCESS; asserts rebuilt request carries identifier into input_data payload'
            }
        )
        behavior_test_charter = [ordered]@{
            proof_kind = 'api_contract'
            production_entry = 'ApplyTaskProcessor.rebuildRequest'
            state_or_output = 'input_data payload contains propagated identifier'
            must_not = 'does not write database, does not change frontend'
            RED_command = 'not required: feature classifier accepts GREEN-only read-only propagation evidence'
            expected_RED_failure = 'missing propagated identifier in rebuilt payload'
            GREEN_command = 'mvn -pl claim-server -Dtest=TaskProcessorRebuildTest test'
            evidence_file = $testFile
        }
        exact_contract_assertions = @(
            [ordered]@{
                literal = 'input_data payload contains propagated identifier'
                symbol_or_field = 'input_data.identifier'
                db_or_wire_or_display = 'wire'
                boundary_type = 'request_payload'
                production_boundary = 'backend task processor rebuilds downstream request input_data payload'
                closure_proof = 'TaskProcessorRebuildTest asserts propagated identifier'
                test_assertion = 'assertEquals("P001", processor.rebuildRequest("P001", null))'
                status = 'CLOSED'
                touched = $true
            }
        )
        side_effect_evidence = [ordered]@{
            status = 'NOT_APPLICABLE'
            entry_call = 'ApplyTaskProcessor.rebuildRequest'
            expected_writes_or_outputs = @('returns rebuilt request payload value')
            must_not_writes = @('database', 'frontend', 'config')
            test_name = 'TaskProcessorRebuildTest'
            red_result = 'NOT_RUN_GREEN_ONLY_ACCEPTED'
            green_result = 'PASS'
        }
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $horizontalScript -SliceResultFile (Join-Path $replayRoot 'SLICE_RESULT_01.json') -FeatureClassificationPath (Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json') | Out-Null
    Assert-True 'horizontal gate accepts Backend + Test for narrow backend fix' ($LASTEXITCODE -eq 0)

    Write-JsonFile -Path (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Value ([ordered]@{
        schema = 'requirement_family_ledger.v1'
        families = @(
            [ordered]@{ id = 'core_entry'; required = $true; status = 'OPEN'; weight = 100; touched_count = 0; closed_by = @(); open_sibling_surfaces = @(); required_proof_type = @('real_entry_behavior') },
            [ordered]@{ id = 'stateful_side_effect'; required = $true; status = 'OPEN'; weight = 90; touched_count = 0; closed_by = @(); open_sibling_surfaces = @(); required_proof_type = @('stateful_side_effect') },
            [ordered]@{ id = 'wire_payload_api_contract'; required = $true; status = 'OPEN'; weight = 80; touched_count = 0; closed_by = @(); open_sibling_surfaces = @(); required_proof_type = @('wire_payload') },
            [ordered]@{ id = 'generated_artifact_template_upload'; required = $true; status = 'OPEN'; weight = 50; touched_count = 0; closed_by = @(); open_sibling_surfaces = @(); required_proof_type = @('rendered_artifact') },
            [ordered]@{ id = 'automation_test_interface'; required = $true; status = 'OPEN'; weight = 40; touched_count = 0; closed_by = @(); open_sibling_surfaces = @(); required_proof_type = @('api_contract') }
        )
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $familyRouterScript -ReplayRoot $replayRoot -Ledger (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') | Out-Null
    $ledger = Read-JsonFile (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json')
    $statefulFamily = @($ledger.families | Where-Object { [string]$_.id -eq 'stateful_side_effect' } | Select-Object -First 1)[0]
    $artifactFamily = @($ledger.families | Where-Object { [string]$_.id -eq 'generated_artifact_template_upload' } | Select-Object -First 1)[0]
    $wireFamily = @($ledger.families | Where-Object { [string]$_.id -eq 'wire_payload_api_contract' } | Select-Object -First 1)[0]
    Assert-True 'family router marks stateful side effect not applicable' ((-not [bool]$statefulFamily.required) -and [string]$statefulFamily.status -eq 'NOT_APPLICABLE_BY_FEATURE_CLASSIFIER')
    Assert-True 'family router marks generated artifact not applicable' ((-not [bool]$artifactFamily.required) -and [string]$artifactFamily.status -eq 'NOT_APPLICABLE_BY_FEATURE_CLASSIFIER')
    Assert-True 'family router keeps wire payload required for payload requirement' ([bool]$wireFamily.required)

    Write-JsonFile -Path (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') -Value ([ordered]@{
        real_entry = 'ApplyTaskProcessor.rebuildRequest'
        selected_carrier = 'ApplyTaskProcessor.rebuildRequest'
        production_boundary = 'backend task processor rebuilds downstream request input_data payload'
        downstream_side_effect_or_output = 'returns rebuilt request payload value'
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        requires_side_effect_evidence = $false
        requires_exact_contract_assertions = $true
        authorization = 'ALLOW'
        issues = @()
    })
    Write-JsonFile -Path (Join-Path $replayRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_01.json') -Value ([ordered]@{
        required_for_this_slice = $true
        rows = @(
            [ordered]@{
                literal = 'input_data payload contains propagated identifier'
                symbol_or_field = 'input_data.identifier'
                db_or_wire_or_display = 'wire'
                boundary_type = 'request_payload'
                production_boundary = 'backend task processor rebuilds downstream request input_data payload'
                closure_proof = 'TaskProcessorRebuildTest asserts propagated identifier'
                test_assertion = 'assertEquals("P001", processor.rebuildRequest("P001", null))'
                status = 'CLOSED'
                touched = $true
                required = $true
                required_for_this_slice = $true
            }
        )
    })
    Write-JsonFile -Path (Join-Path $replayRoot 'GREEN_PHASE_TEST_EXECUTION_01.json') -Value ([ordered]@{
        execution_status = 'PASSED'
        exit_code = 0
        command = 'mvn -pl claim-server -Dtest=TaskProcessorRebuildTest test'
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $closureScript -ReplayRoot $replayRoot -Worktree $worktree -SliceResult (Join-Path $replayRoot 'SLICE_RESULT_01.json') -SliceIndex 1 | Out-Null
    $verify = Read-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_01.json')
    Assert-True 'closure verifier preserves positive adjusted coverage' ([int]$verify.adjusted_coverage_delta -gt 0)
    Assert-True 'closure verifier removes GREEN-only red and side-effect false blockers' (
        @(($verify.authorization_blockers) | Where-Object { @('red_phase_missing', 'side_effect_evidence_missing', 'side_effect_red_not_business_assertion', 'wrong_test_surface') -contains [string]$_ }).Count -eq 0
    )
    Assert-True 'closure verifier records feature-exempted flags' (
        @(($verify.verifier_adjustments_applied.exempted_gap_flags) | Where-Object { [string]$_ -eq 'side_effect_evidence_missing' }).Count -eq 1
    )

    & powershell -NoProfile -ExecutionPolicy Bypass -File $sliceVerifierScript -ReplayRoot $replayRoot -Worktree $worktree -SliceResult (Join-Path $replayRoot 'SLICE_RESULT_01.json') -SliceIndex 1 | Out-Null
    $authorization = Read-JsonFile (Join-Path $replayRoot 'SLICE_AUTHORIZATION_01.json')
    Assert-True 'slice verifier respects feature-exempted original slice flags' ([string]$authorization.status -eq 'PASS')

    $runSliceLoopText = Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    $startRoundText = Get-Content -LiteralPath (Join-Path $scriptRoot 'Start-ReplayRound.ps1') -Raw -Encoding UTF8
    Assert-True 'Run-SliceLoop invokes feature classifier and applies ledger calibration' (
        $runSliceLoopText.Contains('Classify-Feature.ps1') -and
        $runSliceLoopText.Contains('Apply-FeatureClassificationToLedger') -and
        $runSliceLoopText.Contains('FeatureClassificationPath')
    )
    Assert-True 'Start-ReplayRound exposes FEATURE_CLASSIFICATION to prompts' (
        $startRoundText.Contains('Classify-Feature.ps1') -and
        $startRoundText.Contains('FEATURE_CLASSIFICATION')
    )

    Write-Host 'v519 feature classifier narrow-backend calibration regression passed.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
