param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Json {
    param([string]$Path, [object]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-TestHarnessFixture {
    param(
        [string]$Worktree,
        [string]$Module = 'claim-server'
    )
    New-Item -ItemType Directory -Force -Path (Join-Path $Worktree "$Module\src\test\java\sample") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Worktree $Module) | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $Worktree "$Module\pom.xml") -Encoding UTF8
    'class DemoServiceTest {}' | Set-Content -LiteralPath (Join-Path $Worktree "$Module\src\test\java\sample\DemoServiceTest.java") -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptRoot
$runLoopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$promptPath = Join-Path $autopilotRoot 'prompts\phase-plan-tournament.prompt.md'
$schemaGate = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-machine-contract-test-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
    Assert-True 'prompt_requires_plan_result_json' ($promptText -match 'PLAN_RESULT\.json')
    Assert-True 'prompt_declares_machine_readable_authority' ($promptText -match 'machine-readable plan contract')
    Assert-True 'prompt_lists_proceed_required_json_fields' ($promptText -match 'target_carrier_file_path' -and $promptText -match 'expected_test_method' -and $promptText -match 'side_effects')
    Assert-True 'prompt_requires_test_infrastructure_check' ($promptText -match 'test_infrastructure_check' -and $promptText -match 'compilation_dry_run_exit_code' -and $promptText -match 'compilation_dry_run_evidence_file')
    Assert-True 'prompt_requires_profile_specific_test_harness' ($promptText -match 'profile .*test harness' -and $promptText -match 'test_module_for_target' -and $promptText -match '<required-test-module>' -and $promptText -match '-pl <required-test-module> -am test-compile' -and $promptText -match 'No sources to compile')

    $runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8
    Assert-True 'runner_requires_plan_result_json_artifact' ($runLoopText -match "'PLAN_RESULT\.json'")
    Assert-True 'runner_invokes_plan_schema_failfast_before_phase1' ($runLoopText -match 'Invoke-PlanSchemaFailFast\.ps1')
    Assert-True 'runner_stops_on_machine_contract_failure' ($runLoopText -match 'Plan machine contract failed')
    Assert-True 'runner_writes_plan_verdict_on_schema_failfast' ($runLoopText -match 'PLAN_SCHEMA_FAILFAST\.json' -and $runLoopText -match 'source_plan_machine_contract\s*=\s*\$planMachineContractPath' -and $runLoopText -match 'Set-Content[^\r\n]+PLAN_VERDICT\.json')
    Assert-True 'runner_materializes_missing_test_compile_evidence_before_schema' ($runLoopText -match 'function Ensure-PlanTestCompileEvidence' -and $runLoopText -match 'Materializing plan test compile evidence' -and $runLoopText -match 'Ensure-PlanTestCompileEvidence -ReplayRoot' -and $runLoopText -match 'Invoke-PlanSchemaFailFast')
    Assert-True 'runner_overwrites_compile_evidence_without_success_signal' ($runLoopText -match 'function Test-TestCompileEvidenceHasSuccessSignal' -and $runLoopText -match 'BUILD SUCCESS' -and $runLoopText -match '"exit_code"\\s\*:\\s\*0')
    Assert-True 'runner_blocks_dirty_worktree_before_phase1' ($runLoopText -match 'PRE_PHASE1_WORKTREE_CLEAN_CHECK\.json' -and $runLoopText -match 'Get-GitStatusShortSafe' -and $runLoopText -match 'Pre-Phase1 worktree clean gate blocked replay')
    Assert-True 'runner_classifies_agent_isolation_exit_codes' ($runLoopText -match 'protected_root_modified' -and $runLoopText -match 'command_guard_violation' -and $runLoopText -match '\$planExitCode -eq 92' -and $runLoopText -match '\$planExitCode -eq 93')
    Assert-True 'runner_repair_prompt_delegates_test_compile_evidence_to_runner' ($runLoopText -match 'MUST NOT run Maven in this repair prompt' -and $runLoopText -match 'runner materializes that evidence file' -and $runLoopText -match 'isolated worktree root POM')
    Assert-True 'runner_repair_prompt_rejects_null_blocker_reason' ($runLoopText -match 'blocker_reason`` as the string ``"none"``' -and $runLoopText -match 'Do not write ``null``')
    Assert-True 'runner_repair_prompt_defines_structured_side_effects' ($runLoopText -match 'side_effects`` MUST be a populated JSON array' -and $runLoopText -match 'side_effect.*state.*proof')
    Assert-True 'runner_contract_repair_prompt_lists_policy_rebuild_forbidden_patterns' ($runLoopText -match 'Policy rebuild hard repair rules' -and $runLoopText -match 'policy_rebuild_plan_invalid:test_harness_claim_core' -and $runLoopText -match 'taskData == null' -and $runLoopText -match 'req\.setPolicyNum\(buildContext\.getPolicyNum\(\)\)')
    Assert-True 'prompt_rejects_manual_verification_for_policy_rebuild_proceed' ($promptText -match 'manual verification' -and $promptText -match 'none_with_manual_verification' -and $promptText -match 'PROCEED')

    $goodProceedRoot = Join-Path $tempRoot 'good-proceed'
    $goodWorktree = Join-Path $goodProceedRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $goodProceedRoot | Out-Null
    New-TestHarnessFixture -Worktree $goodWorktree -Module 'claim-server'
    Write-Json (Join-Path $goodProceedRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-server -am test-compile'
        exit_code = 0
        stdout_tail = 'BUILD SUCCESS; Compiling 1 source files to claim-server\target\test-classes'
    })
    Write-Json (Join-Path $goodProceedRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/example/DemoService.java'
        target_carrier_line_number = 42
        expected_test_class = 'DemoServiceTest'
        expected_test_method = 'testDemo'
        side_effects = @(
            [ordered]@{
                side_effect = 'DB state update'
                state = 'claim.status'
                proof = 'assert DB state'
            }
        )
        expected_assertions = @('assert DB state')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-server -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $goodProceedRoot -PlanResultPath (Join-Path $goodProceedRoot 'PLAN_RESULT.json') -Worktree $goodWorktree | Out-Null
    Assert-True 'schema_accepts_executable_proceed_contract' ($LASTEXITCODE -eq 0)
    $goodSchema = Get-Content -LiteralPath (Join-Path $goodProceedRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_accepts_structured_side_effect_objects' ([bool]$goodSchema.checks.side_effects_valid)

    $goodPolicyRoot = Join-Path $tempRoot 'good-policy-rebuild'
    $goodPolicyWorktree = Join-Path $goodPolicyRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $goodPolicyRoot | Out-Null
    New-TestHarnessFixture -Worktree $goodPolicyWorktree -Module 'claim-server'
    Write-Json (Join-Path $goodPolicyRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-server -am test-compile'
        exit_code = 0
        stdout_tail = 'BUILD SUCCESS; Compiling 1 source files to claim-server\target\test-classes'
    })
    Write-Json (Join-Path $goodPolicyRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 385
        expected_test_class = 'claim-server/src/test/java/com/huize/claim/test/AiTaskProcessorRebuildTest.java'
        expected_test_method = 'testRebuildTaskData_PreservesPolicyNumAndInsureNum'
        side_effects = @(
            [ordered]@{
                type = 'in_memory'
                description = 'rebuildTaskData preserves policyNum and insureNum'
            }
        )
        expected_assertions = @('assert taskData.policyNum from RequestBuildContext', 'assert taskData.insureNum from RequestBuildContext')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-server -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $goodPolicyRoot -PlanResultPath (Join-Path $goodPolicyRoot 'PLAN_RESULT.json') -Worktree $goodPolicyWorktree | Out-Null
    Assert-True 'schema_accepts_policy_rebuild_claim_server_harness' ($LASTEXITCODE -eq 0)
    $goodPolicySchema = Get-Content -LiteralPath (Join-Path $goodPolicyRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_accepts_compact_type_description_side_effect_objects' ([bool]$goodPolicySchema.checks.side_effects_valid)

    $blockedRoot = Join-Path $tempRoot 'blocked'
    New-Item -ItemType Directory -Force -Path $blockedRoot | Out-Null
    Write-Json (Join-Path $blockedRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'BLOCKED'
        blocker = 'selected_real_entry_missing'
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $blockedRoot -PlanResultPath (Join-Path $blockedRoot 'PLAN_RESULT.json') | Out-Null
    Assert-True 'schema_accepts_blocked_with_blocker' ($LASTEXITCODE -eq 0)

    $badRoot = Join-Path $tempRoot 'bad'
    New-Item -ItemType Directory -Force -Path $badRoot | Out-Null
    Write-Json (Join-Path $badRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        expected_test_class = 'DemoServiceTest'
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $badRoot -PlanResultPath (Join-Path $badRoot 'PLAN_RESULT.json') | Out-Null
    Assert-True 'schema_rejects_incomplete_proceed_contract' ($LASTEXITCODE -ne 0)
    $badSchema = Get-Content -LiteralPath (Join-Path $badRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_reports_missing_target_carrier' ((@($badSchema.checks.missing_fields) -join ' ') -match 'target_carrier_file_path')
    Assert-True 'schema_reports_missing_test_infrastructure_check' ((@($badSchema.checks.test_infrastructure_issues) -join ' ') -match 'test_infrastructure_check_missing')

    $badMissingEvidenceRoot = Join-Path $tempRoot 'bad-missing-evidence'
    $badMissingEvidenceWorktree = Join-Path $badMissingEvidenceRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $badMissingEvidenceRoot | Out-Null
    New-TestHarnessFixture -Worktree $badMissingEvidenceWorktree -Module 'claim-server'
    Write-Json (Join-Path $badMissingEvidenceRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/example/DemoService.java'
        target_carrier_line_number = 42
        expected_test_class = 'DemoServiceTest'
        expected_test_method = 'testDemo'
        side_effects = @('DB state update')
        expected_assertions = @('assert DB state')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-server -am test-compile'
            compilation_dry_run_evidence_file = 'missing-test-compile-evidence.log'
            blocker_reason = 'none'
        }
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $badMissingEvidenceRoot -PlanResultPath (Join-Path $badMissingEvidenceRoot 'PLAN_RESULT.json') -Worktree $badMissingEvidenceWorktree | Out-Null
    Assert-True 'schema_rejects_claimed_compile_evidence_file_that_does_not_exist' ($LASTEXITCODE -ne 0)
    $badMissingEvidenceSchema = Get-Content -LiteralPath (Join-Path $badMissingEvidenceRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_reports_missing_compile_evidence_file' ((@($badMissingEvidenceSchema.checks.test_infrastructure_issues) -join ' ') -match 'compilation_dry_run_evidence_file_not_found')

    $badNullBlockerRoot = Join-Path $tempRoot 'bad-null-blocker'
    $badNullBlockerWorktree = Join-Path $badNullBlockerRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $badNullBlockerRoot | Out-Null
    New-TestHarnessFixture -Worktree $badNullBlockerWorktree -Module 'claim-server'
    Write-Json (Join-Path $badNullBlockerRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-server -am test-compile'
        exit_code = 0
        stdout_tail = 'BUILD SUCCESS; Compiling 1 source files to claim-server\target\test-classes'
    })
    Write-Json (Join-Path $badNullBlockerRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/example/DemoService.java'
        target_carrier_line_number = 42
        expected_test_class = 'DemoServiceTest'
        expected_test_method = 'testDemo'
        side_effects = @('DB state update')
        expected_assertions = @('assert DB state')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-server -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = $null
        }
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $badNullBlockerRoot -PlanResultPath (Join-Path $badNullBlockerRoot 'PLAN_RESULT.json') -Worktree $badNullBlockerWorktree | Out-Null
    Assert-True 'schema_rejects_null_blocker_reason_for_proceed' ($LASTEXITCODE -ne 0)
    $badNullBlockerSchema = Get-Content -LiteralPath (Join-Path $badNullBlockerRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_reports_null_blocker_reason_missing' ((@($badNullBlockerSchema.checks.test_infrastructure_issues) -join ' ') -match 'test_infrastructure_check.blocker_reason missing')

    $badPolicyRoot = Join-Path $tempRoot 'bad-policy-rebuild'
    $badPolicyWorktree = Join-Path $badPolicyRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $badPolicyWorktree 'claim-core') | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $badPolicyWorktree 'claim-core\pom.xml') -Encoding UTF8
    Write-Json (Join-Path $badPolicyRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 385
        expected_test_class = 'claim-core/src/test/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessorTest.java'
        expected_test_method = 'testRebuildTaskData_PreservesPolicyNumAndInsureNum'
        side_effects = @('rebuildTaskData preserves policyNum and insureNum')
        expected_assertions = @('manual verification if no test harness')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-core'
            test_module_has_dependencies = $false
            test_harness_available = $false
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-core -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none_with_manual_verification'
        }
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $badPolicyRoot -PlanResultPath (Join-Path $badPolicyRoot 'PLAN_RESULT.json') -Worktree $badPolicyWorktree | Out-Null
    Assert-True 'schema_rejects_policy_rebuild_claim_core_harness' ($LASTEXITCODE -ne 0)
    $badPolicySchema = Get-Content -LiteralPath (Join-Path $badPolicyRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $badPolicyIssues = @($badPolicySchema.checks.test_infrastructure_issues) -join ' '
    Assert-True 'schema_reports_policy_rebuild_claim_server_required' ($badPolicyIssues -match 'policy_rebuild_test_module_must_be_claim_server')
    Assert-True 'schema_reports_manual_verification_not_allowed' ($badPolicyIssues -match 'manual_verification_not_allowed_for_proceed')

    $badInfraRoot = Join-Path $tempRoot 'bad-infra'
    $badInfraWorktree = Join-Path $badInfraRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $badInfraRoot | Out-Null
    New-TestHarnessFixture -Worktree $badInfraWorktree -Module 'claim-core'
    Write-Json (Join-Path $badInfraRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-core -am test-compile'
        exit_code = 1
        stdout_tail = 'BUILD FAILURE'
    })
    Write-Json (Join-Path $badInfraRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/example/DemoService.java'
        target_carrier_line_number = 42
        expected_test_class = 'DemoServiceTest'
        expected_test_method = 'testDemo'
        side_effects = @('DB state update')
        expected_assertions = @('assert DB state')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-core'
            test_module_has_dependencies = $false
            test_harness_available = $false
            can_import_production_classes = $false
            compilation_dry_run_exit_code = 1
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-core -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'junit_missing'
        }
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $badInfraRoot -PlanResultPath (Join-Path $badInfraRoot 'PLAN_RESULT.json') -Worktree $badInfraWorktree | Out-Null
    Assert-True 'schema_rejects_non_executable_test_infrastructure' ($LASTEXITCODE -ne 0)
    $badInfraSchema = Get-Content -LiteralPath (Join-Path $badInfraRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_reports_compilation_dry_run_failure' ((@($badInfraSchema.checks.test_infrastructure_issues) -join ' ') -match 'compilation_dry_run_exit_code')

    $badNoTestsRoot = Join-Path $tempRoot 'bad-no-tests'
    $badNoTestsWorktree = Join-Path $badNoTestsRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $badNoTestsWorktree 'claim-core') | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $badNoTestsWorktree 'claim-core\pom.xml') -Encoding UTF8
    Write-Json (Join-Path $badNoTestsRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-core -am test-compile'
        exit_code = 0
        stdout_tail = 'BUILD SUCCESS; No sources to compile'
    })
    Write-Json (Join-Path $badNoTestsRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/example/DemoService.java'
        target_carrier_line_number = 42
        expected_test_class = 'DemoServiceTest'
        expected_test_method = 'testDemo'
        side_effects = @('DB state update')
        expected_assertions = @('assert DB state')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-core'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-core -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $badNoTestsRoot -PlanResultPath (Join-Path $badNoTestsRoot 'PLAN_RESULT.json') -Worktree $badNoTestsWorktree | Out-Null
    Assert-True 'schema_rejects_testless_module_even_with_zero_exit' ($LASTEXITCODE -ne 0)
    $badNoTestsSchema = Get-Content -LiteralPath (Join-Path $badNoTestsRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_reports_missing_src_test' ((@($badNoTestsSchema.checks.test_infrastructure_issues) -join ' ') -match 'test_module_missing_src_test:claim-core')

    Write-Host 'PASS: v469 plan machine contract required'
    exit 0
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
