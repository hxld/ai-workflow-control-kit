$ErrorActionPreference = 'Stop'

$runSliceLoop = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
$runSliceLoopText = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8
foreach ($requiredToken in @('runner invocation smoke failed before starting executor', '-ValidateOnly', 'coverage_cap_if_open', 'no_progress_slices', 'ReplayDryRunGate.ps1', 'SliceVerifier.ps1', 'coverage_cap_from_ledger', 'authorized_for_synthesis', 'highest-weight untouched OPEN/PARTIAL family', 'CARRIER_RANK', 'carrier_ranking_hard_stop')) {
    if (-not $runSliceLoopText.Contains($requiredToken)) {
        throw "Run-SliceLoop.ps1 missing required enforcement token: $requiredToken"
    }
}
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Run-SliceLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
}

$functionAsts = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    @('Read-JsonObject', 'Get-StringArray', 'Normalize-SiblingSurface', 'Get-CarrierSurfacePriority', 'Get-FamilyCarrierScore', 'New-CarrierRankMap', 'Get-FamilyTargetSiblingSurface', 'Get-SliceTypeForSurface', 'Get-ForcedFamilyDecision', 'Normalize-SliceProgress') -contains $node.Name
}, $true)
if (@($functionAsts).Count -lt 5) {
    throw 'Required scheduler functions were not found.'
}

$functionOrder = @{
    'Read-JsonObject' = 0
    'Get-StringArray' = 1
    'Normalize-SiblingSurface' = 2
    'Get-CarrierSurfacePriority' = 3
    'Get-FamilyCarrierScore' = 4
    'New-CarrierRankMap' = 5
    'Get-FamilyTargetSiblingSurface' = 6
    'Get-SliceTypeForSurface' = 7
    'Get-ForcedFamilyDecision' = 8
    'Normalize-SliceProgress' = 9
}
foreach ($functionAst in @($functionAsts | Sort-Object { $functionOrder[$_.Name] })) {
    Invoke-Expression $functionAst.Extent.Text
}

function New-Family {
    param(
        [string]$Id,
        [int]$Weight,
        [int]$Touched,
        [string]$Type,
        [string]$Status = 'PARTIAL',
        [string]$PlannedSlice = '',
        [int]$OpenSiblingCount = 0,
        [string]$Carrier = '',
        [string[]]$ProofRequired = @(),
        [string[]]$ForbiddenProof = @(),
        [string[]]$OpenSiblingSurfaces = @(),
        [string]$NextRecommendedSliceType = '',
        [string[]]$LastGapFlags = @()
    )

    [pscustomobject]@{
        id = $Id
        required = $true
        status = $Status
        touched_count = $Touched
        weight = $Weight
        recommended_slice_type = $Type
        planned_slice = $PlannedSlice
        first_executable_carrier = $Carrier
        proof_required = $ProofRequired
        forbidden_proof = $ForbiddenProof
        open_sibling_surfaces = $OpenSiblingSurfaces
        open_sibling_count = $OpenSiblingCount
        last_next_recommended_slice_type = $NextRecommendedSliceType
        last_gap_flags = $LastGapFlags
    }
}

function New-Ledger {
    param([object[]]$Families)
    [pscustomobject]@{ families = $Families }
}

function Assert-Equals {
    param([string]$Name, [object]$Actual, [object]$Expected)
    if ($Actual -ne $Expected) {
        throw "$Name expected [$Expected], actual [$Actual]"
    }
}

$baseFamilies = @(
    (New-Family -Id 'core_entry' -Weight 100 -Touched 0 -Type 'tracer_bullet' -Status 'OPEN'),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 0 -Type 'stateful_success_slice' -Status 'OPEN'),
    (New-Family -Id 'deploy_export_page' -Weight 90 -Touched 0 -Type 'deploy_surface_first_slice' -Status 'OPEN')
)

$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $baseFamilies) -SliceIndex 1
Assert-Equals -Name 'S1 forces core entry' -Actual $decision.family_id -Expected 'core_entry'

$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $baseFamilies) -SliceIndex 2
Assert-Equals -Name 'S2 forces stateful side effects' -Actual $decision.family_id -Expected 'stateful_side_effect'

$rankedCarrierFamilies = @(
    (New-Family -Id 'core_entry' -Weight 100 -Touched 1 -Type 'tracer_bullet' -Status 'PARTIAL' -OpenSiblingSurfaces @('example-core/src/main/java/com/example/OpenFacade.java#report', 'example-core/src/main/java/com/example/NotifyEvent.java#pushPayload')),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 0 -Type 'stateful_success_slice' -Status 'OPEN' -Carrier 'example-core/src/main/java/com/example/StatusService.java#dispose'),
    (New-Family -Id 'deploy_export_page' -Weight 90 -Touched 0 -Type 'deploy_surface_first_slice' -Status 'OPEN' -Carrier 'example-core/src/main/java/com/example/NotifyEvent.java#pushPayload' -ProofRequired @('payload contains exact wire field'))
)
$rankMap = New-CarrierRankMap -Ledger (New-Ledger -Families $rankedCarrierFamilies) -SliceIndex 2
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $rankedCarrierFamilies) -SliceIndex 2 -CarrierRank $rankMap
Assert-Equals -Name 'Carrier rank routes S2 to deploy-facing payload before generic stateful' -Actual $decision.family_id -Expected 'deploy_export_page'
if ([string]$decision.target_sibling_surface -notmatch 'NotifyEvent') {
    throw "Expected ranked target sibling surface to use NotifyEvent payload carrier, got $($decision.target_sibling_surface)"
}

$plannedFamilies = @(
    (New-Family -Id 'core_entry' -Weight 100 -Touched 1 -Type 'tracer_bullet'),
    (New-Family -Id 'deploy_export_page' -Weight 90 -Touched 0 -Type 'deploy_surface_first_slice' -PlannedSlice 'S4')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $plannedFamilies) -SliceIndex 4
Assert-Equals -Name 'Planned breadth runs before stale partial deepening' -Actual $decision.family_id -Expected 'deploy_export_page'

$statefulDepthBeforeBreadthFamilies = @(
    (New-Family -Id 'core_entry' -Weight 100 -Touched 1 -Type 'tracer_bullet'),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 1 -Type 'stateful_success_slice' -OpenSiblingCount 3 -LastGapFlags @('side_effect_ledger_gap')),
    (New-Family -Id 'deploy_export_page' -Weight 90 -Touched 0 -Type 'deploy_surface_first_slice'),
    (New-Family -Id 'wire_payload_api_contract' -Weight 88 -Touched 0 -Type 'exact_contract_slice')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $statefulDepthBeforeBreadthFamilies) -SliceIndex 3
Assert-Equals -Name 'S3 moves to highest-weight untouched deploy family after core and stateful first touch' -Actual $decision.family_id -Expected 'deploy_export_page'

$statefulDepthAfterBreadthFamilies = @(
    (New-Family -Id 'core_entry' -Weight 100 -Touched 2 -Type 'tracer_bullet'),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 2 -Type 'stateful_success_slice' -OpenSiblingCount 2 -LastGapFlags @('side_effect_ledger_gap')),
    (New-Family -Id 'deploy_export_page' -Weight 90 -Touched 1 -Type 'deploy_surface_first_slice'),
    (New-Family -Id 'wire_payload_api_contract' -Weight 88 -Touched 1 -Type 'exact_contract_slice')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $statefulDepthAfterBreadthFamilies) -SliceIndex 8
Assert-Equals -Name 'Stateful gap gets budget after breadth first touch' -Actual $decision.family_id -Expected 'stateful_side_effect'

$siblingPressureFamilies = @(
    (New-Family -Id 'deploy_export_page' -Weight 90 -Touched 1 -Type 'deploy_surface_first_slice' -OpenSiblingCount 2 -NextRecommendedSliceType 'deploy_surface_first_slice'),
    (New-Family -Id 'automation_test_interface' -Weight 78 -Touched 0 -Type 'exact_contract_slice' -PlannedSlice 'S4'),
    (New-Family -Id 'core_entry' -Weight 100 -Touched 1 -Type 'tracer_bullet'),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 1 -Type 'stateful_success_slice')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $siblingPressureFamilies) -SliceIndex 4
Assert-Equals -Name 'Deploy sibling pressure can run before stale partial core revisit' -Actual $decision.family_id -Expected 'deploy_export_page'

$externalSiblingWaitsForFirstTouchFamilies = @(
    (New-Family -Id 'external_integration' -Weight 82 -Touched 1 -Type 'deploy_surface_first_slice' -OpenSiblingCount 2 -NextRecommendedSliceType 'deploy_surface_first_slice'),
    (New-Family -Id 'lifecycle_cleanup_retention' -Weight 76 -Touched 0 -Type 'stateful_success_slice'),
    (New-Family -Id 'core_entry' -Weight 100 -Touched 1 -Type 'tracer_bullet'),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 1 -Type 'stateful_success_slice')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $externalSiblingWaitsForFirstTouchFamilies) -SliceIndex 8
Assert-Equals -Name 'Untouched lifecycle gets first touch before external sibling follow-up' -Actual $decision.family_id -Expected 'lifecycle_cleanup_retention'

$externalSiblingStopsAfterTwoTouches = @(
    (New-Family -Id 'external_integration' -Weight 82 -Touched 2 -Type 'deploy_surface_first_slice' -OpenSiblingCount 2 -NextRecommendedSliceType 'deploy_surface_first_slice'),
    (New-Family -Id 'lifecycle_cleanup_retention' -Weight 76 -Touched 1 -Type 'stateful_success_slice'),
    (New-Family -Id 'core_entry' -Weight 100 -Touched 2 -Type 'tracer_bullet'),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 2 -Type 'stateful_success_slice')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $externalSiblingStopsAfterTwoTouches) -SliceIndex 9
Assert-Equals -Name 'Under-explored lifecycle gets budget after external has two touches' -Actual $decision.family_id -Expected 'lifecycle_cleanup_retention'

$externalSiblingCanGetSecondTouchAfterBreadth = @(
    (New-Family -Id 'external_integration' -Weight 82 -Touched 1 -Type 'deploy_surface_first_slice' -OpenSiblingCount 2 -NextRecommendedSliceType 'deploy_surface_first_slice'),
    (New-Family -Id 'lifecycle_cleanup_retention' -Weight 76 -Touched 1 -Type 'stateful_success_slice'),
    (New-Family -Id 'core_entry' -Weight 100 -Touched 2 -Type 'tracer_bullet'),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 2 -Type 'stateful_success_slice')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $externalSiblingCanGetSecondTouchAfterBreadth) -SliceIndex 9
Assert-Equals -Name 'Non-deploy sibling can get a bounded second touch after breadth' -Actual $decision.family_id -Expected 'external_integration'

$statefulSiblingDoesNotStealDeployFamilies = @(
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 1 -Type 'stateful_success_slice' -OpenSiblingCount 3 -NextRecommendedSliceType 'deploy_surface_first_slice'),
    (New-Family -Id 'automation_test_interface' -Weight 78 -Touched 0 -Type 'exact_contract_slice' -PlannedSlice 'S4'),
    (New-Family -Id 'core_entry' -Weight 100 -Touched 1 -Type 'tracer_bullet')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $statefulSiblingDoesNotStealDeployFamilies) -SliceIndex 4
Assert-Equals -Name 'Planned automation first touch beats stateful sibling note' -Actual $decision.family_id -Expected 'automation_test_interface'

$v192S9Families = @(
    (New-Family -Id 'deploy_export_page' -Weight 90 -Touched 1 -Type 'deploy_surface_first_slice'),
    (New-Family -Id 'config_policy_threshold' -Weight 87 -Touched 1 -Type 'exact_contract_slice'),
    (New-Family -Id 'generated_artifact_template_upload' -Weight 86 -Touched 1 -Type 'deploy_surface_first_slice'),
    (New-Family -Id 'automation_test_interface' -Weight 78 -Touched 1 -Type 'exact_contract_slice'),
    (New-Family -Id 'lifecycle_cleanup_retention' -Weight 76 -Touched 1 -Type 'stateful_success_slice'),
    (New-Family -Id 'core_entry' -Weight 100 -Touched 2 -Type 'tracer_bullet'),
    (New-Family -Id 'wire_payload_api_contract' -Weight 88 -Touched 2 -Type 'exact_contract_slice'),
    (New-Family -Id 'external_integration' -Weight 82 -Touched 2 -Type 'deploy_surface_first_slice'),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 3 -Type 'stateful_success_slice')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $v192S9Families) -SliceIndex 9
Assert-Equals -Name 'Under-explored deploy breadth beats stale core revisit while no core gap is present' -Actual $decision.family_id -Expected 'deploy_export_page'

$balancedFamilies = @(
    (New-Family -Id 'core_entry' -Weight 100 -Touched 3 -Type 'tracer_bullet'),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 3 -Type 'stateful_success_slice'),
    (New-Family -Id 'deploy_export_page' -Weight 90 -Touched 2 -Type 'deploy_surface_first_slice'),
    (New-Family -Id 'lifecycle_cleanup_retention' -Weight 76 -Touched 1 -Type 'stateful_success_slice')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $balancedFamilies) -SliceIndex 9
Assert-Equals -Name 'Lowest-touch required family remains prioritized after first pass' -Actual $decision.family_id -Expected 'lifecycle_cleanup_retention'

$closedCoreFamilies = @(
    (New-Family -Id 'core_entry' -Weight 100 -Touched 3 -Type 'tracer_bullet' -Status 'EXECUTABLE_CLOSED'),
    (New-Family -Id 'stateful_side_effect' -Weight 95 -Touched 3 -Type 'stateful_success_slice' -Status 'EXECUTABLE_CLOSED'),
    (New-Family -Id 'deploy_export_page' -Weight 90 -Touched 2 -Type 'deploy_surface_first_slice' -Status 'EXECUTABLE_CLOSED'),
    (New-Family -Id 'wire_payload_api_contract' -Weight 88 -Touched 1 -Type 'exact_contract_slice')
)
$decision = Get-ForcedFamilyDecision -Ledger (New-Ledger -Families $closedCoreFamilies) -SliceIndex 9
Assert-Equals -Name 'Closed high-weight families are excluded from routing' -Actual $decision.family_id -Expected 'wire_payload_api_contract'

$progressCase = Join-Path ([System.IO.Path]::GetTempPath()) ('slice-progress-{0}.json' -f ([Guid]::NewGuid().ToString('N')))
[ordered]@{
    replay_root = 'old'
    max_slices = 9
    completed = @('S1', 2, 'slice03')
    stopped = $false
    stop_reason = ''
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $progressCase -Encoding UTF8
Normalize-SliceProgress -Path $progressCase -ReplayRoot 'root' -MaxSlices 12 -SliceIndex 4
$progress = Get-Content -LiteralPath $progressCase -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equals -Name 'Progress normalized replay root' -Actual $progress.replay_root -Expected 'root'
Assert-Equals -Name 'Progress normalized max slices' -Actual $progress.max_slices -Expected 12
Assert-Equals -Name 'Progress normalized completed count' -Actual @($progress.completed).Count -Expected 4
Assert-Equals -Name 'Progress normalized completed third' -Actual @($progress.completed)[2] -Expected 3
Normalize-SliceProgress -Path $progressCase -ReplayRoot 'root' -MaxSlices 12 -SliceIndex 4 -MarkStopped -StopReason 'stop'
$progress = Get-Content -LiteralPath $progressCase -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equals -Name 'Progress stop marker' -Actual $progress.stopped -Expected $true
Assert-Equals -Name 'Progress stop reason' -Actual $progress.stop_reason -Expected 'stop'
Remove-Item -LiteralPath $progressCase -Force

Write-Host 'PASS Test-SliceScheduler'
