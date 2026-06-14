param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$RequirementSource = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Read-JsonIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Add-Unique {
    param([System.Collections.Generic.List[string]]$List, [string]$Value)
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
}

function Get-OracleTaskProcessorFiles {
    param([string]$ReplayRoot)

    $oracle = Read-JsonIfExists (Join-Path $ReplayRoot 'ORACLE_DIFF_ANALYSIS.json')
    $files = @()
    if ($null -ne $oracle -and $null -ne $oracle.files) {
        $files = @($oracle.files)
    } elseif ($null -ne $oracle -and $null -ne $oracle.production_changes) {
        $files = @($oracle.production_changes)
    }

    $taskFiles = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) {
        $path = if ($file.PSObject.Properties.Name -contains 'path') { [string]$file.path } else { [string]$file.file }
        $weight = if ($file.PSObject.Properties.Name -contains 'weight') { [string]$file.weight } else { '' }
        $isProduction = if ($file.PSObject.Properties.Name -contains 'is_production') { [bool]$file.is_production } else { ($path -match '/src/main/java/|\\src\\main\\java\\') }
        if ($isProduction -and $weight -eq 'HIGH' -and $path -match '(?i)[/\\]task[/\\].*TaskProcessor\.java$') {
            Add-Unique -List $taskFiles -Value ($path -replace '\\', '/')
        }
    }

    if ($taskFiles.Count -eq 0) {
        foreach ($fallback in @(
            'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java',
            'claim-core/src/main/java/com/huize/claim/core/ai/task/AiCalculateLossApiTaskProcessor.java'
        )) {
            Add-Unique -List $taskFiles -Value $fallback
        }
    }

    return @($taskFiles)
}

$root = Resolve-AbsolutePath $ReplayRoot
$outPath = Join-Path $root 'SOURCE_CHAIN_CONTRACT.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
        output = $outPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$textParts = New-Object System.Collections.Generic.List[string]
foreach ($path in @(
    $RequirementSource,
    (Join-Path $root 'EXPECTED_DIFF_MATRIX.md'),
    (Join-Path $root 'IMPLEMENTATION_CONTRACT.md'),
    (Join-Path $root 'TEST_CHARTER.md'),
    (Join-Path $root 'FAMILY_CONTRACT.json'),
    (Join-Path $root 'FINAL_REPLAY_REPORT.md')
)) {
    Add-Unique -List $textParts -Value (Read-TextIfExists $path)
}
$text = ($textParts -join "`n")

$sourceFields = New-Object System.Collections.Generic.List[string]
$targetFields = New-Object System.Collections.Generic.List[string]
$mustTouchFiles = New-Object System.Collections.Generic.List[string]
$assertions = New-Object System.Collections.Generic.List[string]

$hasPolicySource = $text -match '(?i)\b(CaseRoute\.policyNo|policyNo|policy_no|policyNum)\b'
$hasInsureSource = $text -match '(?i)\b(Insure\.insureNo|insureNo|insure_no|insureNum)\b'
$hasPolicyTarget = $text -match '(?i)\b(policy_num)\b'
$hasInsureTarget = $text -match '(?i)\b(insure_num)\b'
$hasAiPayloadContext = $text -match '(?i)\b(InputData|input_data|AI request|AiClaim|AIClaim|AiApplyClaim|AiCalculateLoss)\b'
$rebuildPathRequirement = $text -match '(?i)\b(rebuildTaskData|rebuild|rebuilt task data|task data is rebuilt|boundary rebuild path)\b'
$oracleTaskProcessorFiles = @(Get-OracleTaskProcessorFiles -ReplayRoot $root)

if ($hasPolicySource -and $hasPolicyTarget -and $hasAiPayloadContext) {
    Add-Unique $sourceFields 'CaseRoute.policyNo'
    Add-Unique $targetFields 'policy_num'
    Add-Unique $assertions 'captured InputData.policy_num equals CaseRoute.policyNo from backend source extraction'
}
if ($hasInsureSource -and $hasInsureTarget -and $hasAiPayloadContext) {
    Add-Unique $sourceFields 'Insure.insureNo'
    Add-Unique $targetFields 'insure_num'
    Add-Unique $assertions 'captured InputData.insure_num equals Insure.insureNo queried by policy number'
}

foreach ($file in @(
    'claim-core/src/main/java/com/huize/claim/core/ai/helper/AiClaimDataAssemblyHelper.java',
    'claim-core/src/main/java/com/huize/claim/core/ai/service/AiApplyClaimService.java',
    'claim-core/src/main/java/com/huize/claim/core/ai/service/AiCalculateLossService.java',
    'claim-domain/src/main/java/com/huize/claim/domain/ai/dto/RequestBuildContext.java',
    'claim-domain/src/main/java/com/huize/claim/domain/ai/dto/AiClaimBaseRequest.java',
    'claim-domain/src/main/java/com/huize/claim/domain/ai/dto/AiClaimBaseTaskData.java',
    'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java',
    'claim-core/src/main/java/com/huize/claim/core/ai/task/AiCalculateLossApiTaskProcessor.java'
)) {
    if ($text -match [regex]::Escape(([System.IO.Path]::GetFileNameWithoutExtension($file)))) {
        Add-Unique $mustTouchFiles $file
    }
}

$hasNamedSource = $sourceFields.Count -gt 0 -and $targetFields.Count -gt 0
$sourceChainMode = if ($hasNamedSource -and $rebuildPathRequirement) {
    'task_processor_rebuild'
} elseif ($hasNamedSource) {
    'full_source_chain'
} else {
    'not_applicable'
}
$activationReason = if ($hasNamedSource) {
    if ($sourceChainMode -eq 'task_processor_rebuild') {
        'rebuild-path source and wire target fields are present; bind first slice to oracle TaskProcessor rebuild carriers'
    } else {
        'source and wire target fields are both present with AI InputData context'
    }
} elseif (($hasPolicySource -or $hasInsureSource) -and -not ($hasPolicyTarget -or $hasInsureTarget)) {
    'source-like terms found, but no exact wire target field policy_num/insure_num; source-chain gate not applicable'
} elseif (($hasPolicyTarget -or $hasInsureTarget) -and -not $hasAiPayloadContext) {
    'wire-like target terms found without AI InputData context; source-chain gate not applicable'
} else {
    'no named source-chain contract detected'
}
$requiredFamilies = @()
if ($hasNamedSource -and $sourceChainMode -eq 'task_processor_rebuild') {
    $requiredFamilies = @(
        [ordered]@{ family = 'task_processor_rebuild'; carrier = 'AiApplyClaimApiTaskProcessor and AiCalculateLossApiTaskProcessor'; reason = 'archived oracle high-weight files are rebuild TaskProcessors; first executable proof must bind to rebuildTaskData' },
        [ordered]@{ family = 'wire_payload'; carrier = 'AiApplyClaimApiTaskProcessor and AiCalculateLossApiTaskProcessor'; reason = 'rebuilt task data must still reach outgoing InputData policy_num/insure_num keys' }
    )
} elseif ($hasNamedSource) {
    $requiredFamilies = @(
        [ordered]@{ family = 'source_helper'; carrier = 'AiClaimDataAssemblyHelper'; reason = 'named source fields must be read from backend source carriers' },
        [ordered]@{ family = 'build_context'; carrier = 'RequestBuildContext'; reason = 'source values must survive request-build context' },
        [ordered]@{ family = 'request_dto'; carrier = 'AiClaimBaseRequest'; reason = 'service request must carry nullable source values' },
        [ordered]@{ family = 'service_entry'; carrier = 'AiApplyClaimService and AiCalculateLossService'; reason = 'deploy-facing backend service entries must copy context/request/task data' },
        [ordered]@{ family = 'task_data'; carrier = 'AiClaimBaseTaskData'; reason = 'persisted/rebuilt task data must carry source values' },
        [ordered]@{ family = 'wire_payload'; carrier = 'AiApplyClaimApiTaskProcessor and AiCalculateLossApiTaskProcessor'; reason = 'outgoing InputData must include exact wire keys' }
    )
}

$nextRequiredSlice = if ($hasNamedSource) {
    if ($sourceChainMode -eq 'task_processor_rebuild') {
        [ordered]@{
            family = 'source_chain'
            entry = 'AiApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and AiCalculateLossApiTaskProcessor.rebuildTaskData(Long caseId)'
            carrier = 'TaskProcessor rebuildTaskData -> AiClaimBaseTaskData.policyNum/insureNum -> InputData.policy_num/InputData.insure_num'
            slice_type = 'exact_contract_slice'
            test_name = 'AiApplyClaimApiTaskProcessorTest.testRebuildTaskData_PreservesPolicyNumAndInsureNum'
            must_touch_files = @($oracleTaskProcessorFiles)
            required_assertions = @(
                'apply-claim rebuildTaskData preserves policyNum',
                'apply-claim rebuildTaskData preserves insureNum',
                'calculate-loss rebuildTaskData preserves policyNum',
                'calculate-loss rebuildTaskData preserves insureNum',
                'final AI input_data includes policy_num and insure_num after rebuild'
            )
            forbidden_proof = @('synthetic_carrier', 'hand_built_task_data_only', 'reflection_setter_only', 'terminal_payload_only', 'dto_existence_only', 'helper_chain_expansion_without_oracle_proof')
        }
    } else {
        [ordered]@{
            family = 'source_chain'
            entry = 'AiClaimDataAssemblyHelper + AiApplyClaimService + AiCalculateLossService'
            carrier = 'CaseRoute.policyNo / Insure.insureNo -> RequestBuildContext -> AiClaimBaseRequest -> AiClaimBaseTaskData -> InputData.policy_num/InputData.insure_num'
            slice_type = 'exact_contract_slice'
            test_name = 'AiPolicyNumSourceChainTest.shouldFillPolicyAndInsureFromBackendSources'
            must_touch_files = @($mustTouchFiles)
            required_assertions = @($assertions)
            forbidden_proof = @('synthetic_carrier', 'hand_built_task_data_only', 'reflection_setter_only', 'terminal_payload_only', 'dto_existence_only')
        }
    }
} else {
    $null
}

$result = [ordered]@{
    schema_version = 1
    replay_root = $root
    required_source_chain = $hasNamedSource
    source_fields = @($sourceFields)
    target_fields = @($targetFields)
    source_chain_mode = $sourceChainMode
    rebuild_path_requirement = $rebuildPathRequirement
    required_families = @($requiredFamilies)
    next_required_slice = $nextRequiredSlice
    gate = 'named_source_chain_contract'
    activation_reason = $activationReason
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12
