param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Name - $Detail"
    }
}

function Get-FunctionText {
    param([string]$Source, [string]$Name)

    $needle = "function $Name"
    $start = $Source.IndexOf($needle, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Function not found: $Name" }

    $braceStart = $Source.IndexOf('{', $start)
    if ($braceStart -lt 0) { throw "Function brace not found: $Name" }

    $depth = 0
    for ($i = $braceStart; $i -lt $Source.Length; $i++) {
        $ch = $Source[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Source.Substring($start, $i - $start + 1)
            }
        }
    }

    throw "Function end not found: $Name"
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$runnerPath = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
$runner = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
Invoke-Expression (Get-FunctionText -Source $runner -Name 'Test-SourceChainOverrideAllowedForForcedDecision')

$assertions = 0
$sourceChain = [pscustomobject]@{
    next_required_slice = [pscustomobject]@{
        carrier = 'TaskProcessor rebuildTaskData -> source.reviewThresholdAmount -> InputData.review_threshold_amount'
        entry = 'ExampleApplyTaskProcessor.rebuildTaskData(Long caseId)'
    }
}

$plannedConfig = [pscustomobject]@{
    family_id = 'config_policy_threshold'
    target_sibling_surface = 'ExampleModuleConfigService'
    reason = 'FAMILY_CONTRACT.json planned config_policy_threshold for S1; runner must honor the machine-readable family contract.'
}
$coreEntry = [pscustomobject]@{
    family_id = 'core_entry'
    target_sibling_surface = 'ExampleApplyTaskProcessor'
    reason = 'Slice 1 must close the highest-weight real entry family first.'
}
$sourceFamily = [pscustomobject]@{
    family_id = 'source_chain'
    target_sibling_surface = 'ExampleApplyTaskProcessor.rebuildTaskData(Long caseId)'
    reason = 'Source-chain family selected.'
}
$matchingSurface = [pscustomobject]@{
    family_id = 'wire_payload_api_contract'
    target_sibling_surface = 'TaskProcessor rebuildTaskData -> source.reviewThresholdAmount -> InputData.review_threshold_amount'
    reason = 'Exact source-chain carrier selected.'
}

Assert-True 'planned_config_slice_rejects_source_chain_override' (-not (Test-SourceChainOverrideAllowedForForcedDecision -ForcedDecision $plannedConfig -SourceChain $sourceChain -SliceIndex 1)) ''
$assertions++
Assert-True 'core_entry_still_allows_source_chain_override' (Test-SourceChainOverrideAllowedForForcedDecision -ForcedDecision $coreEntry -SourceChain $sourceChain -SliceIndex 1) ''
$assertions++
Assert-True 'source_chain_family_allows_override' (Test-SourceChainOverrideAllowedForForcedDecision -ForcedDecision $sourceFamily -SourceChain $sourceChain -SliceIndex 1) ''
$assertions++
Assert-True 'matching_surface_allows_override' (Test-SourceChainOverrideAllowedForForcedDecision -ForcedDecision $matchingSurface -SourceChain $sourceChain -SliceIndex 1) ''
$assertions++
Assert-True 'runner_writes_planned_slice_guard_warning' ($runner -match 'planned_slice_guard' -and $runner -match 'cannot override a concrete non-source-chain slice') ''
$assertions++

[ordered]@{
    status = 'PASS'
    assertions = $assertions
    cases = @(
        'planned_non_source_chain_first_slice_rejects_source_chain_override',
        'core_or_matching_source_chain_routes_still_allow_override',
        'runner_records_planned_slice_guard_warning'
    )
} | ConvertTo-Json -Depth 6
