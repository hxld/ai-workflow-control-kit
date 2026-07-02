param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw $Name }
        throw "$Name :: $Detail"
    }
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-PlanFixture {
    param(
        [string]$Root,
        [string]$EvidenceText,
        [int]$EvidenceExitCode
    )

    $replayRoot = Join-Path $Root 'replay'
    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'example-server\src\test\java\sample') | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'pom.xml') -Encoding UTF8
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'example-server\pom.xml') -Encoding UTF8
    'class ExistingHarnessTest {}' | Set-Content -LiteralPath (Join-Path $worktree 'example-server\src\test\java\sample\ExistingHarnessTest.java') -Encoding UTF8

    Write-JsonFile (Join-Path $replayRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = "mvn -f $worktree\pom.xml -pl example-server -am test-compile"
        module = 'example-server'
        exit_code = $EvidenceExitCode
        raw_exit_code = $EvidenceExitCode
        timed_out = $false
        stdout_tail = $EvidenceText
        stderr_tail = ''
    })

    Write-JsonFile (Join-Path $replayRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 461
        expected_test_class = 'ExampleFlowServiceTest'
        expected_test_method = 'testAutoFlow_AmountWithinFreeReview_CreatesCompensateData'
        side_effects = @(
            [ordered]@{
                side_effect = 'writes compensate detail'
                state = 't_compensate_detail'
                proof = 'Mockito verify insert'
            }
        )
        expected_assertions = @('verify compensate insert')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'example-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = $EvidenceExitCode
            compilation_dry_run_command = "mvn -f $worktree\pom.xml -pl example-server -am test-compile"
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })

    @'
# FIRST_SLICE_PROOF_PLAN

highest_weight_open_gate: core_entry
selected_real_entry: com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.handleTaskResponse
selected_carrier: ExampleApplyClaimApiTaskProcessor
target_subsurface_or_carrier: ExampleApplyClaimApiTaskProcessor
target_carrier_file_path: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java
target_carrier_line_number: 461
expected_test_class: ExampleFlowServiceTest
expected_test_method: testAutoFlow_AmountWithinFreeReview_CreatesCompensateData
expected_assertions: ["verify compensate detail insert","verify compensate info insert","verify case status update"]
expected_side_effects: [{"service":"CompensateService","operation":"insert"}]
minimum_side_effect_or_blocker: compensate detail write
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    @'
Entry Point: ExampleApplyClaimApiTaskProcessor.handleTaskResponse
Test Class: ExampleFlowServiceTest
DB Verification: mapper insert verification
Side Effects: compensate detail write
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER.md') -Encoding UTF8

    return [pscustomobject]@{
        ReplayRoot = $replayRoot
        Worktree = $worktree
        PlanResultPath = (Join-Path $replayRoot 'PLAN_RESULT.json')
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$schemaScript = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'
$preExecutionScript = Join-Path $scriptRoot 'Invoke-PreExecutionConstraintCheck.ps1'
$runnerScript = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v611-' + [guid]::NewGuid().ToString('N'))

try {
    $warningText = @'
[WARNING] The POM for com.alibaba:druid:jar:1.1.21 is invalid
[ERROR] 'dependencies.dependency.systemPath' for com.sun:tools:jar must specify an absolute path but is ${project.basedir}/lib/openjdk-1.8-tools.jar @
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
'@
    $successFixture = New-PlanFixture -Root (Join-Path $tempRoot 'success-warning') -EvidenceText $warningText -EvidenceExitCode 0
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $schemaScript `
        -ReplayRoot $successFixture.ReplayRoot `
        -PlanResultPath $successFixture.PlanResultPath `
        -Worktree $successFixture.Worktree | Out-Null
    Assert-True 'schema_accepts_build_success_with_model_error_warning' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

    New-Item -ItemType Directory -Force -Path (Join-Path $successFixture.Worktree 'example-core\src\main\java\com\example\project\core\ai\task') | Out-Null
    'class ExampleApplyClaimApiTaskProcessor {}' | Set-Content -LiteralPath (Join-Path $successFixture.Worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleApplyClaimApiTaskProcessor.java') -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $preExecutionScript `
        -ReplayRoot $successFixture.ReplayRoot `
        -Worktree $successFixture.Worktree `
        -PlanResultPath $successFixture.PlanResultPath | Out-Null
    Assert-True 'pre_execution_accepts_build_success_with_model_error_warning' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

    $failureText = @'
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-compiler-plugin:compile
[ERROR] COMPILATION ERROR
[INFO] ------------------------------------------------------------------------
[INFO] BUILD FAILURE
'@
    $failureFixture = New-PlanFixture -Root (Join-Path $tempRoot 'real-failure') -EvidenceText $failureText -EvidenceExitCode 0
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $schemaScript `
        -ReplayRoot $failureFixture.ReplayRoot `
        -PlanResultPath $failureFixture.PlanResultPath `
        -Worktree $failureFixture.Worktree | Out-Null
    Assert-True 'schema_still_rejects_zero_exit_real_build_failure' ($LASTEXITCODE -ne 0) "exit=$LASTEXITCODE"
    $schema = Get-Content -LiteralPath (Join-Path $failureFixture.ReplayRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $schemaIssues = @($schema.checks.test_infrastructure_issues) -join ' '
    Assert-True 'schema_reports_real_failure_signal' ($schemaIssues -match 'compilation_dry_run_evidence_contains_failure_signal') $schemaIssues

    $runnerText = Get-Content -LiteralPath $runnerScript -Raw -Encoding UTF8
    Assert-True 'runner_success_short_circuit_prevents_warning_false_positive' ($runnerText.Contains('BUILD SUCCESS') -and $runnerText.Contains('return $false') -and $runnerText.Contains('\[ERROR\]'))

    [ordered]@{
        status = 'PASS'
        version = 'v611'
        assertions = @(
            'plan_schema_accepts_build_success_with_maven_model_error_warning',
            'pre_execution_accepts_build_success_with_maven_model_error_warning',
            'plan_schema_still_rejects_real_build_failure'
        )
    } | ConvertTo-Json -Depth 5
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
