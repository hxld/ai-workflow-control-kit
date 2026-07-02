param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '.tmp\v590-pre-execution-utf8-proof-json')
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsRoot = Split-Path -Parent $scriptRoot
$precheckScript = Join-Path $scriptsRoot 'Invoke-PreExecutionConstraintCheck.ps1'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

try {
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
    $replayRoot = Join-Path $TestRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'example-server\src\test\java\com\example') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'example-core\src\main\java\com\example') | Out-Null

    Write-Utf8 (Join-Path $worktree 'example-server\pom.xml') '<project />'
    Write-Utf8 (Join-Path $worktree 'example-server\src\test\java\com\example\ExistingTaskProcessorTest.java') 'public class ExistingTaskProcessorTest {}'
    Write-Utf8 (Join-Path $worktree 'example-core\src\main\java\com\example\ExistingTaskProcessor.java') @'
package com.example;
public class ExistingTaskProcessor {
    public void handleTaskResponse() {}
}
'@

    $planResult = [ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'example-core/src/main/java/com/example/ExistingTaskProcessor.java'
        expected_test_class = 'ExistingTaskProcessorTest'
        side_effects = @(@{ table = 't_case'; operation = 'update' })
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'example-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = "mvn -f $worktree\pom.xml -pl example-server -am test-compile"
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    }
    $planResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'PLAN_RESULT.json') -Encoding UTF8
    Write-Utf8 (Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json') '{"classification":"data_migration","read_only":false,"verifier_adjustments":{"stateful_side_effect_required":true}}'
    Write-Utf8 (Join-Path $replayRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') '{"exit_code":0,"command":"mvn -f worktree/pom.xml -pl example-server -am test-compile","stdout_tail":"BUILD SUCCESS"}'
    Write-Utf8 (Join-Path $replayRoot 'TEST_CHARTER.md') 'Entry Point: ExistingTaskProcessor.handleTaskResponse; Test Class: ExistingTaskProcessorTest; Side Effects: verify DB update'
    $utf8AssertionText = 'AI' + [string]([char]0x7ED3) + [string]([char]0x8BBA) + [string]([char]0x514D) + [string]([char]0x590D) + [string]([char]0x6838)
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1
highest_weight_open_gate: core_entry
first_red_test: ExistingTaskProcessorTest.testHandleTaskResponse
selected_real_entry: ExistingTaskProcessor.handleTaskResponse
selected_carrier: ExistingTaskProcessor
target_subsurface_or_carrier: ExistingTaskProcessor.handleTaskResponse
real_carrier_kind: production_entry_or_service
minimum_side_effect_or_blocker: update t_case status
forbidden_substitute_check: passed
required_sibling_surfaces: none_with_reason: fixture
production_boundary: example-core/src/main/java/com/example/ExistingTaskProcessor.java
expected_production_diff: ExistingTaskProcessor.java
red_expectation: assertion fails before production update
green_minimum_implementation: update t_case status and emit log
proof_kind: stateful_side_effect
forbidden_substitute_proof: assertion observes production side effect
fail_closed_condition: block if handler is not executable
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: ExistingTaskProcessor.handleTaskResponse
pattern_return_type: void
pattern_error_handling: exception_propagation
pattern_evidence_source: rg "class ExistingTaskProcessor" example-core
target_carrier_file_path: example-core/src/main/java/com/example/ExistingTaskProcessor.java
target_carrier_line_number: 2
expected_test_class: ExistingTaskProcessorTest
expected_test_method: testHandleTaskResponse
expected_assertions: ["verify(primaryRepository).insertRows(eq(3))", "verify(statusGateway).updateStatus(eq(entityId), eq(31), eq(35))", "verify(auditLogGateway).insertBusinessLog(eq(entityId), contains(\"__UTF8_ASSERTION_TEXT__\"))"]
expected_side_effects: [{"table":"t_case","operation":"update"}]
'@
    $proofPath = Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md'
    $proofText = Get-Content -LiteralPath $proofPath -Raw -Encoding UTF8
    Write-Utf8 $proofPath ($proofText.Replace('__UTF8_ASSERTION_TEXT__', $utf8AssertionText))

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $precheckScript `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -PlanResultPath (Join-Path $replayRoot 'PLAN_RESULT.json') `
        -BaselineRoot $worktree `
        -FeatureClassificationPath (Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json') 2>&1

    $cases = New-Object System.Collections.Generic.List[string]
    $cases.Add((Assert-True 'precheck_exit_zero_for_utf8_json_assertions' ($LASTEXITCODE -eq 0))) | Out-Null

    $check = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $cases.Add((Assert-True 'precheck_status_pass' ($check.status -eq 'PASS'))) | Out-Null
    $schemaCheck = @($check.checks | Where-Object { $_.name -eq 'first_slice_proof_schema_valid' })[0]
    $cases.Add((Assert-True 'first_slice_proof_schema_valid_passes' ($schemaCheck.status -eq 'PASS'))) | Out-Null
    $cases.Add((Assert-True 'expected_assertions_not_reported_invalid_json' (-not (@($schemaCheck.missing_fields) -match 'expected_assertions')))) | Out-Null

    [ordered]@{
        status = 'PASS'
        test_name = 'v590_pre_execution_utf8_proof_json'
        assertions = $cases.Count
        cases = @($cases)
        powershell_host = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '$PSVersionTable.PSVersion.ToString()')
        output = @($output)
    } | ConvertTo-Json -Depth 6
} catch {
    [ordered]@{
        status = 'FAIL'
        test_name = 'v590_pre_execution_utf8_proof_json'
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 6
    exit 1
}
