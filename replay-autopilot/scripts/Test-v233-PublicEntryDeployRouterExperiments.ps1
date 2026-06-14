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

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('v233-public-entry-router-{0}' -f ([Guid]::NewGuid().ToString('N')))
$root = Join-Path $temp 'replay'
$worktree = Join-Path $root 'worktree'
New-Item -ItemType Directory -Force -Path $worktree | Out-Null
& git -C $worktree init | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'example-core\src\main\java\demo') | Out-Null
Set-Content -LiteralPath (Join-Path $worktree 'example-core\src\main\java\demo\Service.java') -Encoding UTF8 -Value 'class Service {}'

try {
    Set-Content -LiteralPath (Join-Path $root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8 -Value @'
# First Slice Proof Plan

highest_weight_open_gate: core_entry + stateful_side_effect
first_red_test: example-server/src/test/java/demo/ServiceTest#callback_writes_side_effect
selected_real_entry: DemoFacade.returnTicket(Request) -> DemoService.returnTicket(Request)
selected_carrier: example-core/src/main/java/demo/DemoService.java#returnTicket
target_subsurface_or_carrier: callback validation and service side effect
required_sibling_surfaces: S2 deploy DemoController.getPage; S3 DemoController.submit
production_boundary: example-api/example-core public facade and service boundary
proof_kind: real_entry_behavior + stateful_side_effect
red_expectation: service test fails before production edit
fail-closed condition: stop if public facade response is not covered
'@
    $dry = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-ReplayDryRun.ps1') `
        -ReplayRoot $root `
        -Mode FirstSliceProofPlan | ConvertFrom-Json
    $dryReasons = @($dry.reasons | ForEach-Object { [string]$_ })
    $dryMissing = @($dry.missing_fields | ForEach-Object { [string]$_ })
    Assert-True -Name 'dry-run blocks service-only carrier when public entry is declared' -Condition ([string]$dry.status -eq 'BLOCKED_PLAN_MISMATCH') -Details ($dry | ConvertTo-Json -Depth 10)
    Assert-True -Name 'dry-run records public entry contract gap' -Condition ($dryMissing -contains 'public_entry_contract_coverage') -Details ($dry | ConvertTo-Json -Depth 10)
    Assert-True -Name 'dry-run records deploy sibling warning' -Condition (@($dryReasons | Where-Object { $_ -match 'deploy_facing_sibling' }).Count -gt 0) -Details ($dry | ConvertTo-Json -Depth 10)

    Write-JsonFile -Path (Join-Path $root 'CARRIER_AUTHORIZATION_01.json') -Object ([ordered]@{
        schema_version = 1
        slice_index = 1
        forced_requirement_family = 'core_entry'
        authorization = 'ALLOW'
        real_entry = 'DemoFacade.returnTicket(Request) -> DemoService.returnTicket(Request)'
        selected_carrier = 'example-core/src/main/java/demo/DemoService.java#returnTicket'
        production_boundary = 'example-core/src/main/java/demo/DemoService.java#returnTicket'
        downstream_side_effect_or_output = 'service side effect'
        red_expectation = 'business assertion should fail'
        requires_side_effect_evidence = $true
        requires_exact_contract_assertions = $false
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        proof_required = @('service side effect')
        forbidden_proof = @('mock_only')
        issues = @()
        warnings = @()
        gate = 'production_carrier_authorization'
    })
    Write-JsonFile -Path (Join-Path $root 'EXACT_CONTRACT_ASSERTION_MATRIX_01.json') -Object ([ordered]@{
        schema_version = 1
        slice_index = 1
        required_for_this_slice = $false
        rows = @()
        gate = 'exact_contract_assertion_lock'
    })
    Write-JsonFile -Path (Join-Path $root 'SLICE_RESULT_01.json') -Object ([ordered]@{
        slice_index = 1
        slice_id = 'S1'
        slice_title = 'service-only callback'
        slice_type = 'tracer_bullet'
        slice_status = 'DONE'
        coverage_delta = 20
        target_subsurface_or_carrier = 'DemoService.returnTicket'
        required_sibling_surfaces = @('core_entry: DemoController.getPage')
        production_boundary = 'example-core DemoService.returnTicket'
        proof_kind = 'real_entry_behavior'
        real_carrier_kind = 'production_entry_or_service'
        forbidden_substitute_check = 'passed'
        red_expectation = 'service assertion fails'
        implemented_files = @('example-core/src/main/java/demo/DemoService.java')
        current_slice_changed_files = @('example-core/src/main/java/demo/DemoService.java')
        tests = @(
            [ordered]@{ command = 'mvn -Dtest=ServiceTest test'; phase = 'RED'; result = 'fail'; evidence = 'AssertionError service side effect' },
            [ordered]@{ command = 'mvn -Dtest=ServiceTest test'; phase = 'GREEN'; result = 'pass'; evidence = 'Tests run: 1' }
        )
        exact_contract_assertions = @()
        side_effect_evidence = [ordered]@{
            status = 'CLOSED'
            entry_call = 'DemoFacade.returnTicket -> DemoService.returnTicket'
            expected_writes_or_outputs = @('service side effect')
            must_not_writes = @()
            test_name = 'ServiceTest'
            red_result = 'BUSINESS_ASSERTION_FAILED'
            green_result = 'PASS'
        }
        closed_assertions = @('service side effect')
        must_not_assertions = @()
        remaining_gaps = @()
        gap_flags = @()
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        blocker = ''
        next_recommended_slice_type = ''
    })
    $verify = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1') `
        -ReplayRoot $root `
        -Worktree $worktree `
        -SliceResult (Join-Path $root 'SLICE_RESULT_01.json') `
        -SliceIndex 1 | ConvertFrom-Json
    $flags = @($verify.gap_flags | ForEach-Object { [string]$_ })
    Assert-True -Name 'verifier flags public response contract missing' -Condition ($flags -contains 'public_response_contract_missing') -Details ($verify | ConvertTo-Json -Depth 10)
    Assert-True -Name 'verifier flags deploy surface unproven' -Condition ($flags -contains 'deploy_surface_unproven') -Details ($verify | ConvertTo-Json -Depth 10)
    Assert-True -Name 'verifier keeps service-only slice non-authorizing' -Condition (-not [bool]$verify.authorized_for_next_slice -and -not [bool]$verify.authorized_for_synthesis -and [int]$verify.adjusted_coverage_delta -eq 0) -Details ($verify | ConvertTo-Json -Depth 10)

    $ledgerPath = Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json'
    Write-JsonFile -Path $ledgerPath -Object ([ordered]@{
        schema_version = 1
        families = @(
            [ordered]@{
                id = 'core_entry'
                required = $true
                status = 'PARTIAL'
                weight = 100
                touched_count = 1
                recommended_slice_type = 'stateful_success_slice'
                first_executable_carrier = 'DemoService.returnTicket'
                open_sibling_surfaces = @('DemoController.getPage')
                open_sibling_count = 1
                coverage_cap_if_open = 60
            },
            [ordered]@{
                id = 'deploy_export_page'
                required = $true
                status = 'OPEN'
                weight = 90
                touched_count = 0
                recommended_slice_type = 'deploy_surface_first_slice'
                first_executable_carrier = 'DemoController.getPage'
                open_sibling_surfaces = @('DemoController.getPage')
                open_sibling_count = 1
                coverage_cap_if_open = 80
            }
        )
        coverage_cap = 25
    })
    $router = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'FamilyRouterAndCap.ps1') `
        -ReplayRoot $root `
        -Ledger $ledgerPath `
        -SliceIndex 2 | ConvertFrom-Json
    Assert-True -Name 'router maps deploy sibling to deploy slice type' -Condition ([string]$router.selected_slice_type -eq 'deploy_surface_first_slice') -Details ($router | ConvertTo-Json -Depth 10)
    Assert-True -Name 'router preserves ledger pass cap with open families' -Condition (-not [bool]$router.final_pass_allowed -and [int]$router.open_required_family_count -eq 2) -Details ($router | ConvertTo-Json -Depth 10)
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS Test-v233-PublicEntryDeployRouterExperiments'
