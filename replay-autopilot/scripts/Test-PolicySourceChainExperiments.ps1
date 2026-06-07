param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$RequirementSource = 'D:\opt\claim\.doc\policy-num-extension\requirements.md',
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

function Assert-Contains {
    param([string[]]$Values, [string]$Pattern, [string]$Label)
    $match = @($Values | Where-Object { [string]$_ -match $Pattern })
    if ($match.Count -eq 0) { throw "$Label missing pattern: $Pattern" }
}

$root = Resolve-AbsolutePath $ReplayRoot
$worktree = Join-Path $root 'worktree'
$ledger = Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
        requirement_source = $RequirementSource
    } | ConvertTo-Json -Depth 6
    exit 0
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Analyze-SourceChainContract.ps1') `
    -ReplayRoot $root `
    -RequirementSource $RequirementSource | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Analyze-SourceChainContract failed' }

$contract = Read-JsonObject (Join-Path $root 'SOURCE_CHAIN_CONTRACT.json')
if (-not [bool]$contract.required_source_chain) { throw 'SOURCE_CHAIN_CONTRACT should require source chain' }
Assert-Contains -Values @($contract.source_fields | ForEach-Object { [string]$_ }) -Pattern 'CaseRoute\.policyNo' -Label 'source_fields'
Assert-Contains -Values @($contract.source_fields | ForEach-Object { [string]$_ }) -Pattern 'Insure\.insureNo' -Label 'source_fields'
Assert-Contains -Values @($contract.next_required_slice.must_touch_files | ForEach-Object { [string]$_ }) -Pattern 'AiClaimDataAssemblyHelper|AiApplyClaimService|AiCalculateLossService' -Label 'must_touch_files'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1') `
    -ReplayRoot $root `
    -Worktree $worktree `
    -SliceResult (Join-Path $root 'SLICE_RESULT_01.json') `
    -SliceIndex 1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Verify-SliceClosure failed for S1' }

$verify = Read-JsonObject (Join-Path $root 'SLICE_VERIFY_01.json')
if ([string]$verify.carrier_origin -ne 'synthetic_carrier') { throw "S1 should be classified as synthetic_carrier, got $($verify.carrier_origin)" }
if ([bool]$verify.authorized_for_next_slice) { throw 'S1 synthetic source-chain proof should not authorize next slice' }
Assert-Contains -Values @($verify.gap_flags | ForEach-Object { [string]$_ }) -Pattern 'source_chain_unclosed|synthetic_carrier_gap|wrong_test_surface' -Label 'S1 gap_flags'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Prepare-SliceEvidenceContracts.ps1') `
    -ReplayRoot $root `
    -Worktree $worktree `
    -RequirementFamilyLedger $ledger `
    -SliceIndex 2 `
    -ForcedRequirementFamily 'core_entry' `
    -ForcedSliceType 'exact_contract_slice' `
    -ForcedSiblingSurface ([string]$contract.next_required_slice.carrier) | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Prepare-SliceEvidenceContracts failed for source-chain slice' }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1') `
    -ReplayRoot $root `
    -SliceIndex 2 `
    -ForcedRequirementFamily 'core_entry' `
    -ForcedSliceType 'exact_contract_slice' `
    -ForcedSiblingSurface ([string]$contract.next_required_slice.carrier) | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Authorize-PreSliceEvidence failed for source-chain slice' }
$sourceAuth = Read-JsonObject (Join-Path $root 'PRE_SLICE_AUTHORIZATION_02.json')
if ([string]$sourceAuth.decision -ne 'ALLOW') { throw "source-chain S2 should ALLOW, got $($sourceAuth.decision): $($sourceAuth.issues -join ',')" }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Prepare-SliceEvidenceContracts.ps1') `
    -ReplayRoot $root `
    -Worktree $worktree `
    -RequirementFamilyLedger $ledger `
    -SliceIndex 2 `
    -ForcedRequirementFamily 'stateful_side_effect' `
    -ForcedSliceType 'stateful_success_slice' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Prepare-SliceEvidenceContracts failed for stale stateful slice' }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1') `
    -ReplayRoot $root `
    -SliceIndex 2 `
    -ForcedRequirementFamily 'stateful_side_effect' `
    -ForcedSliceType 'stateful_success_slice' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Authorize-PreSliceEvidence failed for stale stateful slice' }
$staleAuth = Read-JsonObject (Join-Path $root 'PRE_SLICE_AUTHORIZATION_02.json')
if ([string]$staleAuth.decision -ne 'STOP') { throw "stale stateful S2 should STOP, got $($staleAuth.decision)" }
Assert-Contains -Values @($staleAuth.issues | ForEach-Object { [string]$_ }) -Pattern 'source_chain|exact_contract' -Label 'stale S2 issues'

[ordered]@{
    status = 'PASS'
    replay_root = $root
    assertions = @(
        'source_chain_contract_detected',
        'synthetic_terminal_payload_rejected',
        'next_required_slice_emitted',
        'source_chain_slice_authorized',
        'stale_stateful_slice_rejected'
    )
} | ConvertTo-Json -Depth 8
