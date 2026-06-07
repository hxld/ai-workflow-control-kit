param(
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
    Write-Host "PASS: $Message"
}

function Test-HasIssue {
    param(
        [object]$VerifyResult,
        [string]$Pattern
    )
    return (@($VerifyResult.issues | Where-Object { [string]$_ -like $Pattern }).Count -gt 0)
}

function New-BasePhase0Fixture {
    param([string]$Root)

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    @'
# Round Contract

- phase0_status: PROCEED
- selected_real_entry: SampleService.handle()
- first_executable_slice: S1 - core behavior
- first_slice_type: core_path

## Requirement Family Ledger
core_entry

## Real Entry Discovery Matrix
SampleService.handle()

## Behavior Test Charter
RED through SampleService.handle()

## Critical Surface Allocation Plan
side-effect ledger
coverage cap

## exact contract ledger
exact_contract_gap

## side-effect ledger
stateful side effect
'@ | Set-Content -LiteralPath (Join-Path $Root 'ROUND_CONTRACT.md') -Encoding UTF8

    [ordered]@{
        phase0_status = 'PROCEED'
        selected_real_entry = 'SampleService.handle()'
        first_executable_slice = 'S1 - core behavior'
        families = @(
            [ordered]@{
                id = 'core_entry'
                required = $true
                first_executable_carrier = 'SampleService.handle()'
                proof_required = 'real entry behavior'
                coverage_cap_if_open = 60
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Root 'FAMILY_CONTRACT.json') -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v367-schema-exact-" + [guid]::NewGuid().ToString('N'))

try {
    Write-Host 'Test 1: Phase0 BLOCKED on oracle/schema wait is detected as repairable'
    $t1 = Join-Path $tempRoot 'blocked-schema-wait'
    New-BasePhase0Fixture -Root $t1
    @'
# Phase 0 Result

- phase0_status: BLOCKED
- selected_real_entry: SampleService.handle()
- first_executable_slice: S1 - core behavior
- first_slice_type: core_path
- required_flags: exact_contract_gap, schema_verification_gap
- next_action: AWAIT_ORACLE_VERIFICATION_OR_WAIVER

## Critical Blockers

Cannot verify exact oracle method signatures. Provide oracle branch access or use Coverage Cap Waiver before implementation.
'@ | Set-Content -LiteralPath (Join-Path $t1 'PHASE0_RESULT.md') -Encoding UTF8
    @'
# Exploration Report

## Source Boundary
requirement and current code only

## Requirement Literal Inventory
literal A

## Selected Real Entry
selected_real_entry: SampleService.handle()

## Domain Fact Sheet
facts

## Candidate Surface Map
core path

## Uncertainty Ledger
schema_verification_gap and exact_contract_gap

## Planning Input Summary
summary
'@ | Set-Content -LiteralPath (Join-Path $t1 'EXPLORATION_REPORT.md') -Encoding UTF8

    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t1 -Stage Phase0 2>&1
    $verify1 = Get-Content -LiteralPath (Join-Path $t1 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (Test-HasIssue $verify1 '*phase0_blocked_on_oracle_or_schema_uncertainty*') 'repairable BLOCKED must be flagged'
    Assert-True (Test-HasIssue $verify1 '*phase0_manual_oracle_wait*') 'manual oracle/schema wait must be flagged'
    Assert-True (Test-HasIssue $verify1 '*schema_exact_discovery_ledger_missing*') 'schema/exact gap must require discovery ledger'

    Write-Host 'Test 2: Schema/exact gap with discovery ledger and search evidence does not emit discovery ledger issues'
    $t2 = Join-Path $tempRoot 'proceed-with-discovery-ledger'
    New-BasePhase0Fixture -Root $t2
    @'
# Phase 0 Result

- phase0_status: PROCEED
- selected_real_entry: SampleService.handle()
- first_executable_slice: S1 - core behavior
- first_slice_type: core_path
- required_flags: exact_contract_gap, schema_verification_gap
- next_action: PROCEED_WITH_CAPS_AND_DISCOVERY_SLICE
'@ | Set-Content -LiteralPath (Join-Path $t2 'PHASE0_RESULT.md') -Encoding UTF8
    @'
# Exploration Report

## Source Boundary
requirement and current code only

## Requirement Literal Inventory
literal A

## Selected Real Entry
selected_real_entry: SampleService.handle()

## Domain Fact Sheet
facts

## Candidate Surface Map
core path

## Schema and Exact Contract Discovery Ledger
contract item -> current code search command -> discovered source/file/symbol -> confirmed/inferred/blocked -> affected family -> coverage cap -> next executable proof
status field -> rg -n "status" src/main/java -> SampleEntity.java/status -> inferred -> core_entry -> 60 -> RED through SampleService.handle()
payload field -> rg -n "payload" src/main/java -> SampleDto.java/payload -> confirmed -> wire_payload_api_contract -> 40 -> payload shape assertion

## Uncertainty Ledger
schema_verification_gap and exact_contract_gap are capped, not global blockers

## Planning Input Summary
summary
'@ | Set-Content -LiteralPath (Join-Path $t2 'EXPLORATION_REPORT.md') -Encoding UTF8

    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t2 -Stage Phase0 2>&1
    $verify2 = Get-Content -LiteralPath (Join-Path $t2 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (-not (Test-HasIssue $verify2 '*schema_exact_discovery_ledger_missing*')) 'discovery ledger heading should satisfy ledger gate'
    Assert-True (-not (Test-HasIssue $verify2 '*schema_exact_discovery_evidence_missing*')) 'rg/code evidence should satisfy discovery evidence gate'

    Write-Host 'Test 3: Runner has bounded Phase0 unblock repair path'
    $runner = Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($runner.Contains('PHASE0_UNBLOCK_REPAIR_PROMPT.md')) 'runner must create Phase0 unblock repair prompt'
    Assert-True ($runner.Contains('PROCEED_WITH_CAPS_AND_DISCOVERY_SLICE')) 'runner repair must convert schema/exact uncertainty into capped proceed'
    Assert-True ($runner.Contains('phase0_blocked_on_oracle_or_schema_uncertainty')) 'runner must trigger repair on repairable schema/oracle BLOCKED'

    Write-Host 'Test 4: Prompt and control/golden tooling know schema contract discovery'
    $phase0Prompt = Get-Content -LiteralPath (Join-Path $scriptRoot '..\prompts\phase0-contract-gate.prompt.md') -Raw -Encoding UTF8
    $controlSummary = Get-Content -LiteralPath (Join-Path $scriptRoot 'Write-ControlPlaneSummary.ps1') -Raw -Encoding UTF8
    $goldenSlice = Get-Content -LiteralPath (Join-Path $scriptRoot 'Write-GoldenDeliverySlice.ps1') -Raw -Encoding UTF8
    Assert-True ($phase0Prompt.Contains('## Schema and Exact Contract Discovery Ledger')) 'Phase0 prompt must require schema/exact discovery ledger'
    Assert-True ($controlSummary.Contains('schema_contract_discovery_gap')) 'control summary must fingerprint schema/exact discovery gaps'
    Assert-True ($goldenSlice.Contains('schema_exact_discovery_slice')) 'golden delivery slice must provide positive schema/exact guidance'

    [ordered]@{
        status = 'PASS'
        assertions = 10
        cases = @(
            'repairable_phase0_blocked_detected',
            'manual_oracle_wait_detected',
            'schema_exact_discovery_ledger_required',
            'schema_exact_discovery_ledger_satisfies_gate',
            'schema_exact_discovery_evidence_satisfies_gate',
            'runner_unblock_prompt_present',
            'runner_capped_proceed_action_present',
            'runner_repair_trigger_present',
            'phase0_prompt_discovery_ledger_present',
            'control_and_golden_schema_guidance_present'
        )
    } | ConvertTo-Json -Depth 5
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
