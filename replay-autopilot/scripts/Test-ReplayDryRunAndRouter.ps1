param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Text
}

function Write-Json {
    param([string]$Path, $Object)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function New-Family {
    param(
        [string]$Id,
        [string]$Status,
        [int]$Weight,
        [int]$Touched,
        [string]$Type,
        [string]$Carrier = '',
        [string[]]$Proof = @(),
        [string[]]$Forbidden = @()
    )
    [ordered]@{
        id = $Id
        required = $true
        status = $Status
        weight = $Weight
        touched_count = $Touched
        recommended_slice_type = $Type
        first_executable_carrier = $Carrier
        proof_required = @($Proof)
        forbidden_proof = @($Forbidden)
        planned_slice = ''
        open_sibling_count = 0
        open_sibling_surfaces = @()
        last_next_recommended_slice_type = ''
        last_gap_flags = @()
    }
}

function New-ValidDryRunRoot {
    param([string]$Root)
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Text (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- highest_weight_open_gate: core_entry
- selected_real_entry: RealEntry.execute
- selected_carrier: RealEntry.execute
- target_subsurface_or_carrier: RealEntry.execute
- required_sibling_surfaces: none
- production_boundary: existing entry invokes production behavior
- proof_kind: real_entry_behavior
- red_expectation: RED fails on missing production behavior
- fail-closed condition: missing carrier or RED stops implementation
"@
    Write-Json (Join-Path $Root 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
        families = @(
            (New-Family -Id 'core_entry' -Status 'OPEN' -Weight 100 -Touched 0 -Type 'tracer_bullet')
        )
    })
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$tempRoot = Join-Path $scriptRoot ('.tmp\dryrun-router-{0}' -f $PID)
$dryRunScript = Join-Path $PSScriptRoot 'ReplayDryRunGate.ps1'
$routerScript = Join-Path $PSScriptRoot 'Select-NextReplaySlice.ps1'
$familyRouterScript = Join-Path $PSScriptRoot 'FamilyRouterAndCap.ps1'
$prepareScript = Join-Path $PSScriptRoot 'Prepare-SliceEvidenceContracts.ps1'
$preAuthScript = Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        dry_run = $dryRunScript
        router = $routerScript
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 8
    exit 0
}

$validRoot = Join-Path $tempRoot 'valid'
New-ValidDryRunRoot -Root $validRoot
$allow = & powershell -NoProfile -ExecutionPolicy Bypass -File $dryRunScript -ReplayRoot $validRoot -Mode FirstSliceProofPlan -ExpectStatus ALLOW | ConvertFrom-Json
if ([string]$allow.status -ne 'ALLOW') { throw "Expected ALLOW dry-run but got $($allow.status)" }

$carrierRoot = Join-Path $tempRoot 'carrier-authorization'
New-Item -ItemType Directory -Force -Path $carrierRoot | Out-Null
$carrierWorktree = Join-Path $carrierRoot 'worktree'
New-Item -ItemType Directory -Force -Path $carrierWorktree | Out-Null
Write-Json (Join-Path $carrierRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    families = @(
        (New-Family -Id 'core_entry' -Status 'OPEN' -Weight 100 -Touched 0 -Type 'tracer_bullet' -Carrier 'SampleCarrier.execute' -Proof @('RED proves entry invokes downstream state write') -Forbidden @('helper_only', 'mock_only'))
    )
})
$carrierAuth = & powershell -NoProfile -ExecutionPolicy Bypass -File $prepareScript -ReplayRoot $carrierRoot -Worktree $carrierWorktree -RequirementFamilyLedger (Join-Path $carrierRoot 'REQUIREMENT_FAMILY_LEDGER.json') -SliceIndex 1 -ForcedRequirementFamily core_entry -ForcedSliceType tracer_bullet | ConvertFrom-Json
if ([string]$carrierAuth.authorization -ne 'ALLOW') { throw "Expected carrier authorization ALLOW but got $($carrierAuth.authorization)" }
if (-not [bool]$carrierAuth.requires_side_effect_evidence) { throw "Expected core carrier authorization to require side-effect evidence" }
foreach ($expectedArtifact in @('CARRIER_AUTHORIZATION_01.json', 'EXACT_CONTRACT_ASSERTION_MATRIX_01.json', 'SIDE_EFFECT_EVIDENCE_01.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $carrierRoot $expectedArtifact))) { throw "Missing prepared slice evidence artifact: $expectedArtifact" }
}

$plainPlanRoot = Join-Path $tempRoot 'plain-plan-field-bindings'
New-Item -ItemType Directory -Force -Path $plainPlanRoot | Out-Null
$plainPlanWorktree = Join-Path $plainPlanRoot 'worktree'
New-Item -ItemType Directory -Force -Path $plainPlanWorktree | Out-Null
Write-Text (Join-Path $plainPlanRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

first_slice: S1 - prove the production entry.

first_red_test: example-server/src/test/java/com/acme/RealEntryContractTest.java#entryShouldCallSideEffect.

selected_real_entry: RealEntry.execute.

selected_carrier: RealEntry.execute -> DownstreamEvent.publish.

minimum_side_effect_or_blocker: entry reaches downstream event.

forbidden_substitute_check: passed.
"@
Write-Json (Join-Path $plainPlanRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    families = @(
        (New-Family -Id 'core_entry' -Status 'OPEN' -Weight 100 -Touched 0 -Type 'tracer_bullet' -Carrier 'FallbackCarrier.execute' -Proof @('entry reaches downstream event') -Forbidden @('helper_only', 'mock_only'))
    )
})
$plainCarrier = & powershell -NoProfile -ExecutionPolicy Bypass -File $prepareScript -ReplayRoot $plainPlanRoot -Worktree $plainPlanWorktree -RequirementFamilyLedger (Join-Path $plainPlanRoot 'REQUIREMENT_FAMILY_LEDGER.json') -SliceIndex 1 -ForcedRequirementFamily core_entry -ForcedSliceType tracer_bullet | ConvertFrom-Json
if ([string]$plainCarrier.selected_carrier -ne 'RealEntry.execute -> DownstreamEvent.publish') { throw "Expected selected carrier from plain plan, got $($plainCarrier.selected_carrier)" }
if ([string]$plainCarrier.real_entry -ne 'RealEntry.execute') { throw "Expected selected_real_entry to remain RealEntry.execute, got $($plainCarrier.real_entry)" }
$plainSideEffect = Read-Json (Join-Path $plainPlanRoot 'SIDE_EFFECT_EVIDENCE_01.json')
if ([string]$plainSideEffect.test_name -ne 'example-server/src/test/java/com/acme/RealEntryContractTest.java#entryShouldCallSideEffect') { throw "Expected planned test from plain plan, got $($plainSideEffect.test_name)" }
$plainPreAuth = & powershell -NoProfile -ExecutionPolicy Bypass -File $preAuthScript -ReplayRoot $plainPlanRoot -SliceIndex 1 -ForcedRequirementFamily core_entry -ForcedSliceType tracer_bullet | ConvertFrom-Json
if ([string]$plainPreAuth.decision -ne 'ALLOW') { throw "Expected plain plan pre-slice ALLOW, got $($plainPreAuth.decision): $($plainPreAuth.issues -join ',')" }
if ([string]$plainPreAuth.planned_first_red_test -ne 'example-server/src/test/java/com/acme/RealEntryContractTest.java#entryShouldCallSideEffect') { throw "Expected parsed first red test, got $($plainPreAuth.planned_first_red_test)" }
if ([string]$plainPreAuth.planned_selected_entry -ne 'RealEntry.execute') { throw "Expected parsed selected entry, got $($plainPreAuth.planned_selected_entry)" }

$missingPlanBindingsRoot = Join-Path $tempRoot 'preauth-missing-plan-bindings'
New-Item -ItemType Directory -Force -Path $missingPlanBindingsRoot | Out-Null
$missingPlanBindingsWorktree = Join-Path $missingPlanBindingsRoot 'worktree'
New-Item -ItemType Directory -Force -Path $missingPlanBindingsWorktree | Out-Null
Write-Text (Join-Path $missingPlanBindingsRoot 'FIRST_SLICE_PROOF_PLAN.md') '# First Slice Proof Plan'
Write-Json (Join-Path $missingPlanBindingsRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    families = @(
        (New-Family -Id 'core_entry' -Status 'OPEN' -Weight 100 -Touched 0 -Type 'tracer_bullet' -Carrier 'RealEntry.execute' -Proof @('entry reaches side effect') -Forbidden @('helper_only', 'mock_only'))
    )
})
& powershell -NoProfile -ExecutionPolicy Bypass -File $prepareScript -ReplayRoot $missingPlanBindingsRoot -Worktree $missingPlanBindingsWorktree -RequirementFamilyLedger (Join-Path $missingPlanBindingsRoot 'REQUIREMENT_FAMILY_LEDGER.json') -SliceIndex 1 -ForcedRequirementFamily core_entry -ForcedSliceType tracer_bullet | Out-Null
$missingPreAuth = & powershell -NoProfile -ExecutionPolicy Bypass -File $preAuthScript -ReplayRoot $missingPlanBindingsRoot -SliceIndex 1 -ForcedRequirementFamily core_entry -ForcedSliceType tracer_bullet | ConvertFrom-Json
if ([string]$missingPreAuth.decision -ne 'STOP') { throw "Expected missing plan binding pre-slice STOP, got $($missingPreAuth.decision)" }
$missingIssues = @($missingPreAuth.issues | ForEach-Object { [string]$_ })
foreach ($expectedIssue in @('planned_first_red_test_missing', 'planned_selected_carrier_missing', 'planned_selected_entry_missing')) {
    if ($missingIssues -notcontains $expectedIssue) { throw "Expected $expectedIssue, got $($missingIssues -join ',')" }
}

$carrierStopRoot = Join-Path $tempRoot 'carrier-authorization-stop'
New-Item -ItemType Directory -Force -Path $carrierStopRoot | Out-Null
$carrierStopWorktree = Join-Path $carrierStopRoot 'worktree'
New-Item -ItemType Directory -Force -Path $carrierStopWorktree | Out-Null
Write-Json (Join-Path $carrierStopRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    families = @(
        (New-Family -Id 'core_entry' -Status 'OPEN' -Weight 100 -Touched 0 -Type 'tracer_bullet')
    )
})
$carrierStop = & powershell -NoProfile -ExecutionPolicy Bypass -File $prepareScript -ReplayRoot $carrierStopRoot -Worktree $carrierStopWorktree -RequirementFamilyLedger (Join-Path $carrierStopRoot 'REQUIREMENT_FAMILY_LEDGER.json') -SliceIndex 1 -ForcedRequirementFamily core_entry -ForcedSliceType tracer_bullet | ConvertFrom-Json
if ([string]$carrierStop.authorization -ne 'STOP') { throw "Expected carrier authorization STOP but got $($carrierStop.authorization)" }
if (@($carrierStop.issues) -notcontains 'selected_carrier_missing') { throw "Expected selected_carrier_missing issue in carrier authorization STOP" }

$plannedCarrierRoot = Join-Path $tempRoot 'carrier-authorization-planned-stop'
New-Item -ItemType Directory -Force -Path $plannedCarrierRoot | Out-Null
$plannedCarrierWorktree = Join-Path $plannedCarrierRoot 'worktree'
New-Item -ItemType Directory -Force -Path $plannedCarrierWorktree | Out-Null
Write-Json (Join-Path $plannedCarrierRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    families = @(
        (New-Family -Id 'deploy_export_page' -Status 'OPEN' -Weight 90 -Touched 0 -Type 'deploy_surface_first_slice' -Carrier 'planned candidate export carrier' -Proof @('export output proof'))
    )
})
$plannedCarrierStop = & powershell -NoProfile -ExecutionPolicy Bypass -File $prepareScript -ReplayRoot $plannedCarrierRoot -Worktree $plannedCarrierWorktree -RequirementFamilyLedger (Join-Path $plannedCarrierRoot 'REQUIREMENT_FAMILY_LEDGER.json') -SliceIndex 1 -ForcedRequirementFamily deploy_export_page -ForcedSliceType deploy_surface_first_slice | ConvertFrom-Json
if ([string]$plannedCarrierStop.authorization -ne 'STOP') { throw "Expected planned carrier authorization STOP but got $($plannedCarrierStop.authorization)" }
if (@($plannedCarrierStop.issues) -notcontains 'carrier_is_planned_or_not_concrete') { throw "Expected carrier_is_planned_or_not_concrete issue" }

$helperCarrierRoot = Join-Path $tempRoot 'carrier-authorization-helper-stop'
New-Item -ItemType Directory -Force -Path $helperCarrierRoot | Out-Null
$helperCarrierWorktree = Join-Path $helperCarrierRoot 'worktree'
New-Item -ItemType Directory -Force -Path $helperCarrierWorktree | Out-Null
Write-Json (Join-Path $helperCarrierRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    families = @(
        (New-Family -Id 'automation_test_interface' -Status 'OPEN' -Weight 78 -Touched 0 -Type 'exact_contract_slice' -Carrier 'DtoConstantHelper' -Proof @('API response assertion'))
    )
})
$helperCarrierStop = & powershell -NoProfile -ExecutionPolicy Bypass -File $prepareScript -ReplayRoot $helperCarrierRoot -Worktree $helperCarrierWorktree -RequirementFamilyLedger (Join-Path $helperCarrierRoot 'REQUIREMENT_FAMILY_LEDGER.json') -SliceIndex 1 -ForcedRequirementFamily automation_test_interface -ForcedSliceType exact_contract_slice | ConvertFrom-Json
if ([string]$helperCarrierStop.authorization -ne 'STOP') { throw "Expected helper carrier authorization STOP but got $($helperCarrierStop.authorization)" }
if (@($helperCarrierStop.issues) -notcontains 'helper_or_static_only_carrier_for_high_weight_family') { throw "Expected helper_or_static_only_carrier_for_high_weight_family issue" }

$expectedDiffScopeRoot = Join-Path $tempRoot 'family-scope-expected-diff'
New-Item -ItemType Directory -Force -Path $expectedDiffScopeRoot | Out-Null
Write-Text (Join-Path $expectedDiffScopeRoot 'REQUIREMENT_SOURCE_SNAPSHOT.md') 'Requirement text is intentionally compact; concrete surfaces are carried by the accepted family contract and expected diff.'
Write-Json (Join-Path $expectedDiffScopeRoot 'AUTOPILOT_RUN.json') ([ordered]@{
    requirement_source = (Join-Path $expectedDiffScopeRoot 'REQUIREMENT_SOURCE_SNAPSHOT.md')
})
Write-Text (Join-Path $expectedDiffScopeRoot 'EXPECTED_DIFF_MATRIX.md') @"
# Expected Diff Matrix

| requirement | expected file families | validation |
| --- | --- | --- |
| H5 request carries wxId | CaseInfoParam.java; ClaimNofityParam.java | request field reaches payload |
| insurer callback fallback | ExamplePushService.java | callback emits MQ |
"@
Write-Json (Join-Path $expectedDiffScopeRoot 'FAMILY_CONTRACT.json') ([ordered]@{
    schema_version = 1
    families = @(
        [ordered]@{
            id = 'wire_payload_api_contract'
            required = $true
            weight = 95
            first_executable_carrier = 'ClaimNofityParam.wxId -> ClaimNotifyEvent.pushMsgToMQ'
            planned_slice = 'S2'
            proof_required = @('payload includes wxId')
            coverage_cap_if_open = 70
        },
        [ordered]@{
            id = 'external_integration'
            required = $true
            weight = 90
            first_executable_carrier = 'ExamplePushService.updateCaseFlowStatus -> ClaimNotifyEvent.pushMsgToMQ'
            planned_slice = 'S3'
            proof_required = @('callback emits MQ')
            coverage_cap_if_open = 80
        },
        [ordered]@{
            id = 'generated_artifact_template_upload'
            required = $false
            weight = 0
            first_executable_carrier = ''
            planned_slice = 'not_required'
            proof_required = @()
            coverage_cap_if_open = 100
        }
    )
})
Write-Json (Join-Path $expectedDiffScopeRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    families = @(
        (New-Family -Id 'wire_payload_api_contract' -Status 'OPEN' -Weight 95 -Touched 0 -Type 'exact_contract_slice' -Carrier 'ClaimNofityParam.wxId -> ClaimNotifyEvent.pushMsgToMQ' -Proof @('payload includes wxId')),
        (New-Family -Id 'external_integration' -Status 'OPEN' -Weight 90 -Touched 0 -Type 'deploy_surface_first_slice' -Carrier 'ExamplePushService.updateCaseFlowStatus -> ClaimNotifyEvent.pushMsgToMQ' -Proof @('callback emits MQ'))
    )
})
$expectedDiffRoute = & powershell -NoProfile -ExecutionPolicy Bypass -File $familyRouterScript -ReplayRoot $expectedDiffScopeRoot -AssertExpectedFamily wire_payload_api_contract | ConvertFrom-Json
if ([string]$expectedDiffRoute.selected_family -ne 'wire_payload_api_contract') { throw "Expected wire_payload_api_contract route but got $($expectedDiffRoute.selected_family)" }
if ([string]$expectedDiffRoute.target_sibling_surface -ne 'ClaimNofityParam.wxId -> ClaimNotifyEvent.pushMsgToMQ') { throw "Expected full target sibling surface from first_executable_carrier, got $($expectedDiffRoute.target_sibling_surface)" }
if (@($expectedDiffRoute.scope_filtered_families) -contains 'wire_payload_api_contract') { throw "wire_payload_api_contract should not be scope-filtered when family contract and expected diff name it" }
if (@($expectedDiffRoute.scope_filtered_families) -contains 'external_integration') { throw "external_integration should not be scope-filtered when family contract and expected diff name it" }

$siblingRouteRoot = Join-Path $tempRoot 'router-preserves-sibling-surface'
New-Item -ItemType Directory -Force -Path $siblingRouteRoot | Out-Null
$statefulSibling = New-Family -Id 'stateful_side_effect' -Status 'PARTIAL' -Weight 95 -Touched 1 -Type 'stateful_success_slice' -Carrier 'example-core/src/main/java/com/acme/StatefulService.java:save'
$statefulSibling.open_sibling_count = 1
$statefulSibling.open_sibling_surfaces = @('c:example-core/src/main/java/com/acme/StatefulService.java:dispose status/detail side effects')
Write-Json (Join-Path $siblingRouteRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    families = @(
        (New-Family -Id 'core_entry' -Status 'EXECUTABLE_CLOSED' -Weight 100 -Touched 1 -Type 'tracer_bullet'),
        $statefulSibling
    )
})
Write-Json (Join-Path $siblingRouteRoot 'SLICE_PROGRESS.json') ([ordered]@{ completed = @(1) })
$siblingRoute = & powershell -NoProfile -ExecutionPolicy Bypass -File $routerScript -ReplayRoot $siblingRouteRoot -AssertExpectedFamily stateful_side_effect | ConvertFrom-Json
if ([string]$siblingRoute.target_sibling_surface -ne 'example-core/src/main/java/com/acme/StatefulService.java:dispose status/detail side effects') { throw "Expected full normalized sibling surface, got $($siblingRoute.target_sibling_surface)" }

$stopRoot = Join-Path $tempRoot 'stop-loss'
New-ValidDryRunRoot -Root $stopRoot
Write-Text (Join-Path $stopRoot 'STOP_OR_CONTINUE_DECISION.md') '# Stop Or Continue Decision

- decision: `STOP_AND_EVOLVE`
'
$stop = & powershell -NoProfile -ExecutionPolicy Bypass -File $dryRunScript -ReplayRoot $stopRoot -Mode FirstSliceProofPlan | ConvertFrom-Json
if ([string]$stop.status -ne 'STOP') { throw "Expected STOP dry-run but got $($stop.status)" }

$missingRoot = Join-Path $tempRoot 'missing-proof-field'
New-ValidDryRunRoot -Root $missingRoot
Write-Text (Join-Path $missingRoot 'FIRST_SLICE_PROOF_PLAN.md') '# incomplete proof plan'
$blocked = & powershell -NoProfile -ExecutionPolicy Bypass -File $dryRunScript -ReplayRoot $missingRoot -Mode FirstSliceProofPlan | ConvertFrom-Json
if ([string]$blocked.status -ne 'BLOCKED_PLAN_MISMATCH') { throw "Expected BLOCKED_PLAN_MISMATCH but got $($blocked.status)" }

$routerRoot = Join-Path $tempRoot 'router-after-s2'
New-Item -ItemType Directory -Force -Path $routerRoot | Out-Null
Write-Json (Join-Path $routerRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    families = @(
        (New-Family -Id 'core_entry' -Status 'PARTIAL' -Weight 100 -Touched 1 -Type 'tracer_bullet'),
        (New-Family -Id 'stateful_side_effect' -Status 'PARTIAL' -Weight 95 -Touched 1 -Type 'stateful_success_slice'),
        (New-Family -Id 'deploy_export_page' -Status 'OPEN' -Weight 90 -Touched 0 -Type 'deploy_surface_first_slice'),
        (New-Family -Id 'generated_artifact_template_upload' -Status 'OPEN' -Weight 86 -Touched 0 -Type 'deploy_surface_first_slice')
    )
})
Write-Json (Join-Path $routerRoot 'SLICE_PROGRESS.json') ([ordered]@{
    completed = @(1, 2)
})
$route = & powershell -NoProfile -ExecutionPolicy Bypass -File $routerScript -ReplayRoot $routerRoot -AssertExpectedFamily deploy_export_page | ConvertFrom-Json
if ([string]$route.selected_family -ne 'deploy_export_page') { throw "Expected deploy_export_page route before stale core revisit but got $($route.selected_family)" }

$capRoot = Join-Path $tempRoot 'router-cap-v211-shape'
New-Item -ItemType Directory -Force -Path $capRoot | Out-Null
Write-Json (Join-Path $capRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    coverage_cap = 25
    families = @(
        (New-Family -Id 'core_entry' -Status 'PARTIAL' -Weight 100 -Touched 2 -Type 'stateful_success_slice'),
        (New-Family -Id 'stateful_side_effect' -Status 'PARTIAL' -Weight 95 -Touched 2 -Type 'stateful_success_slice'),
        (New-Family -Id 'deploy_export_page' -Status 'EXECUTABLE_CLOSED' -Weight 90 -Touched 3 -Type 'deploy_surface_first_slice'),
        (New-Family -Id 'external_integration' -Status 'OPEN' -Weight 82 -Touched 0 -Type 'deploy_surface_first_slice')
    )
})
$capRoute = & powershell -NoProfile -ExecutionPolicy Bypass -File $familyRouterScript -ReplayRoot $capRoot -AssertExpectedFamily core_entry -ValidateOnly | ConvertFrom-Json
if ([string]$capRoute.selected_family -ne 'core_entry') { throw "Expected family router core_entry but got $($capRoute.selected_family)" }
if (@($capRoute.closed_families) -notcontains 'deploy_export_page') { throw "Expected deploy_export_page to remain closed, not selected" }
if ([int]$capRoute.coverage_cap_from_ledger -gt 25) { throw "Expected ledger cap <= 25 but got $($capRoute.coverage_cap_from_ledger)" }
if ([bool]$capRoute.final_pass_allowed) { throw "Expected final_pass_allowed=false while required families remain open/partial" }

[ordered]@{
    status = 'PASS'
    cases = @('dryrun_allow', 'carrier_authorization_allow', 'plain_plan_field_bindings', 'preauth_missing_plan_bindings_stop', 'carrier_authorization_stop', 'carrier_authorization_planned_stop', 'carrier_authorization_helper_stop', 'family_scope_keeps_contract_expected_diff_required_surfaces', 'router_preserves_full_sibling_surface', 'dryrun_stop_loss_stop', 'dryrun_missing_schema_blocks', 'router_planned_breadth_before_stale_core_revisit', 'family_router_cap_v211_shape')
    temp_root = $tempRoot
} | ConvertTo-Json -Depth 8

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
