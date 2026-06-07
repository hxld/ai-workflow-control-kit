param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [ValidateSet('FirstSliceProofPlan')]
    [string]$Mode = 'FirstSliceProofPlan',
    [string]$ExpectStatus = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Test-AnyPattern {
    param([string]$Text, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        if ($Text -match $pattern) { return $true }
    }
    return $false
}

function Get-PlanField {
    param([string]$Text, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $escaped = [regex]::Escape($Name)
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match "^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?$escaped\s*\*{0,2}\s*:\s*`?([^`\r\n]*)`?\s*$") {
            return $matches[1].Trim().Trim('`').Trim()
        }
    }
    return ''
}

function Test-PublicEntryText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return $Text -match '(?i)(Facade(?:Impl)?|Controller(?:Impl)?|Api|Endpoint|Route)\b'
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        script = $PSCommandPath
        modes = @('FirstSliceProofPlan')
    } | ConvertTo-Json -Depth 6
    exit 0
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
if (-not (Test-Path -LiteralPath $replayRootFull)) {
    throw "ReplayRoot not found: $replayRootFull"
}

$outPath = Join-Path $replayRootFull 'FIRST_SLICE_DRY_RUN.json'
$proofPlanPath = Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md'
$runnerContractPath = Join-Path $replayRootFull 'RUNNER_ENFORCEMENT_CONTRACT.md'
$ledgerPath = Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json'
$stopDecisionPath = Join-Path $replayRootFull 'STOP_OR_CONTINUE_DECISION.md'
$stopLossPath = Join-Path $replayRootFull 'STOP_LOSS_DECISION.md'
$sliceProgressPath = Join-Path $replayRootFull 'SLICE_PROGRESS.json'

$missing = New-Object System.Collections.Generic.List[string]
$reasons = New-Object System.Collections.Generic.List[string]
$status = 'ALLOW'

$completedSliceCount = 0
if (Test-Path -LiteralPath $sliceProgressPath) {
    try {
        $progress = Get-Content -LiteralPath $sliceProgressPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $completedSliceCount = @($progress.completed).Count
    } catch {
        $completedSliceCount = 0
    }
}

$stopText = (Read-TextIfExists $stopDecisionPath) + "`n" + (Read-TextIfExists $stopLossPath)
if ($stopText -match '(?i)STOP_AND_EVOLVE|STOP_DEEP_REVIEW_REQUIRED' -and $completedSliceCount -eq 0) {
    $status = 'STOP'
    $reasons.Add('previous_stop_loss_requires_evolution_before_fresh_replay') | Out-Null
} elseif ($stopText -match '(?i)STOP_AND_EVOLVE|STOP_DEEP_REVIEW_REQUIRED' -and $completedSliceCount -gt 0) {
    $reasons.Add('previous_stop_loss_allows_existing_slice_resume_after_tooling_fix') | Out-Null
}

$proofText = Read-TextIfExists $proofPlanPath
if ([string]::IsNullOrWhiteSpace($proofText)) {
    $status = 'BLOCKED_PLAN_MISMATCH'
    $missing.Add('FIRST_SLICE_PROOF_PLAN.md') | Out-Null
} else {
    $required = [ordered]@{
        highest_weight_open_gate = @('(?im)^\s*\*{0,2}[-*]?(?:#{1,4})?\s*(highest[_ -]?weight[_ -]?open[_ -]?gate|target\s+family)\s*\*{0,2}\s*:')
        selected_real_entry = @('(?im)^\s*\*{0,2}[-*]?(?:#{1,4})?\s*selected[_ -]?real[_ -]?entry\s*\*{0,2}\s*:')
        selected_carrier = @('(?im)^\s*\*{0,2}[-*]?(?:#{1,4})?\s*(selected[_ -]?carrier|existing\s+production\s+carrier|selected[_ -]?real[_ -]?entry)\s*\*{0,2}\s*:')
        target_subsurface_or_carrier = @('(?im)^\s*\*{0,2}[-*]?(?:#{1,4})?\s*(target[_ -]?subsurface[_ -]?or[_ -]?carrier|selected[_ -]?real[_ -]?entry|existing\s+production\s+carrier)\s*\*{0,2}\s*:')
        required_sibling_surfaces = @('(?im)^\s*\*{0,2}[-*]?(?:#{1,4})?\s*(required[_ -]?sibling[_ -]?surfaces|target\s+sibling/surface|target\s+sibling\s+surface)\s*\*{0,2}\s*:')
        production_boundary = @('(?im)^\s*\*{0,2}[-*]?(?:#{1,4})?\s*production[_ -]?boundary\s*\*{0,2}\s*:')
        proof_kind = @('(?im)^\s*\*{0,2}[-*]?(?:#{1,4})?\s*proof[_ -]?kind\s*\*{0,2}\s*:')
        red_expectation = @('(?im)^\s*\*{0,2}[-*]?(?:#{1,4})?\s*(red[_ -]?expectation|red\s+assertion|first[_ -]?red[_ -]?test)\s*\*{0,2}\s*:')
        fail_closed_condition = @('(?im)^\s*\*{0,2}[-*]?(?:#{1,4})?\s*fail[-_ ]?closed[-_ ]?condition\s*\*{0,2}\s*:')
    }
    foreach ($key in $required.Keys) {
        if (-not (Test-AnyPattern -Text $proofText -Patterns $required[$key])) {
            $missing.Add($key) | Out-Null
        }
    }
    if ($missing.Count -gt 0 -and $status -eq 'ALLOW') {
        $status = 'BLOCKED_PLAN_MISMATCH'
        $reasons.Add('first_slice_proof_plan_schema_missing_required_fields') | Out-Null
    }

    $selectedRealEntry = Get-PlanField -Text $proofText -Name 'selected_real_entry'
    $selectedCarrier = Get-PlanField -Text $proofText -Name 'selected_carrier'
    $firstRedTest = Get-PlanField -Text $proofText -Name 'first_red_test'
    $targetSurface = Get-PlanField -Text $proofText -Name 'target_subsurface_or_carrier'
    $requiredSiblings = Get-PlanField -Text $proofText -Name 'required_sibling_surfaces'
    $publicEntryCoverage = Get-PlanField -Text $proofText -Name 'public_entry_contract_coverage'
    $publicEntryRequired = Test-PublicEntryText $selectedRealEntry
    $publicEntryCovered = (Test-PublicEntryText $selectedCarrier) -or (Test-PublicEntryText $firstRedTest) -or (Test-PublicEntryText $targetSurface)
    if ($publicEntryRequired -and [string]::IsNullOrWhiteSpace($publicEntryCoverage)) {
        $status = 'BLOCKED_PLAN_MISMATCH'
        $missing.Add('public_entry_contract_coverage') | Out-Null
        $reasons.Add('public_entry_contract_coverage_missing') | Out-Null
    } elseif ($publicEntryRequired -and -not $publicEntryCovered) {
        $status = 'BLOCKED_PLAN_MISMATCH'
        $missing.Add('public_entry_contract_coverage') | Out-Null
        $reasons.Add('selected_real_entry_names_public_entry_but_first_slice_carrier_and_red_test_do_not_cover_public_entry_response') | Out-Null
    }
    if ($requiredSiblings -match '(?i)\b(Controller|JSP|JS|page|view|display|submit|query)\b' -and $selectedCarrier -notmatch '(?i)\b(Controller|JSP|JS|page|view|display|submit|query)\b') {
        $reasons.Add('deploy_facing_sibling_present_but_first_slice_is_not_deploy_surface') | Out-Null
    }
}

$runnerContractExists = Test-Path -LiteralPath $runnerContractPath
$ledgerExists = Test-Path -LiteralPath $ledgerPath

$result = [ordered]@{
    mode = $Mode
    status = $status
    replay_root = $replayRootFull
    proof_plan = $proofPlanPath
    runner_contract_exists = $runnerContractExists
    requirement_family_ledger_exists = $ledgerExists
    completed_slice_count = $completedSliceCount
    missing_fields = @($missing)
    reasons = @($reasons)
    allowed_next_action = $(if ($status -eq 'ALLOW') { 'start_or_continue_first_slice' } elseif ($status -eq 'STOP') { 'run_evolution_or_deep_review_before_fresh_replay' } else { 'repair_plan_or_runner_contract_before_implementation' })
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outPath -Encoding UTF8
$result | ConvertTo-Json -Depth 8

if (-not [string]::IsNullOrWhiteSpace($ExpectStatus) -and $status -ne $ExpectStatus) {
    exit 1
}
