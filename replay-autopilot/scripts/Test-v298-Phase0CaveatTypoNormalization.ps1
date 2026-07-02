param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\v298-phase0-caveat-typo-normalization'),
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID'; test_root = $TestRoot } | ConvertTo-Json -Depth 4
    exit 0
}

if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

Write-Utf8 (Join-Path $TestRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

## Phase 0 Status

**phase0_status**: `PROCEED_WITH_CAVIETS`

## Selected Real Entry

Primary Entry: ExampleFlowService.processAutoFlow(Long caseId, ExampleCalculatorResult aiResult)

## First Executable Slice

S1 - Core path

## First Slice Type

Type: core_path
'@

Write-Utf8 (Join-Path $TestRoot 'EXPLORATION_REPORT.md') @'
## Source Boundary
ok

## Requirement Literal Inventory
ok

## Selected Real Entry
Primary Entry: ExampleFlowService.processAutoFlow(Long caseId, ExampleCalculatorResult aiResult)

## Candidate Surface Map
ok

## Uncertainty Ledger
ok

## Domain Fact Sheet
ok

## Planning Input Summary
ok
'@

Write-Utf8 (Join-Path $TestRoot 'ROUND_CONTRACT.md') 'selected_real_entry: ExampleFlowService.processAutoFlow'
Write-Utf8 (Join-Path $TestRoot 'FAMILY_CONTRACT.json') (@{
    selected_real_entry = 'ExampleFlowService.processAutoFlow'
    families = @(
        @{
            id = 'core_entry'
            required = $true
            first_executable_carrier = 'ExampleFlowService.processAutoFlow'
            coverage_cap_if_open = 60
        }
    )
} | ConvertTo-Json -Depth 6)

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $TestRoot -Stage Phase0 | Out-Null
$verify = Get-Content -LiteralPath (Join-Path $TestRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$issueText = @($verify.issues) -join ';'
Assert-True ($issueText -notmatch 'phase0_status_not_proceed') "PROCEED_WITH_CAVIETS should still normalize to PROCEED for routing, issues=$issueText"
Assert-True ($issueText -match 'phase0_status_noncanonical:PROCEED_WITH_CAVIETS') "Verifier must fail closed on noncanonical Phase0 status, issues=$issueText"

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Parse-ReplayReport.ps1') -ReplayRoot $TestRoot | Out-Null
$summary = Get-Content -LiteralPath (Join-Path $TestRoot 'AUTOPILOT_SUMMARY.md') -Raw -Encoding UTF8
Assert-True ($summary -match '(?m)^- phase0_status: PROCEED') 'Parser summary should normalize misspelled caveated status to PROCEED'

$runnerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
$verifierText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -Raw -Encoding UTF8
$parserText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Parse-ReplayReport.ps1') -Raw -Encoding UTF8

Assert-True ($runnerText.Contains('CAVEATS|CAVIETS|CAVETS')) 'Runner must normalize correct and misspelled caveated proceed statuses'
Assert-True ($verifierText.Contains('phase0_status_noncanonical')) 'Verifier must flag caveated proceed statuses as noncanonical'
Assert-True ($parserText.Contains('CAVEATS|CAVIETS|CAVETS')) 'Parser must normalize correct and misspelled caveated proceed statuses'

[ordered]@{
    status = 'PASS'
    assertions = 6
    cases = @(
        'verify_plan_contract_normalizes_proceed_with_caviets_for_routing',
        'verify_plan_contract_flags_noncanonical_caviets',
        'parse_replay_report_normalizes_proceed_with_caviets',
        'runner_contains_caveat_typo_normalizer',
        'verifier_flags_caveat_typo_noncanonical',
        'parser_contains_caveat_typo_normalizer'
    )
} | ConvertTo-Json -Depth 5
