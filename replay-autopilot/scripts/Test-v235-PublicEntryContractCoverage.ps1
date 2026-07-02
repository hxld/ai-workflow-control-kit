$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw $Name }
        throw "$Name :: $Details"
    }
}

$promptPath = Join-Path $PSScriptRoot '..\prompts\phase-plan-tournament.prompt.md'
$prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
Assert-True -Name 'plan prompt requires public entry contract field' -Condition ($prompt.Contains('public_entry_contract_coverage:'))

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('v235-public-entry-contract-{0}' -f ([Guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $temp 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8 -Value @'
# First Slice Proof Plan

first_slice: S1_public_facade
highest_weight_open_gate: core_entry
first_red_test: DemoFacadeImplExampleTicketTest#should_return_public_success_and_write_side_effects
selected_real_entry: example-core/src/main/java/demo/facade/DemoFacadeImpl.java#returnTicket
public_entry_contract_coverage: assert public ResultModel success/error contract through DemoFacadeImpl and verify downstream side effects
selected_carrier: DemoFacadeImpl.returnTicket -> DemoService.returnTicket
target_subsurface_or_carrier: DemoFacadeImpl.returnTicket public callback response
required_sibling_surfaces: stateful_side_effect:sibling:receive_write
production_boundary: production facade implementation and downstream service
proof_kind: real_entry_behavior
red_expectation: public facade response assertion fails before production edit
fail-closed condition: stop if RED only targets downstream service or does not assert the public response contract
'@
    $allow = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-ReplayDryRun.ps1') `
        -ReplayRoot $temp `
        -Mode FirstSliceProofPlan | ConvertFrom-Json
    Assert-True -Name 'facade impl with public coverage is allowed' -Condition ([string]$allow.status -eq 'ALLOW') -Details ($allow | ConvertTo-Json -Depth 10)

    (Get-Content -LiteralPath (Join-Path $temp 'FIRST_SLICE_PROOF_PLAN.md') -Raw -Encoding UTF8).Replace('public_entry_contract_coverage: assert public ResultModel success/error contract through DemoFacadeImpl and verify downstream side effects', '') |
        Set-Content -LiteralPath (Join-Path $temp 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8
    $blocked = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-ReplayDryRun.ps1') `
        -ReplayRoot $temp `
        -Mode FirstSliceProofPlan | ConvertFrom-Json
    $missing = @($blocked.missing_fields | ForEach-Object { [string]$_ })
    Assert-True -Name 'missing public coverage blocks public entry plan' -Condition ([string]$blocked.status -eq 'BLOCKED_PLAN_MISMATCH' -and $missing -contains 'public_entry_contract_coverage') -Details ($blocked | ConvertTo-Json -Depth 10)
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS Test-v235-PublicEntryContractCoverage'

