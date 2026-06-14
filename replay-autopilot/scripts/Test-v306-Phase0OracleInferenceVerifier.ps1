param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v306-phase0-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$cases = New-Object System.Collections.Generic.List[string]

try {
    Write-Text (Join-Path $tmp 'PHASE0_RESULT.md') @'
# Phase 0 Result

**phase0_status**: `PROCEED_WITH_CAVEATS`

**selected_real_entry**: `ExampleFlowService`

**Oracle Evidence**:
- Path: `example-core/src/main/java/com/example/project/core/ai/service/ExampleFlowService.java`

**Inference Confidence**: HIGH (based on Oracle metadata)

**Validation Status**: INFERRED (待Oracle post-hoc验证exact method signature)

## Next Action

Phase 0 (DONE) -> Oracle Post-Hoc -> Deep Plan -> OpenSpec -> Dev Workflow
'@
    Write-Text (Join-Path $tmp 'EXPLORATION_REPORT.md') @'
## Source Boundary
ok
## Requirement Literal Inventory
ok
## Selected Real Entry
selected_real_entry: ExampleFlowService
## Domain Fact Sheet
ok
## Candidate Surface Map
ok
## Uncertainty Ledger
ok
## Planning Input Summary
ok
'@
    Write-Text (Join-Path $tmp 'ROUND_CONTRACT.md') @'
selected_real_entry: ExampleFlowService
## Critical Surface Allocation Plan
| Surface / family | Why required | First executable slice | Carrier / entry | Proof required | Deferred blocker / coverage cap |
| --- | --- | --- | --- | --- | --- |
| core_entry | required | S1 | ExampleFlowService | real behavior | none |
'@
    [ordered]@{
        selected_real_entry = 'ExampleFlowService'
        first_executable_slice = 'S1'
        families = @(
            [ordered]@{
                id = 'core_entry'
                required = $true
                first_executable_carrier = 'ExampleFlowService'
                coverage_cap_if_open = 60
            }
        )
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tmp 'FAMILY_CONTRACT.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $tmp -Stage Phase0 | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $tmp 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($verify.issues) -join ';'
    $cases.Add((Assert-True -Name 'noncanonical_phase0_status_rejected' -Condition ($issues -match 'phase0_status_noncanonical:PROCEED_WITH_CAVEATS'))) | Out-Null
    $cases.Add((Assert-True -Name 'oracle_inferred_selected_entry_rejected' -Condition ($issues -match 'phase0_oracle_inferred_selected_entry'))) | Out-Null
    $cases.Add((Assert-True -Name 'manual_oracle_wait_rejected' -Condition ($issues -match 'phase0_manual_oracle_wait'))) | Out-Null
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5

