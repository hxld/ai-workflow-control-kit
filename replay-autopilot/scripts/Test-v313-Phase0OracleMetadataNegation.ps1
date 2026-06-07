param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
}

function Write-Text {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Write-Phase0Fixture {
    param([string]$Root, [string]$SelectedEvidence)
    Write-Text (Join-Path $Root 'PHASE0_RESULT.md') @"
# Phase 0 Result

phase0_status: PROCEED
selected_real_entry: ExistingProcessor.handleTaskResponse()
selected_real_entry_source: worktree
first_executable_slice: core entry executable slice
first_slice_type: core_path

## Selected Real Entry
$SelectedEvidence
"@
    Write-Text (Join-Path $Root 'ROUND_CONTRACT.md') @'
# Round Contract
## Source Boundary
current worktree only
## Requirement Literal Inventory
literal
## Selected Real Entry
ExistingProcessor.handleTaskResponse()
## Critical Surface Allocation Plan
core path
## Diff Ledger Expectations
diff
## Side Effect Ledger
side effect
## Test Charter
test
## First Executable Slice
core entry executable slice
'@
    Write-Text (Join-Path $Root 'EXPLORATION_REPORT.md') @'
# Exploration Report
## Source Boundary
current worktree only
## Requirement Literal Inventory
literal
## Selected Real Entry
ExistingProcessor.handleTaskResponse()
## Critical Surface Allocation Plan
core path
## Diff Ledger Expectations
diff
## Side Effect Ledger
side effect
## Test Charter
test
'@
    Write-Text (Join-Path $Root 'FAMILY_CONTRACT.json') '{"selected_real_entry":"ExistingProcessor.handleTaskResponse()","first_executable_slice":"core entry executable slice"}'
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$validator = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v313-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $negatedRoot = Join-Path $tmp 'negated'
    New-Item -ItemType Directory -Force -Path $negatedRoot | Out-Null
    Write-Phase0Fixture -Root $negatedRoot -SelectedEvidence 'Selected Entry Evidence Source: requirement analysis and existing worktree code. Oracle metadata used for structural reference only, not for entry selection decision.'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $negatedRoot -Stage Phase0 | Out-Null
    $verifyText = Get-Content -LiteralPath (Join-Path $negatedRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8
    Assert-True -Name 'negated_oracle_metadata_reference_not_blocked' -Condition ($verifyText -notmatch 'phase0_oracle_inferred_selected_entry')

    $inferredRoot = Join-Path $tmp 'inferred'
    New-Item -ItemType Directory -Force -Path $inferredRoot | Out-Null
    Write-Phase0Fixture -Root $inferredRoot -SelectedEvidence 'Selected Entry Evidence Source: selected_real_entry is based on Oracle metadata and oracle-added files.'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $inferredRoot -Stage Phase0 | Out-Null
    $verifyText = Get-Content -LiteralPath (Join-Path $inferredRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8
    Assert-True -Name 'oracle_metadata_authority_still_blocked' -Condition ($verifyText -match 'phase0_oracle_inferred_selected_entry')
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

[ordered]@{
    status = 'PASS'
    assertions = 2
    cases = @(
        'negated_oracle_metadata_reference_not_blocked',
        'oracle_metadata_authority_still_blocked'
    )
} | ConvertTo-Json -Depth 5
