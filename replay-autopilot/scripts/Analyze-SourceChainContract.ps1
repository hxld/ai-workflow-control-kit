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

function Add-Unique {
    param([System.Collections.Generic.List[string]]$List, [string]$Value)
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
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

$hasPolicySource = $text -match '(?i)\b(CaseRoute\.policyNo|policyNo|policy_no)\b'
$hasExampleSource = $text -match '(?i)\b(Insure\.recordNo|recordNo|record_no)\b'
$hasPolicyTarget = $text -match '(?i)\b(policy_num)\b'
$hasExampleTarget = $text -match '(?i)\b(insure_num)\b'
$hasAiPayloadContext = $text -match '(?i)\b(InputData|Example|ExampleClaim|ExampleApply|ExampleCalculator)\b'

if ($hasPolicySource -and $hasPolicyTarget -and $hasAiPayloadContext) {
    Add-Unique $sourceFields 'CaseRoute.policyNo'
    Add-Unique $targetFields 'policy_num'
    Add-Unique $assertions 'captured InputData.policy_num equals CaseRoute.policyNo from backend source extraction'
}
if ($hasExampleSource -and $hasExampleTarget -and $hasAiPayloadContext) {
    Add-Unique $sourceFields 'Insure.recordNo'
    Add-Unique $targetFields 'insure_num'
    Add-Unique $assertions 'captured InputData.insure_num equals Insure.recordNo queried by policy number'
}

foreach ($file in @(
    'example-core/src/main/java/com/example/project/core/ai/helper/ExampleDataAssemblyHelper.java',
    'example-core/src/main/java/com/example/project/core/ai/service/ExampleApplyService.java',
    'example-core/src/main/java/com/example/project/core/ai/service/ExampleCalculatorService.java',
    'example-domain/src/main/java/com/example/project/domain/ai/dto/RequestBuildContext.java',
    'example-domain/src/main/java/com/example/project/domain/ai/dto/ExampleBaseRequest.java',
    'example-domain/src/main/java/com/example/project/domain/ai/dto/ExampleBaseTaskData.java',
    'example-core/src/main/java/com/example/project/core/ai/task/ExampleApiTaskProcessor.java',
    'example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java'
)) {
    if ($text -match [regex]::Escape(([System.IO.Path]::GetFileNameWithoutExtension($file)))) {
        Add-Unique $mustTouchFiles $file
    }
}

$hasNamedSource = $sourceFields.Count -gt 0 -and $targetFields.Count -gt 0
$activationReason = if ($hasNamedSource) {
    'source and wire target fields are both present with AI InputData context'
} elseif (($hasPolicySource -or $hasExampleSource) -and -not ($hasPolicyTarget -or $hasExampleTarget)) {
    'source-like terms found, but no exact wire target field policy_num/insure_num; source-chain gate not applicable'
} elseif (($hasPolicyTarget -or $hasExampleTarget) -and -not $hasAiPayloadContext) {
    'wire-like target terms found without AI InputData context; source-chain gate not applicable'
} else {
    'no named source-chain contract detected'
}
$requiredFamilies = @()
if ($hasNamedSource) {
    $requiredFamilies = @(
        [ordered]@{ family = 'source_helper'; carrier = 'ExampleDataAssemblyHelper'; reason = 'named source fields must be read from backend source carriers' },
        [ordered]@{ family = 'build_context'; carrier = 'RequestBuildContext'; reason = 'source values must survive request-build context' },
        [ordered]@{ family = 'request_dto'; carrier = 'ExampleBaseRequest'; reason = 'service request must carry nullable source values' },
        [ordered]@{ family = 'service_entry'; carrier = 'ExampleApplyService and ExampleCalculatorService'; reason = 'deploy-facing backend service entries must copy context/request/task data' },
        [ordered]@{ family = 'task_data'; carrier = 'ExampleBaseTaskData'; reason = 'persisted/rebuilt task data must carry source values' },
        [ordered]@{ family = 'wire_payload'; carrier = 'ExampleApiTaskProcessor and ExampleCalculatorApiTaskProcessor'; reason = 'outgoing InputData must include exact wire keys' }
    )
}

$nextRequiredSlice = if ($hasNamedSource) {
    [ordered]@{
        family = 'source_chain'
        entry = 'ExampleDataAssemblyHelper + ExampleApplyService + ExampleCalculatorService'
        carrier = 'CaseRoute.policyNo / Insure.recordNo -> RequestBuildContext -> ExampleBaseRequest -> ExampleBaseTaskData -> InputData.policy_num/InputData.insure_num'
        slice_type = 'exact_contract_slice'
        test_name = 'AiPolicyNumSourceChainTest.shouldFillFromBackendSources'
        must_touch_files = @($mustTouchFiles)
        required_assertions = @($assertions)
        forbidden_proof = @('synthetic_carrier', 'hand_built_task_data_only', 'reflection_setter_only', 'terminal_payload_only', 'dto_existence_only')
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
    required_families = @($requiredFamilies)
    next_required_slice = $nextRequiredSlice
    gate = 'named_source_chain_contract'
    activation_reason = $activationReason
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12
