param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

function Write-Text {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$validator = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v312-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    Write-Text (Join-Path $tmp 'PHASE0_RESULT.md') @'
# Phase 0 Result

phase0_status: PROCEED
selected_real_entry: ExistingProcessor.handleTaskResponse()
selected_real_entry_source: worktree
first_executable_slice: core entry executable slice
first_slice_type: core_path
Oracle Commit: 07d37b6c30d42f0737a2629f051b9d7b76baf78e
Note: Oracle structural metadata informs priority and cap decisions only.
'@
    Write-Text (Join-Path $tmp 'ROUND_CONTRACT.md') @'
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
    Write-Text (Join-Path $tmp 'EXPLORATION_REPORT.md') @'
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
    Write-Text (Join-Path $tmp 'FAMILY_CONTRACT.json') '{"selected_real_entry":"ExistingProcessor.handleTaskResponse()","first_executable_slice":"core entry executable slice"}'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $tmp -Stage Phase0 | Out-Null
    $verifyText = Get-Content -LiteralPath (Join-Path $tmp 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8
    $null = Assert-True -Name 'oracle_commit_header_not_manual_wait' -Condition ($verifyText -notmatch 'phase0_manual_oracle_wait')

    (Get-Content -LiteralPath (Join-Path $tmp 'PHASE0_RESULT.md') -Raw -Encoding UTF8).Replace('Oracle Commit: 07d37b6c30d42f0737a2629f051b9d7b76baf78e', 'Oracle commit pending before implementation') |
        Set-Content -LiteralPath (Join-Path $tmp 'PHASE0_RESULT.md') -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $tmp -Stage Phase0 | Out-Null
    $verifyText = Get-Content -LiteralPath (Join-Path $tmp 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8
    $null = Assert-True -Name 'oracle_commit_pending_still_blocked' -Condition ($verifyText -match 'phase0_manual_oracle_wait')
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

[ordered]@{
    status = 'PASS'
    assertions = 2
    cases = @(
        'oracle_commit_header_not_manual_wait',
        'oracle_commit_pending_still_blocked'
    )
} | ConvertTo-Json -Depth 5
