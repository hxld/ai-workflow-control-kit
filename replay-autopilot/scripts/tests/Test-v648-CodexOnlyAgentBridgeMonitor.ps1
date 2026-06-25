param(
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$monitorScript = Join-Path $scriptRoot 'Start-AgentBridgeMonitor.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agent-bridge-monitor-codex-only-v648-{0}' -f ([guid]::NewGuid().ToString('N')))
$bridgeRoot = Join-Path $tempRoot 'current'
$archiveRoot = Join-Path $tempRoot 'runs'
$reportRoot = Join-Path $tempRoot 'monitor'

try {
    $text = Get-Content -LiteralPath $monitorScript -Raw -Encoding UTF8

    Assert-True ($text -match '\[ValidateSet\(''codex'',\s*''claude'',\s*''none''\)\]\s*\r?\n\s*\[string\]\$Executor\s*=\s*''codex''') 'Monitor executor must default to codex'
    Assert-True ($text -match '\[string\]\$BridgeClaudeExecutor\s*=\s*''codex''') 'Legacy BridgeClaudeExecutor alias must default to codex'
    Assert-True ($text -match '\[string\]\$BridgePrimaryExecutor\s*=\s*''''') 'Monitor should expose BridgePrimaryExecutor alias'
    Assert-True ($text -match '\[string\]\$BridgeReviewExecutor\s*=\s*''''') 'Monitor should expose BridgeReviewExecutor alias'
    Assert-True ($text -match '\[switch\]\$CodexOnly') 'Monitor should expose CodexOnly switch'
    Assert-True ($text -match '-Executor\s+\$script:MonitorExecutor') 'Monitor prompt execution must use resolved monitor executor'
    Assert-True (-not ($text -match '-Executor\s+claude')) 'Monitor prompt execution must not hard-code claude'
    Assert-True ($text -match '''-PrimaryExecutor'',\s*\$script:BridgePrimaryExecutor') 'Bridge action should pass PrimaryExecutor'
    Assert-True ($text -match '''-ReviewExecutor'',\s*\$script:BridgeReviewExecutor') 'Bridge action should pass ReviewExecutor'
    Assert-True ($text -match '-PrimaryExecutor\s+\$script:BridgePrimaryExecutor') 'RunLoop restart should pass PrimaryExecutor'
    Assert-True ($text -match '-ReviewExecutor\s+\$script:BridgeReviewExecutor') 'RunLoop restart should pass ReviewExecutor'
    Assert-True ($text -match '\$args\s*\+=\s*''-CodexOnly''') 'Bridge action should forward CodexOnly'
    Assert-True ($text -match '\$argLine\s*\+=\s*'' -CodexOnly''') 'RunLoop restart should forward CodexOnly'

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $defaultJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $monitorScript `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ReportRoot $reportRoot `
        -ValidateOnly | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0) 'Default ValidateOnly should succeed'
    Assert-True ($defaultJson.executor -eq 'codex') 'Default monitor executor should resolve to codex'
    Assert-True ($defaultJson.bridge_primary_executor -eq 'codex') 'Default primary bridge executor should resolve to codex'
    Assert-True ($defaultJson.bridge_review_executor -eq 'codex') 'Default review bridge executor should resolve to codex'
    Assert-True ($defaultJson.codex_only -eq $false) 'Default codex_only should be false'

    $codexOnlyJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $monitorScript `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ReportRoot $reportRoot `
        -Executor claude `
        -BridgePrimaryExecutor claude `
        -BridgeReviewExecutor claude `
        -CodexOnly `
        -ValidateOnly | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0) 'CodexOnly ValidateOnly should succeed'
    Assert-True ($codexOnlyJson.executor -eq 'codex') 'CodexOnly should force monitor executor to codex'
    Assert-True ($codexOnlyJson.bridge_primary_executor -eq 'codex') 'CodexOnly should force primary bridge executor to codex'
    Assert-True ($codexOnlyJson.bridge_review_executor -eq 'codex') 'CodexOnly should force review bridge executor to codex'
    Assert-True ($codexOnlyJson.codex_only -eq $true) 'CodexOnly flag should be reported'

    $legacyAliasJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $monitorScript `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ReportRoot $reportRoot `
        -BridgeClaudeExecutor manual `
        -BridgeCodexExecutor claude `
        -ExecutorTimeoutMinutes 7 `
        -ValidateOnly | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0) 'Legacy alias ValidateOnly should succeed'
    Assert-True ($legacyAliasJson.bridge_primary_executor -eq 'manual') 'Legacy BridgeClaudeExecutor should feed primary executor'
    Assert-True ($legacyAliasJson.bridge_review_executor -eq 'claude') 'Legacy BridgeCodexExecutor should feed review executor'
    Assert-True ([int]$legacyAliasJson.executor_timeout_minutes -eq 7) 'ExecutorTimeoutMinutes should override legacy ClaudeTimeoutMinutes'

    [ordered]@{
        status = 'PASS'
        assertions = 25
        monitor_script = $monitorScript
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolved = Resolve-AbsolutePath $tempRoot
        $tempBase = Resolve-AbsolutePath ([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refuse to delete temp outside temp root: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
