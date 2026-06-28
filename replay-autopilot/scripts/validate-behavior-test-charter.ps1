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

function Write-JsonFile {
    param($Value, [string]$Path, [int]$Depth = 8)
    $json = $Value | ConvertTo-Json -Depth $Depth
    $null = $json | ConvertFrom-Json
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $tmp = Join-Path $dir ('.{0}.{1}.{2}.tmp' -f [System.IO.Path]::GetFileName($Path), $PID, [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    $lastError = $null
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        $backup = Join-Path $dir ('.{0}.{1}.{2}.bak' -f [System.IO.Path]::GetFileName($Path), $PID, [guid]::NewGuid().ToString('N'))
        try {
            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                [System.IO.File]::Replace($tmp, $Path, $backup, $true)
                Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
            } else {
                [System.IO.File]::Move($tmp, $Path)
            }
            return
        } catch {
            $lastError = $_
            Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds ([Math]::Min(1000, 25 * $attempt))
        }
    }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw "Failed to atomically write JSON to $Path after retries: $lastError"
}

$replayRootFull = [System.IO.Path]::GetFullPath($ReplayRoot)
$worktreeFull = Resolve-Worktree -ReplayRoot $replayRootFull -Worktree $Worktree
$charterPath = Join-Path $replayRootFull ('TEST_CHARTER_{0:D2}.json' -f $Slice)

$aggregateArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'Invoke-PreSliceExperimentContracts.ps1'),
    '-ReplayRoot', $replayRootFull,
    '-Worktree', $worktreeFull,
    '-SliceIndex', $Slice
)
if (-not (Test-Path -LiteralPath $charterPath -PathType Leaf)) {
    if (-not [string]::IsNullOrWhiteSpace($MavenSettings)) { $aggregateArgs += @('-MavenSettings', $MavenSettings) }
    & powershell @aggregateArgs | Out-Null
    $aggregateExit = $LASTEXITCODE
} else {
    $aggregateExit = 0
}

$preBlockerPath = Join-Path $replayRootFull ('SLICE_RESULT_PRE_{0:D2}.json' -f $Slice)
$charter = Read-Json $charterPath
$preBlocker = Read-Json $preBlockerPath
$issues = New-Object System.Collections.Generic.List[string]

if ($null -eq $charter) {
    $issues.Add('behavior_test_charter_missing') | Out-Null
} else {
    foreach ($field in @('experiment', 'family_id', 'real_entry_method', 'test_class', 'red_assertion', 'green_assertion', 'maven_command', 'test_harness_module', 'behavior_test_charter_status')) {
        if (-not $charter.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$charter.$field)) {
            $issues.Add("behavior_charter_missing_$field") | Out-Null
        }
    }
    if ([string]$charter.experiment -ne 'behavior_test_charter_gate') { $issues.Add('behavior_charter_wrong_experiment') | Out-Null }
    if (@($charter.must_not_assertions).Count -eq 0) { $issues.Add('behavior_charter_missing_must_not_assertions') | Out-Null }
    if ([bool]$charter.side_effect_proof_required -and @($charter.side_effect_assertions).Count -eq 0) {
        $issues.Add('behavior_charter_missing_side_effect_assertions') | Out-Null
    }
    if ([string]$charter.behavior_test_charter_status -notin @('PASS', 'STOP')) { $issues.Add('behavior_charter_invalid_status') | Out-Null }
}

if ($aggregateExit -ne 0 -and $null -ne $preBlocker) {
    if ($preBlocker.PSObject.Properties['executor_invoked'] -and [bool]$preBlocker.executor_invoked) {
        $issues.Add('blocked_behavior_charter_invoked_executor') | Out-Null
    }
    if ([int]$preBlocker.coverage_delta -ne 0) { $issues.Add('blocked_behavior_charter_has_coverage_delta') | Out-Null }
}

$status = if ($issues.Count -eq 0) { if ($aggregateExit -eq 0) { 'PASS' } else { 'STOP' } } else { 'FAIL' }
$result = [ordered]@{
    schema = 'behavior_test_charter_validation.v1'
    status = $status
    aggregate_exit_code = $aggregateExit
    replay_root = $replayRootFull
    worktree = $worktreeFull
    slice = $Slice
    test_charter = $charterPath
    pre_slice_blocker = $preBlockerPath
    issues = @($issues)
}
Write-JsonFile -Value $result -Path (Join-Path $replayRootFull ('BEHAVIOR_TEST_CHARTER_VALIDATE_{0:D2}.json' -f $Slice))

if ($status -eq 'FAIL') { exit 1 }
exit 0
