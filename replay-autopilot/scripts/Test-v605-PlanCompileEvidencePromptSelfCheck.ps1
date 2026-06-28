param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Name - $Detail"
    }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = $PSScriptRoot
$autopilotRoot = Split-Path -Parent $scriptRoot
$promptPath = Join-Path $autopilotRoot 'prompts\phase-plan-tournament.prompt.md'
$runLoopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'

$promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8

$assertions = 0
$cases = [System.Collections.Generic.List[string]]::new()

Assert-True 'prompt_has_v605_output_self_check_section' ($promptText -match 'v605' -and $promptText -match 'Invoke-PlanSchemaFailFast') ''
$assertions++
Assert-True 'self_check_mentions_compilation_dry_run_command' ($promptText -match 'compilation_dry_run_command') ''
$assertions++
Assert-True 'self_check_mentions_compilation_dry_run_evidence_file' ($promptText -match 'compilation_dry_run_evidence_file') ''
$assertions++
Assert-True 'self_check_mentions_compilation_dry_run_exit_code' ($promptText -match 'compilation_dry_run_exit_code') ''
$assertions++
Assert-True 'self_check_mentions_test_module_for_target' ($promptText -match 'test_module_for_target') ''
$assertions++
Assert-True 'self_check_mentions_blocked_consequence' ($promptText -match 'PLAN_BLOCKED_TEST_INFRASTRUCTURE') ''
$assertions++
Assert-True 'self_check_mentions_runner_safety_net' ($promptText -match 'Ensure-PlanTestCompileEvidence') ''
$assertions++
$schemaIndex = $promptText.IndexOf('"test_infrastructure_check"')
$selfCheckIndex = $promptText.IndexOf('v605')
$executeIndex = $promptText.IndexOf('Phase 0.5', [Math]::Max(0, $selfCheckIndex))
Assert-True 'prompt_has_valid_structure' ($schemaIndex -ge 0 -and $selfCheckIndex -gt $schemaIndex -and $executeIndex -gt $selfCheckIndex) "schemaIndex=$schemaIndex selfCheckIndex=$selfCheckIndex executeIndex=$executeIndex"
$assertions++
$cases.Add('prompt_self_check_contract')

Assert-True 'runner_uses_safe_module_property_access' ($runLoopText.Contains("Get-ObjectPropertyString -Object `$infra -Name 'test_module_for_target'")) ''
$assertions++
Assert-True 'runner_injects_missing_compile_command' ($runLoopText.Contains("Set-ObjectPropertyValue -Object `$infra -Name 'compilation_dry_run_command'")) ''
$assertions++
Assert-True 'runner_injects_missing_evidence_file' ($runLoopText.Contains("Set-ObjectPropertyValue -Object `$infra -Name 'compilation_dry_run_evidence_file' -Value 'TEST_INFRASTRUCTURE_DRY_RUN.json'")) ''
$assertions++
Assert-True 'runner_persists_injected_plan_before_materialization' ($runLoopText.Contains('$Plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $PlanResultJsonPath')) ''
$assertions++
Assert-True 'runner_default_command_targets_worktree_pom' ($runLoopText.Contains("Join-Path `$Worktree 'pom.xml'") -and $runLoopText.Contains('-f `"$worktreePom`" -pl $moduleName -am test-compile')) ''
$assertions++
$cases.Add('runner_compile_evidence_injection_contract')

[ordered]@{
    status = 'PASS'
    assertions = $assertions
    cases = @($cases.ToArray())
} | ConvertTo-Json -Depth 5
