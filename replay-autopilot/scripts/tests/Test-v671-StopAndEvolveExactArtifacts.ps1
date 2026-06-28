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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v671-exact-artifacts-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'demo-core\src\main\java\demo') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'
    Write-Utf8 (Join-Path $worktree 'demo-core\src\main\java\demo\RealEntry.java') 'package demo; public class RealEntry { public String handle(String value) { return value; } }'

    $command = "mvn --% -f $(Join-Path $worktree 'pom.xml') -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test"
    @{
        families = @(@{ id = 'core_entry'; required = $true; status = 'OPEN'; weight = 100; required_proof_type = 'real_entry_behavior'; coverage_cap_if_open = 60 })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8
    @{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = 'demo.RealEntry.handle(String): String'
        selected_carrier = 'demo.RealEntry.handle(String): String'
        entry_file = 'demo-core/src/main/java/demo/RealEntry.java'
        production_boundary = 'demo-core/src/main/java/demo/RealEntry.java -> demo.RealEntry.handle(String): String'
        downstream_side_effect_or_output = 'returned payload value'
        red_expectation = 'assertEquals("mapped", result) fails before mapping is fixed'
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    @{
        gate = 'callable_carrier_authorization'
        slice_index = 1
        authorization = 'ALLOW'
        can_proceed = $true
        selected_carrier = 'demo.RealEntry.handle(String): String'
        selected_real_entry = 'demo.RealEntry.handle(String): String'
        file_path = 'demo-core/src/main/java/demo/RealEntry.java'
        resolved_signature = @{ selected_carrier = @{ class_name = 'demo.RealEntry'; visibility = 'public'; formatted = 'String demo.RealEntry.handle(String)' } }
        blockers = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    @{
        callable_carriers = @(@{ signature = 'demo.RealEntry.handle(String): String' })
        failed_carrier_authorizations = @(@{ signature = 'demo.BadEntry.handle()'; reason = 'synthetic_carrier' })
        test_harness_modules = @('demo-harness')
        valid_maven_command_templates = @(@{ module = 'demo-harness'; command = $command })
        forbidden_proof_types_by_family = @{ core_entry = @('mock_only', 'static_only', 'helper_only', 'file_presence') }
        side_effect_probe_examples = @(@{ family = 'core_entry'; probe = 'returned payload value' })
        real_entry_candidates = @(@{ signature = 'demo.RealEntry.handle(String): String' })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRoot 'replay-context-index.json') -Encoding UTF8
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
- selected_carrier: demo.RealEntry.handle(String): String
- selected_real_entry: demo.RealEntry.handle(String): String
- first_red_test: RealEntryContractTest#returnsMappedPayload
- red_command: $command
- green_command: $command
- expected_red_failure: assertEquals("mapped", result) fails before mapping is fixed
- expected_green_assertion: assertEquals("mapped", result) passes through the existing entry
- red_assertion: assertEquals("mapped", result)
- downstream_output_or_side_effect: returned payload value
- entry_file: demo-core/src/main/java/demo/RealEntry.java
- production_boundary: demo-core/src/main/java/demo/RealEntry.java -> demo.RealEntry.handle(String): String
- must_not_behavior: must not use helper-only or mock-only closure
- green_change_boundary: RealEntry.handle return mapping
- validation_command: $command
- entry_invocation_method: new RealEntry().handle("input")
- required_proof_type: real_entry_behavior
"@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType real_entry_behavior | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'pre-slice gate should pass valid v671 exact artifact inputs'

    $carrierResolve = Get-Content -LiteralPath (Join-Path $replayRoot 'carrier_resolve.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $planContract = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_CONTRACT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $testCharter = Get-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$carrierResolve.schema -eq 'carrier_resolve.v1') 'carrier_resolve.json must use exact schema'
    Assert-True ([bool]$carrierResolve.callable) 'carrier_resolve.json must authorize callable carrier'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$carrierResolve.carrier_fqcn)) 'carrier_resolve.json must include carrier_fqcn'
    Assert-True ([string]$planContract.schema -eq 'plan_contract.v1') 'PLAN_CONTRACT.json must use exact schema'
    Assert-True ([string]$planContract.status -eq 'AUTHORIZED') 'PLAN_CONTRACT.json must authorize valid plan'
    Assert-True ([bool]$planContract.not_static_only -and [bool]$planContract.not_helper_only) 'PLAN_CONTRACT.json must reject static/helper proof'
    Assert-True ([string]$testCharter.schema -eq 'test_charter.v1') 'TEST_CHARTER.json must use exact schema'
    Assert-True ([string]$testCharter.status -eq 'AUTHORIZED') 'TEST_CHARTER.json must authorize valid charter'
    Assert-True (@($testCharter.must_not_asserted).Count -gt 0) 'TEST_CHARTER.json must include must-not assertions'

    $promptText = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
    foreach ($needle in @('carrier_resolve.json', 'PLAN_CONTRACT.json', 'TEST_CHARTER.json')) {
        Assert-True ($promptText -match [regex]::Escape($needle)) "phase1 prompt must name $needle"
    }
    $runSliceText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($runSliceText -match 'carrier_resolve\.json') 'Run-SliceLoop stop row must disclose carrier_resolve.json'
    Assert-True ($runSliceText -match 'PLAN_CONTRACT\.json') 'Run-SliceLoop stop row must disclose PLAN_CONTRACT.json'
    Assert-True ($runSliceText -match 'TEST_CHARTER\.json') 'Run-SliceLoop stop row must disclose TEST_CHARTER.json'

    $historyRoot = Join-Path $tempRoot 'history'
    $currentRoot = Join-Path $historyRoot 'claim-codex-replay-v671-autopilot-current'
    $priorRoot = Join-Path $historyRoot 'claim-codex-replay-v670-autopilot-prior'
    foreach ($root in @($currentRoot, $priorRoot)) {
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Write-Utf8 (Join-Path $root 'AUTOPILOT_SUMMARY.md') @"
- oracle_adjusted_coverage: 0
- verification_capped_coverage: 0
- final_status: BLOCKED
wrong_test_surface wrong_test_surface side_effect_ledger_gap exact_contract_gap core_entry_unclosed synthetic_carrier_gap
"@
        Write-Utf8 (Join-Path $root 'ROUND_RESULT.md') @"
- blind_self_assessed_coverage: 0
- verification_capped_coverage: 0
wrong_test_surface side_effect_ledger_gap exact_contract_gap core_entry_unclosed synthetic_carrier_gap
"@
        Write-Utf8 (Join-Path $root 'FINAL_REPLAY_REPORT.md') '- oracle_adjusted_coverage: 0'
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Test-ReplayStopLoss.ps1') `
        -ReplayRoot $currentRoot `
        -HistoryRoot $historyRoot `
        -Lookback 1 `
        -RepeatGapThreshold 1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'stop-loss should complete and write router patch artifact'
    $routerPatch = Get-Content -LiteralPath (Join-Path $currentRoot 'ROUTER_PATCH_REQUIRED.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$routerPatch.status -eq 'REQUIRED') 'ROUTER_PATCH_REQUIRED.json must be required for repeated blocker stop'
    Assert-True (@($routerPatch.blockers).Count -gt 0) 'ROUTER_PATCH_REQUIRED.json must list blockers'
    foreach ($row in @($routerPatch.blockers)) {
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$row.blocker_code)) 'router patch row must include blocker_code'
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$row.producer_artifact)) 'router patch row must include producer_artifact'
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$row.required_artifact)) 'router patch row must include required_artifact'
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$row.acceptance_check)) 'router patch row must include acceptance_check'
    }
    $stopLoss = Get-Content -LiteralPath (Join-Path $currentRoot 'STOP_LOSS_DECISION.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$stopLoss.router_patch_required -match 'ROUTER_PATCH_REQUIRED\.json') 'STOP_LOSS_DECISION.json must reference router patch artifact'

    Write-Host 'v671 Stop-And-Evolve Exact Artifacts: PASS'
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
