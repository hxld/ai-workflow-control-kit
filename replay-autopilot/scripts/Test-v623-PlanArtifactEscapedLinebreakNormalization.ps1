param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Name - $Detail"
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-EscapedNewlinePlan {
    param([string]$Path, [string[]]$Lines)

    $literalNewline = '`n'
    $text = ($Lines -join ("`r" + $literalNewline)) + "`r" + $literalNewline
    Write-Utf8 -Path $Path -Text $text
}

function New-PlanFixture {
    param([string]$Root)

    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'src\main\java\example\config') | Out-Null
    Write-Utf8 (Join-Path $worktree 'src\main\java\example\config\GenericConfigService.java') @'
package example.config;
class GenericConfigService {
  void applyRule() {}
}
'@

    $planLines = @(
        '# Plan Result',
        '- plan_status: BLOCKED',
        '- selected_strategy: generic-config-first',
        '- carrier_search: performed',
        '- carrier_search_queries: rg "class GenericConfigService"; rg "applyRule"; rg "GenericConfigService.java"',
        '- existing_production_carriers: GenericConfigService.applyRule',
        '- selected_carrier_from_search: GenericConfigService.applyRule',
        '- new_service_proposed: false',
        '- oracle_production_file_overlap: 50%',
        '- oracle_high_weight_coverage: 40% (0/1)',
        '- oracle_missing_high_weight_files: GenericConfigService.java',
        '- oracle_expansion_plan: GenericConfigService.java -> GenericConfigService.applyRule -> S1 -> executable test',
        '- oracle_out_of_scope_files: none',
        '- golden_slice_binding: exact_contract_gap -> GenericConfigService.applyRule -> GenericConfigServiceTest.shouldApplyRule -> minimum GREEN -> repository side effect',
        '- first_slice: S1',
        '- first_red_test: GenericConfigServiceTest.shouldApplyRule',
        '- blocker: oracle_high_weight_overlap_below_threshold: stale pre-repair value'
    )
    Write-EscapedNewlinePlan -Path (Join-Path $Root 'PLAN_RESULT.md') -Lines $planLines

    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.json') @'
{
  "plan_status": "BLOCKED",
  "target_carrier_file_path": "src/main/java/example/config/GenericConfigService.java",
  "target_carrier_line_number": 3,
  "expected_test_class": "GenericConfigServiceTest",
  "expected_test_method": "shouldApplyRule",
  "side_effects": ["repository update"],
  "expected_assertions": ["assert captured rule", "verify repository update", "assert response ok"],
  "test_infrastructure_check": {
    "test_module_for_target": "example-server",
    "test_module_has_dependencies": true,
    "test_harness_available": true,
    "can_import_production_classes": true,
    "compilation_dry_run_exit_code": 0,
    "compilation_dry_run_command": "mvn -f worktree/pom.xml -pl example-server -am test-compile",
    "compilation_dry_run_evidence_file": "TEST_INFRASTRUCTURE_DRY_RUN.json",
    "blocker_reason": "none"
  },
  "blocker": "oracle_high_weight_overlap_below_threshold"
}
'@

    foreach ($name in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Utf8 (Join-Path $Root $name) 'candidate: generic-config-first'
    }

    Write-Utf8 (Join-Path $Root 'FAMILY_CONTRACT.json') '{"selected_real_entry":"GenericConfigService.applyRule","first_executable_slice":"S1","families":[{"id":"config_policy_threshold","required":true,"proof_required":["RED","GREEN"]}]}'
    Write-Utf8 (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') '{"files":[{"path":"src/main/java/example/config/GenericConfigService.java","is_production":true,"weight":"HIGH"}],"production_files":1,"high_weight_files":1}'
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') 'first_slice: S1; GenericConfigService.java; GenericConfigService.applyRule'
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') 'selected_real_entry: GenericConfigService.applyRule; first_slice: S1; shallow-green-ban'
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'GenericConfigService.java -> LOGIC_FIX -> GenericConfigServiceTest.shouldApplyRule'
    Write-Utf8 (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'state: generic config; task: apply rule; transaction: repository update; log: assertion'
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') @'
# Test Charter
RED Phase
Entry Point: GenericConfigService.applyRule
Test Class: GenericConfigServiceTest
Test Method: shouldApplyRule
GREEN Phase
DB Verification: ArgumentCaptor verifies repository update
Side Effects:
- verify repository update command is issued
'@
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1
first_red_test: GenericConfigServiceTest.shouldApplyRule
golden_slice_binding: exact_contract_gap -> GenericConfigService.applyRule -> GenericConfigServiceTest.shouldApplyRule -> minimum GREEN -> repository side effect
highest_weight_open_gate: config_policy_threshold
first_slice_family: config_policy_threshold
selected_real_entry: GenericConfigService.applyRule
public_entry_contract_coverage: not_public_entry_with_reason:service_method
selected_carrier: GenericConfigService.applyRule
target_subsurface_or_carrier: GenericConfigService.applyRule
production_boundary: src/main/java/example/config/GenericConfigService.java
proof_kind: stateful_side_effect
real_carrier_kind: production_service_method
required_sibling_surfaces: none
minimum_side_effect_or_blocker: repository update
expected_production_diff: GenericConfigService.java
red_expectation: missing rule branch
green_minimum_implementation: implement applyRule behavior
forbidden_substitute_check: passed
forbidden_substitute_proof: not helper-only
fail_closed_condition: block if repository update is not asserted
coverage_cap_if_not_closed: 60
coverage_cap_if_missing: 0
pattern_to_follow: GenericConfigService.applyRule
pattern_return_type: void
pattern_error_handling: exception_propagation
pattern_evidence_source: rg "class GenericConfigService" src/main/java/example/config/GenericConfigService.java
target_carrier_file_path: src/main/java/example/config/GenericConfigService.java
target_carrier_line_number: 3
expected_test_class: GenericConfigServiceTest
expected_test_method: shouldApplyRule
expected_assertions: ["assert captured rule", "verify repository update", "assert response ok"]
expected_side_effects: [{"state":"repository","operation":"update","proof":"ArgumentCaptor"}]
'@

    return $worktree
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifyScript = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("v623-plan-linebreaks-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'escaped-linebreak-plan'
    $worktree = New-PlanFixture -Root $replayRoot

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ReplayRoot $replayRoot -Stage Plan -Worktree $worktree -SkipCarrierAndOracleChecks | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issuesText = @($verify.issues) -join "`n"
    $warningsText = @($verify.warnings) -join "`n"
    $planText = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_RESULT.md') -Raw -Encoding UTF8

    Assert-True 'escaped_linebreak_warning_recorded' ($warningsText -match 'plan_artifact_linebreaks_normalized:PLAN_RESULT.md') $warningsText
    $literalNewline = [char]96 + 'n'
    $remainingLiteralNewlines = [regex]::Matches($planText, [regex]::Escape($literalNewline)).Count
    Assert-True 'escaped_linebreaks_removed_from_plan_result' ($remainingLiteralNewlines -eq 0) $planText.Substring(0, [Math]::Min(300, $planText.Length))
    Assert-True 'stale_blocked_status_auto_repaired' ($planText -match '(?m)^\s*-\s*plan_status\s*[:=]\s*PROCEED\s*$') $planText
    Assert-True 'plan_status_not_proceed_not_emitted' ($issuesText -notmatch 'plan_status_not_proceed:BLOCKED') $issuesText

    [ordered]@{
        status = 'PASS'
        assertions = 4
        cases = @(
            'escaped_linebreaks_normalized_before_plan_status_gate',
            'dash_prefixed_stale_blocked_auto_repaired_after_normalization'
        )
    } | ConvertTo-Json -Depth 5
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
