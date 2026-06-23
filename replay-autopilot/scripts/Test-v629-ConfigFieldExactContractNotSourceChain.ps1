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

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v629-config-field-source-chain-' + [guid]::NewGuid().ToString('N'))
$assertions = 0

try {
    $configRoot = Join-Path $tmp 'config-field'
    New-Item -ItemType Directory -Force -Path $configRoot | Out-Null
    Write-JsonFile (Join-Path $configRoot 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{
        files = @(
            [ordered]@{ path = 'production-module/src/main/java/com/example/core/task/ExampleApplyTaskProcessor.java'; weight = 'HIGH'; is_production = $true },
            [ordered]@{ path = 'production-module/src/main/java/com/example/core/task/ExampleOcrTaskProcessor.java'; weight = 'HIGH'; is_production = $true }
        )
    })
    $configReq = Join-Path $configRoot 'requirement.md'
    Write-Utf8 $configReq @'
# Requirement

Add a module configuration threshold field. Saving the configuration must persist
reviewThresholdAmount and querying the configuration must return reviewThresholdAmount.
The database column is review_threshold_amount. This is a configuration exact
contract, not a request rebuild path.
'@
    Write-Utf8 (Join-Path $configRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
# First Slice Proof Plan

first_slice: S1
golden_slice_binding: oracle_overlap -> ExampleApplyTaskProcessor high-weight core entry + ExampleModuleConfigService.save() -> RED: ExampleModuleConfigServiceTest.testSaveWithReviewThresholdAmount fails on missing reviewThresholdAmount field -> GREEN: reviewThresholdAmount field added to entity/DTO/XML/service enabling threshold read in TaskProcessor -> stateful_side_effect: reviewThresholdAmount persisted to t_module_config enables the later core entry decision
highest_weight_open_gate: core_entry
first_slice_family: config_policy_threshold
first_red_test: ExampleModuleConfigServiceTest.testSaveWithReviewThresholdAmount
selected_real_entry: ExampleApplyTaskProcessor.handleTaskResponse()
selected_carrier: ExampleModuleConfigService.save()
production_boundary: ExampleModuleConfigService.save() copies reviewThresholdAmount from DTO to entity and returns it from queryById()
minimum_side_effect_or_blocker: DB write to t_module_config.review_threshold_amount and read-back as reviewThresholdAmount
expected_production_diff: ExampleModuleConfigService.java copies reviewThresholdAmount; ExampleModuleConfig.java and ExampleModuleConfigDto.java add the field; ExampleModuleConfigMapper.xml maps review_threshold_amount
expected_side_effects: ["DB write review_threshold_amount to t_module_config","Query returns reviewThresholdAmount in DTO response"]
'@
    Write-Utf8 (Join-Path $configRoot 'IMPLEMENTATION_CONTRACT.md') @'
# Implementation Contract

selected_real_entry: ExampleApplyTaskProcessor.handleTaskResponse()
first_slice: S1
first_red_test: ExampleModuleConfigServiceTest.testSaveWithReviewThresholdAmount

## Phase 1 Changes
- S1-RED: ExampleModuleConfigServiceTest
- S1-GREEN:
  - ExampleModuleConfig.java: add reviewThresholdAmount field
  - ExampleModuleConfigDto.java: add reviewThresholdAmount field
  - ExampleModuleConfigMapper.xml: add review_threshold_amount column in resultMap, insert SQL, and update SQL
  - ExampleModuleConfigService.java: convert() and convert2Dto() copy reviewThresholdAmount

## No-Spring Test Rule Enforcement
- For TaskProcessor/rebuildTaskData tests: use JUnit + Mockito only, no Spring Boot Test annotation
- For ExampleModuleConfigService: service-layer test with mocked mapper

## Slice Delivery Order
- S1: config_policy_threshold (reviewThresholdAmount field) -> prerequisite
- S2: core_entry (auto-flow trigger) -> core behavior
'@
    Write-Utf8 (Join-Path $configRoot 'TEST_CHARTER.md') @'
# Test Charter

Entry Point: ExampleModuleConfigService.save() + queryById()
Test Class: ExampleModuleConfigServiceTest
Test Method: testSaveWithReviewThresholdAmount
DB Verification: ArgumentCaptor verifies mapper receives reviewThresholdAmount and query returns reviewThresholdAmount
Side Effects:
- verify insert/update includes review_threshold_amount
'@
    Write-JsonFile (Join-Path $configRoot 'FAMILY_CONTRACT.json') ([ordered]@{
        families = @(
            [ordered]@{
                id = 'config_policy_threshold'
                required = $true
                first_executable_carrier = 'ExampleModuleConfigService'
                planned_slice = 'S1'
                proof_required = @('DB write of reviewThresholdAmount', 'Query returns reviewThresholdAmount')
            },
            [ordered]@{
                id = 'core_entry'
                required = $true
                first_executable_carrier = 'ExampleApplyTaskProcessor'
                planned_slice = 'S2'
                proof_required = @('Core entry reads reviewThresholdAmount')
            }
        )
    })

    $configContract = Invoke-SourceChainAnalyzer -Root $configRoot -RequirementSource $configReq
    $configJson = $configContract | ConvertTo-Json -Depth 12
    Assert-True 'config_field_does_not_require_source_chain' (-not [bool]$configContract.required_source_chain) $configJson
    $assertions++
    Assert-True 'config_field_has_no_next_required_slice' ($null -eq $configContract.next_required_slice) $configJson
    $assertions++
    Assert-True 'nospring_rebuild_rule_does_not_create_intent' (-not [bool]$configContract.explicit_source_chain_intent) $configJson
    $assertions++
    Assert-True 'config_field_does_not_bind_taskprocessor_rebuild_carrier' ($configJson -notmatch 'TaskProcessor rebuildTaskData|source\.reviewThresholdAmount|InputData\.review_threshold_amount') $configJson
    $assertions++

    $rebuildRoot = Join-Path $tmp 'explicit-rebuild'
    New-Item -ItemType Directory -Force -Path $rebuildRoot | Out-Null
    Write-JsonFile (Join-Path $rebuildRoot 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{
        files = @(
            [ordered]@{ path = 'production-module/src/main/java/com/example/core/task/ExampleApplyTaskProcessor.java'; weight = 'HIGH'; is_production = $true }
        )
    })
    $rebuildReq = Join-Path $rebuildRoot 'requirement.md'
    Write-Utf8 $rebuildReq @'
# Requirement

When task data is rebuilt in the apply processor, rebuildTaskData must preserve
policyNum from RequestBuildContext into the final AI request. The final input_data
must include policy_num.
'@
    $rebuildContract = Invoke-SourceChainAnalyzer -Root $rebuildRoot -RequirementSource $rebuildReq
    $rebuildJson = $rebuildContract | ConvertTo-Json -Depth 12
    Assert-True 'explicit_rebuild_still_requires_source_chain' ([bool]$rebuildContract.required_source_chain) $rebuildJson
    $assertions++
    Assert-True 'explicit_rebuild_still_binds_taskprocessor_mode' ([string]$rebuildContract.source_chain_mode -eq 'task_processor_rebuild') $rebuildJson
    $assertions++

    [ordered]@{
        status = 'PASS'
        assertions = $assertions
        cases = @(
            'config_exact_contract_snake_case_field_does_not_force_source_chain',
            'nospring_rebuild_taskdata_test_rule_does_not_create_source_chain_intent',
            'explicit_rebuild_transfer_still_forces_source_chain'
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
