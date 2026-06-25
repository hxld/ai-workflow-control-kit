param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [int]$SliceIndex,
    [string]$ForcedRequirementFamily = '',
    [string]$ForcedSliceType = '',
    [string]$ForcedSiblingSurface = '',
    [string]$MavenSettings = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-PlanField {
    param([string]$Text, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $escaped = [regex]::Escape($Name)
    foreach ($line in @($Text -split "\r?\n")) {
        if ([string]$line -match "^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?$escaped\s*\*{0,2}\s*:\s*`?([^`\r\n]*)`?\s*$") {
            return $matches[1].Trim().Trim('`').TrimEnd('.').Trim()
        }
    }
    return ''
}

function Get-FirstNonEmpty {
    param([object[]]$Values)
    foreach ($value in $Values) {
        $text = [string]$value
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text.Trim() }
    }
    return ''
}

function Test-ForbiddenProofText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }
    return $Text -match '(?i)\b(none|static_only|helper_only|mock_only|dto_only|unknown|tbd|n/a|placeholder)\b'
}

function Test-CommandUsesIsolatedPom {
    param([string]$Command, [string]$Worktree)
    if ([string]::IsNullOrWhiteSpace($Command) -or [string]::IsNullOrWhiteSpace($Worktree)) { return $false }
    $normalizedCommand = $Command -replace '/', '\'
    $expectedPom = ([System.IO.Path]::Combine($Worktree, 'pom.xml')) -replace '/', '\'
    return $normalizedCommand -match ('(?i)(^|\s)-f\s+["'']?' + [regex]::Escape($expectedPom) + '["'']?(\s|$)')
}

function Test-ForbiddenMavenGoal {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $true }
    return $Command -match '(?i)(^|\s)(deploy|install)(\s|$)'
}

function Get-TestHarnessModuleFromCommand {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    if ($Command -match '(?i)(^|\s)-pl\s+["'']?([^"''\s]+)') { return $matches[2].Trim() }
    return ''
}

function Get-CommandMavenSettings {
    param([string]$ConfiguredValue)
    if ([string]::IsNullOrWhiteSpace($ConfiguredValue)) { return '' }
    return ('-s ' + $ConfiguredValue + ' -Dproject.build.sourceEncoding=UTF-8 -Dfile.encoding=UTF-8')
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
$dryRunPath = Join-Path $replayRootFull ('CARRIER_AUTHORIZATION_DRY_RUN_{0:D2}.json' -f $SliceIndex)
$slicePlanPath = Join-Path $replayRootFull ('SLICE_PLAN_CONTRACT_{0:D2}.json' -f $SliceIndex)
$firstExecutableContractPath = Join-Path $replayRootFull 'FIRST_SLICE_EXECUTABLE_CONTRACT.json'
$runnableAuthorizationPath = Join-Path $replayRootFull ('RUNNABLE_SLICE_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
$testCharterContractPath = Join-Path $replayRootFull ('TEST_CHARTER_{0:D2}.json' -f $SliceIndex)
$preSliceBlockerPath = Join-Path $replayRootFull ('SLICE_RESULT_PRE_{0:D2}.json' -f $SliceIndex)
$contextIndexPath = Join-Path $replayRootFull 'replay-context-index.json'
$contextValidationPath = Join-Path $replayRootFull 'REPLAY_CONTEXT_INDEX_VALIDATION.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $replayRootFull
        worktree = $worktreeFull
        slice_index = $SliceIndex
        carrier_authorization_dry_run = $dryRunPath
        slice_plan_contract = $slicePlanPath
        runnable_slice_authorization = $runnableAuthorizationPath
        test_charter_contract = $testCharterContractPath
        pre_slice_blocker = $preSliceBlockerPath
    } | ConvertTo-Json -Depth 8
    exit 0
}

$carrier = Read-JsonIfExists (Join-Path $replayRootFull ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex))
$callable = Read-JsonIfExists (Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex))
$preAuth = Read-JsonIfExists (Join-Path $replayRootFull ('PRE_SLICE_AUTHORIZATION_{0:D2}.json' -f $SliceIndex))
$sideEffect = Read-JsonIfExists (Join-Path $replayRootFull ('SIDE_EFFECT_EVIDENCE_{0:D2}.json' -f $SliceIndex))
$contextValidation = Read-JsonIfExists $contextValidationPath

$planText = @(
    (Read-TextIfExists (Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md')),
    (Read-TextIfExists (Join-Path $replayRootFull 'IMPLEMENTATION_CONTRACT.md')),
    (Read-TextIfExists (Join-Path $replayRootFull 'TEST_CHARTER.md'))
) -join "`n"

$selectedCarrier = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'selected_carrier'),
    $(if ($null -ne $carrier) { [string]$carrier.selected_carrier } else { '' }),
    $(if ($null -ne $callable) { [string]$callable.selected_carrier } else { '' })
)
$selectedEntry = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'selected_real_entry'),
    (Get-PlanField -Text $planText -Name 'real_entry_method'),
    $(if ($null -ne $carrier) { [string]$carrier.real_entry } else { '' }),
    $(if ($null -ne $callable) { [string]$callable.selected_real_entry } else { '' })
)
$redTestName = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'first_red_test'),
    (Get-PlanField -Text $planText -Name 'expected_test_class'),
    $(if ($null -ne $sideEffect) { [string]$sideEffect.test_name } else { '' })
)
$downstream = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'downstream_output_or_side_effect'),
    $(if ($null -ne $carrier) { [string]$carrier.downstream_side_effect_or_output } else { '' }),
    $(if ($null -ne $sideEffect) { (@(Get-StringArray $sideEffect.expected_writes_or_outputs) -join '; ') } else { '' })
)
$productionBoundary = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'production_boundary'),
    $(if ($null -ne $carrier) { [string]$carrier.production_boundary } else { '' }),
    $selectedCarrier
)
$redAssertion = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'red_assertion'),
    $(if ($null -ne $carrier) { [string]$carrier.red_expectation } else { '' })
)
$greenBoundary = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'green_change_boundary'),
    $productionBoundary
)
$validationCommand = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'validation_command'),
    (Get-PlanField -Text $planText -Name 'green_command')
)
$redCommand = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'red_command'),
    $validationCommand
)
$greenCommand = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'green_command'),
    $validationCommand
)
$expectedRedFailure = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'expected_red_failure'),
    $redAssertion
)
$expectedGreenAssertion = Get-FirstNonEmpty @(
    (Get-PlanField -Text $planText -Name 'expected_green_assertion'),
    (Get-PlanField -Text $planText -Name 'green_assertion'),
    $downstream
)

$runnableIssues = New-Object System.Collections.Generic.List[string]
$redUsesIsolatedPom = Test-CommandUsesIsolatedPom -Command $redCommand -Worktree $worktreeFull
$greenUsesIsolatedPom = Test-CommandUsesIsolatedPom -Command $greenCommand -Worktree $worktreeFull
if ([string]::IsNullOrWhiteSpace($redCommand)) { $runnableIssues.Add('red_command_missing') | Out-Null }
if ([string]::IsNullOrWhiteSpace($greenCommand)) { $runnableIssues.Add('green_command_missing') | Out-Null }
if (-not $redUsesIsolatedPom) { $runnableIssues.Add('red_command_missing_isolated_replay_pom') | Out-Null }
if (-not $greenUsesIsolatedPom) { $runnableIssues.Add('green_command_missing_isolated_replay_pom') | Out-Null }
if (Test-ForbiddenMavenGoal -Command $redCommand) { $runnableIssues.Add('red_command_forbidden_maven_goal') | Out-Null }
if (Test-ForbiddenMavenGoal -Command $greenCommand) { $runnableIssues.Add('green_command_forbidden_maven_goal') | Out-Null }
if ([string]::IsNullOrWhiteSpace($expectedRedFailure) -or (Test-ForbiddenProofText $expectedRedFailure)) { $runnableIssues.Add('expected_red_failure_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($expectedGreenAssertion) -or (Test-ForbiddenProofText $expectedGreenAssertion)) { $runnableIssues.Add('expected_green_assertion_missing_or_forbidden') | Out-Null }
$runnableStatus = if ($runnableIssues.Count -eq 0) { 'AUTHORIZED' } else { 'BLOCKED_NO_RUNNABLE_SLICE' }
$runnableAuthorization = [ordered]@{
    schema_version = 1
    slice_index = $SliceIndex
    status = $runnableStatus
    isolated_pom = ([System.IO.Path]::Combine($worktreeFull, 'pom.xml'))
    maven_settings = Get-CommandMavenSettings -ConfiguredValue $MavenSettings
    test_harness_module = Get-TestHarnessModuleFromCommand -Command $greenCommand
    red_command = $redCommand
    green_command = $greenCommand
    expected_red_failure = $expectedRedFailure
    expected_green_assertion = $expectedGreenAssertion
    forbidden_maven_goals_checked = $true
    uses_isolated_replay_pom = ($redUsesIsolatedPom -and $greenUsesIsolatedPom)
    issues = @($runnableIssues | Select-Object -Unique)
}
$runnableAuthorization | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $runnableAuthorizationPath -Encoding UTF8

$carrierBlockers = New-Object System.Collections.Generic.List[string]
if ($null -eq $carrier) { $carrierBlockers.Add('carrier_authorization_missing') | Out-Null }
elseif ([string]$carrier.authorization -ne 'ALLOW') {
    foreach ($issue in @(Get-StringArray $carrier.issues)) { if (-not [string]::IsNullOrWhiteSpace($issue)) { $carrierBlockers.Add($issue) | Out-Null } }
    if ($carrierBlockers.Count -eq 0) { $carrierBlockers.Add('carrier_authorization_not_allow') | Out-Null }
}
if ($null -ne $preAuth -and [string]$preAuth.decision -ne 'ALLOW') {
    foreach ($issue in @(Get-StringArray $preAuth.issues)) { if (-not [string]::IsNullOrWhiteSpace($issue)) { $carrierBlockers.Add($issue) | Out-Null } }
}
if ($null -ne $callable -and -not [bool]$callable.can_proceed) {
    foreach ($blocker in @(Get-StringArray $callable.blockers)) { if (-not [string]::IsNullOrWhiteSpace($blocker)) { $carrierBlockers.Add($blocker) | Out-Null } }
}
if ([string]::IsNullOrWhiteSpace($selectedCarrier)) { $carrierBlockers.Add('selected_carrier_missing') | Out-Null }
if ([string]::IsNullOrWhiteSpace($selectedEntry)) { $carrierBlockers.Add('selected_real_entry_missing') | Out-Null }

$replacementCandidates = @()
if (Test-Path -LiteralPath $contextIndexPath) {
    $contextIndex = Read-JsonIfExists $contextIndexPath
    foreach ($propName in @('carrier_candidates', 'real_entry_candidates')) {
        if ($null -ne $contextIndex -and $contextIndex.PSObject.Properties.Name -contains $propName) {
            foreach ($candidate in @($contextIndex.$propName | Select-Object -First 3)) {
                if ($candidate -is [string]) { $replacementCandidates += $candidate }
                elseif ($candidate.PSObject.Properties.Name -contains 'signature') { $replacementCandidates += [string]$candidate.signature }
                elseif ($candidate.PSObject.Properties.Name -contains 'carrier') { $replacementCandidates += [string]$candidate.carrier }
                elseif ($candidate.PSObject.Properties.Name -contains 'selected_carrier') { $replacementCandidates += [string]$candidate.selected_carrier }
            }
        }
    }
}

$preAuthorized = ($carrierBlockers.Count -eq 0)
$callableAuthorizationStatus = if ($preAuthorized) { 'AUTHORIZED' } else { 'BLOCKED' }
if ($null -ne $callable) {
    $callableNormalized = [ordered]@{
        gate = 'callable_carrier_authorization'
        slice_index = $SliceIndex
        existing_entry_fqn = $selectedEntry
        existing_entry_signature = if ($null -ne $callable.resolved_signature -and $null -ne $callable.resolved_signature.selected_carrier) { [string]$callable.resolved_signature.selected_carrier.formatted } else { $selectedEntry }
        carrier_origin = 'existing_production_entry'
        test_instantiation_strategy = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'test_instantiation_strategy'), 'instantiate_or_mock_dependencies_without_replacing_entry')
        method_invocation_statement = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'method_invocation_statement'), (Get-PlanField -Text $planText -Name 'test_invocation_expression'), 'invoke the declared existing production entry from the behavior test')
        resolved_in_baseline_index = $preAuthorized
        forbidden_substitute_check = if ($preAuthorized) { 'passed' } else { 'failed' }
        authorization_status = $callableAuthorizationStatus
        can_proceed = $preAuthorized
        selected_carrier = $selectedCarrier
        selected_real_entry = $selectedEntry
        resolved_signature = $callable.resolved_signature
        blockers = @($carrierBlockers | Select-Object -Unique)
    }
    $callableNormalized | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)) -Encoding UTF8
}
$dryRun = [ordered]@{
    schema_version = 1
    slice_index = $SliceIndex
    selected_symbol = $selectedCarrier
    resolved_declaring_class = if ($null -ne $callable -and $null -ne $callable.resolved_signature -and $null -ne $callable.resolved_signature.selected_carrier) { [string]$callable.resolved_signature.selected_carrier.class_name } else { '' }
    visibility = if ($null -ne $callable -and $null -ne $callable.resolved_signature -and $null -ne $callable.resolved_signature.selected_carrier) { [string]$callable.resolved_signature.selected_carrier.visibility } else { '' }
    signature = if ($null -ne $callable -and $null -ne $callable.resolved_signature -and $null -ne $callable.resolved_signature.selected_carrier) { [string]$callable.resolved_signature.selected_carrier.formatted } else { $selectedCarrier }
    test_invocation_expression = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'test_invocation_expression'), 'pre_red_runner_gate')
    pre_authorized = $preAuthorized
    replacement_candidates = @($replacementCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 3)
    chosen_replacement_or_blocked = if ($preAuthorized) { 'authorized_original' } elseif ($replacementCandidates.Count -gt 0) { 'blocked_after_replacement_candidates_recorded' } else { 'blocked_no_valid_replacement' }
    blockers = @($carrierBlockers | Select-Object -Unique)
}
$dryRun | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $dryRunPath -Encoding UTF8

$planBlockers = New-Object System.Collections.Generic.List[string]
if ($runnableStatus -ne 'AUTHORIZED') {
    foreach ($issue in @($runnableIssues | Select-Object -Unique)) { $planBlockers.Add($issue) | Out-Null }
    $planBlockers.Add('runnable_slice_authorization_not_authorized') | Out-Null
}
if ([string]::IsNullOrWhiteSpace($selectedEntry) -or (Test-ForbiddenProofText $selectedEntry)) { $planBlockers.Add('real_entry_method_missing_or_forbidden') | Out-Null }
if (-not $preAuthorized) { $planBlockers.Add('carrier_dry_run_not_authorized') | Out-Null }
if ([string]::IsNullOrWhiteSpace($productionBoundary) -or (Test-ForbiddenProofText $productionBoundary)) { $planBlockers.Add('production_boundary_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($downstream) -or (Test-ForbiddenProofText $downstream)) { $planBlockers.Add('downstream_output_or_side_effect_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($redTestName) -or (Test-ForbiddenProofText $redTestName)) { $planBlockers.Add('red_test_name_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($redAssertion) -or (Test-ForbiddenProofText $redAssertion)) { $planBlockers.Add('red_assertion_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($greenBoundary) -or (Test-ForbiddenProofText $greenBoundary)) { $planBlockers.Add('green_change_boundary_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($validationCommand) -or (Test-ForbiddenProofText $validationCommand)) { $planBlockers.Add('validation_command_missing_or_forbidden') | Out-Null }
if ($null -ne $contextValidation -and [string]$contextValidation.status -eq 'FAIL') { $planBlockers.Add('replay_context_index_validation_failed') | Out-Null }

$requiresSideEffect = @('core_entry', 'stateful_side_effect', 'generated_artifact_template_upload', 'lifecycle_cleanup_retention') -contains $ForcedRequirementFamily
if ($requiresSideEffect -and ([string]::IsNullOrWhiteSpace($downstream) -or (Test-ForbiddenProofText $downstream))) {
    $planBlockers.Add('required_side_effect_or_output_proof_missing') | Out-Null
}

$mustNotBehavior = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'must_not_behavior'), (Get-PlanField -Text $planText -Name 'must_not'), 'do not use helper/static/mock/dto-only proof as closure')
$positiveAssertions = @($redAssertion, $expectedGreenAssertion, $downstream) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and -not (Test-ForbiddenProofText ([string]$_)) } | Select-Object -Unique
$negativeAssertions = @($mustNotBehavior) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and -not (Test-ForbiddenProofText ([string]$_)) } | Select-Object -Unique
$testCharterIssues = New-Object System.Collections.Generic.List[string]
if (-not $preAuthorized) { $testCharterIssues.Add('real_entry_not_authorized_for_charter') | Out-Null }
if ($positiveAssertions.Count -eq 0) { $testCharterIssues.Add('positive_assertions_missing') | Out-Null }
if ($negativeAssertions.Count -eq 0) { $testCharterIssues.Add('negative_must_not_assertions_missing') | Out-Null }
if ([string]::IsNullOrWhiteSpace($downstream) -or (Test-ForbiddenProofText $downstream)) { $testCharterIssues.Add('state_or_output_surface_missing_or_forbidden') | Out-Null }
if ([string]::IsNullOrWhiteSpace($expectedRedFailure) -or (Test-ForbiddenProofText $expectedRedFailure)) { $testCharterIssues.Add('red_phase_business_failure_missing') | Out-Null }
if ([string]::IsNullOrWhiteSpace($expectedGreenAssertion) -or (Test-ForbiddenProofText $expectedGreenAssertion)) { $testCharterIssues.Add('green_phase_business_success_missing') | Out-Null }
$testCharterStatus = if ($testCharterIssues.Count -eq 0) { 'AUTHORIZED' } else { 'BLOCKED' }
$testCharterContract = [ordered]@{
    schema_version = 1
    slice_index = $SliceIndex
    status = $testCharterStatus
    real_entry_invoked = $preAuthorized
    positive_assertions = @($positiveAssertions)
    negative_must_not_assertions = @($negativeAssertions)
    state_or_output_surface = $downstream
    red_phase_business_failure = $expectedRedFailure
    green_phase_business_success = $expectedGreenAssertion
    proof_type = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'required_proof_type'), $ForcedSliceType, 'real_entry_behavior')
    non_authorizing_evidence = @('helper_only', 'mock_only', 'dto_only', 'static_only', 'wiring_only', 'file_presence_only')
    issues = @($testCharterIssues | Select-Object -Unique)
}
$testCharterContract | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $testCharterContractPath -Encoding UTF8
if ($requiresSideEffect -and $testCharterStatus -ne 'AUTHORIZED') {
    foreach ($issue in @($testCharterIssues | Select-Object -Unique)) { $planBlockers.Add($issue) | Out-Null }
    $planBlockers.Add('test_charter_contract_not_authorized') | Out-Null
}

$slicePlan = [ordered]@{
    schema_version = 1
    slice_index = $SliceIndex
    forced_requirement_family = $ForcedRequirementFamily
    forced_slice_type = $ForcedSliceType
    forced_sibling_surface = $ForcedSiblingSurface
    real_entry_method = $selectedEntry
    callable_from_test = $preAuthorized
    production_boundary = $productionBoundary
    downstream_output_or_side_effect = $downstream
    must_not_behavior = $mustNotBehavior
    red_test_name = $redTestName
    red_assertion = $redAssertion
    green_change_boundary = $greenBoundary
    validation_command = $validationCommand
    forbidden_proof_checks = @('none', 'static_only', 'helper_only', 'mock_only', 'dto_only')
    carrier_authorization_dry_run = $dryRunPath
    runnable_slice_authorization = $runnableAuthorizationPath
    callable_carrier_authorization = Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
    test_charter_contract = $testCharterContractPath
    replay_context_index = if (Test-Path -LiteralPath $contextIndexPath) { $contextIndexPath } else { '' }
    replay_context_index_validation = if (Test-Path -LiteralPath $contextValidationPath) { $contextValidationPath } else { '' }
    blockers = @($planBlockers | Select-Object -Unique)
    authorization = if ($planBlockers.Count -eq 0) { 'ALLOW' } else { 'STOP' }
}
$slicePlan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $slicePlanPath -Encoding UTF8

if ($SliceIndex -eq 1) {
    $firstExecutableContract = [ordered]@{
        schema_version = 1
        family_id = $ForcedRequirementFamily
        production_entry_qn = $selectedEntry
        entry_invocation_method = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'entry_invocation_method'), (Get-PlanField -Text $planText -Name 'test_invocation_expression'), 'invoke the selected real production entry from the behavior test')
        required_side_effects = @($downstream) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and -not (Test-ForbiddenProofText ([string]$_)) }
        business_red_assertion = $expectedRedFailure
        negative_guard_assertion = $mustNotBehavior
        forbidden_test_surfaces = @('helper_only', 'static_only', 'dto_only', 'service_only_when_plan_selected_public_entry', 'test_only', 'synthetic_carrier')
        allowed_mock_boundaries = @('collaborator_dependency', 'dao_mapper_gateway', 'common_request_assembly_helper.buildRequestCommon', 'request_builder_function collaborator input')
        maven_test_command_template = $greenCommand
        existing_entry_qn = $selectedEntry
        entry_file = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'entry_file'), $(if ($null -ne $carrier) { [string]$carrier.entry_file } else { '' }))
        method_signature = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'method_signature'), $selectedCarrier)
        required_proof_type = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'required_proof_type'), $ForcedSliceType, 'real_entry_behavior')
        side_effect_or_output = $downstream
        must_not_behavior = $slicePlan.must_not_behavior
        forbidden_substitute_surfaces = @('new_helper_only', 'new_service_without_existing_entry_call', 'dto_only', 'static_contract', 'mock_only', 'test_only')
        red_command = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'red_command'), $validationCommand)
        green_command = Get-FirstNonEmpty @((Get-PlanField -Text $planText -Name 'green_command'), $validationCommand)
        assertion_names = @(
            $redAssertion,
            (Get-PlanField -Text $planText -Name 'assertion_names')
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        authorization = $slicePlan.authorization
        blockers = @($planBlockers | Select-Object -Unique)
        carrier_authorization_dry_run = $dryRunPath
        slice_plan_contract = $slicePlanPath
        runnable_slice_authorization = $runnableAuthorizationPath
        callable_carrier_authorization = Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
        test_charter_contract = $testCharterContractPath
    }
    $firstContractMissing = New-Object System.Collections.Generic.List[string]
    foreach ($fieldName in @('production_entry_qn', 'entry_invocation_method', 'business_red_assertion', 'negative_guard_assertion', 'maven_test_command_template')) {
        if ([string]::IsNullOrWhiteSpace([string]$firstExecutableContract[$fieldName]) -or (Test-ForbiddenProofText ([string]$firstExecutableContract[$fieldName]))) {
            $firstContractMissing.Add($fieldName) | Out-Null
        }
    }
    foreach ($arrayFieldName in @('required_side_effects', 'forbidden_test_surfaces', 'allowed_mock_boundaries')) {
        if (@($firstExecutableContract[$arrayFieldName]).Count -eq 0) {
            $firstContractMissing.Add($arrayFieldName) | Out-Null
        }
    }
    $firstExecutableContract['contract_status'] = if ($firstContractMissing.Count -eq 0) { 'AUTHORIZED' } else { 'BLOCKED' }
    $firstExecutableContract['contract_missing_fields'] = @($firstContractMissing | Select-Object -Unique)
    $firstExecutableContract | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $firstExecutableContractPath -Encoding UTF8
    if ($firstContractMissing.Count -gt 0) {
        foreach ($missingField in @($firstContractMissing | Select-Object -Unique)) { $planBlockers.Add("first_slice_execution_contract_missing_$missingField") | Out-Null }
    }
}

if ($planBlockers.Count -gt 0) {
    $slicePlan.blockers = @($planBlockers | Select-Object -Unique)
    $slicePlan.authorization = 'STOP'
    $slicePlan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $slicePlanPath -Encoding UTF8
    [ordered]@{
        schema_version = 1
        slice_index = 0
        original_slice_index = $SliceIndex
        slice_status = 'BLOCKED'
        slice_type = 'blocker'
        blocker = 'pre_slice_experiment_contract_stop'
        blocker_reasons = @($planBlockers | Select-Object -Unique)
        gap_flags = @('tooling_enforcement_stop', 'feedback_loop_blocker')
        implemented_files = @()
        touched_requirement_families = @()
        closed_requirement_families = @()
        coverage_delta = 0
        has_behavior_evidence = $false
        authorized_for_next_slice = $false
        authorized_for_synthesis = $false
        carrier_authorization_dry_run = $dryRunPath
        slice_plan_contract = $slicePlanPath
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $preSliceBlockerPath -Encoding UTF8
    exit 1
}

exit 0
