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

$carrierLockPath = Join-Path $replayRootFull 'CARRIER_LOCK.json'
$preBlockerPath = Join-Path $replayRootFull ('SLICE_RESULT_PRE_{0:D2}.json' -f $Slice)
$carrierLock = Read-Json $carrierLockPath
$preBlocker = Read-Json $preBlockerPath
$issues = New-Object System.Collections.Generic.List[string]

if ($null -eq $carrierLock) {
    $issues.Add('carrier_lock_missing') | Out-Null
} else {
    foreach ($field in @('experiment', 'family_id', 'selected_carrier', 'forbidden_substitute_check', 'carrier_lock_status')) {
        if (-not $carrierLock.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$carrierLock.$field)) {
            $issues.Add("carrier_lock_missing_$field") | Out-Null
        }
    }
    if ([string]$carrierLock.experiment -ne 'pre_budget_carrier_lock') { $issues.Add('carrier_lock_wrong_experiment') | Out-Null }
    if ([string]$carrierLock.carrier_lock_status -notin @('PASS', 'STOP')) { $issues.Add('carrier_lock_invalid_status') | Out-Null }
    if ([string]$carrierLock.carrier_lock_status -eq 'PASS') {
        foreach ($field in @('qualified_entry', 'production_boundary', 'downstream_side_effect_or_output', 'test_harness_strategy')) {
            if (-not $carrierLock.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$carrierLock.$field)) {
                $issues.Add("carrier_lock_pass_missing_$field") | Out-Null
            }
        }
        $expectedProductionFiles = @()
        if ($carrierLock.PSObject.Properties['expected_production_files']) {
            $expectedProductionFiles = @($carrierLock.expected_production_files | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
        if ($expectedProductionFiles.Count -eq 0) {
            $issues.Add('carrier_lock_pass_missing_expected_production_files') | Out-Null
        }
    }
}

if ($aggregateExit -ne 0) {
    if ($null -eq $preBlocker) {
        $issues.Add('prebudget_blocker_result_missing') | Out-Null
    } else {
        if ($preBlocker.PSObject.Properties['executor_invoked'] -and [bool]$preBlocker.executor_invoked) {
            $issues.Add('blocked_carrier_precheck_invoked_executor') | Out-Null
        }
        if ([string]$preBlocker.slice_status -ne 'BLOCKED') { $issues.Add('prebudget_blocker_status_not_blocked') | Out-Null }
        if (@($preBlocker.implemented_files).Count -ne 0) { $issues.Add('prebudget_blocker_has_implemented_files') | Out-Null }
        if ([int]$preBlocker.coverage_delta -ne 0) { $issues.Add('prebudget_blocker_has_coverage_delta') | Out-Null }
    }
}

$status = if ($issues.Count -eq 0) { if ($aggregateExit -eq 0) { 'PASS' } else { 'STOP' } } else { 'FAIL' }
$result = [ordered]@{
    schema = 'carrier_lock_precheck_validation.v1'
    status = $status
    aggregate_exit_code = $aggregateExit
    replay_root = $replayRootFull
    worktree = $worktreeFull
    slice = $Slice
    carrier_lock = $carrierLockPath
    pre_slice_blocker = $preBlockerPath
    issues = @($issues)
}
Write-JsonFile -Value $result -Path (Join-Path $replayRootFull ('CARRIER_LOCK_PRECHECK_VALIDATE_{0:D2}.json' -f $Slice))

if ($status -eq 'FAIL') { exit 1 }
exit 0
