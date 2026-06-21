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
    param([string]$Root)

    $replayRoot = Join-Path $Root 'replay'
    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-server\src\test\java\sample') | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'claim-server\pom.xml') -Encoding UTF8
    'class ExistingHarnessTest {}' | Set-Content -LiteralPath (Join-Path $worktree 'claim-server\src\test\java\sample\ExistingHarnessTest.java') -Encoding UTF8

    Write-JsonFile (Join-Path $replayRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = "mvn -f $worktree\pom.xml -pl claim-server -am test-compile"
        module = 'claim-server'
        exit_code = 0
        timed_out = $false
        stdout_tail = '[INFO] --- compiler:testCompile ---' + "`n" + '[ERROR] Failed to execute goal org.apache.maven.plugins:maven-compiler-plugin:3.13.0:compile (default-compile) on project claim-domain: Compilation failure'
        stderr_tail = ''
    })

    Write-JsonFile (Join-Path $replayRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 495
        expected_test_class = 'AiApplyClaimAutoFlowTriggerTest'
        expected_test_method = 'shouldTriggerAutoFlowWhenAiResultSuccess'
        side_effects = @(
            [ordered]@{
                side_effect = 'auto flow service called'
                state = 'case flow'
                proof = 'Mockito verify autoFlow'
            }
        )
        expected_assertions = @('verify autoFlow service is called')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = "mvn -f $worktree\pom.xml -pl claim-server -am test-compile"
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })

    @'
# FIRST_SLICE_PROOF_PLAN

highest_weight_open_gate: core_entry
selected_real_entry: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse(AiApplyClaimApiTask, AiApplyClaimApiTaskResponse)
selected_carrier: AiApplyClaimApiTaskProcessor
target_subsurface_or_carrier: AiApplyClaimApiTaskProcessor
target_carrier_file_path: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java
target_carrier_line_number: 495
expected_test_class: AiApplyClaimAutoFlowTriggerTest
expected_test_method: shouldTriggerAutoFlowWhenAiResultSuccess
expected_assertions: ["verify autoFlow service is called"]
expected_side_effects: [{"service":"AiAutoClaimFlowService","operation":"autoFlow"}]
minimum_side_effect_or_blocker: autoFlow service called after AI result save
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    @'
Entry Point: AiApplyClaimApiTaskProcessor.handleTaskResponse
Test Class: AiApplyClaimAutoFlowTriggerTest
DB Verification: not applicable for first trigger slice
Side Effects: verify autoFlow service call
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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v607-' + [guid]::NewGuid().ToString('N'))

try {
    $schemaFixture = New-PlanFixture -Root (Join-Path $tempRoot 'schema')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $schemaScript `
        -ReplayRoot $schemaFixture.ReplayRoot `
        -PlanResultPath $schemaFixture.PlanResultPath `
        -Worktree $schemaFixture.Worktree | Out-Null
    Assert-True 'schema_rejects_zero_exit_compile_failure_log' ($LASTEXITCODE -ne 0) "exit=$LASTEXITCODE"
    $schema = Get-Content -LiteralPath (Join-Path $schemaFixture.ReplayRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $schemaIssues = @($schema.checks.test_infrastructure_issues) -join ' '
    Assert-True 'schema_reports_failure_signal' ($schemaIssues -match 'compilation_dry_run_evidence_contains_failure_signal') $schemaIssues

    $preFixture = New-PlanFixture -Root (Join-Path $tempRoot 'pre-execution')
    New-Item -ItemType Directory -Force -Path (Join-Path $preFixture.Worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task') | Out-Null
    'class AiApplyClaimApiTaskProcessor {}' | Set-Content -LiteralPath (Join-Path $preFixture.Worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task\AiApplyClaimApiTaskProcessor.java') -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $preExecutionScript `
        -ReplayRoot $preFixture.ReplayRoot `
        -Worktree $preFixture.Worktree `
        -PlanResultPath $preFixture.PlanResultPath | Out-Null
    Assert-True 'pre_execution_rejects_zero_exit_compile_failure_log' ($LASTEXITCODE -ne 0) "exit=$LASTEXITCODE"
    $preExecution = Get-Content -LiteralPath (Join-Path $preFixture.ReplayRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $preIssues = @($preExecution.checks | ForEach-Object { @($_.issues) }) -join ' '
    Assert-True 'pre_execution_reports_failure_signal' ($preIssues -match 'compilation_dry_run_evidence_contains_failure_signal') $preIssues

    $runnerText = Get-Content -LiteralPath $runnerScript -Raw -Encoding UTF8
    Assert-True 'runner_success_signal_checks_failure_marker' ($runnerText -match 'function Test-MavenFailureSignal' -and $runnerText -match 'Test-MavenFailureSignal -Text \$text')
    Assert-True 'runner_normalizes_zero_exit_failure_to_nonzero' ($runnerText -match '\$rawExitCode = \$exitCode' -and $runnerText -match '\$exitCode -eq 0 -and \$failureSignalDetected' -and $runnerText -match 'failure_signal_detected')

    [ordered]@{
        status = 'PASS'
        version = 'v607'
        assertions = @(
            'plan_schema_rejects_zero_exit_maven_failure_log',
            'pre_execution_rejects_zero_exit_maven_failure_log',
            'runner_normalizes_maven_failure_signal'
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
