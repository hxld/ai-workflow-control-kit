param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function New-CompatTempFile {
    $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('replay-tool-probe-' + [guid]::NewGuid().ToString('N') + '.tmp'))
    [System.IO.File]::WriteAllText($path, '', [System.Text.Encoding]::UTF8)
    return [pscustomobject]@{ FullName = $path }
}

function Test-ScriptRunnable {
    param(
        [string]$Path,
        [string]$Kind,
        [string[]]$Arguments
    )

    $stdout = New-CompatTempFile
    $stderr = New-CompatTempFile
    try {
        try {
            if ($Kind -eq 'powershell') {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments > $stdout.FullName 2> $stderr.FullName
            } elseif ($Kind -eq 'python') {
                & python $Path @Arguments > $stdout.FullName 2> $stderr.FullName
            } else {
                return [pscustomobject]@{ ok = $false; exit_code = -1; diagnostic = "unknown kind: $Kind" }
            }
            $exitCode = $LASTEXITCODE
        } catch {
            return [pscustomobject]@{ ok = $false; exit_code = -1; diagnostic = ('probe_exception: ' + $_.Exception.Message) }
        }
        $stderrText = if (Test-Path -LiteralPath $stderr.FullName) { Get-Content -LiteralPath $stderr.FullName -Raw -Encoding UTF8 } else { '' }
        if ($null -eq $stderrText) { $stderrText = '' }
        return [pscustomobject]@{
            ok = ($exitCode -eq 0)
            exit_code = $exitCode
            diagnostic = $stderrText.Trim()
        }
    } finally {
        Remove-Item -LiteralPath $stdout.FullName, $stderr.FullName -Force -ErrorAction SilentlyContinue
    }
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
$scriptsRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }

New-Item -ItemType Directory -Force -Path $replayRootFull | Out-Null
$outputPath = Join-Path $replayRootFull 'PRE_SLICE_TOOL_AVAILABILITY.json'

$mandatory = @(
    [pscustomobject]@{ name = 'Invoke-PreSliceExperimentContracts'; path = Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1'; kind = 'powershell'; args = @('-ReplayRoot', $replayRootFull, '-Worktree', $worktreeFull, '-SliceIndex', '1', '-ValidateOnly'); probe = $true },
    [pscustomobject]@{ name = 'pre_slice_authorization_gate'; path = Join-Path $scriptsRoot 'pre_slice_authorization_gate.ps1'; kind = 'powershell'; args = @(); probe = $false },
    [pscustomobject]@{ name = 'proof_type_policy_gate'; path = Join-Path $scriptsRoot 'proof_type_policy_gate.ps1'; kind = 'powershell'; args = @(); probe = $false },
    [pscustomobject]@{ name = 'replay_context_index_contract_check'; path = Join-Path $scriptsRoot 'replay_context_index_contract_check.ps1'; kind = 'powershell'; args = @(); probe = $false },
    [pscustomobject]@{ name = 'verify_first_slice_runnable_contract'; path = Join-Path $scriptsRoot 'verify_first_slice_runnable_contract.ps1'; kind = 'powershell'; args = @(); probe = $false },
    [pscustomobject]@{ name = 'verify_carrier_invocation_contract'; path = Join-Path $scriptsRoot 'verify_carrier_invocation_contract.ps1'; kind = 'powershell'; args = @(); probe = $false },
    [pscustomobject]@{ name = 'Validate-ExecutableEvidenceGate'; path = Join-Path $scriptsRoot 'Validate-ExecutableEvidenceGate.ps1'; kind = 'powershell'; args = @('-ReplayRoot', $replayRootFull, '-Worktree', $worktreeFull, '-SliceResultPath', (Join-Path $replayRootFull '__missing_slice_result__.json'), '-SliceIndex', '1', '-ValidateOnly'); probe = $true },
    [pscustomobject]@{ name = 'verify_carrier_execution_contract'; path = Join-Path $scriptsRoot 'verify_carrier_execution_contract.py'; kind = 'python'; args = @('--self-test'); probe = $true },
    [pscustomobject]@{ name = 'verify_red_green_side_effect_evidence'; path = Join-Path $scriptsRoot 'verify_red_green_side_effect_evidence.py'; kind = 'python'; args = @('--self-test'); probe = $true }
)

$missing = New-Object System.Collections.Generic.List[string]
$unrunnable = New-Object System.Collections.Generic.List[object]
$checks = New-Object System.Collections.Generic.List[object]

foreach ($script in $mandatory) {
    $scriptPath = Resolve-AbsolutePath $script.path
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        $missing.Add($scriptPath) | Out-Null
        $checks.Add([ordered]@{ name = $script.name; path = $scriptPath; exists = $false; runnable = $false; exit_code = $null; diagnostic = 'missing_script' }) | Out-Null
        continue
    }
    if ([bool]$script.probe) {
        $probe = Test-ScriptRunnable -Path $scriptPath -Kind $script.kind -Arguments @($script.args)
    } else {
        $probe = [pscustomobject]@{ ok = $true; exit_code = 0; diagnostic = 'existence_only_probe' }
    }
    if (-not [bool]$probe.ok) {
        $unrunnable.Add([ordered]@{ name = $script.name; path = $scriptPath; exit_code = $probe.exit_code; diagnostic = [string]$probe.diagnostic }) | Out-Null
    }
    $checks.Add([ordered]@{ name = $script.name; path = $scriptPath; exists = $true; runnable = [bool]$probe.ok; exit_code = $probe.exit_code; diagnostic = [string]$probe.diagnostic }) | Out-Null
}

$status = if ($missing.Count -eq 0 -and $unrunnable.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$missingArray = @($missing.ToArray())
$unrunnableArray = @($unrunnable.ToArray())
$checksArray = @($checks.ToArray())
$result = [ordered]@{
    schema = 'pre_slice_tool_availability.v1'
    status = $status
    replay_root = $replayRootFull
    worktree = $worktreeFull
    missing_scripts = $missingArray
    unrunnable_scripts = $unrunnableArray
    retry_allowed = $false
    checks = $checksArray
    generated_at = (Get-Date).ToString('s')
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding UTF8

if ($PassThru) {
    $result | ConvertTo-Json -Depth 12
}

if ($status -ne 'PASS') { exit 1 }
exit 0
