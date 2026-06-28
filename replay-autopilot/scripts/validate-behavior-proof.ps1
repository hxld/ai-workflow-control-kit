param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [int]$Slice = 1,
    [string]$Worktree = '',
    [string]$SliceResultPath = ''
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

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

$replayRootFull = [System.IO.Path]::GetFullPath($ReplayRoot)
$worktreeFull = Resolve-Worktree -ReplayRoot $replayRootFull -Worktree $Worktree
if ([string]::IsNullOrWhiteSpace($SliceResultPath)) {
    $SliceResultPath = Join-Path $replayRootFull ('SLICE_RESULT_{0:D2}.json' -f $Slice)
}
$sliceResultFull = [System.IO.Path]::GetFullPath($SliceResultPath)
$issues = New-Object System.Collections.Generic.List[string]

$sliceObject = Read-Json $sliceResultFull
$verify = Read-Json (Join-Path $replayRootFull ('SLICE_VERIFY_{0:D2}.json' -f $Slice))
$callable = Read-Json (Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $Slice))

if ($null -eq $sliceObject) {
    $issues.Add('slice_result_missing') | Out-Null
} else {
    $coverageDelta = 0
    try { $coverageDelta = [int]$sliceObject.coverage_delta } catch { $coverageDelta = 0 }
    $testExecutionEvidence = $false
    if ($sliceObject.PSObject.Properties['test_execution_evidence']) {
        $testExecutionEvidence = [bool]$sliceObject.test_execution_evidence -or -not [string]::IsNullOrWhiteSpace([string]$sliceObject.test_execution_evidence)
    }
    if (-not $testExecutionEvidence -and $sliceObject.PSObject.Properties['test_execution_exit_code'] -and $sliceObject.test_execution_exit_code -eq 0) {
        $testExecutionEvidence = $true
    }
    foreach ($test in @($sliceObject.tests)) {
        if ($null -ne $test -and [string]$test.phase -match '(?i)^(GREEN|VERIFY)$' -and [string]$test.result -match '(?i)^(pass|success)$') {
            $testExecutionEvidence = $true
        }
    }
    if (-not $testExecutionEvidence) { $issues.Add('test_execution_evidence_missing') | Out-Null }

    $authorizedEntry = ''
    if ($null -ne $callable) {
        foreach ($name in @('selected_real_entry', 'existing_entry_fqn', 'selected_carrier_fqn', 'selected_carrier')) {
            if ($callable.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$callable.$name)) {
                $authorizedEntry = [string]$callable.$name
                break
            }
        }
    }
    $entryEvidence = @(
        [string]$slice.entry_invoked,
        [string]$sliceObject.production_boundary,
        [string]$sliceObject.target_subsurface_or_carrier,
        [string]$sliceObject.test_execution_evidence,
        ((Get-StringArray $sliceObject.closed_assertions) -join '; ')
    ) -join "`n"
    if (-not [string]::IsNullOrWhiteSpace($authorizedEntry) -and $entryEvidence -notmatch [regex]::Escape($authorizedEntry)) {
        $issues.Add('entry_invoked_not_authorized_carrier') | Out-Null
    }

    $assertionText = @(
        ((Get-StringArray $sliceObject.closed_assertions) -join '; '),
        [string]$sliceObject.test_execution_evidence,
        ((@($sliceObject.tests) | ForEach-Object { [string]$_.evidence }) -join '; ')
    ) -join "`n"
    if ($assertionText -notmatch '(?i)(assert|verify|expect|equals|contains|state|payload|response|status|persist|save|update|insert|return value|business)') {
        $issues.Add('business_or_state_assertion_missing') | Out-Null
    }

    $probeText = @(
        [string]$sliceObject.side_effect_probe,
        [string]$sliceObject.payload_probe,
        [string]$sliceObject.negative_probe,
        [string]$sliceObject.must_not_assertion,
        [string]$sliceObject.side_effect_or_output_probe,
        [string]$sliceObject.side_effect_evidence,
        $assertionText
    ) -join "`n"
    if ($probeText -notmatch '(?i)(side.?effect|payload|negative|must.?not|state|status|db|persist|save|update|insert|response|return value)') {
        $issues.Add('side_effect_payload_or_negative_probe_missing') | Out-Null
    }

    $compileOnly = ([string]$sliceObject.proof_kind -match '(?i)compile_only|static|helper_only|dto_only|file_presence') -or ([bool]$sliceObject.compile_only)
    if ($coverageDelta -gt 0 -and $compileOnly) {
        $issues.Add('compile_only_cannot_claim_coverage') | Out-Null
    }
    if ($coverageDelta -gt 0 -and @($issues).Count -gt 0) {
        $issues.Add('nonzero_coverage_without_behavior_proof_schema') | Out-Null
    }
}

if ($null -ne $verify) {
    foreach ($blocker in @(Get-StringArray $verify.authorization_blockers)) {
        if ($blocker -match '(?i)(wrong_test_surface|behavior_evidence_missing|side_effect_evidence_missing|no_test_execution_evidence)') {
            $issues.Add("slice_verify_blocker:$blocker") | Out-Null
        }
    }
}

$statusOut = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema = 'behavior_proof_validation.v1'
    status = $statusOut
    replay_root = $replayRootFull
    worktree = $worktreeFull
    slice = $Slice
    slice_result = $sliceResultFull
    callable_carrier_authorization = Join-Path $replayRootFull ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $Slice)
    slice_verify = Join-Path $replayRootFull ('SLICE_VERIFY_{0:D2}.json' -f $Slice)
    issues = @($issues | Select-Object -Unique)
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRootFull ('BEHAVIOR_PROOF_VALIDATE_{0:D2}.json' -f $Slice)) -Encoding UTF8

if ($statusOut -ne 'PASS') { exit 1 }
exit 0
