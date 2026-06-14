param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        throw "FAIL: $Name $Details"
    }
}

function Assert-Contains {
    param([string]$Name, [string]$Text, [string]$Pattern)
    if ($Text -notmatch $Pattern) {
        throw "FAIL: $Name missing pattern: $Pattern"
    }
}

function Assert-NotContains {
    param([string]$Name, [string]$Text, [string]$Pattern)
    if ($Text -match $Pattern) {
        throw "FAIL: $Name unexpectedly matched pattern: $Pattern"
    }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$runSliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$verifyClosure = Join-Path $scriptRoot 'Verify-SliceClosure.ps1'
$phasePrompt = Join-Path $repoRoot 'prompts\phase1-slice-executor.prompt.md'
$compatFiles = @(
    (Join-Path $repoRoot 'prompts\SIDE_EFFECT_LEDGER_TEMPLATE.md'),
    (Join-Path $repoRoot 'prompts\side_effect_requirements.md'),
    (Join-Path $repoRoot 'prompts\slice_planning.md'),
    (Join-Path $repoRoot 'prompts\tdd-cycle.md'),
    (Join-Path $scriptRoot 'validate_side_effects.py')
)

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        run_slice_loop = $runSliceLoop
        verify_slice_closure = $verifyClosure
        phase_prompt = $phasePrompt
        compat_files = @($compatFiles)
    } | ConvertTo-Json -Depth 6
    exit 0
}

foreach ($path in @($runSliceLoop, $verifyClosure, $phasePrompt) + $compatFiles) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $path"
    }
}

$promptText = Get-Content -LiteralPath $phasePrompt -Raw -Encoding UTF8
Assert-Contains 'phase prompt requires mockito compatibility profile' $promptText 'MOCKITO_COMPATIBILITY_PROFILE'
Assert-Contains 'phase prompt supports legacy runner' $promptText 'org\.mockito\.runners\.MockitoJUnitRunner'
Assert-Contains 'phase prompt supports legacy matchers' $promptText 'org\.mockito\.Matchers'
Assert-Contains 'phase prompt forbids getArgument for legacy or unknown mockito' $promptText '禁止使用 `org\.mockito\.junit\.MockitoJUnitRunner`、`org\.mockito\.ArgumentMatchers`、`invocation\.getArgument\(\.\.\.\)`'
Assert-Contains 'phase prompt requires getArguments fallback' $promptText 'Object\[\] args = invocation\.getArguments\(\);'
Assert-Contains 'phase prompt rejects production evidence file' $promptText 'must not be a production source under `src/main/java`'
Assert-Contains 'phase prompt requires compatibility proof in closure proof' $promptText 'mockito_compatibility_profile'

foreach ($path in $compatFiles) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    Assert-NotContains "compat example avoids getArgument in $([IO.Path]::GetFileName($path))" $text 'invocation\.getArgument\('
    Assert-Contains "compat example uses getArguments in $([IO.Path]::GetFileName($path))" $text 'invocation\.getArguments\(\)'
}

$runSliceText = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8
Assert-Contains 'reuse branch blocks non-authorizing previous slice' $runSliceText 'non_authorizing_existing_artifact_replay'
Assert-Contains 'reuse branch blocks should_continue false artifacts' $runSliceText 'verifier_stop_existing_artifact_replay'
Assert-Contains 'reuse branch records authorization stop' $runSliceText 'reuse replay authorization stop'
Assert-NotContains 'reuse branch no longer continues after verifier stop' $runSliceText 'continuing artifact replay'
Assert-NotContains 'reuse branch no longer has continue contract row' $runSliceText 'reuse replay continue'

$verifyText = Get-Content -LiteralPath $verifyClosure -Raw -Encoding UTF8
Assert-Contains 'verifier rejects production evidence file' $verifyText 'behavior_test_charter_evidence_file_not_test_source'
Assert-Contains 'verifier rejects generated evidence file' $verifyText 'behavior_test_charter_evidence_file_generated_artifact'

[ordered]@{
    status = 'PASS'
    assertions = 19
} | ConvertTo-Json -Depth 4
