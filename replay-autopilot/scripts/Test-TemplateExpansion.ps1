param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-Json {
    param([string]$Path, $Object)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $Object | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$tempRoot = Join-Path $scriptRoot ('.tmp\template-expansion-{0}' -f $PID)
$deepReviewScript = Join-Path $PSScriptRoot 'Invoke-ReplayDeepReview.ps1'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        deep_review_script = $deepReviewScript
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

$currentRoot = Join-Path $tempRoot 'claim-codex-replay-v999-autopilot-test-r01'
$priorRoot = Join-Path $tempRoot 'claim-codex-replay-v998-autopilot-test-r01'
New-Item -ItemType Directory -Force -Path $currentRoot, $priorRoot | Out-Null

Write-Json (Join-Path $currentRoot 'STOP_LOSS_DECISION.json') ([ordered]@{
    should_stop = $true
    decision = 'STOP_DEEP_REVIEW_REQUIRED'
    recent_roots = @($priorRoot)
})

& powershell -NoProfile -ExecutionPolicy Bypass -File $deepReviewScript `
    -ReplayRoot $currentRoot `
    -HistoryRoot $tempRoot `
    -NoExecute `
    -Lookback 4 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Invoke-ReplayDeepReview -NoExecute failed with exit code $LASTEXITCODE"
}

$promptPath = Join-Path $currentRoot 'DEEP_REVIEW_PROMPT.md'
$prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$headingCount = ([regex]::Matches($prompt, [regex]::Escape('# Deep Replay Review Prompt'))).Count
if ($headingCount -ne 1) {
    throw "Expected exactly one deep-review heading, got $headingCount"
}
if ($prompt -match '\{\{REVIEW_ROOTS\}\}') {
    throw 'REVIEW_ROOTS placeholder was not expanded'
}
if ($prompt -match '\$_') {
    throw 'Prompt still contains literal $_, which can trigger Regex replacement pollution'
}
foreach ($expectedRoot in @($currentRoot, $priorRoot)) {
    if (-not $prompt.Contains($expectedRoot)) {
        throw "Prompt missing expected review root: $expectedRoot"
    }
}

[ordered]@{
    status = 'PASS'
    cases = @('deep_review_roots_expand_once_without_regex_replacement_pollution')
    prompt_length = $prompt.Length
    temp_root = $tempRoot
} | ConvertTo-Json -Depth 6

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
