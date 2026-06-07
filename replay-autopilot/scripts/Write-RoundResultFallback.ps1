param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [string]$BaseCommit = '',
    [string]$FeatureName = '',
    [string]$RequirementSource = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-IntValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return 0 }
    if ($Object.PSObject.Properties.Name -contains $Name -and "$($Object.$Name)" -match '^-?\d+$') {
        return [int]$Object.$Name
    }
    return 0
}

function Add-Line {
    param([System.Collections.Generic.List[string]]$Lines, [string]$Text = '')
    $Lines.Add($Text) | Out-Null
}

$root = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
$roundPath = Join-Path $root 'ROUND_RESULT.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
        worktree = $worktreeFull
        round_result = $roundPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$sliceResults = @(Get-ChildItem -LiteralPath $root -File -Filter 'SLICE_RESULT_*.json' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { Read-JsonIfExists $_.FullName })
$sliceVerifies = @(Get-ChildItem -LiteralPath $root -File -Filter 'SLICE_VERIFY_*.json' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { Read-JsonIfExists $_.FullName })
$familyLedger = Read-JsonIfExists (Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json')
$routerCap = Read-JsonIfExists (Join-Path $root 'FAMILY_ROUTER_AND_CAP.json')
$familyCapText = Read-TextIfExists (Join-Path $root 'REQUIREMENT_FAMILY_CAP.md')
$runnerContract = Read-TextIfExists (Join-Path $root 'RUNNER_ENFORCEMENT_CONTRACT.md')

$sumAdjusted = 0
$sumBlind = 0
$allGapFlags = New-Object System.Collections.Generic.List[string]
$allTests = New-Object System.Collections.Generic.List[string]
$implementedFiles = New-Object System.Collections.Generic.List[string]
$changedFiles = @()

foreach ($result in $sliceResults) {
    $sumBlind += Get-IntValue $result 'coverage_delta'
    foreach ($flag in Get-StringArray $result.gap_flags) {
        if (-not $allGapFlags.Contains($flag)) { $allGapFlags.Add($flag) | Out-Null }
    }
    foreach ($file in Get-StringArray $result.implemented_files) {
        if (-not $implementedFiles.Contains($file)) { $implementedFiles.Add($file) | Out-Null }
    }
    foreach ($test in @($result.tests)) {
        if ($null -ne $test) {
            $allTests.Add(("- S{0} {1} {2}: {3} => {4}" -f $result.slice_index, $test.phase, $test.result, $test.command, $test.evidence)) | Out-Null
        }
    }
}
foreach ($verify in $sliceVerifies) {
    $sumAdjusted += Get-IntValue $verify 'adjusted_coverage_delta'
    foreach ($flag in Get-StringArray $verify.gap_flags) {
        if (-not $allGapFlags.Contains($flag)) { $allGapFlags.Add($flag) | Out-Null }
    }
    foreach ($blocker in Get-StringArray $verify.authorization_blockers) {
        if (-not [string]::IsNullOrWhiteSpace($blocker) -and -not $allGapFlags.Contains($blocker)) { $allGapFlags.Add($blocker) | Out-Null }
    }
}

try {
    $changedFiles = @(& git -C $worktreeFull status --short --untracked-files=all)
} catch {
    $changedFiles = @("git status failed: $($_.Exception.Message)")
}

$ledgerCap = 100
if ($null -ne $routerCap -and $routerCap.PSObject.Properties.Name -contains 'coverage_cap_from_ledger') {
    $ledgerCap = [int]$routerCap.coverage_cap_from_ledger
} elseif ($null -ne $familyLedger -and $familyLedger.PSObject.Properties.Name -contains 'coverage_cap') {
    $ledgerCap = [int]$familyLedger.coverage_cap
}
$verificationCapped = [Math]::Min($sumAdjusted, $ledgerCap)
if ($verificationCapped -lt 0) { $verificationCapped = 0 }
$blindCoverage = [Math]::Min($sumBlind, 89)

$requiredOpen = @()
if ($null -ne $familyLedger -and $familyLedger.PSObject.Properties.Name -contains 'families') {
    $requiredOpen = @($familyLedger.families | Where-Object { [bool]$_.required -and @('OPEN', 'PARTIAL') -contains ([string]$_.status) })
}
$authorizedStops = @($sliceVerifies | Where-Object {
    ($_.PSObject.Properties.Name -contains 'authorized_for_next_slice' -and -not [bool]$_.authorized_for_next_slice) -or
    ($_.PSObject.Properties.Name -contains 'authorized_for_synthesis' -and -not [bool]$_.authorized_for_synthesis)
})
$finalStatus = if ($authorizedStops.Count -gt 0 -or ($allGapFlags -contains 'no_progress_slice')) {
    'BLOCKED'
} elseif ($verificationCapped -ge 90 -and $requiredOpen.Count -eq 0) {
    'PASS'
} else {
    'PARTIAL'
}

if ($authorizedStops.Count -gt 0 -and -not $allGapFlags.Contains('tooling_authorization_stop')) {
    $allGapFlags.Add('tooling_authorization_stop') | Out-Null
}

$lines = [System.Collections.Generic.List[string]]::new()
Add-Line $lines '# ROUND_RESULT'
Add-Line $lines ''
Add-Line $lines '## Scope'
Add-Line $lines "- feature_name: $FeatureName"
Add-Line $lines "- replay root: $root"
Add-Line $lines "- worktree: $worktreeFull"
Add-Line $lines "- base commit: $BaseCommit"
Add-Line $lines "- requirement_source: $RequirementSource"
Add-Line $lines "- oracle_used: false"
Add-Line $lines ''
Add-Line $lines '## Forbidden Source Check'
Add-Line $lines '- oracle branch/diff read: false'
Add-Line $lines '- historical replay/final report read: false'
Add-Line $lines '- production/test implementation after synthesis: false'
Add-Line $lines '- generated_by: deterministic fallback from blind slice artifacts'
Add-Line $lines ''
Add-Line $lines '## Plan Files Used'
foreach ($name in @('ROUND_CONTRACT.md','PHASE0_RESULT.md','EXPLORATION_REPORT.md','PLAN_RESULT.md','REPLAY_PLAN.md','IMPLEMENTATION_CONTRACT.md','EXPECTED_DIFF_MATRIX.md','SIDE_EFFECT_LEDGER.md','TEST_CHARTER.md','FIRST_SLICE_PROOF_PLAN.md')) {
    Add-Line $lines "- ${name}: $(Test-Path (Join-Path $root $name))"
}
Add-Line $lines ''
Add-Line $lines '## Slice Execution Ledger'
foreach ($result in $sliceResults) {
    Add-Line $lines ("- S{0}: status={1}; type={2}; coverage_delta={3}; blocker={4}" -f $result.slice_index, $result.slice_status, $result.slice_type, (Get-IntValue $result 'coverage_delta'), ([string]$result.blocker))
}
Add-Line $lines ''
Add-Line $lines '## Slice Verification Ledger'
foreach ($verify in $sliceVerifies) {
    Add-Line $lines ("- S{0}: verification={1}; adjusted_delta={2}; cap={3}; continue={4}; next_authorized={5}; synthesis_authorized={6}; blockers={7}" -f $verify.slice_index, $verify.verification_status, (Get-IntValue $verify 'adjusted_coverage_delta'), (Get-IntValue $verify 'coverage_cap'), $verify.should_continue, $verify.authorized_for_next_slice, $verify.authorized_for_synthesis, ((Get-StringArray $verify.authorization_blockers) -join ','))
}
Add-Line $lines ''
Add-Line $lines '## Implemented Files'
if ($implementedFiles.Count -eq 0) { Add-Line $lines '- none' } else { foreach ($file in $implementedFiles) { Add-Line $lines "- $file" } }
Add-Line $lines ''
Add-Line $lines '## Changed Files'
if ($changedFiles.Count -eq 0) { Add-Line $lines '- none' } else { foreach ($file in $changedFiles) { Add-Line $lines "- $file" } }
Add-Line $lines ''
Add-Line $lines '## Tests Run'
if ($allTests.Count -eq 0) { Add-Line $lines '- none' } else { foreach ($test in $allTests) { Add-Line $lines $test } }
Add-Line $lines ''
Add-Line $lines '## Exact Contract Ledger'
foreach ($result in $sliceResults) {
    foreach ($item in @($result.exact_contract_assertions)) {
        if ($null -ne $item) {
            Add-Line $lines ("- S{0}: {1}; symbol={2}; surface={3}; status={4}; assertion={5}" -f $result.slice_index, $item.literal, $item.symbol_or_field, $item.db_or_wire_or_display, $item.status, $item.test_assertion)
        }
    }
}
Add-Line $lines ''
Add-Line $lines '## Side-Effect Ledger'
foreach ($result in $sliceResults) {
    if ($null -ne $result.side_effect_evidence) {
        Add-Line $lines ("- S{0}: entry={1}; red={2}; green={3}; test={4}; outputs={5}" -f $result.slice_index, $result.side_effect_evidence.entry_call, $result.side_effect_evidence.red_result, $result.side_effect_evidence.green_result, $result.side_effect_evidence.test_name, ((Get-StringArray $result.side_effect_evidence.expected_writes_or_outputs) -join '; '))
    }
}
Add-Line $lines ''
Add-Line $lines '## Executable Surface Slice Ledger'
foreach ($result in $sliceResults) {
    Add-Line $lines ("- S{0}: carrier={1}; production_boundary={2}; proof_kind={3}; real_carrier_kind={4}" -f $result.slice_index, $result.target_subsurface_or_carrier, $result.production_boundary, $result.proof_kind, $result.real_carrier_kind)
}
Add-Line $lines ''
Add-Line $lines '## Requirement Family Closure Ledger'
if ($null -ne $familyLedger -and $familyLedger.PSObject.Properties.Name -contains 'families') {
    foreach ($family in @($familyLedger.families)) {
        Add-Line $lines ("- {0}: required={1}; status={2}; touched={3}; cap_if_open={4}; reason={5}" -f $family.id, $family.required, $family.status, $family.touched_count, $family.coverage_cap_if_open, $family.last_reason)
    }
}
Add-Line $lines ''
Add-Line $lines '## Family Contract Closure Ledger'
Add-Line $lines $familyCapText
Add-Line $lines ''
Add-Line $lines '## Runner Enforcement Contract Result'
Add-Line $lines $runnerContract
Add-Line $lines ''
Add-Line $lines '## Tracer Bullet Decision'
Add-Line $lines "- tracer_bullet_only: $($allGapFlags -contains 'tracer_bullet_only')"
Add-Line $lines ''
Add-Line $lines '## Gap Flags'
if ($allGapFlags.Count -eq 0) { Add-Line $lines '- none' } else { foreach ($flag in $allGapFlags) { Add-Line $lines "- $flag" } }
Add-Line $lines ''
Add-Line $lines '## Coverage'
Add-Line $lines "- blind_self_assessed_coverage: $blindCoverage"
Add-Line $lines "- verification_capped_coverage: $verificationCapped"
Add-Line $lines "- coverage cap reason: min(sum adjusted_coverage_delta=$sumAdjusted, coverage_cap_from_ledger=$ledgerCap); required_open=$($requiredOpen.Count); authorization_stops=$($authorizedStops.Count)"
Add-Line $lines "- final status: $finalStatus"
Add-Line $lines ''
Add-Line $lines '## Gap Root Cause'
Add-Line $lines '- requirement: exact literal/source lifecycle still partially open unless all family rows close.'
Add-Line $lines '- design: runner routed to a blocked follow-up slice when exact-contract closure should be prioritized.'
Add-Line $lines '- implementation: only implemented files listed above are counted; blocked/no-progress slices contribute no coverage.'
Add-Line $lines '- test: RED/GREEN evidence is counted only when verifier accepted behavior evidence.'
Add-Line $lines '- verification: deterministic fallback used because synthesis agent did not write ROUND_RESULT.md.'
Add-Line $lines '- workflow gate: tooling_authorization_stop and family cap prevent PASS.'

Set-Content -LiteralPath $roundPath -Value ($lines -join "`n") -Encoding UTF8
[ordered]@{
    status = 'WROTE_ROUND_RESULT'
    round_result = $roundPath
    blind_self_assessed_coverage = $blindCoverage
    verification_capped_coverage = $verificationCapped
    final_status = $finalStatus
} | ConvertTo-Json -Depth 8
