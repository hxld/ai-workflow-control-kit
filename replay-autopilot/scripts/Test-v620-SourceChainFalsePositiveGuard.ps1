param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Name - $Detail"
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-SourceChainAnalyzer {
    param([string]$Root, [string]$RequirementSource)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Analyze-SourceChainContract.ps1') `
        -ReplayRoot $Root `
        -RequirementSource $RequirementSource | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Analyze-SourceChainContract failed for $Root"
    }
    return Get-Content -LiteralPath (Join-Path $Root 'SOURCE_CHAIN_CONTRACT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v620-source-chain-' + [guid]::NewGuid().ToString('N'))
$assertions = 0

try {
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    $autoFlowRoot = Join-Path $tmp 'auto-flow'
    New-Item -ItemType Directory -Force -Path $autoFlowRoot | Out-Null
    $autoFlowReq = Join-Path $autoFlowRoot 'requirement.md'
    Write-Utf8 $autoFlowReq @'
# Requirement

Trigger auto-flow from handleTaskResponse after AI result save.
The flow checks review_threshold_amount / reviewThresholdAmount, payment_status / paymentStatus,
payment_info / paymentInfo, settlement_info / settlementInfo, and settlement_detail / settlementDetail.
It writes settlement summary, settlement detail, and deduction records.
This is a stateful service flow, not a rebuildTaskData or source-chain replay.
'@
    Write-Utf8 (Join-Path $autoFlowRoot 'IMPLEMENTATION_CONTRACT.md') @'
selected_real_entry: ExampleApplyTaskProcessor.handleTaskResponse()
first_red_test: ExampleAutoFlowServiceTest.shouldTriggerAutoFlowWhenConditionsMet
check review_threshold_amount via module config reviewThresholdAmount
write settlement_info and settlement_detail from AI result
'@
    Write-Utf8 (Join-Path $autoFlowRoot 'TEST_CHARTER.md') @'
test_surface: ExampleAutoFlowService.autoFlow()
entry_point: ExampleApplyTaskProcessor.handleTaskResponse()
test_class: ExampleAutoFlowServiceTest
test_method: shouldTriggerAutoFlowWhenConditionsMet
'@

    $autoFlowContract = Invoke-SourceChainAnalyzer -Root $autoFlowRoot -RequirementSource $autoFlowReq
    Assert-True 'auto_flow_does_not_require_source_chain' (-not [bool]$autoFlowContract.required_source_chain) ($autoFlowContract | ConvertTo-Json -Depth 12)
    $assertions++
    Assert-True 'auto_flow_has_no_next_required_slice' ($null -eq $autoFlowContract.next_required_slice) ($autoFlowContract | ConvertTo-Json -Depth 12)
    $assertions++
    Assert-True 'auto_flow_contract_has_no_placeholder_carrier' (($autoFlowContract | ConvertTo-Json -Depth 12) -notmatch 'ExampleDataAssemblyHelper|ExamplePrimaryIdSourceChainTest|SourceRecord\.primaryId') ($autoFlowContract | ConvertTo-Json -Depth 12)
    $assertions++

    $rebuildRoot = Join-Path $tmp 'rebuild'
    New-Item -ItemType Directory -Force -Path $rebuildRoot | Out-Null
    Write-JsonFile (Join-Path $rebuildRoot 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{
        files = @(
            [ordered]@{ path = 'production-module/src/main/java/com/example/core/task/ExampleApplyTaskProcessor.java'; weight = 'HIGH'; is_production = $true },
            [ordered]@{ path = 'production-module/src/main/java/com/example/core/task/ExampleCalculateTaskProcessor.java'; weight = 'HIGH'; is_production = $true }
        )
    })
    $rebuildReq = Join-Path $rebuildRoot 'requirement.md'
    Write-Utf8 $rebuildReq @'
# Requirement

When task data is rebuilt in the apply processor and calculate processor, rebuildTaskData must
preserve policyNum and insureNum from RequestBuildContext into the final AI request.
The final input_data must include policy_num and insure_num.
'@
    $rebuildContract = Invoke-SourceChainAnalyzer -Root $rebuildRoot -RequirementSource $rebuildReq
    Assert-True 'rebuild_requires_source_chain' ([bool]$rebuildContract.required_source_chain) ($rebuildContract | ConvertTo-Json -Depth 12)
    $assertions++
    Assert-True 'rebuild_uses_task_processor_mode' ([string]$rebuildContract.source_chain_mode -eq 'task_processor_rebuild') ($rebuildContract | ConvertTo-Json -Depth 12)
    $assertions++
    Assert-True 'rebuild_binds_oracle_task_processors' ([string]$rebuildContract.next_required_slice.entry -match 'ExampleApplyTaskProcessor\.rebuildTaskData' -and [string]$rebuildContract.next_required_slice.entry -match 'ExampleCalculateTaskProcessor\.rebuildTaskData') ($rebuildContract | ConvertTo-Json -Depth 12)
    $assertions++

    $prompt = Get-Content -LiteralPath (Join-Path $repoRoot 'prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
    Assert-True 'prompt_scopes_rebuild_rules_to_contract_mode' ($prompt -match 'SOURCE_CHAIN_CONTRACT\.json\.required_source_chain=true' -and $prompt -match 'source_chain_mode=task_processor_rebuild') ''
    $assertions++
    Assert-True 'prompt_has_non_source_chain_escape_hatch' ($prompt -match 'When SOURCE_CHAIN_CONTRACT\.json is absent or required_source_chain=false') ''
    $assertions++

    [ordered]@{
        status = 'PASS'
        assertions = $assertions
        cases = @(
            'stateful_auto_flow_field_names_do_not_force_source_chain',
            'task_processor_rebuild_still_forces_source_chain',
            'phase1_prompt_scopes_rebuild_rules'
        )
    } | ConvertTo-Json -Depth 6
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tmp)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tmp -Recurse -Force
        }
    }
}
