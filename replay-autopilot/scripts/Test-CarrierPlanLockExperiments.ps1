param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$RequirementSource
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

$root = Resolve-AbsolutePath $ReplayRoot
$worktree = Join-Path $root 'worktree'
$ledger = Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Analyze-SourceChainContract.ps1') -ReplayRoot $root -RequirementSource $RequirementSource | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Analyze-SourceChainContract failed' }

$wrongCarrier = [ordered]@{
    schema_version = 1
    slice_index = 1
    forced_requirement_family = 'core_entry'
    forced_slice_type = 'exact_contract_slice'
    forced_sibling_surface = 'CaseRoute.policyNo / Insure.recordNo -> RequestBuildContext -> ExampleBaseRequest -> ExampleBaseTaskData -> InputData.policy_num/InputData.insure_num'
    authorization = 'ALLOW'
    real_entry = 'ExampleDataAssemblyHelper + ExampleApplyClaimService + ExampleCalculatorService'
    selected_carrier = 'ExampleDataAssemblyHelper + ExampleApplyClaimService + ExampleCalculatorService'
    downstream_side_effect_or_output = 'captured InputData.policy_num equals CaseRoute.policyNo'
    requires_side_effect_evidence = $true
    requires_exact_contract_assertions = $true
    proof_required = @('captured InputData.policy_num equals CaseRoute.policyNo')
    forbidden_proof = @('synthetic_carrier')
    issues = @()
    warnings = @()
    gate = 'production_carrier_authorization'
}
$wrongSideEffect = [ordered]@{
    schema_version = 1
    slice_index = 1
    forced_requirement_family = 'core_entry'
    required_for_this_slice = $true
    entry_call = 'ExampleDataAssemblyHelper + ExampleApplyClaimService + ExampleCalculatorService'
    expected_writes_or_outputs = @('captured InputData.policy_num equals CaseRoute.policyNo')
    must_not_writes = @()
    test_name = 'AiPolicyNumSourceChainTest.shouldFillFromBackendSources'
    red_result = 'BLOCKED'
    green_result = 'NOT_RUN'
    status = 'PLANNED'
    gate = 'stateful_side_effect_evidence_harness'
}
$wrongCarrier | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
$wrongCarrier | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'CARRIER_AUTHORIZATION.json') -Encoding UTF8
$wrongSideEffect | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'SIDE_EFFECT_EVIDENCE_01.json') -Encoding UTF8
$wrongSideEffect | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'SIDE_EFFECT_EVIDENCE.json') -Encoding UTF8

$stale = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1') `
    -ReplayRoot $root `
    -SliceIndex 1 `
    -ForcedRequirementFamily core_entry `
    -ForcedSliceType exact_contract_slice `
    -ForcedSiblingSurface 'CaseRoute.policyNo / Insure.recordNo -> RequestBuildContext -> ExampleBaseRequest -> ExampleBaseTaskData -> InputData.policy_num/InputData.insure_num' |
    ConvertFrom-Json
if ([string]$stale.decision -ne 'STOP') {
    throw "Expected stale wrong carrier to STOP, got $($stale.decision)"
}
$staleIssues = @($stale.issues | ForEach-Object { [string]$_ })
if (@($staleIssues | Where-Object { $_ -match 'planned_red_test_mismatch|selected_carrier_mismatch|unrequired_source_chain_carrier' }).Count -eq 0) {
    throw "Expected stale wrong carrier to include plan/carrier mismatch, got $($staleIssues -join ',')"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Prepare-SliceEvidenceContracts.ps1') `
    -ReplayRoot $root `
    -Worktree $worktree `
    -RequirementFamilyLedger $ledger `
    -SliceIndex 1 `
    -ForcedRequirementFamily core_entry `
    -ForcedSliceType tracer_bullet | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Prepare-SliceEvidenceContracts failed' }

$correct = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1') `
    -ReplayRoot $root `
    -SliceIndex 1 `
    -ForcedRequirementFamily core_entry `
    -ForcedSliceType tracer_bullet |
    ConvertFrom-Json
if ([string]$correct.decision -ne 'ALLOW') {
    throw "Expected correct planned carrier to ALLOW, got $($correct.decision): $($correct.issues -join ',')"
}
if ([string]$correct.test_name -notmatch 'TaskServiceTransformCaseTaskPolicyTest') {
    throw "Expected planned TaskService test, got $($correct.test_name)"
}

$verify = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1') `
    -ReplayRoot $root `
    -Worktree $worktree `
    -SliceResult (Join-Path $root 'SLICE_RESULT_01.json') `
    -SliceIndex 1 |
    ConvertFrom-Json
if ([bool]$verify.carrier_family_match) {
    throw 'Expected old wrong slice result to be carrier_family_match=false'
}
$mismatchFamilies = @($verify.proof_type_mismatch_families | ForEach-Object { [string]$_ })
if ($mismatchFamilies -notcontains 'core_entry') {
    throw "Expected core_entry proof mismatch, got $($mismatchFamilies -join ',')"
}
$verifyFlags = @($verify.gap_flags | ForEach-Object { [string]$_ })
if ($verifyFlags -notcontains 'planned_red_test_mismatch') {
    throw "Expected planned_red_test_mismatch, got $($verifyFlags -join ',')"
}

$out = [ordered]@{
    status = 'PASS'
    replay_root = $root
    stale_wrong_carrier_decision = [string]$stale.decision
    correct_carrier_decision = [string]$correct.decision
    correct_test_name = [string]$correct.test_name
    carrier_family_match = [bool]$verify.carrier_family_match
    proof_type_mismatch_families = @($mismatchFamilies)
    expected_carrier_source = [string]$verify.expected_carrier_source
}
$out | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'PLAN_LOCK_EXPERIMENT_RESULT.json') -Encoding UTF8
$out | ConvertTo-Json -Depth 8
