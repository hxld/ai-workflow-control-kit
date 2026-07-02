param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifyScript = Join-Path $scriptRoot 'Verify-SliceClosure.ps1'
$horizontalScript = Join-Path $scriptRoot 'verify-horizontal-slice.ps1'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "FAIL: $Name" }
        throw "FAIL: $Name`n$Details"
    }
    Write-Host "PASS: $Name"
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-Json {
    param([string]$Path, $Value, [int]$Depth = 20)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-autopilot-v528-" + [guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $tempRoot 'replay'
$worktree = Join-Path $tempRoot 'worktree'

try {
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null
    & git -C $worktree init | Out-Null
    & git -C $worktree config user.email "replay-autopilot@example.invalid" | Out-Null
    & git -C $worktree config user.name "Replay Autopilot Eval" | Out-Null

    $prodFile1 = 'example-core/src/main/java/com/acme/claim/core/ai/task/ExampleApplyClaimApiTaskProcessor.java'
    $prodFile2 = 'example-core/src/main/java/com/acme/claim/core/ai/task/ExampleCalculatorApiTaskProcessor.java'
    $testFile = 'example-server/src/test/java/com/acme/claim/core/ai/task/PolicyNumRebuildPathTest.java'

    Write-Text (Join-Path $worktree $prodFile1) @'
package com.acme.claim.core.ai.task;

public class ExampleApplyClaimApiTaskProcessor {
    public TaskData rebuildTaskData(Request request) {
        TaskData taskData = new TaskData();
        taskData.setPolicyNum(request.getPolicyNum());
        taskData.setInsureNum(request.getInsureNum());
        return taskData;
    }
}
'@
    Write-Text (Join-Path $worktree $prodFile2) @'
package com.acme.claim.core.ai.task;

public class ExampleCalculatorApiTaskProcessor {
    public TaskData rebuildTaskData(Request request) {
        TaskData taskData = new TaskData();
        taskData.setPolicyNum(request.getPolicyNum());
        taskData.setInsureNum(request.getInsureNum());
        return taskData;
    }
}
'@
    & git -C $worktree add $prodFile1 $prodFile2 | Out-Null
    & git -C $worktree commit -m 'baseline' | Out-Null

    (Get-Content -LiteralPath (Join-Path $worktree $prodFile1) -Raw -Encoding UTF8).
        Replace('return taskData;', 'taskData.setPolicyNum(request.getPolicyNum()); return taskData;') |
        Set-Content -LiteralPath (Join-Path $worktree $prodFile1) -Encoding UTF8
    (Get-Content -LiteralPath (Join-Path $worktree $prodFile2) -Raw -Encoding UTF8).
        Replace('return taskData;', 'taskData.setInsureNum(request.getInsureNum()); return taskData;') |
        Set-Content -LiteralPath (Join-Path $worktree $prodFile2) -Encoding UTF8

    Write-Text (Join-Path $worktree $testFile) @'
package com.acme.claim.core.ai.task;

import org.junit.Test;
import java.lang.reflect.Field;
import static org.junit.Assert.assertEquals;

public class PolicyNumRebuildPathTest {
    @Test
    public void testApplyClaimRebuildTaskData_SourceChainAssignsPolicyNumAndInsureNum() {
        ExampleApplyClaimApiTaskProcessor processor = new ExampleApplyClaimApiTaskProcessor();
        ExampleCalculatorApiTaskProcessor lossProcessor = new ExampleCalculatorApiTaskProcessor();
        assertEquals("P2024001", processor.rebuildTaskData(new Request("P2024001", "I2024001")).getPolicyNum());
        assertEquals("I2024001", lossProcessor.rebuildTaskData(new Request("P2024001", "I2024001")).getInsureNum());
    }
}
'@

    Write-Json (Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json') ([ordered]@{
        schema = 'feature_classification.v1'
        classification = 'narrow_backend_read_only_fix'
        base_classification = 'narrow_backend_fix'
        read_only = $true
        verifier_adjustments = [ordered]@{
            horizontal_minimum = 2
            horizontal_required_categories = @('Backend', 'Test')
            stateful_side_effect_required = $false
            red_phase_required = $false
            green_only_evidence_accepted = $true
        }
    })

    Write-Json (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') ([ordered]@{
        authorization = 'ALLOW'
        selected_carrier = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
        real_entry = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
        downstream_side_effect_or_output = 'rebuildTaskData preserves policyNum and insureNum'
        requires_side_effect_evidence = $false
        requires_exact_contract_assertions = $false
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        issues = @()
    })

    Write-Json (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{
        required_source_chain = $true
        next_required_slice = [ordered]@{
            must_touch_files = @($prodFile1, $prodFile2)
            forbidden_proof = @('synthetic_carrier')
        }
    })

    Write-Text (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
first_red_test: testApplyClaimRebuildTaskData_SourceChainAssignsPolicyNumAndInsureNum
selected_carrier: ExampleApplyClaimApiTaskProcessor and ExampleCalculatorApiTaskProcessor
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
'@
    Write-Text (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') @'
first_red_test: testApplyClaimRebuildTaskData_SourceChainAssignsPolicyNumAndInsureNum
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
'@

    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    Write-Json $sliceResultPath ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'exact_contract_slice'
        coverage_delta = 100
        target_subsurface_or_carrier = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
        production_boundary = 'ExampleApplyClaimApiTaskProcessor.java:406-407, ExampleCalculatorApiTaskProcessor.java:374-375'
        proof_kind = 'real_entry_behavior'
        red_expectation = 'GREEN-ONLY scenario - baseline contains oracle fix'
        implemented_files = @($testFile)
        current_slice_changed_files = @($testFile)
        tests = @([ordered]@{
            command = 'mvn -pl example-server -am -Dtest=PolicyNumRebuildPathTest test'
            phase = 'GREEN'
            result = 'pass'
            evidence = 'Tests run: 1, Failures: 0, Errors: 0, Skipped: 0'
        })
        exact_contract_assertions = @(
            [ordered]@{
                literal = 'taskData.setPolicyNum(request.getPolicyNum())'
                symbol_or_field = 'taskData.setPolicyNum()'
                db_or_wire_or_display = 'behavior'
                boundary_type = 'behavior'
                production_boundary = 'ExampleApplyClaimApiTaskProcessor.java:406'
                closure_proof = 'Production boundary contains request to taskData assignment'
                test_assertion = 'assertEquals("P2024001", result.getPolicyNum()) and assertEquals("I2024001", result.getInsureNum())'
                status = 'CLOSED'
                touched = $true
            }
        )
        side_effect_evidence = [ordered]@{
            status = 'CLOSED'
            entry_call = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
            expected_writes_or_outputs = @(
                'taskData.setPolicyNum(request.getPolicyNum())',
                'taskData.setInsureNum(request.getInsureNum())'
            )
            must_not_writes = @()
            red_result = 'NOT_RUN'
            green_result = 'PASS'
        }
        behavior_test_charter = [ordered]@{
            proof_kind = 'real_entry_behavior'
            production_entry = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
            state_or_output = 'taskData.getPolicyNum() and taskData.getInsureNum() correctly populated'
            must_not = ''
            RED_command = 'N/A (GREEN-ONLY scenario)'
            expected_RED_failure = 'N/A'
            GREEN_command = 'mvn -pl example-server -am -Dtest=PolicyNumRebuildPathTest test'
            evidence_file = $testFile
        }
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        gap_flags = @()
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $horizontalScript -SliceResultFile $sliceResultPath -FeatureClassificationPath (Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json') | Out-Null
    Assert-True 'horizontal_accepts_backend_plus_test_from_slice_files' ($LASTEXITCODE -eq 0)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ReplayRoot $replayRoot -Worktree $worktree -SliceResult $sliceResultPath -SliceIndex 1 | Out-Null
    Assert-True 'verify_script_exits_zero' ($LASTEXITCODE -eq 0)

    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $verifyJson = $verify | ConvertTo-Json -Depth 20
    Assert-True 'verifier_passes_real_diff_even_when_agent_lists_only_test_file' ([string]$verify.verification_status -eq 'PASS') $verifyJson
    Assert-True 'verifier_marks_behavior_evidence_true' ([bool]$verify.has_behavior_evidence) $verifyJson
    Assert-True 'verifier_authorizes_synthesis' ([bool]$verify.authorized_for_synthesis) $verifyJson
    Assert-True 'verifier_credits_full_delta' ([int]$verify.adjusted_coverage_delta -eq 100) $verifyJson
    Assert-True 'verifier_uses_real_carrier' ([string]$verify.carrier_origin -eq 'declared_or_real_carrier') $verifyJson
    Assert-True 'verifier_has_no_false_blockers' (
        @(($verify.authorization_blockers) | Where-Object {
            @('proof_type_mismatch', 'synthetic_carrier', 'wrong_test_surface', 'shallow_module', 'behavior_evidence_missing') -contains [string]$_
        }).Count -eq 0
    ) $verifyJson
    Assert-True 'verifier_backfills_production_files_from_git_status' (
        @(($verify.implemented_files) | Where-Object { [string]$_ -match 'example-core/src/main/java/.+ExampleApplyClaimApiTaskProcessor\.java' }).Count -eq 1
    ) $verifyJson

    Write-Host 'PASS: v528 read-only verifier accepts real diff and behavior evidence'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
