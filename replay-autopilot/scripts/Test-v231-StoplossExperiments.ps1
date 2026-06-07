$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw $Name }
        throw "$Name :: $Details"
    }
}

function Write-JsonFile {
    param($Object, [string]$Path)
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-TestRoot {
    param([string]$Name)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("v231-$Name-{0}" -f ([Guid]::NewGuid().ToString('N')))
    $worktree = Join-Path $root 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    & git -C $worktree init | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'src') | Out-Null
    Set-Content -LiteralPath (Join-Path $worktree 'src\Carrier.java') -Encoding UTF8 -Value 'class Carrier {}'
    [pscustomobject]@{ root = $root; worktree = $worktree }
}

function New-CarrierAuthorization {
    param(
        [int]$SliceIndex,
        [string]$Family = 'external_integration',
        [string]$Carrier = 'src/Carrier.java#handleCallback',
        [string]$ProductionBoundary = 'src/Carrier.java#handleCallback',
        [string]$Downstream = 'callback output assertion',
        [string]$RedExpectation = 'business assertion should fail before production change',
        [bool]$RequiresExact = $false
    )
    [ordered]@{
        schema_version = 1
        slice_index = $SliceIndex
        forced_requirement_family = $Family
        forced_slice_type = 'deploy_surface_first_slice'
        forced_sibling_surface = $Carrier
        authorization = 'ALLOW'
        real_entry = $Carrier
        selected_carrier = $Carrier
        production_boundary = $ProductionBoundary
        downstream_side_effect_or_output = $Downstream
        red_expectation = $RedExpectation
        requires_side_effect_evidence = $true
        requires_exact_contract_assertions = $RequiresExact
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        proof_required = @($Downstream)
        forbidden_proof = @('helper_only')
        issues = @()
        warnings = @()
        gate = 'production_carrier_authorization'
    }
}

$case1 = New-TestRoot -Name 'carrier-fields'
try {
    Write-JsonFile -Path (Join-Path $case1.root 'CARRIER_AUTHORIZATION_02.json') -Object (New-CarrierAuthorization -SliceIndex 2 -ProductionBoundary '' -RedExpectation '')
    Write-JsonFile -Path (Join-Path $case1.root 'SIDE_EFFECT_EVIDENCE_02.json') -Object ([ordered]@{
        schema_version = 1
        slice_index = 2
        forced_requirement_family = 'external_integration'
        required_for_this_slice = $true
        entry_call = 'src/Carrier.java#handleCallback'
        expected_writes_or_outputs = @('callback output assertion')
        must_not_writes = @()
        test_name = 'CallbackCarrierContractTest'
        red_result = 'PENDING_BUSINESS_ASSERTION'
        green_result = 'PENDING'
        status = 'READY'
        gate = 'stateful_side_effect_evidence_harness'
    })
    $auth = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1') `
        -ReplayRoot $case1.root `
        -SliceIndex 2 `
        -ForcedRequirementFamily external_integration `
        -ForcedSliceType deploy_surface_first_slice `
        -ForcedSiblingSurface 'src/Carrier.java#handleCallback' | ConvertFrom-Json
    $issues = @($auth.issues | ForEach-Object { [string]$_ })
    Assert-True -Name 'carrier authorization missing production boundary fails closed' -Condition ($issues -contains 'carrier_authorization_field_not_ready:production_boundary=') -Details ($auth | ConvertTo-Json -Depth 12)
    Assert-True -Name 'carrier authorization missing red expectation fails closed' -Condition ($issues -contains 'carrier_authorization_field_not_ready:red_expectation=') -Details ($auth | ConvertTo-Json -Depth 12)
    Assert-True -Name 'carrier authorization decision is STOP' -Condition ([string]$auth.decision -eq 'STOP') -Details ($auth | ConvertTo-Json -Depth 12)
} finally {
    Remove-Item -LiteralPath $case1.root -Recurse -Force -ErrorAction SilentlyContinue
}

$case2 = New-TestRoot -Name 'current-slice-diff'
try {
    Set-Content -LiteralPath (Join-Path $case2.worktree 'src\PreviousSlice.java') -Encoding UTF8 -Value 'class PreviousSlice {}'
    Write-JsonFile -Path (Join-Path $case2.root 'SLICE_RESULT_02.json') -Object ([ordered]@{
        slice_index = 2
        slice_id = 'S2'
        slice_title = 'blocked before current slice diff'
        slice_type = 'blocker'
        slice_status = 'BLOCKED'
        coverage_delta = 20
        target_subsurface_or_carrier = 'executor:blocker'
        required_sibling_surfaces = @()
        production_boundary = 'none'
        proof_kind = 'static_contract'
        real_carrier_kind = 'production_service'
        forbidden_substitute_check = 'passed'
        red_expectation = 'not executed'
        implemented_files = @()
        current_slice_changed_files = @()
        tests = @()
        closed_assertions = @()
        must_not_assertions = @()
        remaining_gaps = @('blocked')
        gap_flags = @('tooling_executor_failed')
        touched_requirement_families = @()
        closed_requirement_families = @()
        blocker = 'blocked before implementation'
        next_recommended_slice_type = ''
    })
    $verify = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1') `
        -ReplayRoot $case2.root `
        -Worktree $case2.worktree `
        -SliceResult (Join-Path $case2.root 'SLICE_RESULT_02.json') `
        -SliceIndex 2 | ConvertFrom-Json
    Assert-True -Name 'blocked slice has no current diff' -Condition (-not [bool]$verify.has_diff) -Details ($verify | ConvertTo-Json -Depth 12)
    Assert-True -Name 'blocked slice changed_files is current-slice scoped' -Condition (@($verify.changed_files).Count -eq 0) -Details ($verify | ConvertTo-Json -Depth 12)
    Assert-True -Name 'round snapshot still records prior diff' -Condition (@($verify.round_changed_files_snapshot).Count -gt 0) -Details ($verify | ConvertTo-Json -Depth 12)
    Assert-True -Name 'blocked slice coverage delta forced to zero' -Condition ([int]$verify.coverage_delta -eq 0 -and [int]$verify.adjusted_coverage_delta -eq 0) -Details ($verify | ConvertTo-Json -Depth 12)
    Assert-True -Name 'blocked slice cannot authorize next slice' -Condition (-not [bool]$verify.authorized_for_next_slice -and -not [bool]$verify.authorized_for_synthesis) -Details ($verify | ConvertTo-Json -Depth 12)
} finally {
    Remove-Item -LiteralPath $case2.root -Recurse -Force -ErrorAction SilentlyContinue
}

$case3 = New-TestRoot -Name 'exact-subset'
try {
    Write-JsonFile -Path (Join-Path $case3.root 'SIDE_EFFECT_EVIDENCE_02.json') -Object ([ordered]@{
        test_name = 'PayloadBoundaryContractTest'
    })
    Write-JsonFile -Path (Join-Path $case3.root 'EXACT_CONTRACT_ASSERTION_MATRIX_02.json') -Object ([ordered]@{
        schema_version = 1
        slice_index = 2
        forced_requirement_family = 'wire_payload_api_contract'
        required_for_this_slice = $true
        rows = @(
            [ordered]@{
                literal = 'wxId'
                symbol_or_field = 'wxId'
                db_or_wire_or_display = 'wire'
                boundary_type = 'wire'
                production_boundary = 'src/Carrier.java#buildPayload'
                test_assertion = 'payload contains wxId'
                status = 'OPEN'
                source_type = 'requirement'
            },
            [ordered]@{
                literal = 'git diff'
                symbol_or_field = 'git diff'
                db_or_wire_or_display = 'workflow'
                boundary_type = 'behavior'
                production_boundary = 'src/Carrier.java#buildPayload'
                test_assertion = 'git show proves it'
                status = 'OPEN'
                source_type = 'requirement'
            }
        )
        gate = 'exact_contract_assertion_lock'
    })
    $stop = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-NextSliceExactContract.ps1') `
        -ReplayRoot $case3.root `
        -SliceIndex 2 `
        -MaxRows 5 `
        -FailOnBroadRows | ConvertFrom-Json
    Assert-True -Name 'broad exact rows fail closed' -Condition ([string]$stop.decision -eq 'STOP') -Details ($stop | ConvertTo-Json -Depth 12)
    Assert-True -Name 'broad exact row issue recorded' -Condition (@($stop.issues | Where-Object { [string]$_ -match 'broad_exact_contract_row' }).Count -gt 0) -Details ($stop | ConvertTo-Json -Depth 12)

    $matrix = Get-Content -LiteralPath (Join-Path $case3.root 'EXACT_CONTRACT_ASSERTION_MATRIX_02.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $matrix.rows = @($matrix.rows | Where-Object { [string]$_.literal -ne 'git diff' })
    Write-JsonFile -Path (Join-Path $case3.root 'EXACT_CONTRACT_ASSERTION_MATRIX_02.json') -Object $matrix
    $allow = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-NextSliceExactContract.ps1') `
        -ReplayRoot $case3.root `
        -SliceIndex 2 `
        -MaxRows 5 `
        -FailOnBroadRows | ConvertFrom-Json
    Assert-True -Name 'minimal exact subset can allow valid row' -Condition ([string]$allow.decision -eq 'ALLOW') -Details ($allow | ConvertTo-Json -Depth 12)
    Assert-True -Name 'minimal exact subset has at most five rows' -Condition (@($allow.rows).Count -le 5 -and @($allow.rows).Count -eq 1) -Details ($allow | ConvertTo-Json -Depth 12)
    $row = @($allow.rows)[0]
    foreach ($field in @('literal', 'symbol_or_field', 'db_or_wire_or_display', 'production_boundary', 'test_assertion', 'red_command', 'blocker_condition')) {
        Assert-True -Name "minimal exact subset field present: $field" -Condition (-not [string]::IsNullOrWhiteSpace([string]$row.$field)) -Details ($allow | ConvertTo-Json -Depth 12)
    }
} finally {
    Remove-Item -LiteralPath $case3.root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS Test-v231-StoplossExperiments'
