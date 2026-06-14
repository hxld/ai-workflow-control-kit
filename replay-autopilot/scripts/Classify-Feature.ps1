param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$Worktree = '',
    [string]$RequirementSource = '',
    [string]$OutPath = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Read-JsonIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-IntValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return 0 }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return 0 }
    $text = [string]$property.Value
    if ($text -match '^-?\d+$') { return [int]$text }
    return 0
}

function New-CodepointString {
    param([int[]]$Codepoints)
    return -join ($Codepoints | ForEach-Object { [char]$_ })
}

function Join-RegexAlternation {
    param([string[]]$Terms)
    return (@($Terms | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [regex]::Escape([string]$_) }) -join '|')
}

function Join-RegexPattern {
    param(
        [string]$AsciiPattern,
        [string[]]$UnicodeTerms
    )
    $unicodePattern = Join-RegexAlternation -Terms $UnicodeTerms
    if ([string]::IsNullOrWhiteSpace($unicodePattern)) { return $AsciiPattern }
    return "$AsciiPattern|$unicodePattern"
}

function Get-OracleFiles {
    param($Oracle)
    if ($null -eq $Oracle -or $null -eq $Oracle.files) { return @() }
    if ($Oracle.files -is [System.Array]) { return @($Oracle.files) }
    return @($Oracle.files)
}

function Test-TextHasPositiveWriteSignal {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    $writeRegex = Join-RegexPattern `
        -AsciiPattern "(?i)\b(insert|update|delete|persist|save|write|transaction|rollback|state\s+transition|migration|schema|ddl|database|table|mapper|dao)\b" `
        -UnicodeTerms @(
            (New-CodepointString -Codepoints @(0x843D, 0x5E93)),
            (New-CodepointString -Codepoints @(0x5199, 0x5165)),
            (New-CodepointString -Codepoints @(0x66F4, 0x65B0)),
            (New-CodepointString -Codepoints @(0x5220, 0x9664)),
            (New-CodepointString -Codepoints @(0x72B6, 0x6001, 0x6D41, 0x8F6C)),
            (New-CodepointString -Codepoints @(0x4E8B, 0x52A1)),
            (New-CodepointString -Codepoints @(0x8FC1, 0x79FB)),
            (New-CodepointString -Codepoints @(0x8868, 0x7ED3, 0x6784))
        )
    $negativeRegex = Join-RegexPattern `
        -AsciiPattern "(?i)\b(do\s+not|don't|must\s+not|no\s+new|no\s+db\s+writes?|no\s+schema|not\s+add|not\s+change|not\s+introduce|not\s+introduced|without\s+schema|must\s+remain)\b" `
        -UnicodeTerms @(
            (New-CodepointString -Codepoints @(0x7981, 0x6B62)),
            (New-CodepointString -Codepoints @(0x4E0D, 0x8981)),
            (New-CodepointString -Codepoints @(0x4E0D, 0x65B0, 0x589E)),
            (New-CodepointString -Codepoints @(0x4E0D, 0x6DFB, 0x52A0)),
            (New-CodepointString -Codepoints @(0x4E0D, 0x6539, 0x53D8)),
            (New-CodepointString -Codepoints @(0x4E0D, 0x6539)),
            (New-CodepointString -Codepoints @(0x4E0D, 0x5199))
        )
    $negativeRegex = "$negativeRegex|$([regex]::Escape((New-CodepointString -Codepoints @(0x65E0))) )\s*DB\s*$([regex]::Escape((New-CodepointString -Codepoints @(0x5199))) )|$([regex]::Escape((New-CodepointString -Codepoints @(0x6CA1, 0x6709))) )\s*DB\s*$([regex]::Escape((New-CodepointString -Codepoints @(0x5199))) )"

    foreach ($line in @($Text -split "\r?\n")) {
        $lineText = [string]$line
        if ([string]::IsNullOrWhiteSpace($lineText)) { continue }
        if ($lineText -match $negativeRegex) { continue }
        if ($lineText -match $writeRegex) { return $true }
    }
    return $false
}

function Test-TextHasReadOnlyOrFieldPropagationSignal {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $pattern = Join-RegexPattern `
        -AsciiPattern '(?i)(read[- ]?only|preserve|propagate|copy|pass[- ]?through|rebuilt?\s+request|rebuilt?\s+task|nullable|no\s+schema|do\s+not\s+change\s+frontend|field[- ]?propagation)' `
        -UnicodeTerms @(
            (New-CodepointString -Codepoints @(0x53EA, 0x8BFB)),
            (New-CodepointString -Codepoints @(0x5B57, 0x6BB5)),
            (New-CodepointString -Codepoints @(0x4FDD, 0x7559)),
            (New-CodepointString -Codepoints @(0x4F20, 0x9012)),
            (New-CodepointString -Codepoints @(0x900F, 0x4F20)),
            (New-CodepointString -Codepoints @(0x91CD, 0x5EFA)),
            (New-CodepointString -Codepoints @(0x517C, 0x5BB9)),
            (New-CodepointString -Codepoints @(0x53EF, 0x7A7A))
        )
    $noAdd = [regex]::Escape((New-CodepointString -Codepoints @(0x4E0D, 0x65B0, 0x589E)))
    $noChangeShort = [regex]::Escape((New-CodepointString -Codepoints @(0x4E0D, 0x6539)))
    $noChangeLong = [regex]::Escape((New-CodepointString -Codepoints @(0x4E0D, 0x6539, 0x53D8)))
    $frontend = [regex]::Escape((New-CodepointString -Codepoints @(0x524D, 0x7AEF)))
    $pattern = "$pattern|$noAdd.*schema|$noChangeShort.*$frontend|$noChangeLong.*$frontend"
    return $Text -match $pattern
}

function Test-PathMatchesAny {
    param([string]$Path, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        if ($Path -match $pattern) { return $true }
    }
    return $false
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $replayRootFull 'FEATURE_CLASSIFICATION.json'
}
$outFull = Resolve-AbsolutePath $OutPath

$run = Read-JsonIfExists (Join-Path $replayRootFull 'AUTOPILOT_RUN.json')
if ([string]::IsNullOrWhiteSpace($RequirementSource) -and $null -ne $run) {
    $RequirementSource = [string]$run.requirement_source
}
if ([string]::IsNullOrWhiteSpace($Worktree) -and $null -ne $run) {
    $Worktree = [string]$run.worktree
}

$oracle = Read-JsonIfExists (Join-Path $replayRootFull 'ORACLE_DIFF_ANALYSIS.json')
$files = @(Get-OracleFiles -Oracle $oracle)
$productionFiles = @()
$testFiles = @()
$uiFiles = @()
$schemaFiles = @()
$configFiles = @()
$apiEndpointFiles = @()
$backendFiles = @()
$totalAdditions = 0
$totalDeletions = 0

foreach ($file in $files) {
    $path = ([string]$file.path).Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    $isTest = $false
    if ($null -ne $file.PSObject.Properties['is_test']) {
        $isTest = [bool]$file.is_test
    } elseif ($path -match '(^|/)src/test/|Test\.(java|kt|cs|ts|js)$') {
        $isTest = $true
    }

    $isProduction = $false
    if ($null -ne $file.PSObject.Properties['is_production']) {
        $isProduction = [bool]$file.is_production
    } elseif (-not $isTest -and $path -match '(^|/)src/main/') {
        $isProduction = $true
    }

    $totalAdditions += Get-IntValue -Object $file -Name 'additions'
    $totalDeletions += Get-IntValue -Object $file -Name 'deletions'

    if ($isTest) { $testFiles += $path }
    if ($isProduction) {
        $productionFiles += $path
        if (Test-PathMatchesAny -Path $path -Patterns @('/src/main/java/', '/service/', '/core/', '/server/', '/task/', '/processor/', '/facade/', '/controller/')) {
            $backendFiles += $path
        }
        if (Test-PathMatchesAny -Path $path -Patterns @('/web/', '/ui/', '/view/', '\.jsp$', '\.html$', '\.vue$', '\.tsx?$', '\.jsx?$')) {
            $uiFiles += $path
        }
        if (Test-PathMatchesAny -Path $path -Patterns @('/db/', '/sql/', '/migration/', '\.sql$', 'Mapper\.xml$')) {
            $schemaFiles += $path
        }
        if (Test-PathMatchesAny -Path $path -Patterns @('\.ya?ml$', '\.properties$', '/config/', 'Config\.java$')) {
            $configFiles += $path
        }
        if (Test-PathMatchesAny -Path $path -Patterns @('Controller\.(java|kt)$', 'Endpoint\.(java|kt)$', 'Resource\.(java|kt)$', '/api/')) {
            $apiEndpointFiles += $path
        }
    }
}

if ($totalAdditions -eq 0 -and $null -ne $oracle) { $totalAdditions = Get-IntValue -Object $oracle -Name 'total_additions' }
if ($totalDeletions -eq 0 -and $null -ne $oracle) { $totalDeletions = Get-IntValue -Object $oracle -Name 'total_deletions' }

$requirementText = Read-TextIfExists $RequirementSource
$hasPositiveWriteSignal = Test-TextHasPositiveWriteSignal -Text $requirementText
$hasReadOnlyOrPropagationSignal = Test-TextHasReadOnlyOrFieldPropagationSignal -Text $requirementText
$negativeRequirementLineRegex = Join-RegexPattern `
    -AsciiPattern '(?i)do\s+not|must\s+not|no\s+new|not\s+introduce|not\s+introduced|without\s+schema|must\s+remain' `
    -UnicodeTerms @(
        (New-CodepointString -Codepoints @(0x7981, 0x6B62)),
        (New-CodepointString -Codepoints @(0x4E0D, 0x8981)),
        (New-CodepointString -Codepoints @(0x4E0D, 0x65B0, 0x589E)),
        (New-CodepointString -Codepoints @(0x4E0D, 0x6539, 0x53D8)),
        (New-CodepointString -Codepoints @(0x4E0D, 0x6539))
    )
$positiveRequirementText = (($requirementText -split "\r?\n" | Where-Object { [string]$_ -notmatch $negativeRequirementLineRegex }) -join "`n")
$hasPayloadSignal = $requirementText -match (Join-RegexPattern `
    -AsciiPattern '(?i)(payload|request|response|api|json|input_data|wire|body)' `
    -UnicodeTerms @(
        (New-CodepointString -Codepoints @(0x62A5, 0x6587)),
        (New-CodepointString -Codepoints @(0x8BF7, 0x6C42)),
        (New-CodepointString -Codepoints @(0x54CD, 0x5E94)),
        (New-CodepointString -Codepoints @(0x63A5, 0x53E3))
    ))
$hasUiRequirement = $positiveRequirementText -match (Join-RegexPattern `
    -AsciiPattern '(?i)(frontend|page|screen|view|display|jsp|javascript|vue|html)' `
    -UnicodeTerms @(
        (New-CodepointString -Codepoints @(0x524D, 0x7AEF)),
        (New-CodepointString -Codepoints @(0x9875, 0x9762)),
        (New-CodepointString -Codepoints @(0x5C55, 0x793A))
    ))
$hasConfigRequirement = $positiveRequirementText -match (Join-RegexPattern `
    -AsciiPattern '(?i)(config|configuration|threshold)' `
    -UnicodeTerms @(
        (New-CodepointString -Codepoints @(0x5F00, 0x5173)),
        (New-CodepointString -Codepoints @(0x914D, 0x7F6E)),
        (New-CodepointString -Codepoints @(0x9608, 0x503C))
    ))
$hasSchemaRequirement = Test-TextHasPositiveWriteSignal -Text $positiveRequirementText

$smallProductionChange = $productionFiles.Count -gt 0 -and $productionFiles.Count -le 5 -and ($totalAdditions + $totalDeletions) -le 25
$backendOnly = $productionFiles.Count -gt 0 -and $backendFiles.Count -eq $productionFiles.Count -and $uiFiles.Count -eq 0 -and $schemaFiles.Count -eq 0 -and $configFiles.Count -eq 0
$readOnly = $backendOnly -and -not $hasPositiveWriteSignal -and $schemaFiles.Count -eq 0 -and $uiFiles.Count -eq 0 -and ($hasReadOnlyOrPropagationSignal -or $smallProductionChange)

$classification = 'broad_fullstack_feature'
$baseClassification = 'broad_fullstack_feature'
if ($schemaFiles.Count -gt 0 -or ($hasSchemaRequirement -and -not $readOnly)) {
    $classification = 'data_migration'
    $baseClassification = 'data_migration'
} elseif ($configFiles.Count -gt 0 -or $hasConfigRequirement) {
    $classification = 'config_change'
    $baseClassification = 'config_change'
} elseif ($apiEndpointFiles.Count -gt 0 -and -not $readOnly) {
    $classification = 'api_endpoint'
    $baseClassification = 'api_endpoint'
} elseif ($backendOnly -and $smallProductionChange) {
    $baseClassification = 'narrow_backend_fix'
    if ($readOnly) {
        $classification = 'narrow_backend_read_only_fix'
    } else {
        $classification = 'narrow_backend_fix'
    }
}

$nonApplicableFamilies = @()
if ($classification -eq 'narrow_backend_read_only_fix') {
    $nonApplicableFamilies = @(
        'stateful_side_effect',
        'deploy_export_page',
        'config_policy_threshold',
        'generated_artifact_template_upload',
        'external_integration',
        'lifecycle_cleanup_retention'
    )
    if (-not $hasPayloadSignal) {
        $nonApplicableFamilies += 'wire_payload_api_contract'
    }
}

$adjustments = [ordered]@{
    horizontal_minimum = $(if ($baseClassification -eq 'narrow_backend_fix') { 2 } else { 3 })
    horizontal_required_categories = $(if ($baseClassification -eq 'narrow_backend_fix') { @('Backend', 'Test') } else { @('Frontend', 'Backend', 'Database') })
    stateful_side_effect_required = $(if ($classification -eq 'narrow_backend_read_only_fix') { $false } else { $true })
    facade_entry_required = $(if ($baseClassification -eq 'narrow_backend_fix') { $false } else { $true })
    red_phase_required = $(if ($classification -eq 'narrow_backend_read_only_fix') { $false } else { $true })
    green_only_evidence_accepted = $(if ($classification -eq 'narrow_backend_read_only_fix') { $true } else { $false })
    accepted_test_tiers = $(if ($baseClassification -eq 'narrow_backend_fix') { @('unit_method_public', 'unit_method_package', 'unit_method_reflection', 'cross_module_unit_harness') } else { @('real_entry_integration') })
    non_applicable_families = @($nonApplicableFamilies | Select-Object -Unique)
}

$evidence = [ordered]@{
    production_file_count = $productionFiles.Count
    test_file_count = $testFiles.Count
    backend_file_count = $backendFiles.Count
    ui_file_count = $uiFiles.Count
    schema_file_count = $schemaFiles.Count
    config_file_count = $configFiles.Count
    api_endpoint_file_count = $apiEndpointFiles.Count
    total_additions = $totalAdditions
    total_deletions = $totalDeletions
    small_production_change = $smallProductionChange
    backend_only = $backendOnly
    read_only_signal = $readOnly
    field_or_propagation_signal = $hasReadOnlyOrPropagationSignal
    positive_write_signal = $hasPositiveWriteSignal
    payload_signal = $hasPayloadSignal
    ui_requirement_signal = $hasUiRequirement
}

$result = [ordered]@{
    schema = 'feature_classification.v1'
    generated_at = (Get-Date).ToString('s')
    replay_root = $replayRootFull
    worktree = $Worktree
    requirement_source = $RequirementSource
    classification = $classification
    base_classification = $baseClassification
    read_only = $readOnly
    backend_only = $backendOnly
    confidence = $(if ($classification -eq 'narrow_backend_read_only_fix' -and $smallProductionChange -and $hasReadOnlyOrPropagationSignal) { 'high' } elseif ($baseClassification -eq 'narrow_backend_fix') { 'medium' } else { 'medium' })
    evidence = $evidence
    verifier_adjustments = $adjustments
    production_files = @($productionFiles)
    gate = 'feature_classifier'
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outFull -Encoding UTF8
Get-Content -LiteralPath $outFull -Encoding UTF8
