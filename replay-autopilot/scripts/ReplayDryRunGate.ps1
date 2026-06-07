param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [ValidateSet('FirstSliceProofPlan', 'ValidateOnly')]
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

function Invoke-UnderlyingDryRun {
    param([string]$Root, [string]$Expected)

    $script = Join-Path $PSScriptRoot 'Invoke-ReplayDryRun.ps1'
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $script,
        '-ReplayRoot', $Root,
        '-Mode', 'FirstSliceProofPlan'
    )
    if (-not [string]::IsNullOrWhiteSpace($Expected)) {
        $args += @('-ExpectStatus', $Expected)
    }
    $output = & powershell @args
    $exit = $LASTEXITCODE
    $jsonText = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        throw "Invoke-ReplayDryRun.ps1 produced no JSON output."
    }
    $json = $jsonText | ConvertFrom-Json
    return [ordered]@{
        exit_code = $exit
        result = $json
    }
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
if (-not (Test-Path -LiteralPath $replayRootFull)) {
    throw "ReplayRoot not found: $replayRootFull"
}

$stopText = @(
    (Read-TextIfExists (Join-Path $replayRootFull 'STOP_OR_CONTINUE_DECISION.md')),
    (Read-TextIfExists (Join-Path $replayRootFull 'STOP_LOSS_DECISION.md')),
    (Read-TextIfExists (Join-Path $replayRootFull 'DEEP_REVIEW_REPORT.md'))
) -join "`n"
$hasStopDecision = $stopText -match '(?i)STOP_AND_EVOLVE|STOP_DEEP_REVIEW_REQUIRED|STOP_DEEP_REVIEW|do not start another fresh replay'

if ($ValidateOnly -or $Mode -eq 'ValidateOnly') {
    $expected = if ($hasStopDecision) { 'STOP' } else { '' }
    $underlying = Invoke-UnderlyingDryRun -Root $replayRootFull -Expected $expected
    $dry = $underlying.result

    $status = [string]$dry.status
    $reasons = @()
    if ($null -ne $dry.reasons) { $reasons = @($dry.reasons | ForEach-Object { [string]$_ }) }

    $validationStatus = 'PASS'
    $validationIssues = New-Object System.Collections.Generic.List[string]
    if ($hasStopDecision -and $status -ne 'STOP') {
        $validationStatus = 'FAIL'
        $validationIssues.Add('stop_loss_not_enforced') | Out-Null
    }
    if (-not $hasStopDecision -and @('ALLOW', 'BLOCKED_PLAN_MISMATCH') -notcontains $status) {
        $validationStatus = 'FAIL'
        $validationIssues.Add('unexpected_dry_run_status') | Out-Null
    }

    $result = [ordered]@{
        status = $status
        validation_status = $validationStatus
        mode = 'ValidateOnly'
        replay_root = $replayRootFull
        stop_decision_detected = $hasStopDecision
        missing_fields = @($dry.missing_fields)
        reasons = @($reasons)
        validation_issues = @($validationIssues)
        allowed_next_action = [string]$dry.allowed_next_action
        gate = 'first_slice_dry_run_stop_gate'
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRootFull 'DRY_RUN_GATE.json') -Encoding UTF8
    $result | ConvertTo-Json -Depth 10

    if ($validationStatus -ne 'PASS') { exit 1 }
    if (-not [string]::IsNullOrWhiteSpace($ExpectStatus) -and $status -ne $ExpectStatus) { exit 1 }
    exit 0
}

$underlying = Invoke-UnderlyingDryRun -Root $replayRootFull -Expected $ExpectStatus
$dry = $underlying.result
$result = [ordered]@{
    status = [string]$dry.status
    validation_status = $(if ($underlying.exit_code -eq 0) { 'PASS' } else { 'FAIL' })
    mode = $Mode
    replay_root = $replayRootFull
    stop_decision_detected = $hasStopDecision
    missing_fields = @($dry.missing_fields)
    reasons = @($dry.reasons)
    allowed_next_action = [string]$dry.allowed_next_action
    gate = 'first_slice_dry_run_stop_gate'
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRootFull 'DRY_RUN_GATE.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 10

if ($underlying.exit_code -ne 0) { exit $underlying.exit_code }
