param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "FAIL: $Name" }
        throw "FAIL: $Name - $Details"
    }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..\..')
$controlScript = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'
$latestPath = Join-Path $repoRoot 'workflow-history\latest.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        control_script = $controlScript
        latest_path = $latestPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$expected = Get-Content -LiteralPath $latestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $controlScript -ValidateOnly | Out-String
$actual = $output | ConvertFrom-Json

Assert-True 'unattended_control_uses_workflow_history_latest' ($actual.latest_knowledge_version -eq [string]$expected.latest) "expected=$($expected.latest); actual=$($actual.latest_knowledge_version)"
Assert-True 'unattended_control_reports_workflow_history_source' ([string]$actual.latest_knowledge_source -like '*workflow-history*latest.json') "source=$($actual.latest_knowledge_source)"

[ordered]@{
    status = 'PASS'
    expected_latest = [string]$expected.latest
    actual_latest = [string]$actual.latest_knowledge_version
    source = [string]$actual.latest_knowledge_source
} | ConvertTo-Json -Depth 4
