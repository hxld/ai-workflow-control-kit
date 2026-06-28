#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$autopilotRoot = Split-Path -Parent $scriptsRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v647-preslice-contracts-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $worktree = Join-Path $tempRoot 'worktree'
    $sourceDir = Join-Path $worktree 'src\main\java\demo'
    New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
    Write-Utf8 (Join-Path $sourceDir 'RealEntry.java') @'
package demo;

public class RealEntry {
    public String handle(String value) {
        return value;
    }
}
'@

    $passRoot = Join-Path $tempRoot 'pass'
    New-Item -ItemType Directory -Force -Path $passRoot | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'demo-harness') | Out-Null
    @{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = 'demo.RealEntry.handle(String): String'
        selected_carrier = 'demo.RealEntry.handle(String): String'
        entry_file = 'src/main/java/demo/RealEntry.java'
        production_boundary = 'src/main/java/demo/RealEntry.java -> demo.RealEntry.handle(String): String'
        downstream_side_effect_or_output = 'returned payload value'
        red_expectation = 'RealEntryContractTest should fail before the return mapping is fixed'
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $passRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    @{
        gate = 'callable_carrier_authorization'
        slice_index = 1
        authorization = 'ALLOW'
        can_proceed = $true
        selected_carrier = 'demo.RealEntry.handle(String): String'
        selected_real_entry = 'demo.RealEntry.handle(String): String'
        file_path = 'src/main/java/demo/RealEntry.java'
        resolved_signature = @{
            selected_carrier = @{
                class_name = 'demo.RealEntry'
                visibility = 'public'
                formatted = 'String demo.RealEntry.handle(String)'
            }
        }
        blockers = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $passRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    @{
        status = 'PASS'
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $passRoot 'REPLAY_CONTEXT_INDEX_VALIDATION.json') -Encoding UTF8
    @{
        families = @(@{
            id = 'core_entry'
            required = $true
            status = 'OPEN'
            weight = 100
            required_proof_type = 'real_entry_behavior'
            coverage_cap_if_open = 60
        })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $passRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8
    @{
        freshness_metadata = @{ initial_after_start_replay_round = 'abc1234' }
        callable_carriers = @(@{ signature = 'demo.RealEntry.handle(String): String' })
        failed_carrier_authorizations = @(@{ signature = 'helper_only'; reason = 'synthetic_carrier' })
        test_harness_modules = @('demo-harness')
        valid_maven_command_templates = @(@{ module = 'demo-harness'; command = "mvn --% -f $(Join-Path $worktree 'pom.xml') -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test" })
        forbidden_proof_types_by_family = @{ core_entry = @('helper_only', 'mock_only', 'static_only') }
        side_effect_probe_examples = @(@{ family = 'core_entry'; probe = 'returned payload value' })
        carrier_candidates = @(@{ signature = 'demo.RealEntry.handle(String): String'; family_id = 'core_entry'; callable_status = 'callable' })
        families = @(@{ id = 'core_entry'; weight = 100 })
        callable_status = @{ 'demo.RealEntry.handle(String): String' = 'callable' }
        test_harness_module = @{ core_entry = 'demo-harness' }
        proof_type = @{ core_entry = 'real_entry_behavior' }
        forbidden_proof = @('helper_only', 'mock_only', 'static_only')
        failed_signature_cache = @()
        real_entry_candidates = @(@{ signature = 'demo.RealEntry.handle(String): String' })
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $passRoot 'replay-context-index.json') -Encoding UTF8
    Write-Utf8 (Join-Path $passRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
- selected_carrier: demo.RealEntry.handle(String): String
- selected_real_entry: demo.RealEntry.handle(String): String
- first_red_test: RealEntryContractTest#returnsMappedPayload
- red_command: mvn --% -f WORKTREE\pom.xml -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test
- green_command: mvn --% -f WORKTREE\pom.xml -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test
- expected_red_failure: assertEquals("mapped", result) fails before mapping is fixed
- expected_green_assertion: assertEquals("mapped", result) passes through RealEntry
- red_assertion: assertEquals("mapped", result)
- downstream_output_or_side_effect: returned payload value
- entry_file: src/main/java/demo/RealEntry.java
- production_boundary: src/main/java/demo/RealEntry.java -> demo.RealEntry.handle(String): String
- must_not_behavior: must not use helper-only or mock-only closure
- green_change_boundary: RealEntry.handle return mapping
- validation_command: mvn --% -f WORKTREE\pom.xml -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test
'@
    $planPath = Join-Path $passRoot 'FIRST_SLICE_PROOF_PLAN.md'
    (Get-Content -LiteralPath $planPath -Raw -Encoding UTF8).Replace('WORKTREE', ($worktree -replace '\\', '\')) | Set-Content -LiteralPath $planPath -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $passRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType stateful_core_slice
    Assert-True ($LASTEXITCODE -eq 0) 'authorizing pre-slice contract should pass'
    $dryRun = Get-Content -LiteralPath (Join-Path $passRoot 'CARRIER_AUTHORIZATION_DRY_RUN_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = Get-Content -LiteralPath (Join-Path $passRoot 'SLICE_PLAN_CONTRACT_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $firstExecutable = Get-Content -LiteralPath (Join-Path $passRoot 'FIRST_SLICE_EXECUTABLE_CONTRACT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $runnable = Get-Content -LiteralPath (Join-Path $passRoot 'RUNNABLE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $callable = Get-Content -LiteralPath (Join-Path $passRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $charter = Get-Content -LiteralPath (Join-Path $passRoot 'TEST_CHARTER_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $carrierLock = Get-Content -LiteralPath (Join-Path $passRoot 'CARRIER_LOCK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$dryRun.pre_authorized) 'dry-run must expose pre_authorized=true'
    Assert-True ([string]$plan.authorization -eq 'ALLOW') 'slice plan contract must authorize valid proof plan'
    Assert-True ([string]$firstExecutable.authorization -eq 'ALLOW') 'first slice executable contract must authorize valid proof plan'
    Assert-True ([string]$firstExecutable.contract_status -eq 'AUTHORIZED') 'first slice executable contract must expose contract_status=AUTHORIZED'
    Assert-True ([string]$firstExecutable.real_entry_fqn -match 'demo\.RealEntry') 'first slice executable contract must expose real_entry_fqn'
    Assert-True ([string]$firstExecutable.test_harness_module -eq 'demo-harness') 'first slice executable contract must expose test_harness_module'
    Assert-True ([string]$firstExecutable.test_class -eq 'RealEntryContractTest') 'first slice executable contract must expose test_class'
    Assert-True ([string]$firstExecutable.test_method -eq 'returnsMappedPayload') 'first slice executable contract must expose test_method'
    Assert-True ([bool]$firstExecutable.uses_isolated_replay_pom) 'first slice executable contract must prove isolated replay POM use'
    Assert-True ([string]$firstExecutable.green_business_assertion -match 'assertEquals') 'first slice executable contract must expose green business assertion'
    Assert-True ([string]$firstExecutable.existing_entry_qn -match 'demo\.RealEntry') 'first slice executable contract must bind an existing entry qn'
    Assert-True (@($carrierLock.expected_production_files) -contains 'src/main/java/demo/RealEntry.java') 'carrier lock must expose expected production file'
    Assert-True ([string]$runnable.status -eq 'AUTHORIZED') 'runnable slice authorization must authorize copy-ready commands'
    Assert-True ([string]$runnable.real_entry_fqn -match 'demo\.RealEntry') 'runnable authorization must expose real_entry_fqn'
    Assert-True ([string]$runnable.test_harness_module -eq 'demo-harness') 'runnable authorization must expose test_harness_module'
    Assert-True ([string]$runnable.test_class -eq 'RealEntryContractTest') 'runnable authorization must expose test_class'
    Assert-True ([string]$runnable.test_method -eq 'returnsMappedPayload') 'runnable authorization must expose test_method'
    Assert-True ([string]$runnable.maven_test_command_template -match '-pl demo-harness -am') 'runnable authorization must expose Maven test command template'
    Assert-True ([string]$runnable.green_business_assertion -match 'assertEquals') 'runnable authorization must expose green business assertion'
    Assert-True ([bool]$runnable.uses_isolated_replay_pom) 'runnable slice authorization must require isolated replay POM'
    Assert-True ([string]$callable.authorization_status -eq 'AUTHORIZED') 'callable carrier authorization must expose authorization_status=AUTHORIZED'
    Assert-True ([string]$callable.carrier_origin -eq 'existing_production_entry') 'callable carrier authorization must bind existing production entry origin'
    Assert-True ([string]$charter.status -eq 'AUTHORIZED') 'test charter contract must authorize state/output and must-not proof'
    Assert-True ([bool]$charter.side_effect_proof_required) 'test charter contract must require side-effect proof for core_entry'
    Assert-True ([string]$charter.side_effect_target -match 'returned payload') 'test charter contract must expose side-effect target'
    Assert-True ([string]$charter.capture_mechanism -match 'behavior test assertion') 'test charter contract must expose capture mechanism'
    Assert-True ([string]$charter.must_fail_before_change -match 'assertEquals') 'test charter contract must expose business RED failure'
    Assert-True ([string]$charter.forbidden_test_surface -match 'helper-only') 'test charter contract must expose forbidden test surface'
    Assert-True (@($charter.positive_assertions).Count -gt 0) 'test charter contract must include positive assertions'

    $blockedRoot = Join-Path $tempRoot 'blocked'
    New-Item -ItemType Directory -Force -Path $blockedRoot | Out-Null
    @{
        schema_version = 1
        slice_index = 1
        authorization = 'STOP'
        selected_carrier = 'helper_only'
        real_entry = 'none'
        issues = @('helper_or_static_only_carrier_for_high_weight_family')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $blockedRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $blockedRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType stateful_core_slice 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'non-authorizing carrier should fail before executor'
    $blockedPre = Get-Content -LiteralPath (Join-Path $blockedRoot 'SLICE_RESULT_PRE_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([int]$blockedPre.slice_index -eq 0) 'blocked pre-slice result must preserve slice_index=0'
    Assert-True (-not [bool]$blockedPre.authorized_for_synthesis) 'blocked pre-slice result must not authorize synthesis'

    $missingRoot = Join-Path $tempRoot 'missing-fields'
    New-Item -ItemType Directory -Force -Path $missingRoot | Out-Null
    @{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = 'demo.RealEntry.handle(String): String'
        selected_carrier = 'demo.RealEntry.handle(String): String'
        production_boundary = 'demo.RealEntry.handle(String): String'
        downstream_side_effect_or_output = 'returned payload value'
        red_expectation = 'business assertion fails before mapping is fixed'
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $missingRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    @{
        gate = 'callable_carrier_authorization'
        slice_index = 1
        authorization = 'ALLOW'
        can_proceed = $true
        selected_carrier = 'demo.RealEntry.handle(String): String'
        selected_real_entry = 'demo.RealEntry.handle(String): String'
        resolved_signature = @{ selected_carrier = @{ class_name = 'demo.RealEntry'; visibility = 'public'; formatted = 'String demo.RealEntry.handle(String)' } }
        blockers = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $missingRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    Write-Utf8 (Join-Path $missingRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
- selected_carrier: demo.RealEntry.handle(String): String
- selected_real_entry: demo.RealEntry.handle(String): String
- first_red_test: RealEntryContractTest
- expected_red_failure: assertEquals("mapped", result) fails before mapping is fixed
- expected_green_assertion: assertEquals("mapped", result) passes through RealEntry
- downstream_output_or_side_effect: returned payload value
- production_boundary: demo.RealEntry.handle(String): String
- must_not_behavior: must not use helper-only closure
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $missingRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily deploy_export_page `
        -ForcedSliceType deploy_surface_slice 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'missing executable contract fields should stop before executor'
    $missingRunnable = Get-Content -LiteralPath (Join-Path $missingRoot 'RUNNABLE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $missingCodes = @($missingRunnable.issues | ForEach-Object { [string]$_ })
    Assert-True ($missingCodes -contains 'missing_test_harness_module') 'missing -pl module must emit missing_test_harness_module'
    Assert-True ($missingCodes -contains 'missing_test_method') 'missing method must emit missing_test_method'
    Assert-True ($missingCodes -contains 'missing_maven_test_command_template') 'missing command template must emit missing_maven_test_command_template'
    Assert-True ($missingCodes -contains 'missing_red_command') 'missing red command must emit missing_red_command'
    Assert-True ($missingCodes -contains 'missing_green_command') 'missing green command must emit missing_green_command'
    Assert-True ($missingCodes -contains 'non_isolated_pom_command') 'missing isolated POM proof must emit non_isolated_pom_command'
    $missingCharter = Get-Content -LiteralPath (Join-Path $missingRoot 'TEST_CHARTER_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$missingCharter.side_effect_proof_required) 'deploy_export_page must require side-effect proof charter'

    $runnerText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    $promptText = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
    Assert-True ($runnerText -match 'Invoke-PreSliceExperimentContracts\.ps1') 'Run-SliceLoop must invoke the pre-slice experiment contract gate'
    Assert-True ($runnerText -match 'carrier_authorization_dry_run') 'Run-SliceLoop must surface carrier dry-run artifact'
    Assert-True ($runnerText -match 'FIRST_SLICE_EXECUTABLE_CONTRACT') 'Run-SliceLoop must surface first slice executable contract artifact'
    Assert-True ($runnerText -match 'RUNNABLE_SLICE_AUTHORIZATION') 'Run-SliceLoop must surface runnable authorization artifact'
    Assert-True ($runnerText -match 'TEST_CHARTER_\{0:D2\}') 'Run-SliceLoop must surface test charter contract artifact'
    Assert-True ($promptText -match 'pre_authorized=true') 'Phase1 prompt must block implementation until carrier dry-run is pre-authorized'
    Assert-True ($promptText -match 'authorization=ALLOW') 'Phase1 prompt must bind SLICE_PLAN_CONTRACT authorization'
    Assert-True ($promptText -match 'RUNNABLE_FIRST_SLICE') 'Phase1 prompt must require runnable-first-slice state'
    Assert-True ($promptText -match 'BLOCKED_NO_RUNNABLE_SLICE') 'Phase1 prompt must require blocked-no-runnable-slice state'

    Write-Host 'v647 Pre-Slice Experiment Contracts: PASS'
    exit 0
} catch {
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
