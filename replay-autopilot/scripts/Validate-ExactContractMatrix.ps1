param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$MatrixPath = '',
    [string[]]$RequiredLiteral = @(),
    [switch]$AllowOraclePostHoc,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonObject {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Get-StringValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return '' }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        return [string]$Object.$Name
    }
    return ''
}

function Test-MetadataLiteral {
    param([string]$Literal)
    if ([string]::IsNullOrWhiteSpace($Literal)) { return $true }
    $value = $Literal.Trim()
    if ($value -match '^[A-Za-z]:\\|^/|\\|/|\.java$|\.md$|\.json$') { return $true }
    if ($value -match '^[a-f0-9]{32,40}$') { return $true }
    if ($value -match '^(PASS|FAIL|DONE|PARTIAL|BLOCKED|OPEN|CLOSED|PROCEED|VALID|INVALID_REPLAY)$') { return $true }
    if ($value -match '^(phase0_status|plan_status|final_status|blocker|decision)\s*[:=]') { return $true }
    if ($value -match '(?i)(gap|blocker|stop|authorization|workflow|coverage).*(gap|blocked|stop|partial|fail)') { return $true }
    if ($value -match '^(example-core|example-server|example-web|example-api|example-domain)$') { return $true }
    if ($value -match '^--%$|^-s$|^-f$|^-D') { return $true }
    if ($value -match '^(Noop|Stub|Fake|Dummy|Placeholder|Mock|InMemory|TestOnly|Scaffold)$') { return $true }
    if ($value -match '^[A-Z][A-Za-z0-9_]*(?:Test|Service|Controller|Mapper|Facade|Impl|Dto|DTO|VO|Vo|Request|Response|Query)?(?:#[A-Za-z0-9_]+)?$') { return $true }
    return $false
}

function Get-ReportHints {
    param([string]$Text)
    $hints = New-Object System.Collections.Generic.List[string]
    if ($Text -match '15\s*-?>\s*150|15\s*->\s*150') {
        $hints.Add('page_size 15 -> 150') | Out-Null
    }
    if ($Text -match '\bP15\b' -and $Text -match '\bP29\b') {
        $hints.Add('P15..P29') | Out-Null
    }
    if ($Text -match 'page_no\s*=\s*1') {
        $hints.Add('page_no=1') | Out-Null
    }
    return @($hints)
}

$root = Resolve-AbsolutePath $ReplayRoot
$requiredItems = @($RequiredLiteral | ForEach-Object {
    [string]$_ -split '\|'
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ([string]::IsNullOrWhiteSpace($MatrixPath)) {
    $MatrixPath = Join-Path $root 'EXACT_CONTRACT_ASSERTION_MATRIX.json'
}
$matrixFull = Resolve-AbsolutePath $MatrixPath
$validationPath = Join-Path $root 'EXACT_CONTRACT_VALIDATION.json'
$hintsPath = Join-Path $root 'EXACT_CONTRACT_ROUTING_HINTS.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
        matrix = $matrixFull
        validation_path = $validationPath
        hints_path = $hintsPath
    } | ConvertTo-Json -Depth 8
    exit 0
}

if (-not (Test-Path -LiteralPath $matrixFull)) {
    throw "Exact contract matrix not found: $matrixFull"
}

$matrix = Read-JsonObject -Path $matrixFull
$rows = @($matrix.rows)
$invalidRows = New-Object System.Collections.Generic.List[object]
$validRows = New-Object System.Collections.Generic.List[object]
$allowedSources = @('requirement', 'oracle_post_hoc', 'code_fact')

foreach ($row in $rows) {
    $literal = Get-StringValue $row 'literal'
    $sourceType = Get-StringValue $row 'source_type'
    if ([string]::IsNullOrWhiteSpace($sourceType)) {
        $sourceType = Get-StringValue $row 'source'
    }
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($field in @('literal', 'symbol_or_field', 'db_or_wire_or_display', 'test_assertion')) {
        if ([string]::IsNullOrWhiteSpace((Get-StringValue $row $field))) {
            $problems.Add("missing_$field") | Out-Null
        }
    }
    if ($allowedSources -notcontains $sourceType) {
        $problems.Add("invalid_source_type:$sourceType") | Out-Null
    }
    if ($sourceType -eq 'oracle_post_hoc' -and -not $AllowOraclePostHoc) {
        $problems.Add('oracle_post_hoc_not_allowed_in_blind_phase') | Out-Null
    }
    if (Test-MetadataLiteral -Literal $literal) {
        $problems.Add('metadata_or_non_behavior_literal') | Out-Null
    }

    if ($problems.Count -gt 0) {
        $invalidRows.Add([ordered]@{
            literal = $literal
            source_type = $sourceType
            problems = @($problems)
        }) | Out-Null
    } else {
        $validRows.Add($row) | Out-Null
    }
}

$finalReportText = Read-TextIfExists (Join-Path $root 'FINAL_REPLAY_REPORT.md')
$postHocHints = if ($AllowOraclePostHoc) { @(Get-ReportHints -Text $finalReportText) } else { @() }
$availableLiterals = @(
    @($validRows | ForEach-Object { Get-StringValue $_ 'literal' })
    $postHocHints
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$missingRequired = New-Object System.Collections.Generic.List[string]
foreach ($required in $requiredItems) {
    $found = $false
    foreach ($literal in $availableLiterals) {
        if ($literal.IndexOf($required, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $required.IndexOf($literal, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $found = $true
            break
        }
    }
    if (-not $found) {
        $missingRequired.Add($required) | Out-Null
    }
}

$issues = New-Object System.Collections.Generic.List[string]
if ($invalidRows.Count -gt 0) { $issues.Add("invalid_metadata_rows:$($invalidRows.Count)") | Out-Null }
if ($missingRequired.Count -gt 0) { $issues.Add("missing_required_literals:$($missingRequired -join ',')") | Out-Null }

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$validation = [ordered]@{
    status = $status
    replay_root = $root
    matrix = $matrixFull
    invalid_metadata_rows = $invalidRows.Count
    valid_row_count = $validRows.Count
    required_literals = @($requiredItems)
    missing_required_literals = @($missingRequired)
    post_hoc_hints = @($postHocHints)
    issues = @($issues)
    invalid_rows = @($invalidRows | Select-Object -First 50)
    gate = 'exact_contract_matrix_schema_and_metadata_filter'
}
$validation | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $validationPath -Encoding UTF8

$nextTarget = if ($missingRequired.Count -eq 0 -and ($RequiredLiteral.Count -gt 0 -or $postHocHints.Count -gt 0)) { 'exact_contract_slice' } else { '' }
[ordered]@{
    status = $status
    replay_root = $root
    next_target = $nextTarget
    priority_literals = @($availableLiterals | Select-Object -Unique)
    post_hoc_only = [bool]$AllowOraclePostHoc
    source = 'exact_contract_validation'
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $hintsPath -Encoding UTF8

Get-Content -LiteralPath $validationPath -Encoding UTF8
if ($status -ne 'PASS') { exit 1 }
