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

function Get-SafeFileStem {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }

    $leaf = @(([string]$Path -replace '\\', '/') -split '/')[-1]
    if ([string]::IsNullOrWhiteSpace($leaf)) { return '' }
    return ($leaf -replace '\.[^.]+$', '')
}

function Convert-SnakeToCamel {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }

    $parts = @([string]$Value -split '_')
    if ($parts.Count -eq 0) { return '' }

    $camel = [string]$parts[0]
    for ($i = 1; $i -lt $parts.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($parts[$i])) { continue }
        $part = [string]$parts[$i]
        $camel += $part.Substring(0, 1).ToUpperInvariant() + $part.Substring(1)
    }
    return $camel
}

function Test-NegatedSourceChainIntent {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    return (
        $Text -match '(?i)\bnot\s+(a\s+)?(rebuildTaskData|rebuild\s+path|source[-_\s]?chain)\b' -or
        $Text -match '(?i)\bnot\s+(a\s+)?rebuildTaskData\s+or\s+source[-_\s]?chain\b'
    )
}

function Test-ExplicitSourceChainIntent {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if (Test-NegatedSourceChainIntent -Text $Text) { return $false }

    $normalized = [string]$Text
    if (
        $normalized -match '(?i)\bsource[-_\s]?chain\b' -or
        $normalized -match '(?i)\b(source extraction|backend source extraction|from backend source)\b' -or
        $normalized -match '(?i)\b(RequestBuildContext|buildRequestCommon|RequestBuildFunction)\b'
    ) {
        return $true
    }

    $paragraphs = @([regex]::Split($normalized, '(?:\r?\n\s*){2,}'))
    foreach ($paragraph in $paragraphs) {
        if ([string]::IsNullOrWhiteSpace($paragraph)) { continue }
        if ($paragraph -notmatch '(?i)\b(rebuildTaskData|rebuilt task data|task data is rebuilt|boundary rebuild path)\b') { continue }

        if ($paragraph -match '(?i)\b(No-Spring Test Rule|test rule|tests?:\s*use|JUnit|Mockito|Spring Boot Test annotation|Test resides)\b') {
            continue
        }

        $hasTransferVerb = $paragraph -match '(?i)\b(preserve|propagate|copy|carry|map|assign|fill|read|write|from|into|through|via)\b'
        $hasSourceOrWireBoundary = $paragraph -match '(?i)\b(source|InputData|input_data|wire|payload|RequestBuildContext|build context|task data|AI request|field|[a-z][a-z0-9]+_[a-z0-9_]+)\b'
        if ($hasTransferVerb -and $hasSourceOrWireBoundary) {
            return $true
        }
    }

    return $false
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
$explicitSourceChainIntent = Test-ExplicitSourceChainIntent -Text $text
$rebuildPathRequirement = $explicitSourceChainIntent -and (
    $text -match '(?i)\b(rebuildTaskData|rebuilt task data|task data is rebuilt|boundary rebuild path)\b'
)
$oracleTaskProcessorFiles = @(Get-OracleTaskProcessorFiles -ReplayRoot $root)

if ($explicitSourceChainIntent -and $hasPrimarySource -and $hasPrimaryTarget -and $hasAiPayloadContext) {
    Add-Unique $sourceFields 'SourceRecord.primaryId'
    Add-Unique $targetFields 'primary_id'
    Add-Unique $assertions 'captured InputData.primary_id equals SourceRecord.primaryId from backend source extraction'
}
if ($explicitSourceChainIntent -and $hasSecondarySource -and $hasSecondaryTarget -and $hasAiPayloadContext) {
    Add-Unique $sourceFields 'SecondaryRecord.secondaryId'
    Add-Unique $targetFields 'secondary_id'
    Add-Unique $assertions 'captured InputData.secondary_id equals SecondaryRecord.secondaryId queried by policy number'
}

$ignoredWireTokens = @(
    'input_data',
    'task_data',
    'source_chain',
    'wire_payload',
    'request_body',
    'response_body'
)
$wireTokens = @()
if ($explicitSourceChainIntent) {
    $wireTokens = @([regex]::Matches($text, '(?i)\b[a-z][a-z0-9]+(?:_[a-z0-9]+)+\b') | ForEach-Object {
        $_.Value.ToLowerInvariant()
    } | Where-Object {
        $ignoredWireTokens -notcontains $_
    } | Select-Object -Unique)
    foreach ($wireToken in $wireTokens) {
        $camelToken = Convert-SnakeToCamel -Value $wireToken
        if ([string]::IsNullOrWhiteSpace($camelToken)) { continue }
        if ($text -match ('(?i)\b' + [regex]::Escape($camelToken) + '\b')) {
            Add-Unique $sourceFields "source.$camelToken"
            Add-Unique $targetFields $wireToken
            Add-Unique $assertions "captured InputData.$wireToken equals source.$camelToken from backend source extraction"
        }
    }
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
    $fileStem = Get-SafeFileStem -Path $file
    if (-not [string]::IsNullOrWhiteSpace($fileStem) -and $text -match [regex]::Escape($fileStem)) {
        Add-Unique $mustTouchFiles $file
    }
}

$oracleTaskProcessorClassNames = New-Object System.Collections.Generic.List[string]
foreach ($file in @($oracleTaskProcessorFiles)) {
    Add-Unique -List $oracleTaskProcessorClassNames -Value (Get-SafeFileStem -Path $file)
}
$taskProcessorCarrierNames = if ($oracleTaskProcessorClassNames.Count -gt 0) {
    @($oracleTaskProcessorClassNames) -join ' and '
} else {
    'TaskProcessor rebuildTaskData'
}
$taskProcessorEntry = if ($oracleTaskProcessorClassNames.Count -gt 0) {
    @($oracleTaskProcessorClassNames | ForEach-Object { "$_.rebuildTaskData(Long caseId)" }) -join ' and '
} else {
    'TaskProcessor.rebuildTaskData(Long caseId)'
}
$sourceFieldDisplay = if ($sourceFields.Count -gt 0) { @($sourceFields) -join '/' } else { 'source fields' }
$targetFieldDisplay = if ($targetFields.Count -gt 0) { @($targetFields) -join '/' } else { 'wire fields' }

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
} elseif (-not $explicitSourceChainIntent -and ($wireTokens.Count -eq 0)) {
    'field-name pairs found without explicit source-chain/rebuild intent; source-chain gate not applicable'
} else {
    'no named source-chain contract detected'
}
$requiredFamilies = @()
if ($hasNamedSource -and $sourceChainMode -eq 'task_processor_rebuild') {
    $requiredFamilies = @(
        [ordered]@{ family = 'task_processor_rebuild'; carrier = $taskProcessorCarrierNames; reason = 'archived oracle high-weight files are rebuild TaskProcessors; first executable proof must bind to rebuildTaskData' },
        [ordered]@{ family = 'wire_payload'; carrier = $taskProcessorCarrierNames; reason = "rebuilt task data must still reach outgoing InputData $targetFieldDisplay keys" }
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
            entry = $taskProcessorEntry
            carrier = "TaskProcessor rebuildTaskData -> $sourceFieldDisplay -> InputData.$targetFieldDisplay"
            slice_type = 'exact_contract_slice'
            test_name = "$(@($oracleTaskProcessorClassNames | Select-Object -First 1))Test.testRebuildTaskData_PreservesSourceFields"
            must_touch_files = @($oracleTaskProcessorFiles)
            required_assertions = @($assertions)
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
    explicit_source_chain_intent = $explicitSourceChainIntent
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
