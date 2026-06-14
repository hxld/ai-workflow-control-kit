param(
    [Parameter(Mandatory = $true)]
    [string]$EvidenceRoot,
    [string]$ReplayRootBase = '',
    [ValidateSet('codex', 'claude', 'manual')]
    [string]$Executor = 'claude',
    [ValidateSet('codex', 'claude', 'manual', '')]
    [string]$RequireExecutor = '',
    [string]$Model = '',
    [string]$OutputPath = '',
    [switch]$Probe,
    [switch]$ValidateOnly,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Read-JsonIfExists {
    param([string]$Path)
    $text = Read-TextIfExists -Path $Path
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        return $text | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-StringArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return @($text -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-CreditBlockerText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match '(?i)executor_credit_required|\b402\b|credit required|positive balance|required for this model|insufficient credits|not enough credits')
}

function Get-RecentControlCreditBlocker {
    param([string]$EvidenceRootFull)

    $controlLatest = Join-Path $EvidenceRootFull '_control\RUN_CONTROL_LATEST.json'
    $controlLatestMd = Join-Path $EvidenceRootFull '_control\RUN_CONTROL_LATEST.md'
    $failureLatest = Join-Path $EvidenceRootFull '_control\FAILURE_AUDIT_PACK_LATEST.json'
    $fingerprintsLatest = Join-Path $EvidenceRootFull '_control\BLOCKER_REGISTRY.json'

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($path in @($controlLatest, $failureLatest, $fingerprintsLatest)) {
        $json = Read-JsonIfExists -Path $path
        if ($null -eq $json) { continue }
        $text = $json | ConvertTo-Json -Depth 16 -Compress
        if (Test-CreditBlockerText -Text $text) {
            $candidates.Add([pscustomobject]@{
                source = $path
                reason = 'recent_control_contains_executor_credit_required'
                evidence = $text
            }) | Out-Null
        }
    }

    $md = Read-TextIfExists -Path $controlLatestMd
    if (Test-CreditBlockerText -Text $md) {
        $candidates.Add([pscustomobject]@{
            source = $controlLatestMd
            reason = 'recent_control_markdown_contains_executor_credit_required'
            evidence = $md
        }) | Out-Null
    }

    if ($candidates.Count -eq 0) { return $null }
    return $candidates[0]
}

function Write-PreflightResult {
    param(
        [string]$Path,
        $Data
    )

    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Data | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8

    $mdPath = [System.IO.Path]::ChangeExtension($Path, '.md')
    $md = @(
        '# Executor Resource Preflight',
        '',
        "- generated_at: $($Data.generated_at)",
        "- decision: $($Data.decision)",
        "- executor: $($Data.executor)",
        "- failure_category: $($Data.failure_category)",
        "- reason: $($Data.reason)",
        "- source: $($Data.source)",
        '',
        '## Next',
        '',
        $Data.recommended_next_step
    ) -join "`n"
    Set-Content -LiteralPath $mdPath -Encoding UTF8 -Value $md
}

function Invoke-LiveProbe {
    param(
        [string]$Executor,
        [string]$Model,
        [string]$OutputRoot
    )

    $probeRoot = Join-Path $OutputRoot ('executor-resource-probe-{0}' -f ([guid]::NewGuid().ToString('N')))
    $workDir = Join-Path $probeRoot 'work'
    $logDir = Join-Path $probeRoot 'logs'
    New-Item -ItemType Directory -Force -Path $workDir, $logDir | Out-Null
    $promptPath = Join-Path $probeRoot 'PROMPT.md'
    $completionPath = Join-Path $probeRoot 'EXECUTOR_RESOURCE_PROBE_RESULT.json'
    @(
        'This is an unattended executor resource preflight.',
        "Write this exact JSON file: $completionPath",
        '',
        '```json',
        '{"status":"OK","probe":"executor_resource_preflight"}',
        '```',
        '',
        'Do not edit project files.'
    ) | Set-Content -LiteralPath $promptPath -Encoding UTF8

    $invoke = Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $invoke,
        '-PromptPath', $promptPath,
        '-WorkDir', $workDir,
        '-LogDir', $logDir,
        '-Executor', $Executor,
        '-CompletionPath', $completionPath,
        '-CompletionQuietSeconds', '15',
        '-TimeoutMinutes', '1',
        '-Name', 'executor-resource-preflight'
    )
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $args += @('-Model', $Model)
    }

    & powershell @args | Out-Null
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $metaPath = Join-Path $logDir 'executor-resource-preflight.exec.json'
    $meta = Read-JsonIfExists -Path $metaPath
    return [pscustomobject]@{
        exit_code = $exitCode
        meta_path = $metaPath
        stdout_log = if ($null -ne $meta) { [string]$meta.stdout_log } else { Join-Path $logDir 'executor-resource-preflight.stdout.log' }
        failure_category = if ($null -ne $meta) { [string]$meta.failure_category } else { '' }
        probe_root = $probeRoot
        completion_path = $completionPath
    }
}

$evidenceRootFull = Resolve-AbsolutePath $EvidenceRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $evidenceRootFull '_control\EXECUTOR_RESOURCE_PREFLIGHT.json'
}
$outputPathFull = Resolve-AbsolutePath $OutputPath

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        evidence_root = $evidenceRootFull
        replay_root_base = $ReplayRootBase
        executor = $Executor
        require_executor = $RequireExecutor
        model = $Model
        output_path = $outputPathFull
        probe = [bool]$Probe
    } | ConvertTo-Json -Depth 6
    exit 0
}

$now = (Get-Date).ToString('s')
if ($Executor -eq 'manual') {
    $result = [ordered]@{
        schema = 'executor_resource_preflight.v1'
        generated_at = $now
        decision = 'ALLOW'
        executor = $Executor
        require_executor = $RequireExecutor
        model = $Model
        replay_root_base = $ReplayRootBase
        failure_category = ''
        reason = 'manual_executor_no_resource_probe'
        source = ''
        probe = [bool]$Probe
        recommended_next_step = 'Manual mode: prompts may be prepared without executor resource preflight.'
    }
    Write-PreflightResult -Path $outputPathFull -Data $result
    if (-not $Quiet) { Write-Host "Executor resource preflight: ALLOW" }
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($RequireExecutor) -and $RequireExecutor -ne $Executor) {
    $result = [ordered]@{
        schema = 'executor_resource_preflight.v1'
        generated_at = $now
        decision = 'BLOCK'
        executor = $Executor
        require_executor = $RequireExecutor
        model = $Model
        replay_root_base = $ReplayRootBase
        failure_category = 'executor_policy_violation'
        reason = 'required_executor_mismatch'
        source = ''
        probe = [bool]$Probe
        recommended_next_step = 'Fix executor policy before replay starts.'
    }
    Write-PreflightResult -Path $outputPathFull -Data $result
    if (-not $Quiet) { Write-Host "Executor resource preflight: BLOCK executor policy mismatch" }
    exit 87
}

$recentBlocker = Get-RecentControlCreditBlocker -EvidenceRootFull $evidenceRootFull
if ($null -ne $recentBlocker -and -not $Probe) {
    $result = [ordered]@{
        schema = 'executor_resource_preflight.v1'
        generated_at = $now
        decision = 'BLOCK'
        executor = $Executor
        require_executor = $RequireExecutor
        model = $Model
        replay_root_base = $ReplayRootBase
        failure_category = 'executor_credit_required'
        reason = [string]$recentBlocker.reason
        source = [string]$recentBlocker.source
        probe = [bool]$Probe
        recommended_next_step = 'Restore Claude/executor credit or run this preflight with -Probe after credit is restored. Do not start another blind replay from a known executor-credit blocker.'
    }
    Write-PreflightResult -Path $outputPathFull -Data $result
    if (-not $Quiet) { Write-Host "Executor resource preflight: BLOCK executor_credit_required" }
    exit 86
}

if ($Probe) {
    $probeOutputRoot = Join-Path $evidenceRootFull '_control\executor-resource-probes'
    $probeResult = Invoke-LiveProbe -Executor $Executor -Model $Model -OutputRoot $probeOutputRoot
    if ($probeResult.exit_code -eq 0) {
        $result = [ordered]@{
            schema = 'executor_resource_preflight.v1'
            generated_at = $now
            decision = 'ALLOW'
            executor = $Executor
            require_executor = $RequireExecutor
            model = $Model
            replay_root_base = $ReplayRootBase
            failure_category = ''
            reason = 'live_probe_passed'
            source = [string]$probeResult.meta_path
            probe = [bool]$Probe
            probe_root = [string]$probeResult.probe_root
            recommended_next_step = 'Executor probe passed; replay may start if other gates allow it.'
        }
        Write-PreflightResult -Path $outputPathFull -Data $result
        if (-not $Quiet) { Write-Host "Executor resource preflight: ALLOW live probe passed" }
        exit 0
    }

    $category = [string]$probeResult.failure_category
    if ([string]::IsNullOrWhiteSpace($category) -and $probeResult.exit_code -eq 86) {
        $category = 'executor_resource_blocker'
    }
    $isResource = @('executor_credit_required', 'usage_limit', 'auth', 'executor_resource_blocker') -contains $category
    $result = [ordered]@{
        schema = 'executor_resource_preflight.v1'
        generated_at = $now
        decision = 'BLOCK'
        executor = $Executor
        require_executor = $RequireExecutor
        model = $Model
        replay_root_base = $ReplayRootBase
        failure_category = $category
        reason = 'live_probe_failed'
        source = [string]$probeResult.meta_path
        stdout_log = [string]$probeResult.stdout_log
        probe = [bool]$Probe
        probe_root = [string]$probeResult.probe_root
        recommended_next_step = 'Fix executor resource/authentication before replay starts. Do not score this as implementation or verifier progress.'
    }
    Write-PreflightResult -Path $outputPathFull -Data $result
    if (-not $Quiet) { Write-Host "Executor resource preflight: BLOCK $category" }
    if ($isResource) { exit 86 }
    exit 1
}

$result = [ordered]@{
    schema = 'executor_resource_preflight.v1'
    generated_at = $now
    decision = 'ALLOW'
    executor = $Executor
    require_executor = $RequireExecutor
    model = $Model
    replay_root_base = $ReplayRootBase
    failure_category = ''
    reason = 'no_recent_executor_credit_blocker'
    source = ''
    probe = [bool]$Probe
    recommended_next_step = 'No recent executor credit blocker found; replay may start if other gates allow it.'
}
Write-PreflightResult -Path $outputPathFull -Data $result
if (-not $Quiet) { Write-Host "Executor resource preflight: ALLOW" }
exit 0
