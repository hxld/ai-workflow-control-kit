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
            '<production-module>/src/main/java/com/example/project/core/task/ExampleApplyTaskProcessor.java',
            '<production-module>/src/main/java/com/example/project/core/task/ExampleCalculateTaskProcessor.java'
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

$hasPrimarySource = $text -match '(?i)\b(CaseRoute\.primaryId|primaryId|primary_id|primaryId)\b'
$hasSecondarySource = $text -match '(?i)\b(Secondary\.secondaryId|secondaryId|secondary_id|secondaryId)\b'
$hasPrimaryTarget = $text -match '(?i)\b(primary_id)\b'
$hasSecondaryTarget = $text -match '(?i)\b(secondary_id)\b'
$hasAiPayloadContext = $text -match '(?i)\b(InputData|input_data|AI request|Example|Example|ExampleApply|ExampleCalculate)\b'
$rebuildPathRequirement = $text -match '(?i)\b(rebuildTaskData|rebuild|rebuilt task data|task data is rebuilt|boundary rebuild path)\b'
$oracleTaskProcessorFiles = @(Get-OracleTaskProcessorFiles -ReplayRoot $root)

if ($hasPrimarySource -and $hasPrimaryTarget -and $hasAiPayloadContext) {
    Add-Unique $sourceFields 'SourceRecord.primaryId'
    Add-Unique $targetFields 'primary_id'
    Add-Unique $assertions 'captured InputData.primary_id equals SourceRecord.primaryId from backend source extraction'
}
if ($hasSecondarySource -and $hasSecondaryTarget -and $hasAiPayloadContext) {
    Add-Unique $sourceFields 'SecondaryRecord.secondaryId'
    Add-Unique $targetFields 'secondary_id'
    Add-Unique $assertions 'captured InputData.secondary_id equals SecondaryRecord.secondaryId queried by policy number'
}

foreach ($file in @(
    '<production-module>/src/main/java/com/example/project/core/helper/ExampleDataAssemblyHelper.java',
    '<production-module>/src/main/java/com/example/project/core/service/ExampleApplyService.java',
    '<production-module>/src/main/java/com/example/project/core/service/ExampleCalculateService.java',
    '<domain-module>/src/main/java/com/example/project/domain/dto/RequestBuildContext.java',
    '<domain-module>/src/main/java/com/example/project/domain/dto/ExampleBaseRequest.java',
    '<domain-module>/src/main/java/com/example/project/domain/dto/ExampleBaseTaskData.java',
    '<production-module>/src/main/java/com/example/project/core/task/ExampleApplyTaskProcessor.java',
    '<production-module>/src/main/java/com/example/project/core/task/ExampleCalculateTaskProcessor.java'
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
} elseif (($hasPrimarySource -or $hasSecondarySource) -and -not ($hasPrimaryTarget -or $hasSecondaryTarget)) {
    'source-like terms found, but no exact wire target field primary_id/secondary_id; source-chain gate not applicable'
} elseif (($hasPrimaryTarget -or $hasSecondaryTarget) -and -not $hasAiPayloadContext) {
    'wire-like target terms found without AI InputData context; source-chain gate not applicable'
} else {
    'no named source-chain contract detected'
}
$requiredFamilies = @()
if ($hasNamedSource -and $sourceChainMode -eq 'task_processor_rebuild') {
    $requiredFamilies = @(
        [ordered]@{ family = 'task_processor_rebuild'; carrier = 'ExampleApplyTaskProcessor and ExampleCalculateTaskProcessor'; reason = 'archived oracle high-weight files are rebuild TaskProcessors; first executable proof must bind to rebuildTaskData' },
        [ordered]@{ family = 'wire_payload'; carrier = 'ExampleApplyTaskProcessor and ExampleCalculateTaskProcessor'; reason = 'rebuilt task data must still reach outgoing InputData primary_id/secondary_id keys' }
    )
} elseif ($hasNamedSource) {
    $requiredFamilies = @(
        [ordered]@{ family = 'source_helper'; carrier = 'ExampleDataAssemblyHelper'; reason = 'named source fields must be read from backend source carriers' },
        [ordered]@{ family = 'build_context'; carrier = 'RequestBuildContext'; reason = 'source values must survive request-build context' },
        [ordered]@{ family = 'request_dto'; carrier = 'ExampleBaseRequest'; reason = 'service request must carry nullable source values' },
        [ordered]@{ family = 'service_entry'; carrier = 'ExampleApplyService and ExampleCalculateService'; reason = 'deploy-facing backend service entries must copy context/request/task data' },
        [ordered]@{ family = 'task_data'; carrier = 'ExampleBaseTaskData'; reason = 'persisted/rebuilt task data must carry source values' },
        [ordered]@{ family = 'wire_payload'; carrier = 'ExampleApplyTaskProcessor and ExampleCalculateTaskProcessor'; reason = 'outgoing InputData must include exact wire keys' }
    )
}

$nextRequiredSlice = if ($hasNamedSource) {
    if ($sourceChainMode -eq 'task_processor_rebuild') {
        [ordered]@{
            family = 'source_chain'
            entry = 'ExampleApplyTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculateTaskProcessor.rebuildTaskData(Long caseId)'
            carrier = 'TaskProcessor rebuildTaskData -> ExampleBaseTaskData.primaryId/secondaryId -> InputData.primary_id/InputData.secondary_id'
            slice_type = 'exact_contract_slice'
            test_name = 'ExampleApplyTaskProcessorTest.testRebuildTaskData_PreservesPrimaryNumAndSecondaryNum'
            must_touch_files = @($oracleTaskProcessorFiles)
            required_assertions = @(
                'apply-example rebuildTaskData preserves primaryId',
                'apply-example rebuildTaskData preserves secondaryId',
                'calculate-example rebuildTaskData preserves primaryId',
                'calculate-example rebuildTaskData preserves secondaryId',
                'final AI input_data includes primary_id and secondary_id after rebuild'
            )
            forbidden_proof = @('synthetic_carrier', 'hand_built_task_data_only', 'reflection_setter_only', 'terminal_payload_only', 'dto_existence_only', 'helper_chain_expansion_without_oracle_proof')
        }
    } else {
        [ordered]@{
            family = 'source_chain'
            entry = 'ExampleDataAssemblyHelper + ExampleApplyService + ExampleCalculateService'
            carrier = 'SourceRecord.primaryId / SecondaryRecord.secondaryId -> RequestBuildContext -> ExampleBaseRequest -> ExampleBaseTaskData -> InputData.primary_id/InputData.secondary_id'
            slice_type = 'exact_contract_slice'
            test_name = 'ExamplePrimaryIdSourceChainTest.shouldFillPrimaryAndSecondaryFromBackendSources'
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
