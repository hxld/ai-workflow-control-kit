$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw $Name }
        throw "$Name :: $Details"
    }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('v230-carrier-evidence-{0}' -f ([Guid]::NewGuid().ToString('N')))
$worktree = Join-Path $root 'worktree'
New-Item -ItemType Directory -Force -Path $worktree | Out-Null
& git -C $worktree init | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'src') | Out-Null
Set-Content -LiteralPath (Join-Path $worktree 'src\Carrier.java') -Encoding UTF8 -Value 'class Carrier {}'

$ledgerPath = Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json'
[ordered]@{
    schema_version = 1
    families = @(
        [ordered]@{
            id = 'stateful_side_effect'
            title = 'Stateful side effects'
            required = $true
            status = 'OPEN'
            touched_count = 0
            weight = 95
            recommended_slice_type = 'stateful_success_slice'
            planned_slice = 'S2'
            first_executable_carrier = 'src/Carrier.java#dispose'
            proof_required = @('status transition writes expected side effect')
            forbidden_proof = @('mock_only')
            open_sibling_surfaces = @('src/Carrier.java#dispose')
            open_sibling_count = 1
        }
    )
    coverage_cap = 100
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ledgerPath -Encoding UTF8

Set-Content -LiteralPath (Join-Path $root 'REPLAY_PLAN.md') -Encoding UTF8 -Value @'
| slice | requirement rows | surfaces | existing production carrier(s) | carrier_search_terms | files | tests | DoD | blocker / coverage cap |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S2 | stateful transition side effect | service | `src/Carrier.java#dispose` | dispose | `src/Carrier.java` | `StatefulCarrierContractTest` | business RED then GREEN | cap if missing |
'@
Set-Content -LiteralPath (Join-Path $root 'TEST_CHARTER.md') -Encoding UTF8 -Value 'S2 uses `StatefulCarrierContractTest` for side-effect proof.'

[ordered]@{
    schema_version = 1
    slice_index = 2
    families = @(
        [ordered]@{
            family = 'stateful_side_effect'
            required = $true
            status = 'OPEN'
            rank = 1
            rank_score = 95
            production_carrier = 'src/Carrier.java#dispose'
            required_assertion = 'status transition writes expected side effect'
            forbidden_substitute = 'mock_only'
        }
    )
    missing_required_rank1 = @()
    gate = 'carrier_ranking_hard_stop'
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $root 'CARRIER_RANK_02.json') -Encoding UTF8

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Prepare-SliceEvidenceContracts.ps1') `
    -ReplayRoot $root `
    -Worktree $worktree `
    -RequirementFamilyLedger $ledgerPath `
    -SliceIndex 2 `
    -ForcedRequirementFamily stateful_side_effect `
    -ForcedSliceType stateful_success_slice `
    -ForcedSiblingSurface 'src/Carrier.java#dispose' | Out-Null
Assert-True -Name 'Prepare-SliceEvidenceContracts exit code' -Condition ($LASTEXITCODE -eq 0)

$side = Get-Content -LiteralPath (Join-Path $root 'SIDE_EFFECT_EVIDENCE_02.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True -Name 'side-effect evidence is READY before executor' -Condition ([string]$side.status -eq 'READY') -Details ($side | ConvertTo-Json -Depth 8)
Assert-True -Name 'planned test name extracted from replay plan' -Condition ([string]$side.test_name -match 'StatefulCarrierContractTest') -Details ([string]$side.test_name)

$allow = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1') `
    -ReplayRoot $root `
    -SliceIndex 2 `
    -ForcedRequirementFamily stateful_side_effect `
    -ForcedSliceType stateful_success_slice `
    -ForcedSiblingSurface 'src/Carrier.java#dispose' | ConvertFrom-Json
Assert-True -Name 'READY side-effect evidence allows executor' -Condition ([string]$allow.decision -eq 'ALLOW') -Details ($allow | ConvertTo-Json -Depth 10)

$side.status = 'PLANNED'
$side.test_name = ''
$side.red_result = 'PENDING'
$side.green_result = 'PENDING'
$side | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $root 'SIDE_EFFECT_EVIDENCE_02.json') -Encoding UTF8
$stop = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1') `
    -ReplayRoot $root `
    -SliceIndex 2 `
    -ForcedRequirementFamily stateful_side_effect `
    -ForcedSliceType stateful_success_slice `
    -ForcedSiblingSurface 'src/Carrier.java#dispose' | ConvertFrom-Json
$stopIssues = @($stop.issues | ForEach-Object { [string]$_ })
Assert-True -Name 'PLANNED side-effect evidence stops before executor' -Condition ([string]$stop.decision -eq 'STOP') -Details ($stop | ConvertTo-Json -Depth 10)
Assert-True -Name 'STOP includes side effect readiness issue' -Condition (@($stopIssues | Where-Object { $_ -match 'side_effect_evidence_not_ready|test_name_missing' }).Count -gt 0) -Details ($stopIssues -join ',')

[ordered]@{
    schema_version = 1
    slice_index = 1
    forced_requirement_family = 'wire_payload_api_contract'
    required_for_this_slice = $true
    rows = @(
        [ordered]@{
            literal = 'payloadField'
            symbol_or_field = 'payloadField'
            db_or_wire_or_display = 'wire_or_display'
            boundary_type = 'wire'
            production_boundary = 'src/Carrier.java#buildPayload'
            closure_proof = ''
            test_assertion = 'enum-only assertion'
            status = 'OPEN'
            touched = $false
            source_type = 'requirement'
        }
    )
    gate = 'exact_contract_assertion_lock'
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $root 'EXACT_CONTRACT_ASSERTION_MATRIX_01.json') -Encoding UTF8

[ordered]@{
    schema_version = 1
    slice_index = 1
    forced_requirement_family = 'wire_payload_api_contract'
    authorization = 'ALLOW'
    real_entry = 'src/Carrier.java#buildPayload'
    selected_carrier = 'src/Carrier.java#buildPayload'
    downstream_side_effect_or_output = 'payloadField appears in outgoing JSON'
    requires_side_effect_evidence = $false
    requires_exact_contract_assertions = $true
    proof_required = @('payloadField appears in outgoing JSON')
    forbidden_proof = @('enum_only')
    issues = @()
    warnings = @()
    gate = 'production_carrier_authorization'
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $root 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

[ordered]@{
    slice_index = 1
    slice_id = 'S1'
    slice_title = 'wire contract without boundary proof'
    slice_type = 'exact_contract_slice'
    slice_status = 'DONE'
    coverage_delta = 10
    target_subsurface_or_carrier = 'src/Carrier.java#buildPayload'
    required_sibling_surfaces = @()
    production_boundary = 'src/Carrier.java#buildPayload'
    proof_kind = 'payload_shape_behavior'
    real_carrier_kind = 'production_payload_builder'
    forbidden_substitute_check = 'passed'
    red_expectation = 'payloadField absent before implementation'
    implemented_files = @('src/Carrier.java')
    tests = @(
        [ordered]@{ command = 'mvn -Dtest=PayloadContractTest test'; phase = 'RED'; result = 'fail'; evidence = 'AssertionError: missing payloadField' },
        [ordered]@{ command = 'mvn -Dtest=PayloadContractTest test'; phase = 'GREEN'; result = 'pass'; evidence = 'Tests run: 1, Failures: 0' }
    )
    exact_contract_assertions = @(
        [ordered]@{
            literal = 'payloadField'
            symbol_or_field = 'payloadField'
            db_or_wire_or_display = 'wire_or_display'
            boundary_type = 'wire'
            production_boundary = 'src/Carrier.java#buildPayload'
            closure_proof = ''
            production_predicate = 'payloadField exists'
            forbidden_extra_predicate = 'enum-only'
            test_assertion = 'enum-only assertion'
            source_type = 'requirement'
            status = 'CLOSED'
        }
    )
    side_effect_evidence = $null
    closed_assertions = @('payloadField exists')
    must_not_assertions = @()
    remaining_gaps = @()
    gap_flags = @()
    touched_requirement_families = @('wire_payload_api_contract')
    closed_requirement_families = @('wire_payload_api_contract')
    blocker = ''
    next_recommended_slice_type = ''
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $root 'SLICE_RESULT_01.json') -Encoding UTF8

$verify = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1') `
    -ReplayRoot $root `
    -Worktree $worktree `
    -SliceResult (Join-Path $root 'SLICE_RESULT_01.json') `
    -SliceIndex 1 | ConvertFrom-Json
$verifyFlags = @($verify.gap_flags | ForEach-Object { [string]$_ })
Assert-True -Name 'wire/db/display exact contract requires boundary closure proof' -Condition ($verifyFlags -contains 'exact_contract_boundary_proof_missing') -Details ($verify | ConvertTo-Json -Depth 10)
Assert-True -Name 'required exact boundary proof gap is hard stop' -Condition ($verifyFlags -contains 'exact_contract_boundary_proof_stop') -Details ($verify | ConvertTo-Json -Depth 10)

Remove-Item -LiteralPath $root -Recurse -Force
Write-Host 'PASS Test-v230-CarrierEvidenceExperiments'
