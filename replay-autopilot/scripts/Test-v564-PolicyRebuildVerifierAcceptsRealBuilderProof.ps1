param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

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

$scriptRoot = Split-Path -Parent $PSCommandPath
$sliceVerifier = Join-Path $scriptRoot 'SliceVerifier.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-autopilot-v564-" + [guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $tempRoot 'replay'
$worktree = Join-Path $tempRoot 'worktree'

try {
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null
    & git -C $worktree init | Out-Null
    & git -C $worktree config user.email "replay-autopilot@example.invalid" | Out-Null
    & git -C $worktree config user.name "Replay Autopilot Eval" | Out-Null

    $applyFile = 'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java'
    $lossFile = 'example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java'
    $testFile = 'example-server/src/test/java/com/example/project/core/ai/task/ExampleApiTaskProcessorRebuildTest.java'

    Write-Text (Join-Path $worktree $applyFile) @'
package com.example.project.core.ai.task;

public class ExampleApplyClaimApiTaskProcessor {
    private Object rebuildTaskData(Long caseId) {
        return null;
    }
}
'@
    Write-Text (Join-Path $worktree $lossFile) @'
package com.example.project.core.ai.task;

public class ExampleCalculatorApiTaskProcessor {
    private Object rebuildTaskData(Long caseId) {
        return null;
    }
}
'@
    & git -C $worktree add $applyFile $lossFile | Out-Null
    & git -C $worktree commit -m 'baseline' | Out-Null

    Write-Text (Join-Path $worktree $applyFile) @'
package com.example.project.core.ai.task;

public class ExampleApplyClaimApiTaskProcessor {
    private Object rebuildTaskData(Long caseId) {
        req.setPolicyNum(buildContext.getPolicyNum());
        req.setInsureNum(buildContext.getInsureNum());
        return taskData;
    }
}
'@
    Write-Text (Join-Path $worktree $lossFile) @'
package com.example.project.core.ai.task;

public class ExampleCalculatorApiTaskProcessor {
    private Object rebuildTaskData(Long caseId) {
        req.setPolicyNum(buildContext.getPolicyNum());
        req.setInsureNum(buildContext.getInsureNum());
        return taskData;
    }
}
'@
    Write-Text (Join-Path $worktree $testFile) @'
package com.example.project.core.ai.task;

import com.example.project.core.ai.helper.ExampleDataAssemblyHelper;
import com.example.project.core.ai.helper.RequestBuildContext;
import org.junit.Assert;
import org.junit.Test;

public class ExampleApiTaskProcessorRebuildTest {
    private static final Long TEST_CASE_ID = 12345L;
    private static final String TEST_POLICY_NUM = "P2024001X";
    private static final String TEST_INSURE_NUM = "I2024001Y";

    @Test
    public void testRebuildApplyClaim_PreservesPolicyNum() throws Exception {
        ExampleDataAssemblyHelper.RequestBuildFunction builder = null;
        RequestBuildContext buildContext = new RequestBuildContext();
        buildContext.setCaseId(TEST_CASE_ID);
        buildContext.setPolicyNum(TEST_POLICY_NUM);
        buildContext.setInsureNum(TEST_INSURE_NUM);
        when(example-featureDataAssemblyHelper.buildRequestCommon(anyLong(), any(), anyBoolean(), anyBoolean(), anyBoolean(), anyBoolean(), anyBoolean(), anyBoolean(), any()))
                .thenAnswer(invocation -> builder.apply(buildContext));
        Object taskData = applyClaimRebuildMethod.invoke(applyClaimProcessor, TEST_CASE_ID);
        Assert.assertEquals(TEST_POLICY_NUM, taskData.getPolicyNum());
        Assert.assertEquals(TEST_INSURE_NUM, taskData.getInsureNum());
    }
}
'@

    Write-Json (Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json') ([ordered]@{
        schema = 'feature_classification.v1'
        classification = 'narrow_backend_read_only_fix'
        base_classification = 'narrow_backend_fix'
        read_only = $true
        backend_only = $true
        verifier_adjustments = [ordered]@{
            stateful_side_effect_required = $false
            red_phase_required = $false
            green_only_evidence_accepted = $true
        }
    })
    Write-Json (Join-Path $replayRoot 'FAMILY_CONTRACT.json') ([ordered]@{
        families = @(
            [ordered]@{
                id = 'core_entry'
                required = $true
                weight = 100
                proof_required = @('behavior_test_rebuild_preserves_policyNum', 'code_evidence_rebuild_lambda_copies_fields')
            },
            [ordered]@{
                id = 'stateful_side_effect'
                required = $false
                weight = 0
            }
        )
    })
    Write-Json (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') ([ordered]@{
        authorization = 'ALLOW'
        selected_carrier = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) + ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
        real_entry = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) AND ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
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
            entry = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
            carrier = 'TaskProcessor rebuildTaskData -> RequestBuildFunction -> request -> taskData'
            slice_type = 'exact_contract_slice'
            test_name = 'ExampleApplyClaimApiTaskProcessorTest.testRebuildTaskData_PreservesPolicyNumAndInsureNum'
            must_touch_files = @($applyFile, $lossFile)
        }
    })
    Write-Text (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
first_red_test: RebuildTaskDataGapTest.testRebuildRequestBuildFunctionMissingPolicyNumAssignment
selected_carrier: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) + ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) AND ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
'@
    Write-Text (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') @'
first_red_test: RebuildTaskDataGapTest.testRebuildRequestBuildFunctionMissingPolicyNumAssignment
selected_carrier: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) + ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) AND ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
'@

    $sliceResult = [ordered]@{
        slice_index = 1
        slice_id = 'S1'
        slice_title = 'policy rebuild source chain'
        slice_type = 'exact_contract_slice'
        slice_status = 'DONE'
        coverage_delta = 40
        target_subsurface_or_carrier = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) + ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
        production_boundary = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
        proof_kind = 'real_entry_behavior'
        red_expectation = 'expected:<P2024001X> but was:<null>'
        implemented_files = @($applyFile, $lossFile, $testFile)
        current_slice_changed_files = @($applyFile, $lossFile, $testFile)
        tests = @(
            [ordered]@{
                command = 'mvn -pl example-server -am -Dtest=ExampleApiTaskProcessorRebuildTest#testRebuildApplyClaim_PreservesPolicyNum test'
                phase = 'RED'
                result = 'fail'
                evidence = 'expected:<P2024001X> but was:<null> - business assertion failure before production fix'
            },
            [ordered]@{
                command = 'mvn -pl example-server -am -Dtest=ExampleApiTaskProcessorRebuildTest#testRebuildApplyClaim_PreservesPolicyNum test'
                phase = 'GREEN'
                result = 'pass'
                evidence = 'BUILD SUCCESS; Tests run: 4, Failures: 0, Errors: 0'
            }
        )
        test_compilation_exit_code = 0
        test_execution_exit_code = 0
        exact_contract_assertions = @([ordered]@{
            literal = 'req.setPolicyNum(buildContext.getPolicyNum());'
            symbol_or_field = 'req.setPolicyNum(buildContext.getPolicyNum());'
            db_or_wire_or_display = 'behavior'
            boundary_type = 'behavior'
            production_boundary = 'TaskProcessor rebuildTaskData'
            closure_proof = 'RequestBuildFunction builder.apply(buildContext) copies policyNum and insureNum through the production lambda.'
            test_assertion = 'Assert.assertEquals(TEST_POLICY_NUM, taskData.getPolicyNum())'
            source_type = 'requirement'
            status = 'CLOSED'
        })
        side_effect_evidence = [ordered]@{
            status = 'CLOSED'
            entry_call = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) AND ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
            expected_writes_or_outputs = @('policyNum preserved', 'insureNum preserved')
            must_not_writes = @()
            red_result = 'BUSINESS_ASSERTION_FAILED'
            green_result = 'PASS'
        }
        behavior_test_charter = [ordered]@{
            proof_kind = 'real_entry_behavior'
            production_entry = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) + ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
            state_or_output = 'rebuildTaskData preserves policyNum and insureNum'
            must_not = 'no database dependency'
            RED_command = 'mvn -Dtest=ExampleApiTaskProcessorRebuildTest#testRebuildApplyClaim_PreservesPolicyNum test'
            expected_RED_failure = 'expected:<P2024001X> but was:<null>'
            GREEN_command = 'mvn -Dtest=ExampleApiTaskProcessorRebuildTest test'
            evidence_file = $testFile
            evidence_files = @($testFile)
        }
        closed_assertions = @('RequestBuildFunction copies policyNum and insureNum from buildContext')
        gap_flags = @()
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
    }
    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    Write-Json $sliceResultPath $sliceResult

    & powershell -NoProfile -ExecutionPolicy Bypass -File $sliceVerifier -ReplayRoot $replayRoot -Worktree $worktree -SliceResult $sliceResultPath -SliceIndex 1 -SkipRemediationMap | Out-Null
    Assert-True 'slice_authorization_wrapper_passes' ($LASTEXITCODE -eq 0)

    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $verifyJson = $verify | ConvertTo-Json -Depth 20
    Assert-True 'real_builder_source_chain_is_pass' ([string]$verify.verification_status -eq 'PASS') $verifyJson
    Assert-True 'real_builder_source_chain_has_behavior_evidence' ([bool]$verify.has_behavior_evidence) $verifyJson
    Assert-True 'real_builder_source_chain_authorizes_next_slice' ([bool]$verify.authorized_for_next_slice) $verifyJson
    Assert-True 'real_builder_source_chain_authorizes_synthesis' ([bool]$verify.authorized_for_synthesis) $verifyJson
    Assert-True 'real_builder_source_chain_credits_delta' ([int]$verify.adjusted_coverage_delta -eq 40) $verifyJson
    Assert-True 'fixed_caseid_is_warning_not_synthetic_blocker' (@($verify.warnings) -contains 'source_chain_fixed_caseid_fixture_warning') $verifyJson
    Assert-True 'planned_test_name_mismatch_is_warning_only' (@($verify.warnings) -contains 'planned_red_test_name_mismatch_warn_only') $verifyJson
    Assert-True 'no_false_authorization_blockers' (
        @(($verify.authorization_blockers) | Where-Object {
            @('behavior_evidence_missing', 'wrong_test_surface', 'shallow_module', 'synthetic_carrier', 'proof_type_mismatch') -contains [string]$_
        }).Count -eq 0
    ) $verifyJson
    Assert-True 'severity_schema_present' ($verify.PSObject.Properties.Name -contains 'gap_flag_severity') $verifyJson

    Write-Host 'PASS: v564 policy rebuild verifier accepts real RequestBuildFunction source-chain proof'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
