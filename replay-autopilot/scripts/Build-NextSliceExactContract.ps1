param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [int]$SliceIndex = 1,
    [string]$MatrixPath = '',
    [int]$MaxRows = 5,
    [switch]$FailOnBroadRows,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Get-StringValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return '' }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        return [string]$Object.$Name
    }
    return ''
}

function Get-BoolValue {
    param($Object, [string]$Name)
    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) { return $false }
    $value = $Object.$Name
    if ($value -is [bool]) { return [bool]$value }
    return @('true', '1', 'yes', 'allow', 'required') -contains ([string]$value).Trim().ToLowerInvariant()
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return @($text)
}

function Test-BroadExactRow {
    param($Row)
    $literalText = @(
        (Get-StringValue $Row 'literal'),
        (Get-StringValue $Row 'symbol_or_field'),
        (Get-StringValue $Row 'test_assertion')
    ) -join ' '
    $text = @(
        $literalText,
        (Get-StringValue $Row 'db_or_wire_or_display')
    ) -join ' '
    if ([string]::IsNullOrWhiteSpace($text)) { return $true }
    if ($text -match '(?i)\bgit\s+(diff|show|status|log)\b') { return $true }
    if ($text -match '(?i)\b(branch|commit|hash|sha|phase|status|coverage|gap[_ -]?flag|workflow|replay root)\b') { return $true }
    if ($literalText -match '^[A-Za-z]:\\|^/|\\|/|\.md\b|\.json\b') { return $true }
    if ($literalText -match '^[a-f0-9]{32,40}$') { return $true }
    return $false
}

function Test-ExactRowMatchesSideEffectScope {
    param($Row, [string[]]$AllowedLiterals, [string]$SelectedCarrier)

    if ($AllowedLiterals.Count -eq 0) { return $true }
    $literal = Get-StringValue $Row 'literal'
    $symbol = Get-StringValue $Row 'symbol_or_field'
    $assertion = Get-StringValue $Row 'test_assertion'
    $boundary = Get-StringValue $Row 'production_boundary'
    $rowText = @($literal, $symbol, $assertion) -join ' '

    foreach ($allowed in $AllowedLiterals) {
        if ([string]::IsNullOrWhiteSpace($allowed)) { continue }
        if ($literal -eq $allowed -or $symbol -eq $allowed) { return $true }
        if ($rowText -match [regex]::Escape($allowed)) { return $true }
    }

    if (-not [string]::IsNullOrWhiteSpace($SelectedCarrier) -and -not [string]::IsNullOrWhiteSpace($boundary) -and $boundary -eq $SelectedCarrier) {
        $carrierLeaf = ''
        if ($SelectedCarrier -match '\.([A-Z][A-Za-z0-9_]+)\.([A-Za-z_][A-Za-z0-9_]*)$') {
            $carrierLeaf = "$($matches[1]).$($matches[2])"
        } elseif ($SelectedCarrier -match '([A-Z][A-Za-z0-9_]+[.#][A-Za-z_][A-Za-z0-9_]*)') {
            $carrierLeaf = $matches[1] -replace '#', '.'
        }
        if (-not [string]::IsNullOrWhiteSpace($carrierLeaf) -and ($literal -eq $carrierLeaf -or $symbol -eq $carrierLeaf)) {
            return $true
        }
    }

    return $false
}

function Get-ExactRowClass {
    param($Row, [string]$SelectedCarrier, [bool]$RequiredForSlice, [string[]]$AllowedLiterals = @())

    if (Test-BroadExactRow -Row $Row) { return 'invalid_meta_row' }
    if (-not (Test-ExactRowMatchesSideEffectScope -Row $Row -AllowedLiterals $AllowedLiterals -SelectedCarrier $SelectedCarrier)) {
        return 'out_of_slice_scope'
    }

    $literal = Get-StringValue $Row 'literal'
    $symbol = Get-StringValue $Row 'symbol_or_field'
    $boundary = Get-StringValue $Row 'production_boundary'
    $surface = Get-StringValue $Row 'db_or_wire_or_display'
    $assertion = Get-StringValue $Row 'test_assertion'
    $rowText = @($literal, $symbol, $boundary, $surface, $assertion) -join ' '

    if ($rowText -match '(?i)\b(git diff|git log|git show|phase0|phase1|phase2|coverage|gap_flags?|replay root|oracle branch|commit)\b') {
        return 'invalid_meta_row'
    }
    if ($literal -match '^[A-Za-z0-9_.$#]+\(?\.\.\.\)?$' -or $literal -match '^[A-Za-z0-9_.$#]+#[A-Za-z0-9_]+') {
        return 'warning_only'
    }
    if (-not $RequiredForSlice -and -not [string]::IsNullOrWhiteSpace($SelectedCarrier) -and -not [string]::IsNullOrWhiteSpace($boundary) -and $boundary -ne $SelectedCarrier) {
        return 'sibling_followup'
    }
    return 'blocking_for_selected_carrier'
}

$root = Resolve-AbsolutePath $ReplayRoot
$outPath = Join-Path $root ('NEXT_SLICE_EXACT_CONTRACT_{0:D2}.json' -f $SliceIndex)
$genericOutPath = Join-Path $root 'NEXT_SLICE_EXACT_CONTRACT.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
        slice_index = $SliceIndex
        output = $outPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

if ([string]::IsNullOrWhiteSpace($MatrixPath)) {
    $MatrixPath = Join-Path $root ('EXACT_CONTRACT_ASSERTION_MATRIX_{0:D2}.json' -f $SliceIndex)
    if (-not (Test-Path -LiteralPath $MatrixPath)) {
        $MatrixPath = Join-Path $root 'EXACT_CONTRACT_ASSERTION_MATRIX.json'
    }
}

$matrix = Read-JsonIfExists $MatrixPath
$sideEffect = Read-JsonIfExists (Join-Path $root ('SIDE_EFFECT_EVIDENCE_{0:D2}.json' -f $SliceIndex))
if ($null -eq $sideEffect) { $sideEffect = Read-JsonIfExists (Join-Path $root 'SIDE_EFFECT_EVIDENCE.json') }
$carrier = Read-JsonIfExists (Join-Path $root ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex))
if ($null -eq $carrier) { $carrier = Read-JsonIfExists (Join-Path $root 'CARRIER_AUTHORIZATION.json') }

$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$rows = @()
$requiredForSlice = $false
$matrixRowScope = ''
if ($null -ne $matrix) {
    if ($matrix.PSObject.Properties.Name -contains 'required_for_this_slice') {
        $requiredForSlice = [bool]$matrix.required_for_this_slice
    }
    if ($matrix.PSObject.Properties.Name -contains 'row_scope') {
        $matrixRowScope = [string]$matrix.row_scope
    }
    if ($null -ne $matrix.rows) {
        if ($matrix.rows -is [System.Array]) { $rows = @($matrix.rows) } else { $rows = @($matrix.rows) }
    }
} elseif ($null -ne $carrier -and [bool]$carrier.requires_exact_contract_assertions) {
    $requiredForSlice = $true
}

if ($null -ne $carrier -and [bool]$carrier.requires_exact_contract_assertions) {
    $requiredForSlice = $true
}
$selectedCarrier = Get-StringValue $carrier 'selected_carrier'
$sideEffectStatus = Get-StringValue $sideEffect 'status'
$sideEffectExpected = @(Get-StringArray $sideEffect.expected_writes_or_outputs)
$sideEffectExactScope = (
    $requiredForSlice -and
    $sideEffectExpected.Count -gt 0 -and
    (
        $sideEffectStatus -eq 'READY' -or
        (Get-BoolValue $carrier 'requires_side_effect_evidence')
    )
)
$allowedSideEffectRows = if ($sideEffectExactScope) { @($sideEffectExpected | Select-Object -Unique) } else { @() }

if ($requiredForSlice -and $rows.Count -eq 0) {
    $issues.Add('exact_contract_rows_missing') | Out-Null
}

$testName = Get-StringValue $sideEffect 'test_name'
$fallbackRedCommand = ''
if (-not [string]::IsNullOrWhiteSpace($testName)) {
    $fallbackRedCommand = "run focused RED test: $testName"
}

$selected = New-Object System.Collections.Generic.List[object]
$rowClasses = New-Object System.Collections.Generic.List[object]
foreach ($row in $rows) {
    if ($selected.Count -ge $MaxRows) { break }
    $rowClass = Get-ExactRowClass -Row $row -SelectedCarrier $selectedCarrier -RequiredForSlice $requiredForSlice -AllowedLiterals $allowedSideEffectRows
    $rowClasses.Add([pscustomobject][ordered]@{
        literal = (Get-StringValue $row 'literal')
        class = $rowClass
        production_boundary = (Get-StringValue $row 'production_boundary')
    }) | Out-Null
    if ($rowClass -eq 'invalid_meta_row') {
        $warnings.Add("invalid_meta_row_skipped:$((Get-StringValue $row 'literal'))") | Out-Null
        continue
    }
    if ($rowClass -eq 'warning_only' -and -not $requiredForSlice) {
        $warnings.Add("warning_only_exact_row:$((Get-StringValue $row 'literal'))") | Out-Null
    }
    if ($rowClass -eq 'out_of_slice_scope') {
        $warnings.Add("out_of_slice_exact_row_skipped:$((Get-StringValue $row 'literal'))") | Out-Null
        continue
    }

    $literal = Get-StringValue $row 'literal'
    $symbol = Get-StringValue $row 'symbol_or_field'
    $surface = Get-StringValue $row 'db_or_wire_or_display'
    $boundary = Get-StringValue $row 'production_boundary'
    $assertion = Get-StringValue $row 'test_assertion'
    $redCommand = Get-StringValue $row 'red_command'
    if ([string]::IsNullOrWhiteSpace($redCommand)) { $redCommand = $fallbackRedCommand }
    $blocker = Get-StringValue $row 'blocker_condition'
    if ([string]::IsNullOrWhiteSpace($blocker)) { $blocker = 'missing executable exact-contract boundary proof' }

    $missing = @()
    if ([string]::IsNullOrWhiteSpace($literal)) { $missing += 'literal' }
    if ([string]::IsNullOrWhiteSpace($symbol)) { $missing += 'symbol_or_field' }
    if ([string]::IsNullOrWhiteSpace($surface)) { $missing += 'db_or_wire_or_display' }
    if ([string]::IsNullOrWhiteSpace($boundary)) { $missing += 'production_boundary' }
    if ([string]::IsNullOrWhiteSpace($assertion)) { $missing += 'test_assertion' }
    if ([string]::IsNullOrWhiteSpace($redCommand)) { $missing += 'red_command' }
    if ([string]::IsNullOrWhiteSpace($blocker)) { $missing += 'blocker_condition' }
    if ($missing.Count -gt 0) {
        $issues.Add("next_slice_exact_contract_required_field_missing:$($missing -join ','):$literal") | Out-Null
    }

    $selected.Add([pscustomobject][ordered]@{
        literal = $literal
        symbol_or_field = $symbol
        db_or_wire_or_display = $surface
        boundary_type = (Get-StringValue $row 'boundary_type')
        production_boundary = $boundary
        test_assertion = $assertion
        red_command = $redCommand
        blocker_condition = $blocker
    }) | Out-Null
}

if ($requiredForSlice -and $selected.Count -eq 0) {
    $issues.Add('next_slice_exact_contract_subset_empty') | Out-Null
}

$decision = if ($issues.Count -eq 0) { 'ALLOW' } else { 'STOP' }
$selectedRows = @($selected.ToArray())
$issueRows = @($issues.ToArray() | Select-Object -Unique)
$warningRows = @($warnings.ToArray() | Select-Object -Unique)
$result = [ordered]@{
    schema_version = 1
    decision = $decision
    replay_root = $root
    slice_index = $SliceIndex
    required_for_this_slice = $requiredForSlice
    row_scope = if ($sideEffectExactScope) { 'side_effect_expected_outputs' } elseif (-not [string]::IsNullOrWhiteSpace($matrixRowScope)) { $matrixRowScope } else { 'matrix_rows' }
    side_effect_scope_literals = @($allowedSideEffectRows)
    max_rows = $MaxRows
    matrix_path = $MatrixPath
    rows = @($selectedRows)
    row_classes = @($rowClasses.ToArray())
    issues = @($issueRows)
    warnings = @($warningRows)
    gate = 'next_slice_exact_contract_subset'
}

$json = $result | ConvertTo-Json -Depth 12
$json | Set-Content -LiteralPath $outPath -Encoding UTF8
$json | Set-Content -LiteralPath $genericOutPath -Encoding UTF8
$json
