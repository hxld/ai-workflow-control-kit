# v472: Backend TaskProcessor replay exception and forbidden Maven command guard
param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$invokeAgentPath = Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1'
$authorizePath = Join-Path $scriptRoot 'Authorize-PreSliceEvidence.ps1'
$sourceChainPath = Join-Path $scriptRoot 'Analyze-SourceChainContract.ps1'
$preflightPath = Join-Path $scriptRoot 'pre-flight-check.ps1'

$cases = @()

foreach ($path in @($invokeAgentPath, $authorizePath, $sourceChainPath, $preflightPath)) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $parseErrors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize($text, [ref]$parseErrors)
    $cases += (Assert-True -Name ("parse_" + [System.IO.Path]::GetFileNameWithoutExtension($path)) -Condition ($parseErrors.Count -eq 0))
}

$invokeText = Get-Content -LiteralPath $invokeAgentPath -Raw -Encoding UTF8
$cases += (Assert-True -Name 'agent_has_replay_command_guard' -Condition ($invokeText -match 'function Invoke-ReplayCommandGuard'))
$cases += (Assert-True -Name 'agent_forbids_maven_deploy' -Condition ($invokeText -match 'maven_deploy_forbidden' -and $invokeText -match 'mvn deploy'))
$cases += (Assert-True -Name 'agent_forbids_protected_root_pom' -Condition ($invokeText -match 'protected_root_pom_forbidden' -and $invokeText -match 'only allowed project POM'))
$cases += (Assert-True -Name 'agent_cleans_forbidden_process_tree' -Condition ($invokeText -match 'function Stop-ReplayCommandGuardViolations' -and $invokeText -match 'function Invoke-ReplayCommandGuardCleanup' -and $invokeText -match 'command_guard_violation'))

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v472-' + [guid]::NewGuid().ToString('N'))
$authRoot = Join-Path $testRoot 'auth'
$sourceRoot = Join-Path $testRoot 'source'
$reqPath = Join-Path $testRoot 'requirement.md'

try {
    New-Item -ItemType Directory -Force -Path $authRoot, $sourceRoot | Out-Null

    $oracle = [ordered]@{
        schema_version = 1
        production_files = 2
        high_weight_files = 2
        layer_summary = [ordered]@{ Service = 2 }
        files = @(
            [ordered]@{
                path = 'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java'
                layer = 'Service'
                weight = 'HIGH'
                is_test = $false
                is_production = $true
                additions = 2
                deletions = 0
            },
            [ordered]@{
                path = 'example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java'
                layer = 'Service'
                weight = 'HIGH'
                is_test = $false
                is_production = $true
                additions = 2
                deletions = 0
            }
        )
    }
    Write-JsonFile -Path (Join-Path $authRoot 'ORACLE_DIFF_ANALYSIS.json') -Value $oracle
    Write-JsonFile -Path (Join-Path $sourceRoot 'ORACLE_DIFF_ANALYSIS.json') -Value $oracle

    Write-JsonFile -Path (Join-Path $authRoot 'CARRIER_AUTHORIZATION_01.json') -Value ([ordered]@{
        schema_version = 1
        slice_index = 1
        forced_requirement_family = 'core_entry'
        forced_slice_type = 'exact_contract_slice'
        authorization = 'ALLOW'
        real_entry = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
        selected_carrier = 'ExampleDataAssemblyHelper + ExampleApplyClaimService + ExampleCalculatorService'
        production_boundary = 'ExampleDataAssemblyHelper + ExampleApplyClaimService + ExampleCalculatorService'
        downstream_side_effect_or_output = 'captured InputData.policy_num and InputData.insure_num are populated after rebuild'
        red_expectation = 'business assertion should fail in AiPolicyNumSourceChainTest.shouldFillFromBackendSources before production change'
        authorization_note = 'test fixture'
    })

    Write-JsonFile -Path (Join-Path $authRoot 'SIDE_EFFECT_EVIDENCE_01.json') -Value ([ordered]@{
        status = 'READY'
        red_result = 'PENDING_BUSINESS_ASSERTION'
        green_result = 'PENDING'
        test_name = 'AiPolicyNumSourceChainTest.shouldFillFromBackendSources'
        entry_call = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
        expected_writes_or_outputs = @(
            'captured InputData.policy_num equals CaseRoute.policyNo from backend source extraction',
            'captured InputData.insure_num equals Insure.recordNo queried by policy number'
        )
    })

    Write-JsonFile -Path (Join-Path $authRoot 'NEXT_SLICE_EXACT_CONTRACT.json') -Value ([ordered]@{
        decision = 'ALLOW'
        rows = @(
            [ordered]@{
                literal = 'policy_num'
                symbol_or_field = 'InputData.policy_num'
                test_assertion = 'assertEquals(policyNo, capturedInputData.get("policy_num"))'
            }
        )
    })

    Write-JsonFile -Path (Join-Path $authRoot 'SOURCE_CHAIN_CONTRACT.json') -Value ([ordered]@{
        required_source_chain = $true
        next_required_slice = [ordered]@{
            entry = 'ExampleDataAssemblyHelper + ExampleApplyClaimService + ExampleCalculatorService'
            carrier = 'CaseRoute.policyNo / Insure.recordNo -> RequestBuildContext -> ExampleBaseRequest -> ExampleBaseTaskData -> InputData.policy_num/InputData.insure_num'
            slice_type = 'exact_contract_slice'
            test_name = 'AiPolicyNumSourceChainTest.shouldFillFromBackendSources'
        }
    })

    @'
# First Slice Proof Plan

highest_weight_open_gate: core_entry
first_red_test: ExampleApplyClaimApiTaskProcessorTest.testRebuildTaskData_PreservesPolicyNumAndInsureNum
selected_carrier: ExampleApplyClaimApiTaskProcessor.rebuildTaskData()
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
'@ | Set-Content -LiteralPath (Join-Path $authRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $authorizePath `
        -ReplayRoot $authRoot `
        -SliceIndex 1 `
        -ForcedRequirementFamily 'core_entry' `
        -ForcedSliceType 'exact_contract_slice' `
        -ForcedSiblingSurface 'CaseRoute.policyNo / Insure.recordNo -> InputData.policy_num/InputData.insure_num' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Authorize-PreSliceEvidence failed with exit code $LASTEXITCODE" }

    $auth = Get-Content -LiteralPath (Join-Path $authRoot 'PRE_SLICE_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $cases += (Assert-True -Name 'backend_task_processor_authorization_allows' -Condition ([string]$auth.decision -eq 'ALLOW'))
    $cases += (Assert-True -Name 'backend_oracle_exception_recorded' -Condition ([bool]$auth.surface_validation.backend_oracle_exception))
    $cases += (Assert-True -Name 'source_chain_plan_mismatch_not_blocking' -Condition (-not (($auth.issues -join "`n") -match 'planned_red_test_mismatch|selected_carrier_mismatch')))

    @'
# Requirement

When task data is rebuilt in the AI apply-claim processor or the AI calculate-loss processor,
the rebuilt request/task data SHALL preserve policyNum and insureNum, and final AI request
input_data SHALL include policy_num and insure_num.
'@ | Set-Content -LiteralPath $reqPath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $sourceChainPath -ReplayRoot $sourceRoot -RequirementSource $reqPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Analyze-SourceChainContract failed with exit code $LASTEXITCODE" }

    $sourceContract = Get-Content -LiteralPath (Join-Path $sourceRoot 'SOURCE_CHAIN_CONTRACT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $cases += (Assert-True -Name 'source_chain_uses_rebuild_mode' -Condition ([string]$sourceContract.source_chain_mode -eq 'task_processor_rebuild'))
    $cases += (Assert-True -Name 'source_chain_binds_task_processors' -Condition ([string]$sourceContract.next_required_slice.entry -match 'ExampleApplyClaimApiTaskProcessor\.rebuildTaskData' -and [string]$sourceContract.next_required_slice.entry -match 'ExampleCalculatorApiTaskProcessor\.rebuildTaskData'))
    $cases += (Assert-True -Name 'source_chain_avoids_helper_expansion' -Condition ([string]$sourceContract.next_required_slice.entry -notmatch 'ExampleDataAssemblyHelper \+ ExampleApplyClaimService'))

    [ordered]@{
        status = 'PASS'
        assertions = $cases.Count
        cases = $cases
        repo_root = $repoRoot
    } | ConvertTo-Json -Depth 8
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}
