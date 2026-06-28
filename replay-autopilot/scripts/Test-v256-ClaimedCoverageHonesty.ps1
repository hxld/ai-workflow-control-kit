param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-JsonFile {
    param($Object, [string]$Path)
    $Object | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) {
        throw $Message
    }
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$tempRoot = Join-Path $scriptRoot ('.tmp\v256-claimed-coverage-{0}' -f $PID)
$enforcer = Join-Path $PSScriptRoot 'Enforce-RoundCoverageCap.ps1'
$slicePrompt = Join-Path $scriptRoot 'prompts\phase1-slice-executor.prompt.md'
$synthesisPrompt = Join-Path $scriptRoot 'prompts\phase1-round-synthesis.prompt.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        enforcer = $enforcer
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

if (-not (Test-Path -LiteralPath $enforcer)) {
    throw "Missing enforcer script: $enforcer"
}

$slicePromptText = Get-Content -LiteralPath $slicePrompt -Raw -Encoding UTF8
$synthesisPromptText = Get-Content -LiteralPath $synthesisPrompt -Raw -Encoding UTF8
Assert-Contains $slicePromptText 'non_authorizing_evidence' 'slice executor prompt missing non-authorizing evidence honesty gate'
Assert-Contains $slicePromptText 'coverage_delta' 'slice executor prompt must mention coverage_delta honesty for non-authorizing gap flags'
Assert-Contains $synthesisPromptText 'self_assessment_honesty_override' 'synthesis prompt missing self-assessment honesty override'

New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$roundResult = Join-Path $tempRoot 'ROUND_RESULT.md'
$routerCap = Join-Path $tempRoot 'FAMILY_ROUTER_AND_CAP.json'
$sliceVerify = Join-Path $tempRoot 'SLICE_VERIFY_01.json'

Set-Content -LiteralPath $roundResult -Encoding UTF8 -Value (@(
    '# Round Result',
    '',
    'blind_self_assessed_coverage: 90',
    'verification_capped_coverage: 90',
    'coverage_cap: 90',
    'final_status: PASS'
) -join "`n")

Write-JsonFile -Path $routerCap -Object ([ordered]@{
    coverage_cap_from_ledger = 10
    final_pass_allowed = $false
    open_required_families = @('stateful_side_effect', 'deploy_export_page')
})

Write-JsonFile -Path $sliceVerify -Object ([ordered]@{
    verification_status = 'PARTIAL'
    adjusted_coverage_delta = 0
    coverage_cap = 10
    authorized_for_next_slice = $false
    authorized_for_synthesis = $false
    authorization_blockers = @('wrong_test_surface', 'side_effect_ledger_gap', 'core_entry_unclosed')
})

& powershell -NoProfile -ExecutionPolicy Bypass -File $enforcer `
    -RoundResultPath $roundResult `
    -RouterCapPath $routerCap `
    -ReplayRoot $tempRoot
if ($LASTEXITCODE -ne 0) {
    throw "Enforce-RoundCoverageCap.ps1 failed with exit code $LASTEXITCODE"
}

$text = Get-Content -LiteralPath $roundResult -Raw -Encoding UTF8
Assert-Contains $text 'blind_self_assessed_coverage: 10' 'blind self-assessed coverage was not capped to ledger cap'
Assert-Contains $text 'verification_capped_coverage: 0' 'verification capped coverage was not capped to verifier-adjusted coverage'
Assert-Contains $text 'coverage_cap: 10' 'coverage cap was not capped to ledger cap'
Assert-Contains $text 'final_status: BLOCKED' 'final status was not blocked when final_pass_allowed=false'
Assert-Contains $text 'original_blind_self_assessed_coverage: 90' 'runner enforcement did not preserve original blind coverage'
Assert-Contains $text 'verifier_adjusted_coverage: 0' 'runner enforcement did not disclose verifier-adjusted coverage'
Assert-Contains $text 'wrong_test_surface' 'runner enforcement did not disclose authorization blockers'
Assert-NotContains $text 'final_status: PASS' 'PASS status leaked after enforcement'

[ordered]@{
    status = 'PASS'
    assertions = 11
    temp_root = $tempRoot
} | ConvertTo-Json -Depth 6

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
