$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRoot = Join-Path $env:TEMP ("replay-v222-experiments-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

function Write-Json {
    param([string]$Path, $Object)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-Family {
    param(
        [string]$Id,
        [bool]$Required = $true,
        [string]$Status = 'OPEN',
        [int]$Weight = 90,
        [int]$Touched = 0,
        [string]$Carrier = '',
        [string]$Type = 'stateful_success_slice'
    )
    [ordered]@{
        id = $Id
        title = $Id
        weight = $Weight
        recommended_slice_type = $Type
        required = $Required
        status = $Status
        touched_count = $Touched
        first_slice = $null
        last_slice = $null
        slices = @()
        first_executable_carrier = $Carrier
        planned_slice = ''
        proof_required = @()
        forbidden_proof = @()
        coverage_cap_if_open = 70
        open_sibling_surfaces = @()
        open_sibling_count = 0
        last_next_recommended_slice_type = ''
        last_gap_flags = @()
        evidence_keywords = @()
        last_reason = 'test fixture'
    }
}

function New-ReplayRoot {
    param([string]$Name, [string]$RequirementText)
    $root = Join-Path $tempRoot $Name
    $worktree = Join-Path $root 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    git -C $worktree init -q
    git -C $worktree config user.email test@example.com
    git -C $worktree config user.name tester
    $requirement = Join-Path $root 'requirements.md'
    Set-Content -LiteralPath $requirement -Encoding UTF8 -Value $RequirementText
    Write-Json (Join-Path $root 'AUTOPILOT_RUN.json') ([ordered]@{
        requirement_source = $requirement
    })
    return [pscustomobject]@{
        root = $root
        worktree = $worktree
        requirement = $requirement
    }
}

function Write-MinimalTaskService {
    param([string]$Worktree)
    $path = Join-Path $Worktree 'example-core/src/main/java/com/example/TaskService.java'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    $source = @'
package com.example;

public class TaskService {
    public void waitExamineTask(CaseRoute caseRoute) {
        expired(caseRoute);
        if (shouldSkipTransferAuditTask(caseRoute, 5)) {
            return;
        }
        taskMapper.insert(5);
        caseTimeOutService.addUserTimeOut(caseRoute.getId());
    }

    private boolean shouldSkipTransferAuditTask(CaseRoute caseRoute, int taskId) {
        return true;
    }

    private void expired(CaseRoute caseRoute) {
        taskMapper.updateCaseHandTask(caseRoute.getId());
    }

    private final TaskMapper taskMapper = new TaskMapper();
    private final CaseTimeOutService caseTimeOutService = new CaseTimeOutService();
    static class CaseRoute { long getId() { return 1L; } }
    static class TaskMapper { void insert(int id) {} void updateCaseHandTask(long id) {} }
    static class CaseTimeOutService { void addUserTimeOut(long id) {} }
}
'@
    Set-Content -LiteralPath $path -Encoding UTF8 -Value $source
    git -C $Worktree add example-core/src/main/java/com/example/TaskService.java
    git -C $Worktree commit -q -m baseline
}

function New-SliceResult {
    param([string[]]$MustNotWrites)
    [ordered]@{
        slice_index = 1
        slice_id = 'S1'
        slice_title = 'stateful guard'
        slice_type = 'stateful_success_slice'
        slice_status = 'DONE'
        coverage_delta = 20
        target_subsurface_or_carrier = 'example-core/src/main/java/com/example/TaskService.java#waitExamineTask(CaseRoute)'
        required_sibling_surfaces = @()
        production_boundary = 'example-core/src/main/java/com/example/TaskService.java#waitExamineTask(CaseRoute)'
        proof_kind = 'stateful_side_effect'
        real_carrier_kind = 'production_entry_or_service'
        forbidden_substitute_check = 'passed'
        red_expectation = 'suppression should avoid writes'
        implemented_files = @('example-core/src/main/java/com/example/TaskService.java')
        tests = @(
            [ordered]@{ command = 'mvn test'; phase = 'RED'; result = 'fail'; evidence = 'business assertion failed' },
            [ordered]@{ command = 'mvn test'; phase = 'GREEN'; result = 'pass'; evidence = 'pass' }
        )
        exact_contract_assertions = @()
        side_effect_evidence = [ordered]@{
            status = 'CLOSED'
            entry_call = 'TaskService.waitExamineTask'
            expected_writes_or_outputs = @('normal branch writes insert and timeout')
            must_not_writes = @($MustNotWrites)
            test_name = 'TaskServiceTest'
            red_result = 'BUSINESS_ASSERTION_FAILED'
            green_result = 'PASS'
        }
        closed_assertions = @('asserts task insert and timeout behavior')
        must_not_assertions = @($MustNotWrites)
        remaining_gaps = @()
        gap_flags = @()
        touched_requirement_families = @('stateful_side_effect')
        closed_requirement_families = @('stateful_side_effect')
        blocker = ''
        next_recommended_slice_type = 'stateful_success_slice'
    }
}

$statefulRequirement = (@(
    '# Requirement',
    'transfer case does not create first-upload audit task'
) -join [Environment]::NewLine)
$stateful = New-ReplayRoot -Name 'stateful-pre-guard' -RequirementText $statefulRequirement
Write-MinimalTaskService -Worktree $stateful.worktree
Write-Json (Join-Path $stateful.root 'CARRIER_AUTHORIZATION_01.json') ([ordered]@{
    authorization = 'ALLOW'
    selected_carrier = 'example-core/src/main/java/com/example/TaskService.java#waitExamineTask(CaseRoute)'
    downstream_side_effect_or_output = 'stateful side effect'
    requires_side_effect_evidence = $true
    requires_exact_contract_assertions = $false
    issues = @()
})
Write-Json (Join-Path $stateful.root 'SLICE_RESULT_01.json') (New-SliceResult -MustNotWrites @('TaskMapper.insert', 'CaseTimeOutService.addUserTimeOut'))
$verifyMissing = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-SliceClosure.ps1') -ReplayRoot $stateful.root -Worktree $stateful.worktree -SliceResult (Join-Path $stateful.root 'SLICE_RESULT_01.json') -SliceIndex 1 | ConvertFrom-Json
if (@($verifyMissing.gap_flags) -notcontains 'pre_guard_write_inventory_gap') {
    throw 'Expected pre_guard_write_inventory_gap when expired/updateCaseHandTask is not in must_not_writes.'
}
if (-not [bool]$verifyMissing.authorized_for_next_slice) {
    throw 'Expected verifier to authorize the next slice so the blocker can be closed instead of stopping the round.'
}

Write-Json (Join-Path $stateful.root 'SLICE_RESULT_01.json') (New-SliceResult -MustNotWrites @('expired', 'updateCaseHandTask', 'TaskMapper.insert', 'CaseTimeOutService.addUserTimeOut'))
$verifyClosed = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-SliceClosure.ps1') -ReplayRoot $stateful.root -Worktree $stateful.worktree -SliceResult (Join-Path $stateful.root 'SLICE_RESULT_01.json') -SliceIndex 1 | ConvertFrom-Json
if (@($verifyClosed.gap_flags) -contains 'pre_guard_write_inventory_gap') {
    throw 'Expected pre_guard_write_inventory_gap to clear when pre-guard writes are listed.'
}

$scopeRequirement = (@(
    '# Requirement',
    'transfer cases do not create first-upload or supplemented-material audit tasks; my task list is reduced as data absence'
) -join [Environment]::NewLine)
$scope = New-ReplayRoot -Name 'family-scope' -RequirementText $scopeRequirement
Write-Json (Join-Path $scope.root 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    schema_version = 1
    replay_root = $scope.root
    max_slices = 3
    coverage_cap = 100
    no_progress_slices = @()
    families = @(
        (New-Family -Id 'deploy_export_page' -Weight 90 -Carrier 't_task pending row / TaskMapper query-list surface' -Type 'deploy_surface_first_slice'),
        (New-Family -Id 'stateful_side_effect' -Weight 95 -Carrier 'TaskService#waitExamineTask' -Type 'stateful_success_slice')
    )
})
$router = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'FamilyRouterAndCap.ps1') -ReplayRoot $scope.root | ConvertFrom-Json
if (@($router.scope_filtered_families) -notcontains 'deploy_export_page') {
    throw 'Expected deploy_export_page to be filtered for a data-absence requirement without explicit deploy/page/export surface.'
}
if ([string]$router.selected_family -ne 'stateful_side_effect') {
    throw "Expected stateful_side_effect after scope filtering; got $($router.selected_family)."
}

$deployRequirement = (@(
    '# Requirement',
    'add report export Excel field and display the field on page'
) -join [Environment]::NewLine)
$deploy = New-ReplayRoot -Name 'family-scope-deploy' -RequirementText $deployRequirement
Write-Json (Join-Path $deploy.root 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
    schema_version = 1
    replay_root = $deploy.root
    max_slices = 3
    coverage_cap = 100
    no_progress_slices = @()
    families = @(
        (New-Family -Id 'deploy_export_page' -Weight 90 -Carrier 'ReportController#export' -Type 'deploy_surface_first_slice'),
        (New-Family -Id 'stateful_side_effect' -Weight 95 -Carrier 'TaskService#waitExamineTask' -Type 'stateful_success_slice')
    )
})
$deployRouter = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'FamilyRouterAndCap.ps1') -ReplayRoot $deploy.root | ConvertFrom-Json
if (@($deployRouter.scope_filtered_families) -contains 'deploy_export_page') {
    throw 'Deploy family should not be filtered when the requirement explicitly names export/page display.'
}

[ordered]@{
    status = 'PASS'
    cases = @(
        'pre_guard_write_missing_detected',
        'pre_guard_write_listed_clears_gap',
        'unsupported_deploy_family_filtered',
        'explicit_deploy_family_preserved'
    )
    temp_root = $tempRoot
} | ConvertTo-Json -Depth 6
