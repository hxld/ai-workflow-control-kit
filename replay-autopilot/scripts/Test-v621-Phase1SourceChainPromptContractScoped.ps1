param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Name - $Detail"
    }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$promptPath = Join-Path $repoRoot 'prompts\phase1-slice-executor.prompt.md'
$prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$assertions = 0

$forbiddenUnscopedLiterals = @(
    '对本轮 primaryId/secondaryId rebuild source-chain',
    'ExampleDataAssemblyHelper.buildRequestCommon',
    'ExampleDataAssemblyHelper.RequestBuildFunction',
    'ExampleApplyRequest',
    'ExampleCalculateRequest',
    'ExampleApplyTaskProcessor.rebuildTaskData(Long caseId)` 与 `ExampleCalculateTaskProcessor.rebuildTaskData(Long caseId)',
    'req.setPrimaryId(buildContext.getPrimaryId())',
    'req.setSecondaryId(buildContext.getSecondaryId())',
    'taskData.getPrimaryId()',
    'taskData.getSecondaryId()'
)

foreach ($literal in $forbiddenUnscopedLiterals) {
    Assert-True "forbidden_literal_removed:$literal" (-not $prompt.Contains($literal)) "phase1 prompt still contains unscoped source-chain example literal"
    $assertions++
}

Assert-True 'source_chain_true_gate_present' ($prompt -match 'SOURCE_CHAIN_CONTRACT\.json\.required_source_chain=true') ''
$assertions++
Assert-True 'task_processor_rebuild_mode_gate_present' ($prompt -match 'source_chain_mode=task_processor_rebuild') ''
$assertions++
Assert-True 'rebuild_task_data_entry_gate_present' ($prompt -match 'next_required_slice\.entry.*rebuildTaskData') ''
$assertions++
Assert-True 'source_chain_false_escape_hatch_present' ($prompt -match 'required_source_chain=false.*first_red_test.*selected_carrier.*test_surface') ''
$assertions++
Assert-True 'source_chain_contract_true_only_enforcement_present' ($prompt -match 'required_source_chain=true.*next_required_slice') ''
$assertions++

[ordered]@{
    status = 'PASS'
    assertions = $assertions
    prompt = $promptPath
    cases = @(
        'source_chain_false_prompt_has_no_unscoped_example_carriers',
        'source_chain_rules_are_contract_gated',
        'source_chain_true_dynamic_next_required_slice_still_supported'
    )
} | ConvertTo-Json -Depth 6
