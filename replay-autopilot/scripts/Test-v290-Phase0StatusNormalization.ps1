param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\v290-phase0-status-normalization'),
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

**Status**: `PROCEED_WITH_CAVEATS`

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
Assert-True ($issueText -notmatch 'phase0_status_not_proceed') "PROCEED_WITH_CAVEATS should normalize to PROCEED, issues=$issueText"

$runnerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
$verifierText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -Raw -Encoding UTF8
$phase0Prompt = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\prompts\phase0-contract-gate.prompt.md') -Raw -Encoding UTF8

Assert-True ($runnerText.Contains('Normalize-Phase0Status') -and $runnerText.Contains('CAVEATS|CAVIETS')) 'Runner must normalize caveated proceed status, including common typo'
Assert-True ($verifierText.Contains('Normalize-Phase0Status') -and $verifierText.Contains('CAVEATS|CAVIETS')) 'Verifier must normalize caveated proceed status, including common typo'
Assert-True ($phase0Prompt.Contains('custom status values') -and $phase0Prompt.Contains('PROCEED_WITH_CAVEATS')) 'Phase0 prompt must forbid custom status values'

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

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $TestRoot -Stage Phase0 | Out-Null
$typoVerify = Get-Content -LiteralPath (Join-Path $TestRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$typoIssueText = @($typoVerify.issues) -join ';'
Assert-True ($typoIssueText -notmatch 'phase0_status_not_proceed') "PROCEED_WITH_CAVIETS should normalize to PROCEED, issues=$typoIssueText"

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Parse-ReplayReport.ps1') -ReplayRoot $TestRoot | Out-Null
$summaryText = Get-Content -LiteralPath (Join-Path $TestRoot 'AUTOPILOT_SUMMARY.md') -Raw -Encoding UTF8
Assert-True ($summaryText -match '(?m)^- phase0_status: PROCEED') 'Parse-ReplayReport should normalize PROCEED_WITH_CAVIETS to PROCEED'

[ordered]@{
    status = 'PASS'
    assertions = 6
    cases = @(
        'verify_plan_contract_normalizes_caveated_status',
        'runner_contains_status_normalizer',
        'verifier_contains_status_normalizer',
        'phase0_prompt_forbids_custom_status',
        'verify_plan_contract_normalizes_misspelled_caveated_status',
        'parse_replay_report_normalizes_misspelled_caveated_status'
    )
} | ConvertTo-Json -Depth 5
