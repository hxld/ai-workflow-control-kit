param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonObject {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$root = Resolve-AbsolutePath $ReplayRoot
if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
    } | ConvertTo-Json -Depth 6
    exit 0
}

$worktree = Join-Path $root 'worktree'
$ledger = Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json'
if (-not (Test-Path -LiteralPath $worktree)) { throw "Worktree not found: $worktree" }
if (-not (Test-Path -LiteralPath $ledger)) { throw "Requirement family ledger not found: $ledger" }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Prepare-SliceEvidenceContracts.ps1') `
    -ReplayRoot $root `
    -Worktree $worktree `
    -RequirementFamilyLedger $ledger `
    -SliceIndex 2 `
    -ForcedRequirementFamily 'stateful_side_effect' `
    -ForcedSliceType 'stateful_success_slice' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Slice evidence contract preparation failed' }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Validate-ExactContractMatrix.ps1') `
    -ReplayRoot $root `
    -RequiredLiteral 'page_size 15 -> 150|P15..P29' `
    -AllowOraclePostHoc | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Exact contract matrix validation failed' }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1') `
    -ReplayRoot $root `
    -SliceIndex 1 `
    -ForcedRequirementFamily 'core_entry' `
    -ForcedSliceType 'tracer_bullet' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Pre-slice authorization S1 invocation failed' }
$s1 = Read-JsonObject (Join-Path $root 'PRE_SLICE_AUTHORIZATION_01.json')
if ([string]$s1.decision -ne 'ALLOW') { throw "S1 pre-slice authorization should ALLOW, got $($s1.decision)" }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1') `
    -ReplayRoot $root `
    -SliceIndex 2 `
    -ForcedRequirementFamily 'stateful_side_effect' `
    -ForcedSliceType 'stateful_success_slice' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Pre-slice authorization S2 invocation failed' }
$s2 = Read-JsonObject (Join-Path $root 'PRE_SLICE_AUTHORIZATION_02.json')
if ([string]$s2.decision -ne 'STOP') { throw "S2 pre-slice authorization should STOP, got $($s2.decision)" }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Calibrate-FamilyRouter.ps1') `
    -ReplayRoot $root `
    -AssertNextTarget 'exact_contract_slice' `
    -AssertDeployClassification 'soft_residual' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Router/cap calibration failed' }

[ordered]@{
    status = 'PASS'
    replay_root = $root
    assertions = @(
        'exact_contract_matrix_validated',
        'oracle_post_hoc_literals_available',
        's1_pre_slice_allows_tracer',
        's2_pre_slice_stops_invalid_red',
        'router_prioritizes_exact_contract',
        'deploy_surface_soft_residual'
    )
} | ConvertTo-Json -Depth 8
