param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "FAIL: $Name" }
        throw "FAIL: $Name - $Details"
    }
    Write-Host "PASS: $Name"
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("phase0-entry-method-alias-v631-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    Write-Text (Join-Path $replayRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

phase0_status: PROCEED

## Selected Real Entry

1. ExistingTaskProcessor.handleTaskResponse

## First Executable Slice

S1
'@
    Write-Text (Join-Path $replayRoot 'EXPLORATION_REPORT.md') @'
## Source Boundary
## Requirement Literal Inventory
## Candidate Surface Map
## Uncertainty Ledger
baseline confirmed
'@
    Write-Text (Join-Path $replayRoot 'ROUND_CONTRACT.md') @'
## Requirement Family Ledger
## Real Entry Discovery Matrix
## Behavior Test Charter
## Critical Surface Allocation Plan
## Side-effect Ledger
## Coverage Cap
'@

    # Test 1: single object with entry_method (the format produced by contract repair)
    ([ordered]@{
        selected_real_entry = [ordered]@{
            carrier_class = 'com.example.replay.ExistingTaskProcessor'
            entry_method = 'handleTaskResponse(TaskRequest, TaskResponse)'
            carrier_status = 'EXISTING'
        }
        first_executable_slice = 'S1'
        families = @(
            [ordered]@{ id = 'core_entry'; required = $true; proof_required = @('Unit test') },
            [ordered]@{ id = 'wire_payload_api_contract'; required = $true; proof_required = @('Map assertion') }
        )
    } | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $replayRoot 'FAMILY_CONTRACT.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Stage Phase0 | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($verify.issues)

    Assert-True 'phase0_accepts_single_object_entry_method' (-not ($issues -contains 'family_contract_selected_real_entry_missing')) ($issues -join ';')
    Assert-True 'phase0_single_object_entry_method_passes' ([string]$verify.verification_status -eq 'PASS') ($issues -join ';')

    # Test 2: array of objects with entry_method (edge case)
    ([ordered]@{
        selected_real_entry = @(
            [ordered]@{
                processor = 'ExistingTaskProcessor'
                entry_method = 'handleTaskResponse'
                carrier_class = 'com.example.replay.ExistingTaskProcessor'
                carrier_status = 'EXISTING'
            },
            [ordered]@{
                processor = 'SecondaryTaskProcessor'
                entry_method = 'secondaryStep'
                carrier_class = 'com.example.replay.SecondaryTaskProcessor'
                carrier_status = 'EXISTING'
            }
        )
        first_executable_slice = 'S1'
        families = @(
            [ordered]@{ id = 'core_entry'; required = $true; proof_required = @('Unit test') }
        )
    } | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $replayRoot 'FAMILY_CONTRACT.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Stage Phase0 | Out-Null
    $verify2 = Get-Content -LiteralPath (Join-Path $replayRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues2 = @($verify2.issues)

    Assert-True 'phase0_accepts_array_entry_method' (-not ($issues2 -contains 'family_contract_selected_real_entry_missing')) ($issues2 -join ';')
    Assert-True 'phase0_array_entry_method_passes' ([string]$verify2.verification_status -eq 'PASS') ($issues2 -join ';')

    # Test 3: existing method field still works (regression)
    ([ordered]@{
        selected_real_entry = @(
            [ordered]@{
                processor = 'ExistingTaskProcessor'
                method = 'rebuildTaskData'
                carrier_class = 'com.example.replay.ExistingTaskProcessor'
                carrier_status = 'EXISTING'
            }
        )
        first_executable_slice = 'S1'
        families = @(
            [ordered]@{ id = 'core_entry'; required = $true; proof_required = @('Unit test') }
        )
    } | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $replayRoot 'FAMILY_CONTRACT.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Stage Phase0 | Out-Null
    $verify3 = Get-Content -LiteralPath (Join-Path $replayRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues3 = @($verify3.issues)

    Assert-True 'regression_accepts_method_field' (-not ($issues3 -contains 'family_contract_selected_real_entry_missing')) ($issues3 -join ';')
    Assert-True 'regression_method_field_passes' ([string]$verify3.verification_status -eq 'PASS') ($issues3 -join ';')

    Write-Host "PASS: v631 phase0 family contract entry_method alias"
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
