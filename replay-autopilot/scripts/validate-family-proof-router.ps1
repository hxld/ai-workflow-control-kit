param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [int]$Slice = 1,
    [string]$Worktree = '',
    [string]$MavenSettings = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-Worktree {
    param([string]$ReplayRoot, [string]$Worktree)
    if (-not [string]::IsNullOrWhiteSpace($Worktree)) { return [System.IO.Path]::GetFullPath($Worktree) }
    return [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($ReplayRoot), 'worktree')
}

function Read-Json {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$replayRootFull = [System.IO.Path]::GetFullPath($ReplayRoot)
$worktreeFull = Resolve-Worktree -ReplayRoot $replayRootFull -Worktree $Worktree

$aggregateArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'Invoke-PreSliceExperimentContracts.ps1'),
    '-ReplayRoot', $replayRootFull,
    '-Worktree', $worktreeFull,
    '-SliceIndex', $Slice
)
if (-not [string]::IsNullOrWhiteSpace($MavenSettings)) { $aggregateArgs += @('-MavenSettings', $MavenSettings) }
& powershell @aggregateArgs | Out-Null
$aggregateExit = $LASTEXITCODE

$slicePlanPath = Join-Path $replayRootFull ('SLICE_PLAN_CONTRACT_{0:D2}.json' -f $Slice)
$preBlockerPath = Join-Path $replayRootFull ('SLICE_RESULT_PRE_{0:D2}.json' -f $Slice)
$slicePlan = Read-Json $slicePlanPath
$preBlocker = Read-Json $preBlockerPath
$issues = New-Object System.Collections.Generic.List[string]

if ($null -eq $slicePlan) {
    $issues.Add('family_router_contract_missing') | Out-Null
} else {
    foreach ($field in @('experiment', 'selected_family', 'highest_weight_open_family', 'family_id', 'selected_carrier', 'required_proof_type', 'expected_actual_proof_type', 'coverage_cap_if_open', 'forbidden_proof', 'router_status')) {
        if (-not $slicePlan.PSObject.Properties[$field]) {
            $issues.Add("family_router_missing_$field") | Out-Null
        } elseif ($field -ne 'coverage_cap_if_open' -and $field -ne 'forbidden_proof' -and [string]::IsNullOrWhiteSpace([string]$slicePlan.$field)) {
            $issues.Add("family_router_empty_$field") | Out-Null
        }
    }
    if ([string]$slicePlan.experiment -ne 'high_weight_family_proof_router') { $issues.Add('family_router_wrong_experiment') | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace([string]$slicePlan.highest_weight_open_family) -and [string]$slicePlan.selected_family -ne [string]$slicePlan.highest_weight_open_family) {
        $issues.Add('family_router_not_highest_weight_open_family') | Out-Null
    }
    if (@($slicePlan.forbidden_proof).Count -eq 0) { $issues.Add('family_router_missing_forbidden_proof') | Out-Null }
    if ([string]$slicePlan.router_status -notin @('PASS', 'STOP')) { $issues.Add('family_router_invalid_status') | Out-Null }
}

if ($aggregateExit -ne 0 -and $null -ne $preBlocker) {
    if ($preBlocker.PSObject.Properties['executor_invoked'] -and [bool]$preBlocker.executor_invoked) {
        $issues.Add('blocked_router_invoked_executor') | Out-Null
    }
    if ([int]$preBlocker.coverage_delta -ne 0) { $issues.Add('blocked_router_has_coverage_delta') | Out-Null }
}

$status = if ($issues.Count -eq 0) { if ($aggregateExit -eq 0) { 'PASS' } else { 'STOP' } } else { 'FAIL' }
$result = [ordered]@{
    schema = 'family_proof_router_validation.v1'
    status = $status
    aggregate_exit_code = $aggregateExit
    replay_root = $replayRootFull
    worktree = $worktreeFull
    slice = $Slice
    slice_plan_contract = $slicePlanPath
    pre_slice_blocker = $preBlockerPath
    issues = @($issues)
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRootFull ('FAMILY_PROOF_ROUTER_VALIDATE_{0:D2}.json' -f $Slice)) -Encoding UTF8

if ($status -eq 'FAIL') { exit 1 }
exit 0
