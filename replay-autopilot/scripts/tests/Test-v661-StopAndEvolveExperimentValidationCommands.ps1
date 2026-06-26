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

function New-ValidReplayFixture {
    param([string]$ReplayRoot, [string]$Worktree)

    New-Item -ItemType Directory -Force -Path (Join-Path $Worktree 'demo-harness') | Out-Null
    Write-Utf8 (Join-Path $Worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'
    $command = "mvn --% -f $(Join-Path $Worktree 'pom.xml') -pl demo-harness -am -Dtest=RealEntryContractTest#returnsMappedPayload -Dsurefire.failIfNoSpecifiedTests=false test"

    @{
        families = @(
            @{ id = 'core_entry'; required = $true; status = 'OPEN'; weight = 100; required_proof_type = 'real_entry_behavior'; coverage_cap_if_open = 60 },
            @{ id = 'stateful_side_effect'; required = $true; status = 'OPEN'; weight = 95; required_proof_type = 'stateful_side_effect'; coverage_cap_if_open = 60 }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8

    @{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = 'demo.RealEntry.handle(String): String'
        selected_carrier = 'demo.RealEntry.handle(String): String'
        production_boundary = 'demo.RealEntry.handle(String): String'
        downstream_side_effect_or_output = 'returned payload value and audit status write'
        red_expectation = 'assertEquals("mapped", result) fails before mapping is fixed'
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    @{
        gate = 'callable_carrier_authorization'
        slice_index = 1
        authorization = 'ALLOW'
        can_proceed = $true
        selected_carrier = 'demo.RealEntry.handle(String): String'
        selected_real_entry = 'demo.RealEntry.handle(String): String'
        resolved_signature = @{ selected_carrier = @{ class_name = 'demo.RealEntry'; visibility = 'public'; formatted = 'String demo.RealEntry.handle(String)' } }
        blockers = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    Write-Utf8 (Join-Path $ReplayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
- selected_carrier: demo.RealEntry.handle(String): String
- selected_real_entry: demo.RealEntry.handle(String): String
- first_red_test: RealEntryContractTest#returnsMappedPayload
- red_command: $command
- green_command: $command
- expected_red_failure: assertEquals("mapped", result) fails before mapping is fixed
- expected_green_assertion: assertEquals("mapped", result) passes through the existing entry
- red_assertion: assertEquals("mapped", result)
- downstream_output_or_side_effect: returned payload value and audit status write
- production_boundary: demo.RealEntry.handle(String): String
- must_not_behavior: must not use helper-only or mock-only closure
- green_change_boundary: RealEntry.handle return mapping
- validation_command: $command
- entry_invocation_method: new RealEntry().handle("input")
- required_proof_type: real_entry_behavior
"@
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$autopilotRoot = Split-Path -Parent $scriptsRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v661-stop-evolve-validation-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    New-ValidReplayFixture -ReplayRoot $replayRoot -Worktree $worktree

    foreach ($scriptName in @('run-carrier-lock-precheck.ps1', 'validate-first-slice-contract.ps1', 'validate-behavior-test-charter.ps1', 'validate-family-proof-router.ps1')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $scriptsRoot $scriptName)) "$scriptName must exist"
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot $scriptName) -ReplayRoot $replayRoot -Slice 1 | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "$scriptName should pass or stop cleanly on valid aggregate gate inputs"
    }

    $carrierLock = Get-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_LOCK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $charter = Get-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $slicePlan = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_PLAN_CONTRACT_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$carrierLock.experiment -eq 'pre_budget_carrier_lock') 'CARRIER_LOCK.json must identify the carrier-lock experiment'
    Assert-True ([string]$carrierLock.carrier_lock_status -eq 'PASS') 'valid carrier lock must report PASS'
    Assert-True ([string]$charter.experiment -eq 'behavior_test_charter_gate') 'TEST_CHARTER_01.json must identify the behavior-charter experiment'
    Assert-True ([string]$charter.behavior_test_charter_status -eq 'PASS') 'valid behavior charter must report PASS'
    Assert-True (@($charter.side_effect_assertions).Count -gt 0) 'behavior charter must carry side-effect assertions'
    Assert-True ([string]$slicePlan.experiment -eq 'high_weight_family_proof_router') 'SLICE_PLAN_CONTRACT_01.json must identify the proof-router experiment'
    Assert-True ([string]$slicePlan.selected_family -eq 'core_entry') 'proof router must select the highest-weight open family'
    Assert-True ([string]$slicePlan.router_status -eq 'PASS') 'valid proof router must report PASS'

    $badReplayRoot = Join-Path $tempRoot 'bad-replay'
    $badWorktree = Join-Path $badReplayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $badWorktree | Out-Null
    Write-Utf8 (Join-Path $badWorktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'
    @{
        families = @(@{ id = 'core_entry'; required = $true; status = 'OPEN'; weight = 100; required_proof_type = 'real_entry_behavior'; coverage_cap_if_open = 60 })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $badReplayRoot 'REQUIREMENT_FAMILY_LEDGER.json') -Encoding UTF8
    @{
        schema_version = 1
        slice_index = 1
        authorization = 'STOP'
        real_entry = ''
        selected_carrier = 'helper_only'
        production_boundary = 'helper_only'
        downstream_side_effect_or_output = 'static_only'
        red_expectation = ''
        issues = @('synthetic_carrier')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $badReplayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'run-carrier-lock-precheck.ps1') -ReplayRoot $badReplayRoot -Slice 1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'carrier precheck should treat invalid carrier as a clean STOP, not a script failure'
    $badBlocker = Get-Content -LiteralPath (Join-Path $badReplayRoot 'SLICE_RESULT_PRE_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$badBlocker.slice_status -eq 'BLOCKED') 'invalid carrier must write blocked pre-slice result'
    Assert-True (-not [bool]$badBlocker.executor_invoked) 'invalid carrier stop must keep executor_invoked=false'
    Assert-True (@($badBlocker.implemented_files).Count -eq 0) 'invalid carrier stop must not claim implemented files'
    Assert-True ([int]$badBlocker.coverage_delta -eq 0) 'invalid carrier stop must not claim coverage'

    $aggregateText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') -Raw -Encoding UTF8
    $promptText = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
    Assert-True ($aggregateText -match 'pre_budget_carrier_lock') 'aggregate gate must emit pre-budget carrier lock experiment marker'
    Assert-True ($aggregateText -match 'behavior_test_charter_gate') 'aggregate gate must emit behavior charter experiment marker'
    Assert-True ($aggregateText -match 'high_weight_family_proof_router') 'aggregate gate must emit proof router experiment marker'
    Assert-True ($promptText -match 'run-carrier-lock-precheck\.ps1') 'slice prompt must name carrier-lock validation command'
    Assert-True ($promptText -match 'validate-behavior-test-charter\.ps1') 'slice prompt must name behavior-charter validation command'
    Assert-True ($promptText -match 'validate-family-proof-router\.ps1') 'slice prompt must name family-router validation command'
    Assert-True ($promptText -match 'validate-first-slice-contract\.ps1') 'slice prompt must name first-slice contract validation command'
    Assert-True ($promptText -match 'validate-behavior-proof\.ps1') 'slice prompt must name behavior-proof validation command'

    $validSlice = @{
        slice_status = 'DONE'
        coverage_delta = 10
        test_execution_evidence = 'GREEN Maven pass invoked demo.RealEntry.handle(String): String and asserted returned payload value'
        test_execution_exit_code = 0
        entry_invoked = 'demo.RealEntry.handle(String): String'
        production_boundary = 'demo.RealEntry.handle(String): String'
        proof_kind = 'real_entry_behavior'
        closed_assertions = @('assert returned payload value and audit status state')
        side_effect_probe = 'audit status write'
        negative_probe = 'must not use helper-only closure'
        tests = @(@{ phase = 'GREEN'; result = 'pass'; evidence = 'assert returned payload value and audit status state'; command = $command })
    }
    $validSlice | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Encoding UTF8
    @{
        authorized_for_next_slice = $true
        authorization_blockers = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'validate-behavior-proof.ps1') -ReplayRoot $replayRoot -Slice 1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'behavior-proof validator must pass executed real-entry behavior proof'

    $compileOnlySlice = $validSlice.Clone()
    $compileOnlySlice.proof_kind = 'compile_only'
    $compileOnlySlice.test_execution_evidence = ''
    $compileOnlySlice.entry_invoked = 'helper_only'
    $compileOnlySlice | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'validate-behavior-proof.ps1') -ReplayRoot $replayRoot -Slice 1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'behavior-proof validator must reject compile-only/helper-only nonzero coverage'

    Write-Host 'v661 STOP_AND_EVOLVE experiment validation commands: PASS'
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
