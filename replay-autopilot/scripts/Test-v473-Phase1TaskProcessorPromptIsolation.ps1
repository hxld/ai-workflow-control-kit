$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($args -contains '-ValidateOnly') {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$promptPath = Join-Path $repoRoot 'prompts\phase1-slice-executor.prompt.md'
$prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$cases = @()

$condition = $prompt.Contains('.memory/build-test-profile.yaml') -and $prompt.Contains('-f {{PROJECT_ROOT}}\pom.xml') -and $prompt.Contains('-f {{WORKTREE}}\pom.xml')
$cases += (Assert-True -Name 'phase1_overrides_memory_build_profile_root_pom' -Condition $condition)

$condition = $prompt.Contains('PROJECT_ROOT') -and $prompt.Contains('repo rules') -and $prompt.Contains('{{WORKTREE}}\pom.xml')
$cases += (Assert-True -Name 'phase1_project_root_reference_only' -Condition $condition)

$condition = $prompt.Contains('TaskProcessor') -and $prompt.Contains('rebuildTaskData') -and $prompt.Contains('Service/TaskProcessor')
$cases += (Assert-True -Name 'phase1_taskprocessor_service_surface_allowed' -Condition $condition)

$condition = $prompt.Contains('<expected_test_class>') -and $prompt.Contains('PLAN_RESULT.json.expected_test_class')
$cases += (Assert-True -Name 'phase1_expected_test_class_required' -Condition $condition)

$condition = $prompt.Contains('memory/progress') -or $prompt.Contains('unrelated memory')
$cases += (Assert-True -Name 'phase1_forbids_unrelated_memory_tests' -Condition $condition)

$condition = -not $prompt.Contains('Test class at Facade/Controller layer, NOT Service layer')
$cases += (Assert-True -Name 'phase1_no_facade_only_test_charter_rule' -Condition $condition)

$condition = -not $prompt.Contains('Exact Facade/Controller method to test')
$cases += (Assert-True -Name 'phase1_no_exact_facade_only_entry_rule' -Condition $condition)

$condition = -not $prompt.Contains('claim-core has no test')
$cases += (Assert-True -Name 'phase1_no_unconditional_claim_core_test_ban' -Condition $condition)

$condition = $prompt.Contains('测试 harness 模块由当前 worktree 的实际测试依赖') -and $prompt.Contains('候选模块 `pom.xml`') -and $prompt.Contains('-pl <test-module>') -and $prompt.Contains('-am') -and $prompt.Contains('JUnit/Mockito/Spring Test')
$cases += (Assert-True -Name 'phase1_carrier_uses_existing_harness_module' -Condition $condition)

$condition = $prompt.Contains('mvn --% {{MAVEN_SETTINGS_ARG}} -f {{WORKTREE}}\pom.xml -pl <test-module> -am') -and $prompt.Contains('-Dtest=<expected_test_class>#<expected_test_method>') -and $prompt.Contains('-Dsurefire.failIfNoSpecifiedTests=false')
$cases += (Assert-True -Name 'phase1_powershell_maven_test_command_is_copy_ready' -Condition $condition)

$condition = $prompt.Contains('coverage_delta > 0') -and $prompt.Contains('test_compilation_exit_code') -and $prompt.Contains('test_execution_exit_code') -and $prompt.Contains('no_test_execution_evidence')
$cases += (Assert-True -Name 'phase1_requires_compile_and_execution_before_coverage' -Condition $condition)

$condition = $prompt.Contains('`-pl <module>`') -and $prompt.Contains('`-am`') -and $prompt.Contains('SNAPSHOT')
$cases += (Assert-True -Name 'phase1_requires_also_make_for_project_list' -Condition $condition)

$condition = $prompt.Contains('AbstractTestClass') -and $prompt.Contains('@SpringBootTest') -and $prompt.Contains('@RunWith(SpringJUnit4ClassRunner.class)') -and $prompt.Contains('@Resource') -and $prompt.Contains('no-Spring')
$cases += (Assert-True -Name 'phase1_forbids_full_spring_context_for_taskprocessor_rebuild' -Condition $condition)

$condition = $prompt.Contains('AiClaimDataAssemblyHelper.buildRequestCommon') -and $prompt.Contains('AiClaimDataAssemblyHelper.RequestBuildFunction') -and $prompt.Contains('RequestBuildContext') -and $prompt.Contains('thenAnswer') -and $prompt.Contains('taskData == null') -and $prompt.Contains('return new AiApplyClaimRequest') -and $prompt.Contains('return new AiCalculateLossRequest')
$cases += (Assert-True -Name 'phase1_requires_deterministic_request_build_context_red' -Condition $condition)

$condition = $prompt.Contains('AiApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId)') -and $prompt.Contains('AiCalculateLossApiTaskProcessor.rebuildTaskData(Long caseId)') -and $prompt.Contains('sibling surface')
$cases += (Assert-True -Name 'phase1_requires_apply_and_calculate_rebuild_siblings' -Condition $condition)

$invokePath = Join-Path $repoRoot 'scripts\Invoke-AgentPrompt.ps1'
$invoke = Get-Content -LiteralPath $invokePath -Raw -Encoding UTF8
$condition = $invoke.Contains('maven_pl_without_am_forbidden') -and $invoke.Contains('$hasProjectList') -and $invoke.Contains('$hasAlsoMake')
$cases += (Assert-True -Name 'invoke_agent_prompt_guards_pl_without_am' -Condition $condition)

$condition = $invoke.Contains('AbstractTestClass') -and $invoke.Contains('RequestBuildFunction') -and $invoke.Contains('fixed database caseIds') -and $invoke.Contains('hand-built request from thenAnswer')
$cases += (Assert-True -Name 'invoke_agent_prompt_injects_no_spring_rebuild_guard' -Condition $condition)

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = $cases
    repo_root = $repoRoot
} | ConvertTo-Json -Depth 8
