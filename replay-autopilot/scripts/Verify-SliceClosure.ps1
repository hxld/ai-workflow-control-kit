param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [string]$SliceResult,
    [int]$SliceIndex = 1,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonObject {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        return $text | ConvertFrom-Json
    } catch {
        $start = $text.IndexOf('{')
        $end = $text.LastIndexOf('}')
        if ($start -ge 0 -and $end -gt $start) {
            $json = $text.Substring($start, $end - $start + 1)
            return $json | ConvertFrom-Json
        }
        throw
    }
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-ObjectStringValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return '' }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        return [string]$Object.$Name
    }
    return ''
}

function Test-PublicEntryText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return $Text -match '(?i)(Facade(?:Impl)?|Controller(?:Impl)?|Api|Endpoint|Route)\b'
}

function Read-WorktreeText {
    param([string]$Root, [string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return '' }
    $candidate = $RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
    if ([System.IO.Path]::IsPathRooted($candidate)) {
        $path = $candidate
    } else {
        $path = Join-Path $Root $candidate
    }
    if (Test-Path -LiteralPath $path) {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8
    }
    return ''
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Get-CarrierFileAndMethod {
    param([string]$Carrier)
    if ([string]::IsNullOrWhiteSpace($Carrier)) { return $null }
    if ($Carrier -match '([^#;`"\r\n]+\.java)#([A-Za-z_][A-Za-z0-9_]*)\s*\(') {
        return [pscustomobject]@{
            file = $matches[1].Trim()
            method = $matches[2].Trim()
        }
    }
    if ($Carrier -match '([^#;`"\r\n]+\.java)#([A-Za-z_][A-Za-z0-9_]*)') {
        return [pscustomobject]@{
            file = $matches[1].Trim()
            method = $matches[2].Trim()
        }
    }
    return $null
}

function Get-MethodLines {
    param([string[]]$Lines, [string]$Method)
    if ([string]::IsNullOrWhiteSpace($Method)) { return $Lines }
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match ("\b" + [regex]::Escape($Method) + "\s*\(")) {
            $start = $i
            break
        }
    }
    if ($start -lt 0) { return $Lines }
    $depth = 0
    $seenBrace = $false
    $body = New-Object System.Collections.Generic.List[string]
    for ($i = $start; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        $body.Add($line) | Out-Null
        $opens = ([regex]::Matches($line, '\{')).Count
        $closes = ([regex]::Matches($line, '\}')).Count
        if ($opens -gt 0) { $seenBrace = $true }
        if ($seenBrace) {
            $depth += $opens
            $depth -= $closes
            if ($depth -le 0 -and $i -gt $start) { break }
        }
    }
    return @($body)
}

function Find-PreGuardWriteCalls {
    param([string]$WorktreeRoot, [string]$Carrier)

    $carrierInfo = Get-CarrierFileAndMethod -Carrier $Carrier
    if ($null -eq $carrierInfo) { return @() }
    $relative = $carrierInfo.file -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $path = if ([System.IO.Path]::IsPathRooted($relative)) { $relative } else { Join-Path $WorktreeRoot $relative }
    if (-not (Test-Path -LiteralPath $path)) { return @() }

    $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
    $methodLines = @(Get-MethodLines -Lines $lines -Method $carrierInfo.method)
    $callRegex = '(?i)\b(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*)\s*\('
    $writeNameRegex = '(?i)(insert|update|delete|save|remove|persist|write|expire|expired|complete|finish|addUserTimeOut|updateCaseHandTask)'
    $guardRegex = '(?i)\b(shouldSkip[A-Za-z0-9_]*|skip[A-Za-z0-9_]*|suppress[A-Za-z0-9_]*|suHzAudit)\b'
    $seen = New-Object System.Collections.Generic.List[string]
    foreach ($line in $methodLines) {
        if ($line -match $guardRegex -and $seen.Count -gt 0) {
            return @($seen | Select-Object -Unique)
        }
        foreach ($m in [regex]::Matches($line, $callRegex)) {
            $name = [string]$m.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($name) -and $name -match $writeNameRegex -and -not $seen.Contains($name)) {
                $seen.Add($name) | Out-Null
            }
        }
    }
    return @()
}

function Get-PlanField {
    param([string]$Text, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $escaped = [regex]::Escape($Name)
    $lines = @($Text -split "\r?\n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if ($line -match "^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?$escaped\s*\*{0,2}\s*:\s*`?([^`\r\n]*)`?\s*$") {
            $value = $matches[1].Trim().Trim('`').Trim()
            if ([string]::IsNullOrWhiteSpace($value)) {
                for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                    $next = [string]$lines[$j]
                    if ([string]::IsNullOrWhiteSpace($next)) { continue }
                    if ($next -match '^\s*:\s*`?([^`\r\n]+)`?\s*$') {
                        $value = $matches[1].Trim().Trim('`').Trim()
                    }
                    break
                }
            }
            return $value.TrimEnd('.').Trim()
        }
    }
    return ''
}

function Get-PrimaryCarrierClassName {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $head = @($Text -split '\s*->\s*' | Select-Object -First 1)
    if ($head.Count -eq 0) { return '' }
    if ([string]$head[0] -match '\b([A-Z][A-Za-z0-9_]*(?:Service|Controller|Facade|Event|Mapper|Processor|Handler|Client|Provider|Task|Util|Helper))\b') {
        return $matches[1]
    }
    return ''
}

function Get-SubclassedClassNames {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Text, '(?s)\bclass\s+\w+\s+extends\s+([A-Z][A-Za-z0-9_]*)')) {
        $name = [string]$m.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($name) -and -not $names.Contains($name)) {
            $names.Add($name) | Out-Null
        }
    }
    return @($names)
}

function Get-TestClassNameFromBinding {
    param([string]$Binding)
    if ([string]::IsNullOrWhiteSpace($Binding)) { return '' }
    $value = ([string]$Binding).Trim().Trim('`').TrimEnd('.').Trim()
    $value = @($value -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)[0]
    $classPart = @($value -split '#')[0]
    $classPart = $classPart -replace '\\', '/'
    $leaf = @($classPart -split '/' | Select-Object -Last 1)[0]
    $leaf = $leaf -replace '\.java$', ''
    $segments = @($leaf -split '\.')
    $testClassSegment = @($segments | Where-Object { [string]$_ -match '^[A-Z][A-Za-z0-9_]*(?:Test|Tests)$' } | Select-Object -Last 1)
    if ($testClassSegment.Count -gt 0) {
        return ([string]$testClassSegment[0]).Trim()
    }
    if ($leaf -match '^([A-Z][A-Za-z0-9_]+)\.[a-z_][A-Za-z0-9_]*$') {
        return $matches[1].Trim()
    }
    return ([string]$leaf).Trim()
}

function Get-ObjectString {
    param($InputItem, [string]$Name)
    if ($null -eq $InputItem -or [string]::IsNullOrWhiteSpace($Name)) { return '' }
    $property = $InputItem.PSObject.Properties[$Name]
    if ($null -ne $property -and $null -ne $property.Value) { return [string]$property.Value }
    return ''
}

function Get-FamilySiblingSurfaces {
    param(
        $Value,
        [string]$FamilyId,
        [string[]]$TouchedFamilies
    )

    $all = @(Get-StringArray $Value)
    $matched = New-Object System.Collections.Generic.List[string]
    $unscoped = New-Object System.Collections.Generic.List[string]
    foreach ($item in $all) {
        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match '^\s*([a-z][a-z0-9_]+)\s*:\s*(.+)$') {
            if ($matches[1] -eq $FamilyId) {
                $matched.Add($matches[2].Trim()) | Out-Null
            }
        } else {
            $unscoped.Add($text.Trim()) | Out-Null
        }
    }
    if ($matched.Count -gt 0) { return @($matched) }
    if (@($TouchedFamilies).Count -eq 1 -or (@($TouchedFamilies).Count -gt 0 -and [string]$TouchedFamilies[0] -eq $FamilyId)) {
        return @($unscoped)
    }
    return @()
}

function Read-FamilyContract {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    try {
        $contract = Read-JsonObject -Path $Path
        $map = @{}
        foreach ($family in @($contract.families)) {
            if ($null -ne $family.id -and -not [string]::IsNullOrWhiteSpace([string]$family.id)) {
                $map[[string]$family.id] = $family
            }
        }
        return $map
    } catch {
        return @{}
    }
}

function Get-DefaultRequiredProofTypes {
    param([string]$FamilyId)
    switch ($FamilyId) {
        'core_entry' { return @('real_entry_behavior', 'stateful_side_effect', 'wire_payload', 'export_output', 'rendered_artifact') }
        'stateful_side_effect' { return @('stateful_side_effect', 'transaction') }
        'deploy_export_page' { return @('export_output', 'controller') }
        'wire_payload_api_contract' { return @('wire_payload', 'payload_shape') }
        'config_policy_threshold' { return @('wire_payload', 'payload_shape', 'persistence', 'service') }
        'generated_artifact_template_upload' { return @('rendered_artifact', 'template_render') }
        'external_integration' { return @('wire_payload', 'integration') }
        'automation_test_interface' { return @('controller', 'api_contract') }
        'lifecycle_cleanup_retention' { return @('lifecycle_cleanup', 'stateful_side_effect') }
        default { return @('behavior') }
    }
}

function Test-ProofTypeMatch {
    param([string[]]$Required, [string[]]$Actual)
    if (@($Required).Count -eq 0) { return $true }
    $actualText = ((@($Actual) | ForEach-Object { [string]$_ }) -join ' ').ToLowerInvariant()
    foreach ($requiredItem in @($Required)) {
        $requiredText = ([string]$requiredItem).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($requiredText)) { continue }
        if ($actualText.Contains($requiredText)) { return $true }
        switch -Regex ($requiredText) {
            'real.*entry|entry.*behavior' { if ($actualText -match 'real_entry_behavior|controller|processor|handler') { return $true } }
            'state|side.*effect|transaction|db|database|persist|rollback' { if ($actualText -match 'stateful_side_effect|transaction') { return $true } }
            'wire|payload|api|json|schema|dto' { if ($actualText -match 'wire_payload|payload_shape|api_contract|controller') { return $true } }
            'export|page|report|display|download' { if ($actualText -match 'export_output|controller') { return $true } }
            'artifact|template|render|image|upload|file' { if ($actualText -match 'rendered_artifact|template_render') { return $true } }
            'cleanup|retention|lifecycle' { if ($actualText -match 'lifecycle_cleanup|stateful_side_effect') { return $true } }
            'integration|external' { if ($actualText -match 'integration|wire_payload') { return $true } }
        }
    }
    return $false
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
$sliceResultFull = Resolve-AbsolutePath $SliceResult
$verifyPath = Join-Path $replayRootFull ('SLICE_VERIFY_{0:D2}.json' -f $SliceIndex)
$familyContractPath = Join-Path $replayRootFull 'FAMILY_CONTRACT.json'
$carrierAuthorizationPath = Join-Path $replayRootFull ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
$exactContractMatrixPath = Join-Path $replayRootFull ('EXACT_CONTRACT_ASSERTION_MATRIX_{0:D2}.json' -f $SliceIndex)
$sideEffectEvidencePath = Join-Path $replayRootFull ('SIDE_EFFECT_EVIDENCE_{0:D2}.json' -f $SliceIndex)
$sourceChainContractPath = Join-Path $replayRootFull 'SOURCE_CHAIN_CONTRACT.json'

if ($ValidateOnly) {
    [pscustomobject]@{
        status = 'VALID'
        replay_root = $replayRootFull
        worktree = $worktreeFull
        slice_result = $sliceResultFull
        verify_path = $verifyPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$familyContracts = Read-FamilyContract -Path $familyContractPath
$carrierAuthorization = $null
$exactContractMatrix = $null
$sideEffectEvidenceFile = $null
$sourceChainContract = $null

if (Test-Path -LiteralPath $carrierAuthorizationPath) {
    try { $carrierAuthorization = Read-JsonObject -Path $carrierAuthorizationPath } catch { $warnings.Add("carrier_authorization_json_invalid") }
} elseif (Test-Path -LiteralPath (Join-Path $replayRootFull 'CARRIER_AUTHORIZATION.json')) {
    try { $carrierAuthorization = Read-JsonObject -Path (Join-Path $replayRootFull 'CARRIER_AUTHORIZATION.json') } catch { $warnings.Add("carrier_authorization_json_invalid") }
}
if (Test-Path -LiteralPath $exactContractMatrixPath) {
    try { $exactContractMatrix = Read-JsonObject -Path $exactContractMatrixPath } catch { $warnings.Add("exact_contract_matrix_json_invalid") }
} elseif (Test-Path -LiteralPath (Join-Path $replayRootFull 'EXACT_CONTRACT_ASSERTION_MATRIX.json')) {
    try { $exactContractMatrix = Read-JsonObject -Path (Join-Path $replayRootFull 'EXACT_CONTRACT_ASSERTION_MATRIX.json') } catch { $warnings.Add("exact_contract_matrix_json_invalid") }
}
if (Test-Path -LiteralPath $sideEffectEvidencePath) {
    try { $sideEffectEvidenceFile = Read-JsonObject -Path $sideEffectEvidencePath } catch { $warnings.Add("side_effect_evidence_json_invalid") }
} elseif (Test-Path -LiteralPath (Join-Path $replayRootFull 'SIDE_EFFECT_EVIDENCE.json')) {
    try { $sideEffectEvidenceFile = Read-JsonObject -Path (Join-Path $replayRootFull 'SIDE_EFFECT_EVIDENCE.json') } catch { $warnings.Add("side_effect_evidence_json_invalid") }
}
if (Test-Path -LiteralPath $sourceChainContractPath) {
    try { $sourceChainContract = Read-JsonObject -Path $sourceChainContractPath } catch { $warnings.Add("source_chain_contract_json_invalid") }
}
$planLockText = @(
    (Read-TextIfExists -Path (Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md')),
    (Read-TextIfExists -Path (Join-Path $replayRootFull 'IMPLEMENTATION_CONTRACT.md'))
) -join "`n"
$plannedFirstRedTest = Get-PlanField -Text $planLockText -Name 'first_red_test'
$plannedSelectedCarrier = Get-PlanField -Text $planLockText -Name 'selected_carrier'
$plannedSelectedEntry = Get-PlanField -Text $planLockText -Name 'selected_real_entry'

if (-not (Test-Path -LiteralPath $sliceResultFull)) {
    $issues.Add("slice_result_missing")
    $result = $null
} else {
    try {
        $result = Read-JsonObject -Path $sliceResultFull
    } catch {
        $issues.Add("slice_result_json_invalid")
        $warnings.Add($_.Exception.Message)
        $result = $null
    }
}

$sliceStatus = ''
$sliceType = ''
$implementedFiles = @()
$currentSliceChangedFiles = @()
$roundChangedFilesSnapshot = @()
$tests = @()
$gapFlags = @()
$coverageDelta = $null
$nextRecommended = ''
$targetSubsurface = ''
$productionBoundary = ''
$proofKind = ''
$redExpectation = ''
$touchedFamilies = @()
$closedFamilies = @()
$resultEvidenceText = ''

if ($null -ne $result) {
    $sliceStatus = [string]$result.slice_status
    $sliceType = [string]$result.slice_type
    $implementedFiles = @(Get-StringArray $result.implemented_files)
    if ($result.PSObject.Properties.Name -contains 'current_slice_changed_files') {
        $currentSliceChangedFiles = @(Get-StringArray $result.current_slice_changed_files)
    }
    if ($result.PSObject.Properties.Name -contains 'round_changed_files_snapshot') {
        $roundChangedFilesSnapshot = @(Get-StringArray $result.round_changed_files_snapshot)
    }
    $gapFlags = @(Get-StringArray $result.gap_flags)
    $touchedFamilies = @(Get-StringArray $result.touched_requirement_families)
    $closedFamilies = @(Get-StringArray $result.closed_requirement_families)
    $nextRecommended = [string]$result.next_recommended_slice_type
    $targetSubsurface = [string]$result.target_subsurface_or_carrier
    $productionBoundary = [string]$result.production_boundary
    $proofKind = [string]$result.proof_kind
    $redExpectation = [string]$result.red_expectation
    $resultEvidenceText = ($result | ConvertTo-Json -Depth 12)
    if ($null -ne $result.coverage_delta -and "$($result.coverage_delta)" -match '^[0-9]+$') {
        $coverageDelta = [int]$result.coverage_delta
    }
    if ($null -ne $result.tests) {
        if ($result.tests -is [System.Array]) { $tests = @($result.tests) } else { $tests = @($result.tests) }
    }
}

if ([string]::IsNullOrWhiteSpace($sliceStatus)) { $issues.Add("slice_status_missing") }
if ([string]::IsNullOrWhiteSpace($sliceType)) { $warnings.Add("slice_type_missing") }
if ($implementedFiles.Count -eq 0 -and $sliceStatus -notmatch 'BLOCKED|INVALID') { $warnings.Add("implemented_files_empty") }
if ($tests.Count -eq 0 -and $sliceStatus -notmatch 'BLOCKED|INVALID') { $warnings.Add("tests_empty") }
if ($sliceStatus -eq 'DONE') {
    if ([string]::IsNullOrWhiteSpace($targetSubsurface)) { $warnings.Add("target_subsurface_missing") }
    if ([string]::IsNullOrWhiteSpace($productionBoundary)) { $warnings.Add("production_boundary_missing") }
    if ([string]::IsNullOrWhiteSpace($proofKind)) { $warnings.Add("proof_kind_missing") }
    if ([string]::IsNullOrWhiteSpace($redExpectation)) { $warnings.Add("red_expectation_missing") }
    if ($proofKind -eq 'static_contract') { $warnings.Add("static_contract_cannot_close_family_alone") }
}
if ($gapFlags -contains 'tracer_bullet_only' -and [string]::IsNullOrWhiteSpace($nextRecommended)) {
    $issues.Add("tracer_bullet_without_next_slice")
}

$statusOutput = (& git -C $worktreeFull status --short 2>&1 | Out-String).Trim()
$changedFiles = @()
if (-not [string]::IsNullOrWhiteSpace($statusOutput)) {
    $changedFiles = $statusOutput -split "`r?`n" | ForEach-Object {
        if ($_ -match '^\s*(..)\s+(.+)$') { $matches[2].Trim() } else { $_.Trim() }
    }
}
if ($roundChangedFilesSnapshot.Count -eq 0) {
    $roundChangedFilesSnapshot = @($changedFiles)
}
if ($currentSliceChangedFiles.Count -eq 0) {
    if ($SliceIndex -eq 1) {
        $currentSliceChangedFiles = @($changedFiles)
    } elseif ($implementedFiles.Count -gt 0) {
        $currentSliceChangedFiles = @($implementedFiles)
    }
}

$testCommands = @()
$redTests = @()
$redFailed = $false
$redPassed = $false
$redBlocked = $false
$greenOrVerifyPassed = $false
foreach ($test in $tests) {
    if ($null -ne $test.command) {
        $testCommands += [string]$test.command
    } elseif ($test -is [string]) {
        $testCommands += [string]$test
    }

    if ($null -ne $test.phase -and ([string]$test.phase).ToUpperInvariant() -eq 'RED') {
        $redTests += $test
        if ($null -ne $test.result -and ([string]$test.result).ToLowerInvariant() -eq 'fail') {
            $redFailed = $true
        }
        if ($null -ne $test.result -and ([string]$test.result).ToLowerInvariant() -eq 'pass') {
            $redPassed = $true
        }
        if ($null -ne $test.result -and ([string]$test.result).ToLowerInvariant() -eq 'blocked') {
            $redBlocked = $true
        }
    }
    if ($null -ne $test.phase -and @('GREEN', 'VERIFY') -contains ([string]$test.phase).ToUpperInvariant() -and
        $null -ne $test.result -and ([string]$test.result).ToLowerInvariant() -eq 'pass') {
        $greenOrVerifyPassed = $true
    }
}

$isExecutorBlockedSlice = (
    $sliceStatus -match 'BLOCKED|INVALID' -or
    $gapFlags -contains 'tooling_executor_failed' -or
    [string]$targetSubsurface -match '(?i)^executor:'
)
$hasBehaviorEvidence = $testCommands.Count -gt 0 -and -not $isExecutorBlockedSlice
$hasTrackedOrUntrackedDiff = $currentSliceChangedFiles.Count -gt 0
$forceCurrentSliceNoDiffStop = $implementedFiles.Count -eq 0 -and -not $hasTrackedOrUntrackedDiff
if ($forceCurrentSliceNoDiffStop) {
    $warnings.Add('current_slice_diff_missing') | Out-Null
    if ($gapFlags -notcontains 'no_progress_slice') { $gapFlags += 'no_progress_slice' }
    $coverageDelta = 0
}
$isCoreEntrySlice = ($touchedFamilies -contains 'core_entry') -or ($closedFamilies -contains 'core_entry') -or ([string]$targetSubsurface -match '(?i)\b(entry|handler|processor|callback|route|controller)\b')
$hasStatefulGap = @('side_effect_ledger_gap', 'needs_transaction_test', 'core_entry_unclosed') | Where-Object { $gapFlags -contains $_ }
$hasSurfaceGap = @('executable_surface_slice_gap', 'surface_budget_gap', 'deploy_surface_lock_gap', 'deploy_surface_contract_gap', 'external_integration_sibling_gap', 'family_sibling_gap') | Where-Object { $gapFlags -contains $_ }
$hasExactGap = @('exact_contract_gap') | Where-Object { $gapFlags -contains $_ }
$hasNoProgressSignal = $isExecutorBlockedSlice -or ($implementedFiles.Count -eq 0 -and $sliceStatus -notmatch 'BLOCKED|INVALID') -or ($gapFlags -contains 'no_progress_slice')
$hasTddRedNotReplayed = $gapFlags -contains 'tdd_red_not_replayed'
$hasRedPhaseDidNotFail = $redTests.Count -gt 0 -and -not $redFailed -and -not $isExecutorBlockedSlice
$implementedProductionPathCount = @($implementedFiles | Where-Object { [string]$_ -notmatch '(^|/)src/test/|(^|\\)src\\test\\|Test\.java$|/test/|\\test\\' }).Count
$hasImplementationAfterBlockedRed = $redBlocked -and -not $redFailed -and (($implementedFiles.Count -gt 0) -or ($currentSliceChangedFiles.Count -gt 0))
$closedAssertionCount = @(Get-StringArray $result.closed_assertions).Count
$closedExactCount = if ($null -ne $result -and $null -ne $result.exact_contract_assertions) {
    @($result.exact_contract_assertions | Where-Object { [string]$_.status -eq 'CLOSED' }).Count
} else { 0 }
$alreadyImplementedEvidenceSlice = (
    $sliceStatus -eq 'PARTIAL' -and
    $redPassed -and
    $greenOrVerifyPassed -and
    $implementedProductionPathCount -eq 0 -and
    ($closedAssertionCount -gt 0 -or $closedExactCount -gt 0) -and
    $resultEvidenceText -match '(?i)No new production diff|current baseline|existing|already|strengthens existing'
)
if ($alreadyImplementedEvidenceSlice) {
    $gapFlags = @($gapFlags | Where-Object {
        @('tdd_red_not_replayed', 'feedback_loop_blocker', 'wrong_test_surface', 'side_effect_red_not_business_assertion', 'side_effect_evidence_missing', 'tooling_enforcement_stop') -notcontains [string]$_
    })
    if ($gapFlags -notcontains 'already_implemented_evidence_slice') { $gapFlags += 'already_implemented_evidence_slice' }
    $hasTddRedNotReplayed = $false
    $hasRedPhaseDidNotFail = $false
    $warnings.Add('already_implemented_evidence_slice') | Out-Null
}

if ($hasRedPhaseDidNotFail) {
    $warnings.Add("red_phase_did_not_fail")
}
if ($sliceStatus -eq 'DONE' -and $redTests.Count -eq 0) {
    $warnings.Add("red_phase_missing")
}
if ($redPassed) {
    $warnings.Add("red_phase_passed_before_fix")
}
if ($hasTddRedNotReplayed) {
    $warnings.Add("tdd_red_not_replayed")
}
if ($hasImplementationAfterBlockedRed) {
    $warnings.Add("implementation_after_blocked_red")
    if ($gapFlags -notcontains 'implementation_after_blocked_red') { $gapFlags += 'implementation_after_blocked_red' }
    if ($gapFlags -notcontains 'tdd_red_not_replayed') { $gapFlags += 'tdd_red_not_replayed' }
    if ($gapFlags -notcontains 'tooling_enforcement_stop') { $gapFlags += 'tooling_enforcement_stop' }
}
if ($hasNoProgressSignal) {
    $warnings.Add("no_progress_slice")
    if ($gapFlags -notcontains 'no_progress_slice') {
        $gapFlags += 'no_progress_slice'
    }
}

$blockingSiblingSurfaces = @()
foreach ($family in $closedFamilies) {
    $blockingSiblingSurfaces += @(Get-FamilySiblingSurfaces -Value $result.required_sibling_surfaces -FamilyId ([string]$family) -TouchedFamilies $touchedFamilies)
}
if ($sliceStatus -eq 'DONE' -and $closedFamilies.Count -gt 0 -and $blockingSiblingSurfaces.Count -gt 0) {
    $warnings.Add("family_sibling_surface_open")
    if ($gapFlags -notcontains 'family_sibling_gap') {
        $gapFlags += 'family_sibling_gap'
    }
}

$productionImplementedFiles = @($implementedFiles | Where-Object { $_ -notmatch '(^|/)src/test/|(^|\\)src\\test\\|Test\.java$|/test/|\\test\\' })
$testImplementedFiles = @($implementedFiles | Where-Object { $_ -match '(^|/)src/test/|(^|\\)src\\test\\|Test\.java$|/test/|\\test\\' })
$productionImplementedText = (($productionImplementedFiles | ForEach-Object { Read-WorktreeText -Root $worktreeFull -RelativePath $_ }) -join "`n")
$testImplementedText = (($testImplementedFiles | ForEach-Object { Read-WorktreeText -Root $worktreeFull -RelativePath $_ }) -join "`n")

# v370 TODO Blocker Enforcement: Scan production code for TODO placeholders
$todoCount = 0
$todoFiles = @{}
foreach ($file in $productionImplementedFiles) {
    $filePath = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $worktreeFull ($file -replace '/', [System.IO.Path]::DirectorySeparatorChar) }
    if (Test-Path -LiteralPath $filePath) {
        $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
        $todos = [regex]::Matches($content, '\bTODO\b')
        if ($todos.Count -gt 0) {
            $todoCount += $todos.Count
            $todoFiles[$file] = $todos.Count
        }
    }
}
if ($todoCount -gt 0) {
    $warnings.Add("production_code_contains_TODO_placeholders")
    if ($gapFlags -notcontains 'todo_placeholder_exists') { $gapFlags += 'todo_placeholder_exists' }
    $hasShallowModule = @('shallow_module') | Where-Object { $gapFlags -contains $_ }
    if ($hasShallowModule.Count -eq 0) { $gapFlags += 'shallow_module' }
    foreach ($file in $todoFiles.GetEnumerator()) {
        $warnings.Add("  $($file.Key): $($file.Value) TODO(s)")
    }
}

$highWeightFamilyIds = @(
    'core_entry',
    'stateful_side_effect',
    'deploy_export_page',
    'wire_payload_api_contract',
    'config_policy_threshold',
    'generated_artifact_template_upload',
    'external_integration',
    'automation_test_interface',
    'lifecycle_cleanup_retention'
)
$highWeightTouchedFamilies = @(@($touchedFamilies + $closedFamilies) | Where-Object { $highWeightFamilyIds -contains [string]$_ } | Select-Object -Unique)
$behaviorCharter = $null
if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'behavior_test_charter') {
    $behaviorCharter = $result.behavior_test_charter
}
$behaviorCharterRequired = $highWeightTouchedFamilies.Count -gt 0 -and $sliceStatus -notmatch 'BLOCKED|INVALID'
$behaviorCharterReady = $false
if ($behaviorCharterRequired) {
    $missingCharterFields = New-Object System.Collections.Generic.List[string]
    if ($null -eq $behaviorCharter) {
        $warnings.Add('behavior_test_charter_missing') | Out-Null
        $missingCharterFields.Add('behavior_test_charter') | Out-Null
    } else {
        foreach ($fieldName in @('proof_kind', 'production_entry', 'state_or_output', 'must_not', 'RED_command', 'expected_RED_failure', 'GREEN_command', 'evidence_file')) {
            $fieldValue = Get-ObjectStringValue $behaviorCharter $fieldName
            if ([string]::IsNullOrWhiteSpace($fieldValue)) {
                $missingCharterFields.Add($fieldName) | Out-Null
            }
        }
        $charterText = ($behaviorCharter | ConvertTo-Json -Depth 8)
        if ($charterText -match '(?i)\b(mock-only|helper-only|static-only|file_presence_only|mapper-presence-only|Noop|Stub|Fake|Dummy|Placeholder|InMemory|TestOnly|Scaffold)\b') {
            $warnings.Add('behavior_test_charter_non_authorizing') | Out-Null
            $missingCharterFields.Add('authorizing_behavior_boundary') | Out-Null
        }
    }
    if ($missingCharterFields.Count -gt 0) {
        foreach ($flag in @('behavior_test_charter_gap', 'wrong_test_surface', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    } else {
        $behaviorCharterReady = $true
    }
}
$carrierStart = $targetSubsurface
$carrierOrigin = 'declared_or_real_carrier'
$nextRequiredSlice = $null
if ($null -ne $sourceChainContract -and [bool]$sourceChainContract.required_source_chain) {
    $nextRequiredSlice = $sourceChainContract.next_required_slice
    $mustTouchFiles = @()
    if ($null -ne $nextRequiredSlice) {
        $mustTouchFiles = @(Get-StringArray $nextRequiredSlice.must_touch_files)
    }
    $sourceChainTouched = @($implementedFiles | Where-Object {
        $impl = [string]$_
        @($mustTouchFiles | Where-Object {
            $leaf = [System.IO.Path]::GetFileName([string]$_)
            -not [string]::IsNullOrWhiteSpace($leaf) -and $impl.IndexOf($leaf, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        }).Count -gt 0
    })
    $syntheticSourceCarrier = (
        $testImplementedText -match '(?i)setFieldIfPresent|setRequiredField|java\.lang\.reflect\.Field|new\s+AiApplyClaimTaskData|new\s+AiCalculateLossTaskData|hand[- ]?built|manual(?:ly)?\s+injected' -or
        $resultEvidenceText -match '(?i)hand[- ]?built task data|manually injected|when values already exist on task data|terminal payload'
    )
    $terminalOnly = $sourceChainTouched.Count -eq 0 -and (
        $implementedFiles -match 'AiApplyClaimApiTaskProcessor|AiCalculateLossApiTaskProcessor|AiClaimBaseTaskData|AIClaimConstant'
    )
    if ($syntheticSourceCarrier -or $terminalOnly) {
        $carrierOrigin = 'synthetic_carrier'
        $carrierStart = 'downstream_terminal_payload_or_hand_built_task_data'
        foreach ($flag in @('wrong_test_surface', 'shallow_module', 'synthetic_carrier_gap', 'source_chain_unclosed')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $warnings.Add('synthetic_carrier_for_named_source_chain') | Out-Null
        $hasBehaviorEvidence = $false
    }
}
if ($sliceStatus -eq 'DONE' -and $closedFamilies.Count -gt 0 -and $productionImplementedFiles.Count -eq 0) {
    $warnings.Add("production_carrier_missing")
    if ($gapFlags -notcontains 'wrong_test_surface') {
        $gapFlags += 'wrong_test_surface'
    }
}

$trackedProductionImplementedFiles = New-Object System.Collections.Generic.List[string]
foreach ($file in $productionImplementedFiles) {
    $trackedMatch = @(& git -C $worktreeFull ls-files -- $file 2>$null)
    if (@($trackedMatch | Where-Object { [string]$_ -eq [string]$file }).Count -gt 0) {
        $trackedProductionImplementedFiles.Add([string]$file) | Out-Null
    }
}

$trackedChangedProductionFiles = New-Object System.Collections.Generic.List[string]
foreach ($file in $changedFiles) {
    $text = [string]$file
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    if ($text -match '(^|/)src/test/|(^|\\)src\\test\\|Test\.java$|/test/|\\test\\') { continue }
    $trackedMatch = @(& git -C $worktreeFull ls-files -- $text 2>$null)
    if (@($trackedMatch | Where-Object { [string]$_ -eq $text }).Count -gt 0) {
        $trackedChangedProductionFiles.Add($text) | Out-Null
    }
}

$statefulDomainCarrierText = @($productionImplementedText, $productionBoundary, $resultEvidenceText) -join "`n"
$statefulNewCarrierLooksDomainReal = (
    ($closedFamilies -contains 'stateful_side_effect') -and
    $productionImplementedFiles.Count -gt 0 -and
    ($statefulDomainCarrierText -match '(?i)\b(mapper|service|insert|update|save|persist|complete|process|progress|status|task|log|transaction|rollback)\b') -and
    ($statefulDomainCarrierText -match '(?i)\b(must-not|must_not|failure|exception|isolation|no\s+case\s+progress|does\s+not)\b')
)

if ($sliceStatus -eq 'DONE' -and ($closedFamilies -contains 'core_entry') -and
    $trackedProductionImplementedFiles.Count -eq 0 -and $trackedChangedProductionFiles.Count -eq 0) {
    $warnings.Add("existing_production_carrier_missing")
    if ($gapFlags -notcontains 'shallow_module') {
        $gapFlags += 'shallow_module'
    }
}
if ($sliceStatus -eq 'DONE' -and ($closedFamilies -contains 'stateful_side_effect') -and
    $trackedProductionImplementedFiles.Count -eq 0 -and -not $statefulNewCarrierLooksDomainReal) {
    $warnings.Add("existing_production_carrier_missing")
    if ($gapFlags -notcontains 'shallow_module') {
        $gapFlags += 'shallow_module'
    }
}

$syntheticCarrierRegex = '(?i)(^|[\\/])[^\\/]*(Noop|Stub|Fake|Dummy|Placeholder|Mock|InMemory|TestOnly|Scaffold)[^\\/]*\.(java|kt|cs|ts|js|py|go)$'
$syntheticCarrierEvidence = @(
    $productionImplementedFiles | Where-Object { [string]$_ -match $syntheticCarrierRegex }
) + @(
    @($targetSubsurface, $productionBoundary) | Where-Object { [string]$_ -match '(?i)\b(Noop|Stub|Fake|Dummy|Placeholder|Mock|InMemory|TestOnly|Scaffold)\b' }
)
$highWeightCarrierTouched = @('core_entry', 'stateful_side_effect', 'generated_artifact_template_upload') | Where-Object {
    ($touchedFamilies -contains $_) -or ($closedFamilies -contains $_)
}
if ($highWeightCarrierTouched.Count -gt 0 -and @($syntheticCarrierEvidence).Count -gt 0) {
    $warnings.Add("synthetic_production_carrier")
    foreach ($flag in @('shallow_module', 'wrong_test_surface', 'synthetic_carrier_gap')) {
        if ($gapFlags -notcontains $flag) {
            $gapFlags += $flag
        }
    }
}

$emptyMethodRegex = '(?s)\b(protected|public|private)\s+(?:[\w<>\[\],?]+\s+)+\w+\s*\([^;{}]*\)\s*\{\s*(?:(?://[^\r\n]*(?:\r?\n)?\s*)|(?:/\*.*?\*/\s*))*\}'
$hasEmptyOrNoopProductionHook = $highWeightCarrierTouched.Count -gt 0 -and (
    $productionImplementedText -match $emptyMethodRegex -or
    $productionImplementedText -match '(?i)\b(no-op|noop|only\s+lands\s+the\s+.*hook|tracer\s+bullet.*hook|empty\s+hook)\b'
)
$primaryCarrierClass = ''
if ($null -ne $carrierAuthorization) {
    $primaryCarrierClass = Get-PrimaryCarrierClassName -Text ([string]$carrierAuthorization.selected_carrier)
    if ([string]::IsNullOrWhiteSpace($primaryCarrierClass)) {
        $primaryCarrierClass = Get-PrimaryCarrierClassName -Text ([string]$carrierAuthorization.real_entry)
    }
}
if ([string]::IsNullOrWhiteSpace($primaryCarrierClass)) {
    $primaryCarrierClass = Get-PrimaryCarrierClassName -Text $plannedSelectedCarrier
}
$subclassedClassNames = @(Get-SubclassedClassNames -Text $testImplementedText)
$counterProofText = @($testImplementedText, $resultEvidenceText) -join "`n"
$hasCounterProofSignal = $counterProofText -match '(?i)(invokeCount|autoFlowInvokeCount|counter|get\w*Count|assertEquals\s*\(\s*\d+\s*,\s*\w+\.get\w*Count)'
$subclassesPrimaryCarrier = -not [string]::IsNullOrWhiteSpace($primaryCarrierClass) -and (@($subclassedClassNames | Where-Object { [string]$_ -eq $primaryCarrierClass }).Count -gt 0)
$hasSubclassCounterProof = $highWeightCarrierTouched.Count -gt 0 -and (
    (
        $subclassesPrimaryCarrier -and
        $testImplementedText -match '(?s)@Override' -and
        $hasCounterProofSignal
    ) -or
    $resultEvidenceText -match '(?i)(subclass\s+counter|override\s+count|testable\s+subclass|subclass-only)'
)
$hasDependencySpyCounterProof = $highWeightCarrierTouched.Count -gt 0 -and -not $hasSubclassCounterProof -and
    $subclassedClassNames.Count -gt 0 -and $testImplementedText -match '(?s)@Override' -and $hasCounterProofSignal
$hasSubstituteProof = $hasEmptyOrNoopProductionHook -or $hasSubclassCounterProof
if ($hasEmptyOrNoopProductionHook) {
    $warnings.Add("empty_or_noop_production_carrier")
}
if ($hasSubclassCounterProof) {
    $warnings.Add("subclass_only_proof")
}
if ($hasDependencySpyCounterProof) {
    $warnings.Add("dependency_spy_counter_proof")
    if ($gapFlags -notcontains 'dependency_spy_output_gap') {
        $gapFlags += 'dependency_spy_output_gap'
    }
}
if ($hasSubstituteProof) {
    $warnings.Add("tooling_enforcement_stop")
    $hasBehaviorEvidence = $false
    foreach ($flag in @('wrong_test_surface', 'synthetic_carrier_gap', 'shallow_module', 'tooling_enforcement_stop')) {
        if ($gapFlags -notcontains $flag) {
            $gapFlags += $flag
        }
    }
}

$carrierAuthorizationRequired = $touchedFamilies.Count -gt 0 -or $closedFamilies.Count -gt 0 -or $sliceStatus -notmatch 'BLOCKED|INVALID'
if ($carrierAuthorizationRequired -and $null -eq $carrierAuthorization) {
    $warnings.Add("carrier_authorization_missing")
    foreach ($flag in @('carrier_authorization_missing', 'tooling_enforcement_stop')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
    $hasBehaviorEvidence = $false
}
if ($null -ne $carrierAuthorization) {
    $carrierIssues = @(Get-StringArray $carrierAuthorization.issues)
    if ([string]$carrierAuthorization.authorization -ne 'ALLOW') {
        $warnings.Add("carrier_authorization_stop")
        foreach ($flag in @('carrier_authorization_stop', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$carrierAuthorization.selected_carrier)) {
        $warnings.Add("selected_carrier_missing")
        foreach ($flag in @('carrier_authorization_missing', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$carrierAuthorization.downstream_side_effect_or_output)) {
        $warnings.Add("downstream_side_effect_or_output_missing")
        foreach ($flag in @('side_effect_ledger_gap', 'executable_surface_slice_gap', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
    if ([bool]$carrierAuthorization.forbidden_synthetic_carrier -or ($carrierIssues -contains 'synthetic_carrier_selected')) {
        $warnings.Add("carrier_authorization_synthetic_carrier")
        foreach ($flag in @('synthetic_carrier_gap', 'shallow_module', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
    if ([bool]$carrierAuthorization.forbidden_helper_only_carrier -or ($carrierIssues -contains 'helper_or_static_only_carrier_for_high_weight_family')) {
        $warnings.Add("carrier_authorization_helper_only")
        foreach ($flag in @('wrong_test_surface', 'shallow_module', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
}

$behaviorCarrierFacadePath = Join-Path $replayRootFull 'BEHAVIOR_CARRIER_FACADE_VALIDATION.json'
$behaviorCarrierFacadeValidation = $null
$bcfvScript = Join-Path $PSScriptRoot 'Validate-BehaviorCarrierFacade.ps1'
if (Test-Path -LiteralPath $bcfvScript) {
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $bcfvScript -ReplayRoot $replayRootFull -Mode DryRun 2>$null | Out-Null
        if (Test-Path -LiteralPath $behaviorCarrierFacadePath) {
            $behaviorCarrierFacadeValidation = Read-JsonObject -Path $behaviorCarrierFacadePath
        }
    } catch {
        $warnings.Add("behavior_carrier_facade_validation_error") | Out-Null
    }
}
if ($null -ne $behaviorCarrierFacadeValidation -and [string]$behaviorCarrierFacadeValidation.status -eq 'BLOCKED') {
    $bcfvIssues = @($behaviorCarrierFacadeValidation.issues)
    $bcfvIssueTypes = @($bcfvIssues | ForEach-Object { [string]$_.issue } | Select-Object -Unique)
    if ($bcfvIssueTypes -contains 'data_only_carrier_for_behavior_requirement') {
        $warnings.Add("data_only_carrier_for_behavior_requirement") | Out-Null
        foreach ($flag in @('wrong_test_surface', 'behavior_carrier_gap', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
    if ($bcfvIssueTypes -contains 'facade_direction_not_exhaustively_searched') {
        $warnings.Add("facade_direction_not_exhaustively_searched") | Out-Null
        foreach ($flag in @('carrier_authorization_stop', 'facade_direction_gap', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
    if ($bcfvIssueTypes -contains 'downstream_behavior_without_behavior_carrier') {
        $warnings.Add("downstream_behavior_without_behavior_carrier") | Out-Null
        foreach ($flag in @('wrong_test_surface', 'behavior_carrier_gap', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
    if ($bcfvIssueTypes -contains 'side_effect_entry_is_data_only_for_behavior') {
        $warnings.Add("side_effect_entry_is_data_only_for_behavior") | Out-Null
        foreach ($flag in @('side_effect_evidence_missing', 'behavior_carrier_gap', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
    if ($bcfvIssueTypes -contains 'slice_result_carrier_is_data_only_for_behavior') {
        $warnings.Add("slice_result_carrier_is_data_only_for_behavior") | Out-Null
        foreach ($flag in @('wrong_test_surface', 'behavior_carrier_gap', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
}

$exactContractFamilies = @(
    'wire_payload_api_contract',
    'config_policy_threshold',
    'deploy_export_page',
    'generated_artifact_template_upload',
    'external_integration',
    'automation_test_interface',
    'lifecycle_cleanup_retention'
)
$touchedOrClosedFamilies = @(($touchedFamilies + $closedFamilies) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
$exactContractTouched = @($touchedOrClosedFamilies | Where-Object { $exactContractFamilies -contains [string]$_ }).Count -gt 0
$exactContractRequiredForThisSlice = $null -ne $carrierAuthorization -and [bool]$carrierAuthorization.requires_exact_contract_assertions
if ($exactContractRequiredForThisSlice) { $exactContractTouched = $true }
$resultExactAssertions = @()
if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'exact_contract_assertions') {
    if ($null -ne $result.exact_contract_assertions) {
        if ($result.exact_contract_assertions -is [System.Array]) { $resultExactAssertions = @($result.exact_contract_assertions) } else { $resultExactAssertions = @($result.exact_contract_assertions) }
    }
}
$matrixRows = @()
if ($null -ne $exactContractMatrix -and $null -ne $exactContractMatrix.rows) {
    if ($exactContractMatrix.rows -is [System.Array]) { $matrixRows = @($exactContractMatrix.rows) } else { $matrixRows = @($exactContractMatrix.rows) }
}
$closedExactAssertions = @($resultExactAssertions | Where-Object { @('CLOSED', 'BLOCKED') -contains ([string]$_.status).ToUpperInvariant() })
$closedMatrixRows = @($matrixRows | Where-Object { [bool]$_.touched -and @('CLOSED', 'BLOCKED') -contains ([string]$_.status).ToUpperInvariant() })
$autopilotRunPath = Join-Path $replayRootFull 'AUTOPILOT_RUN.json'
$requirementText = ''
if (Test-Path -LiteralPath $autopilotRunPath) {
    try {
        $autopilotRun = Read-JsonObject -Path $autopilotRunPath
        $requirementSource = [string]$autopilotRun.requirement_source
        if (-not [string]::IsNullOrWhiteSpace($requirementSource) -and (Test-Path -LiteralPath $requirementSource)) {
            $requirementText = Read-TextIfExists -Path $requirementSource
        }
    } catch {
        $warnings.Add('requirement_source_unreadable_for_exact_predicate_check') | Out-Null
    }
}
$extraPredicateHits = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($requirementText)) {
    foreach ($assertion in $closedExactAssertions) {
        $assertionIntent = @(
            [string]$assertion.literal,
            [string]$assertion.test_assertion
        ) -join ' '
        if ($assertionIntent -match '(?i)\b(ordinary|normal|unchanged|preserve|preserves|compatibility|existing)\b') { continue }
        $assertionPredicateText = @(
            [string]$assertion.literal,
            [string]$assertion.symbol_or_field,
            [string]$assertion.test_assertion,
            [string]$assertion.production_predicate,
            [string]$assertion.forbidden_extra_predicate
        ) -join "`n"
        $candidatePredicates = [regex]::Matches($assertionPredicateText, '(?i)\b(?:CaseStatusType\.)?[A-Z][A-Z0-9_]{2,}\b|\bstatusId\b|\bcaseStatus\b|\b状态\b') | ForEach-Object { $_.Value } | Select-Object -Unique
        $candidatePredicates = @($candidatePredicates | Where-Object {
            $_ -match 'CaseStatusType\.|statusId|caseStatus|DSH|YSH|WAIT|STATUS|TASK_STATUS|CASE_STATUS'
        } | Select-Object -Unique)
        foreach ($predicate in $candidatePredicates) {
            $normalizedPredicate = [string]$predicate
            if ($normalizedPredicate -match '^(?i)(TRUE|FALSE|PASS|FAIL|DONE|OPEN|CLOSED|PARTIAL|BLOCKED|RED|GREEN|BUILD|SUCCESS|NULL)$') { continue }
            if ($normalizedPredicate -match '^(?i)(SCSCDSH|YBJDSH)$') { continue }
            if ($requirementText -notmatch [regex]::Escape($normalizedPredicate)) {
                $extraPredicateHits.Add($normalizedPredicate) | Out-Null
            }
        }
    }
}
if ($extraPredicateHits.Count -gt 0) {
    $warnings.Add('unproven_extra_requirement_predicate') | Out-Null
    foreach ($flag in @('exact_contract_gap', 'provisional_exact_contract_gap')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
}
if ($closedExactAssertions.Count -gt 0 -and $matrixRows.Count -gt 0) {
    foreach ($assertion in $closedExactAssertions) {
        $literal = [string]$assertion.literal
        $symbol = [string]$assertion.symbol_or_field
        $assertionText = [string]$assertion.test_assertion
        $status = ([string]$assertion.status).ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($status)) { $status = 'CLOSED' }
        $matched = $false
        foreach ($row in $matrixRows) {
            $rowLiteral = [string]$row.literal
            $rowSymbol = [string]$row.symbol_or_field
            if ((-not [string]::IsNullOrWhiteSpace($literal) -and $rowLiteral -eq $literal) -or
                (-not [string]::IsNullOrWhiteSpace($symbol) -and $rowSymbol -eq $symbol) -or
                (-not [string]::IsNullOrWhiteSpace($literal) -and $rowSymbol -eq $literal) -or
                (-not [string]::IsNullOrWhiteSpace($symbol) -and $rowLiteral -eq $symbol)) {
                $row.touched = $true
                $row.status = $status
                if (-not [string]::IsNullOrWhiteSpace($assertionText)) {
                    $row.test_assertion = $assertionText
                }
                if ($assertion.PSObject.Properties.Name -contains 'db_or_wire_or_display' -and -not [string]::IsNullOrWhiteSpace([string]$assertion.db_or_wire_or_display)) {
                    $row.db_or_wire_or_display = [string]$assertion.db_or_wire_or_display
                }
                if ($assertion.PSObject.Properties.Name -contains 'source_type' -and -not [string]::IsNullOrWhiteSpace([string]$assertion.source_type)) {
                    $row.source_type = [string]$assertion.source_type
                }
                foreach ($boundaryField in @('boundary_type', 'production_boundary', 'closure_proof')) {
                    $boundaryValue = Get-ObjectString $assertion $boundaryField
                    if (-not [string]::IsNullOrWhiteSpace($boundaryValue)) {
                        if ($row.PSObject.Properties.Name -contains $boundaryField) {
                            $row.$boundaryField = $boundaryValue
                        } else {
                            $row | Add-Member -NotePropertyName $boundaryField -NotePropertyValue $boundaryValue
                        }
                    }
                }
                $matched = $true
            }
        }
        if (-not $matched) {
            $matrixRows += [pscustomobject]@{
                literal = $literal
                symbol_or_field = $symbol
                db_or_wire_or_display = [string]$assertion.db_or_wire_or_display
                boundary_type = (Get-ObjectString $assertion 'boundary_type')
                production_boundary = (Get-ObjectString $assertion 'production_boundary')
                closure_proof = (Get-ObjectString $assertion 'closure_proof')
                test_assertion = $assertionText
                status = $status
                touched = $true
                source_type = [string]$assertion.source_type
                derived_from_slice = $SliceIndex
            }
        }
    }
    $exactContractMatrix.rows = @($matrixRows)
    if ($exactContractMatrix.PSObject.Properties.Name -contains 'updated_by_verifier') {
        $exactContractMatrix.updated_by_verifier = $true
    } else {
        $exactContractMatrix | Add-Member -NotePropertyName 'updated_by_verifier' -NotePropertyValue $true
    }
    if ($exactContractMatrix.PSObject.Properties.Name -contains 'updated_slice_index') {
        $exactContractMatrix.updated_slice_index = $SliceIndex
    } else {
        $exactContractMatrix | Add-Member -NotePropertyName 'updated_slice_index' -NotePropertyValue $SliceIndex
    }
    $exactContractMatrix | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $exactContractMatrixPath -Encoding UTF8
    $genericExactPath = Join-Path $replayRootFull 'EXACT_CONTRACT_ASSERTION_MATRIX.json'
    $exactContractMatrix | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $genericExactPath -Encoding UTF8
    $closedMatrixRows = @($matrixRows | Where-Object { [bool]$_.touched -and @('CLOSED', 'BLOCKED') -contains ([string]$_.status).ToUpperInvariant() })
}

# v270: enforce a minimum exact-contract closure ratio when the slice is
# explicitly exact-contract-bearing. This converts a documented gate into a
# measurable stop condition instead of allowing one token assertion to stand in
# for the whole contract surface.
$matrixRequiresExactForThisSlice = $false
if ($null -ne $exactContractMatrix -and $exactContractMatrix.PSObject.Properties.Name -contains 'required_for_this_slice') {
    $matrixRequiresExactForThisSlice = [bool]$exactContractMatrix.required_for_this_slice
}
if (($exactContractRequiredForThisSlice -or $matrixRequiresExactForThisSlice) -and $matrixRows.Count -gt 0) {
    $requiredExactRows = @($matrixRows | Where-Object {
        ([bool]$_.touched) -or
        ($_.PSObject.Properties.Name -contains 'required' -and [bool]$_.required) -or
        ($_.PSObject.Properties.Name -contains 'required_for_this_slice' -and [bool]$_.required_for_this_slice)
    })
    if ($requiredExactRows.Count -eq 0) { $requiredExactRows = @($matrixRows) }
    $closedRequiredExactRows = @($requiredExactRows | Where-Object { ([string]$_.status).ToUpperInvariant() -eq 'CLOSED' })
    $exactClosurePercent = if ($requiredExactRows.Count -gt 0) { [math]::Floor(($closedRequiredExactRows.Count / $requiredExactRows.Count) * 100) } else { 100 }
    if ($exactClosurePercent -lt 50) {
        $warnings.Add("exact_contract_minimum_coverage_gap:$exactClosurePercent%<50%") | Out-Null
        foreach ($flag in @('exact_contract_minimum_coverage_gap', 'exact_contract_gap', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
}

$boundaryProofFailures = New-Object System.Collections.Generic.List[string]
$boundaryRowsToCheck = @($closedExactAssertions + $closedMatrixRows)
foreach ($row in $boundaryRowsToCheck) {
    $status = ([string]$row.status).ToUpperInvariant()
    if ($status -ne 'CLOSED') { continue }
    $surface = @(
        [string]$row.db_or_wire_or_display,
        [string]$row.boundary_type,
        [string]$row.literal,
        [string]$row.symbol_or_field
    ) -join ' '
    $requiresBoundary = $surface -match '(?i)\b(wire|db|database|display|payload|callback|exchange|queue|export|page|response|request)\b|_id\b|_amount\b'
    if (-not $requiresBoundary) { continue }
    $closureProof = [string]$row.closure_proof
    $productionBoundary = [string]$row.production_boundary
    $testAssertion = [string]$row.test_assertion
    $proofText = @($closureProof, $productionBoundary, $testAssertion) -join ' '
    $weakProof = [string]::IsNullOrWhiteSpace($closureProof) -or $proofText -match '(?i)\b(enum[-_ ]?only|dto[-_ ]?only|helper[-_ ]?only|static[-_ ]?only|mock[-_ ]?only|constant[-_ ]?only|presence[-_ ]?only)\b'
    $boundaryLooksExecutable = $proofText -match '(?i)\b(wire|payload|request|response|json|db|database|mapper|insert|update|display|export|download|controller|endpoint|callback|message|mq|queue|exchange|publish|render|template|artifact)\b'
    if ($weakProof -or -not $boundaryLooksExecutable) {
        $literalForFailure = [string]$row.literal
        if ([string]::IsNullOrWhiteSpace($literalForFailure)) { $literalForFailure = [string]$row.symbol_or_field }
        $boundaryProofFailures.Add($literalForFailure) | Out-Null
    }
}
if ($boundaryProofFailures.Count -gt 0) {
    $warnings.Add("exact_contract_boundary_proof_missing:$((@($boundaryProofFailures | Select-Object -Unique | Select-Object -First 5)) -join ',')") | Out-Null
    foreach ($flag in @('exact_contract_boundary_proof_missing', 'exact_contract_gap')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
    $hardBoundaryProofFailure = $exactContractRequiredForThisSlice -and $gapFlags -notcontains 'provisional_exact_contract_gap'
    if ($hardBoundaryProofFailure) {
        foreach ($flag in @('exact_contract_boundary_proof_stop', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
}
if ($exactContractTouched -and $closedExactAssertions.Count -eq 0 -and $closedMatrixRows.Count -eq 0) {
    $warnings.Add("exact_contract_assertion_missing")
    if ($exactContractRequiredForThisSlice) {
        foreach ($flag in @('exact_contract_assertion_missing', 'exact_contract_gap', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    } else {
        if ($gapFlags -notcontains 'opportunistic_exact_contract_overclaim') { $gapFlags += 'opportunistic_exact_contract_overclaim' }
    }
}
if ($exactContractTouched -and $gapFlags -contains 'exact_contract_gap') {
    $warnings.Add("exact_contract_open")
    if ($exactContractRequiredForThisSlice -and $gapFlags -notcontains 'provisional_exact_contract_gap') {
        if ($gapFlags -notcontains 'exact_contract_not_closed') {
            $gapFlags += 'exact_contract_not_closed'
        }
        $hasBehaviorEvidence = $false
    }
}

$sideEvidenceObject = $null
if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'side_effect_evidence' -and $null -ne $result.side_effect_evidence) {
    $sideEvidenceObject = $result.side_effect_evidence
} elseif ($null -ne $sideEffectEvidenceFile) {
    $sideEvidenceObject = $sideEffectEvidenceFile
}
$sideEffectEvidenceRequired = (
    (($touchedFamilies -contains 'stateful_side_effect') -or ($closedFamilies -contains 'stateful_side_effect') -or ([string]$targetSubsurface -match '(?i)state|task|progress|log|persist|transaction|rollback|database|db')) -or
    $isCoreEntrySlice -or
    ([string]$sliceType -match '(?i)stateful') -or
    ($null -ne $carrierAuthorization -and [bool]$carrierAuthorization.requires_side_effect_evidence)
)
$sideEvidenceComplete = $false
if ($null -ne $sideEvidenceObject) {
    $sideEntry = [string]$sideEvidenceObject.entry_call
    $sideExpected = @(Get-StringArray $sideEvidenceObject.expected_writes_or_outputs)
    $sideRed = ([string]$sideEvidenceObject.red_result).ToUpperInvariant()
    $sideGreen = ([string]$sideEvidenceObject.green_result).ToUpperInvariant()
    $sideStatus = ([string]$sideEvidenceObject.status).ToUpperInvariant()
    if ($sideEffectEvidenceRequired -and @('PLANNED', 'PENDING', '') -contains $sideStatus -and -not $alreadyImplementedEvidenceSlice) {
        $warnings.Add("side_effect_evidence_not_closed")
        if ($gapFlags -notcontains 'side_effect_evidence_missing') { $gapFlags += 'side_effect_evidence_missing' }
        if ($gapFlags -notcontains 'side_effect_ledger_gap') { $gapFlags += 'side_effect_ledger_gap' }
    }
    $sideRedAcceptable = $sideRed -eq 'BUSINESS_ASSERTION_FAILED' -or ($alreadyImplementedEvidenceSlice -and $sideGreen -eq 'PASS')
    $sideEvidenceComplete = (
        -not [string]::IsNullOrWhiteSpace($sideEntry) -and
        $sideExpected.Count -gt 0 -and
        $sideRedAcceptable -and
        $sideGreen -eq 'PASS'
    )
    if ($sideEffectEvidenceRequired -and $sideRed -ne 'BUSINESS_ASSERTION_FAILED' -and -not $alreadyImplementedEvidenceSlice) {
        $warnings.Add("side_effect_red_not_business_assertion")
        if ($gapFlags -notcontains 'side_effect_red_not_business_assertion') { $gapFlags += 'side_effect_red_not_business_assertion' }
    }
    # v270: stateful side effects must be supported by executable DB/state
    # evidence when the expected outputs name a write-like boundary.
    $sideEvidenceText = @(
        $sideEntry,
        ($sideExpected -join ' '),
        ((Get-StringArray $sideEvidenceObject.must_not_writes) -join ' '),
        ([string]$sideEvidenceObject.test_name),
        ((Get-StringArray $result.closed_assertions) -join ' ')
    ) -join ' '
    $sideEffectLooksStateful = $sideEvidenceText -match '(?i)\b(db|database|table|mapper|dao|repository|insert|update|delete|save|persist|status|state|task|progress|log|transaction|rollback)\b'
    $sideEffectHasExecutableStateProof = $sideEvidenceText -match '(?i)\b(select|assert|query|count|row|mapper|dao|repository|transaction|rollback|inserted|updated|deleted|saved|persisted)\b'
    if ($sideEffectEvidenceRequired -and $sideEffectLooksStateful -and -not $sideEffectHasExecutableStateProof) {
        $warnings.Add("side_effect_db_evidence_missing") | Out-Null
        foreach ($flag in @('side_effect_db_evidence_missing', 'side_effect_ledger_gap', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
}
if ($sideEffectEvidenceRequired -and -not $sideEvidenceComplete) {
    $warnings.Add("side_effect_evidence_missing")
    foreach ($flag in @('side_effect_evidence_missing', 'side_effect_ledger_gap', 'wrong_test_surface', 'tooling_enforcement_stop')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
    $hasBehaviorEvidence = $false
}

$mustNotWrites = if ($null -ne $sideEvidenceObject) { @(Get-StringArray $sideEvidenceObject.must_not_writes) } else { @() }
$preGuardWriteCalls = @()
if ($sideEffectEvidenceRequired -and ([string]$sliceType -match '(?i)stateful|lifecycle' -or ($touchedFamilies -contains 'stateful_side_effect') -or ($closedFamilies -contains 'stateful_side_effect'))) {
    $preGuardWriteCalls = @(Find-PreGuardWriteCalls -WorktreeRoot $worktreeFull -Carrier $productionBoundary)
    if ($preGuardWriteCalls.Count -eq 0) {
        $preGuardWriteCalls = @(Find-PreGuardWriteCalls -WorktreeRoot $worktreeFull -Carrier $targetSubsurface)
    }
    if ($preGuardWriteCalls.Count -eq 0 -and $null -ne $carrierAuthorization) {
        $preGuardWriteCalls = @(Find-PreGuardWriteCalls -WorktreeRoot $worktreeFull -Carrier ([string]$carrierAuthorization.selected_carrier))
    }
}
$missingPreGuardWriteCalls = @()
foreach ($call in $preGuardWriteCalls) {
    $found = @($mustNotWrites | Where-Object { [string]$_ -match [regex]::Escape([string]$call) }).Count -gt 0
    if (-not $found) { $missingPreGuardWriteCalls += [string]$call }
}
if ($missingPreGuardWriteCalls.Count -gt 0) {
    $warnings.Add("pre_guard_write_inventory_missing:$($missingPreGuardWriteCalls -join ',')") | Out-Null
    foreach ($flag in @('pre_guard_write_inventory_gap', 'side_effect_ledger_gap')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
}

$artifactFamilyTouched = (
    ($touchedFamilies -contains 'generated_artifact_template_upload') -or
    ($closedFamilies -contains 'generated_artifact_template_upload') -or
    ([string]$targetSubsurface -match '(?i)template|render|upload|image|png|file|attachment')
)
$artifactFamilyClosed = $closedFamilies -contains 'generated_artifact_template_upload'
$artifactProofLooksComplete = (
    ([string]$proofKind -eq 'template_render') -or
    (($resultEvidenceText -match '(?i)template|render') -and ($resultEvidenceText -match '(?i)upload|attachment|metadata|file'))
)
$mentionsPlaceholderArtifact = $artifactFamilyTouched -and ($resultEvidenceText -match '(?i)\bplaceholder\b|\bdummy\b|\bfake\b|stub-only|empty\s+png|1x1')
if ($artifactFamilyClosed -and -not $artifactProofLooksComplete) {
    $warnings.Add("generated_artifact_proof_incomplete")
    if ($gapFlags -notcontains 'generated_artifact_template_upload_gap') {
        $gapFlags += 'generated_artifact_template_upload_gap'
    }
}
if ($mentionsPlaceholderArtifact) {
    $warnings.Add("placeholder_artifact_cannot_close_family")
    if ($gapFlags -notcontains 'placeholder_artifact_gap') {
        $gapFlags += 'placeholder_artifact_gap'
    }
}
$hasGeneratedArtifactGap = @(
    'placeholder_artifact_gap',
    'generated_artifact_template_upload_gap',
    'template_render_gap',
    'upload_metadata_gap'
) | Where-Object { $gapFlags -contains $_ }

$implementedFileText = ($implementedFiles -join "`n")
$deployFamilyTouched = (
    ($touchedFamilies -contains 'deploy_export_page') -or
    ($closedFamilies -contains 'deploy_export_page') -or
    ([string]$proofKind -match '(?i)export_output|deploy|export') -or
    ([string]$targetSubsurface -match '(?i)deploy|export|page|view|screen|display|download|workbook|excel')
)
$deployFamilyClosed = $closedFamilies -contains 'deploy_export_page'
$deployCarrierLooksExecutable = (
    ($implementedFileText -match '(?i)(controller|endpoint|route|handler|mapper|query|export|report|excel|download|header|view|page|screen|display|\.jsp$|\.js$|\.ts$|\.tsx$|\.vue$|\.html$|\.ftl$|\.vm$)')
)
$deployAuthorizationText = ''
if ($null -ne $carrierAuthorization) {
    $deployAuthorizationText = @(
        [string]$carrierAuthorization.selected_carrier,
        [string]$carrierAuthorization.real_entry,
        [string]$carrierAuthorization.downstream_side_effect_or_output,
        (Get-StringArray $carrierAuthorization.proof_required) -join ' '
    ) -join "`n"
}
$deployAuthorizationFamily = if ($null -ne $carrierAuthorization) { [string]$carrierAuthorization.forced_requirement_family } else { '' }
$deployRouteOrOutputRequired = (
    ($deployAuthorizationFamily -eq 'deploy_export_page' -or $deployFamilyTouched) -and
    ($deployAuthorizationText -match '(?i)\b(route|endpoint|exportMyTask|export|download|workbook|excel)\b')
)
$deployClosedEvidenceText = @(
    $targetSubsurface,
    $productionBoundary,
    $proofKind,
    ($implementedFiles -join ' '),
    ($testCommands -join ' '),
    (Get-StringArray $result.closed_assertions) -join ' '
) -join "`n"
$deployRouteOrOutputProven = $deployClosedEvidenceText -match '(?i)\b(controller|route|endpoint|exportMyTask|export|download|workbook|excel)\b'
if ($deployRouteOrOutputRequired -and -not $deployRouteOrOutputProven) {
    $warnings.Add("deploy_route_or_output_proof_missing")
    foreach ($flag in @('wrong_test_surface', 'deploy_surface_contract_gap', 'tooling_enforcement_stop')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
}
if ($deployFamilyTouched -and $deployFamilyClosed -and -not $deployCarrierLooksExecutable) {
    $warnings.Add("deploy_asset_or_endpoint_proof_missing")
    if ($gapFlags -notcontains 'deploy_asset_gap') {
        $gapFlags += 'deploy_asset_gap'
    }
}

$publicEntryRequired = Test-PublicEntryText $plannedSelectedEntry
$publicEvidenceText = @(
    $targetSubsurface,
    $productionBoundary,
    $proofKind,
    ($implementedFiles -join "`n"),
    ($testCommands -join "`n")
) -join "`n"
if ($publicEntryRequired -and -not (Test-PublicEntryText $publicEvidenceText)) {
    $warnings.Add("public_entry_response_contract_missing") | Out-Null
    foreach ($flag in @('public_response_contract_missing', 'wrong_test_surface', 'shallow_module', 'tooling_enforcement_stop')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
}

# --- Test Contract Verification (v267) ---
# Detect return-value-vs-exception mismatch and assertion surface mismatch
$planContractText = @(
    (Read-TextIfExists -Path (Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md')),
    (Read-TextIfExists -Path (Join-Path $replayRootFull 'IMPLEMENTATION_CONTRACT.md')),
    (Read-TextIfExists -Path (Join-Path $replayRootFull 'REPLAY_PLAN.md'))
) -join "`n"
$plannedReturnType = ''
$plannedErrorHandling = ''
$returnTypeMatch = [regex]::Match($planContractText, '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:pattern_return_type|interface_contract_return_type)\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$')
if ($returnTypeMatch.Success) { $plannedReturnType = $returnTypeMatch.Groups[1].Value.Trim().Trim('`').Trim() }
$errorHandlingMatch = [regex]::Match($planContractText, '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:pattern_error_handling|interface_contract_error_handling)\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$')
if ($errorHandlingMatch.Success) { $plannedErrorHandling = $errorHandlingMatch.Groups[1].Value.Trim().Trim('`').Trim() }
$selectedEntryIsVoid = $plannedSelectedEntry -match '\bvoid\b'
$selectedEntryHasNonVoidReturn = -not [string]::IsNullOrWhiteSpace($plannedReturnType) -and
    $plannedReturnType -notmatch '(?i)^(void|VOID)$' -and
    $plannedReturnType -notmatch '(?i)^(TBD|unknown|N/A|placeholder|CONTRACT_INFERRED_FROM_SIMILAR)$'
$testText = @($testImplementedFiles | ForEach-Object { Read-WorktreeText -Root $worktreeFull -RelativePath $_ }) -join "`n"
$testHasExceptionCatch = $testText -match '(?s)\bcatch\s*\(\s*\w+Exception'
$testHasReturnValueAssertion = $testText -match '(?i)\w+\s+result\s*=\s*\w+\.' -or $testText -match '(?i)assertEquals\s*\(\s*["\x27]\d{3}["\x27]'
$testHasResponseCodeAssertion = $testText -match '(?i)\.getCode\s*\(\s*\)\s*\)|["\x27][45]\d{2}["\x27]'
# Return-value-vs-exception mismatch: plan says non-void return but tests only catch exceptions
if ($selectedEntryHasNonVoidReturn -and $testHasExceptionCatch -and -not $testHasReturnValueAssertion) {
    $warnings.Add("return_value_vs_exception_mismatch") | Out-Null
    foreach ($flag in @('return_value_vs_exception_mismatch', 'test_contract_mismatch', 'wrong_test_surface', 'tooling_enforcement_stop')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
    $hasBehaviorEvidence = $false
}
# Error handling pattern mismatch: plan says response_codes but tests use exception-catching
if (-not [string]::IsNullOrWhiteSpace($plannedErrorHandling) -and
    $plannedErrorHandling -match '(?i)response.code' -and
    $testHasExceptionCatch -and -not $testHasResponseCodeAssertion) {
    $warnings.Add("error_handling_pattern_mismatch") | Out-Null
    foreach ($flag in @('test_contract_mismatch', 'assertion_surface_mismatch', 'wrong_test_surface', 'tooling_enforcement_stop')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
    $hasBehaviorEvidence = $false
}
# Assertion surface mismatch for public entries: tests assert on internal mocks but not on public response
if ($publicEntryRequired -and $testHasExceptionCatch -and -not $testHasReturnValueAssertion -and -not $testHasResponseCodeAssertion) {
    $testAssertsOnMock = $testText -match '(?i)verify\s*\(\s*\w+\s*\)' -and -not ($testText -match '(?i)result\s*=\s*\w+\.')
    if ($testAssertsOnMock) {
        $warnings.Add("assertion_surface_mismatch_public_entry") | Out-Null
        foreach ($flag in @('assertion_surface_mismatch', 'test_contract_mismatch', 'wrong_test_surface', 'tooling_enforcement_stop')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $hasBehaviorEvidence = $false
    }
}

$rawRequiredSiblingText = ''
if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'required_sibling_surfaces') {
    $rawSiblingItems = New-Object System.Collections.Generic.List[string]
    foreach ($rawSibling in @(Get-StringArray $result.required_sibling_surfaces)) {
        $rawSiblingText = [string]$rawSibling
        if ([string]::IsNullOrWhiteSpace($rawSiblingText)) { continue }
        if ($rawSiblingText -match '^\s*([a-z][a-z0-9_]+)\s*:\s*(.+)$') {
            $scopedFamily = [string]$matches[1]
            if ($closedFamilies -contains $scopedFamily) {
                $rawSiblingItems.Add($matches[2].Trim()) | Out-Null
            }
        } else {
            $rawSiblingItems.Add($rawSiblingText.Trim()) | Out-Null
        }
    }
    $rawRequiredSiblingText = @($rawSiblingItems) -join "`n"
}
$deploySiblingMentioned = (
    @($blockingSiblingSurfaces | Where-Object { [string]$_ -match '(?i)(Controller|JSP|JS|page|view|display|submit|query|mapper|route)\b' }).Count -gt 0 -or
    $rawRequiredSiblingText -match '(?i)(Controller|JSP|JS|page|view|display|submit|query|mapper|route)\b'
)
if ($deploySiblingMentioned -and -not ($deployCarrierLooksExecutable -or $deployRouteOrOutputProven)) {
    $warnings.Add("deploy_surface_unproven") | Out-Null
    foreach ($flag in @('deploy_surface_unproven', 'executable_surface_slice_gap', 'wrong_test_surface', 'tooling_enforcement_stop')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
}

$wireFamilyTouched = (
    ($touchedFamilies -contains 'wire_payload_api_contract') -or
    ($closedFamilies -contains 'wire_payload_api_contract') -or
    ([string]$targetSubsurface -match '(?i)wire|payload|request|response|api|dto|json')
)
$wireFamilyClosed = $closedFamilies -contains 'wire_payload_api_contract'
$wirePayloadShapeLooksExecutable = (
    ($resultEvidenceText -match '(?i)\b(request body|response body|payload|wire|json|array|schema|field|dto|serializer|deserializer|actual request|actual response)\b') -and
    ($implementedFileText -match '(?i)(controller|client|gateway|adapter|dto|request|response|payload|mapper|serializer|deserializer|api)')
)
if ($wireFamilyTouched -and $wireFamilyClosed -and -not $wirePayloadShapeLooksExecutable) {
    $warnings.Add("wire_payload_shape_proof_missing")
    if ($gapFlags -notcontains 'wire_payload_shape_gap') {
        $gapFlags += 'wire_payload_shape_gap'
    }
}

$statefulFamilyTouched = (
    ($touchedFamilies -contains 'stateful_side_effect') -or
    ($closedFamilies -contains 'stateful_side_effect') -or
    ([string]$targetSubsurface -match '(?i)state|task|progress|log|persist|transaction|rollback|database|db')
)
$statefulFamilyClosed = $closedFamilies -contains 'stateful_side_effect'
$sideEffectCategoryPatterns = [ordered]@{
    persistence = '(?i)\b(persist|database|db|insert|update|delete|mapper|dao|save|remove|write|row)\b'
    transaction = '(?i)\b(transaction|rollback|commit|after-commit|after commit|ordering|order)\b'
    state = '(?i)\b(state|status|transition|flow status|case status)\b'
    task = '(?i)\b(task|job|worker|sla|complete|finish)\b'
    progress = '(?i)\b(progress|step|timeline|process)\b'
    log = '(?i)\b(log|record|examine|audit)\b'
    failureIsolation = '(?i)\b(failure isolation|fail.*not.*block|not block|must-not|rollback|exception)\b'
}
$sideEffectCategoryHits = @($sideEffectCategoryPatterns.Keys | Where-Object { $resultEvidenceText -match $sideEffectCategoryPatterns[$_] })
$transactionDepthLooksExecutable = (
    ([string]$proofKind -match '(?i)transaction') -or
    ($sideEffectCategoryHits.Count -ge 4)
)
if ($statefulFamilyTouched -and $statefulFamilyClosed -and -not $transactionDepthLooksExecutable) {
    $warnings.Add("transaction_depth_proof_missing")
    if ($gapFlags -notcontains 'transaction_depth_gap') {
        $gapFlags += 'transaction_depth_gap'
    }
}
if ($statefulFamilyClosed -and $sideEffectCategoryHits.Count -lt 4) {
    $warnings.Add("side_effect_ledger_depth_incomplete")
    if ($gapFlags -notcontains 'side_effect_ledger_gap') {
        $gapFlags += 'side_effect_ledger_gap'
    }
}

$hasDeployCarrierGap = @('deploy_asset_gap') | Where-Object { $gapFlags -contains $_ }
$hasWirePayloadGap = @('wire_payload_shape_gap') | Where-Object { $gapFlags -contains $_ }
$hasTransactionDepthGap = @('transaction_depth_gap') | Where-Object { $gapFlags -contains $_ }
$hasSiblingSurfaceGap = @('family_sibling_gap') | Where-Object { $gapFlags -contains $_ }
$hasWrongSurfaceGap = @('wrong_test_surface') | Where-Object { $gapFlags -contains $_ }
$hasShallowModuleGap = @('shallow_module') | Where-Object { $gapFlags -contains $_ }
$hasSyntheticCarrierGap = @('synthetic_carrier_gap') | Where-Object { $gapFlags -contains $_ }
$hasDependencySpyGap = @('dependency_spy_output_gap') | Where-Object { $gapFlags -contains $_ }

$expectedCarrierSource = 'none'
$carrierFamilyMatch = $true
$planMismatchedFamilies = New-Object System.Collections.Generic.List[string]
$currentCarrierText = @(
    $targetSubsurface,
    $productionBoundary,
    $proofKind,
    $resultEvidenceText,
    ($testCommands -join "`n")
) -join "`n"
$sourceChainRequiredForPlanLock = $null -ne $sourceChainContract -and [bool]$sourceChainContract.required_source_chain
$unrequiredSourceChainCarrier = (
    -not $sourceChainRequiredForPlanLock -and
    $currentCarrierText -match '(?i)\b(AiClaimDataAssemblyHelper|AiApplyClaimService|AiCalculateLossService|InputData|policy_num|insure_num|AiPolicyNumSourceChainTest)\b'
)
if ($unrequiredSourceChainCarrier) {
    $carrierFamilyMatch = $false
    $expectedCarrierSource = 'SOURCE_CHAIN_CONTRACT.required_source_chain=false'
    foreach ($familyId in @($touchedFamilies | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        if (-not $planMismatchedFamilies.Contains([string]$familyId)) { $planMismatchedFamilies.Add([string]$familyId) | Out-Null }
    }
    foreach ($flag in @('wrong_test_surface', 'carrier_plan_mismatch')) {
        if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
    }
    $warnings.Add('unrequired_source_chain_carrier') | Out-Null
}
if ($touchedFamilies -contains 'core_entry') {
    $plannedCarrierHead = if ([string]::IsNullOrWhiteSpace($plannedSelectedCarrier)) { '' } else { (($plannedSelectedCarrier -split '\s*->\s*')[0]).Trim() }
    $plannedCarrierToken = if ([string]::IsNullOrWhiteSpace($plannedCarrierHead)) { '' } else { ($plannedCarrierHead -split '\.')[0] }
    if (-not [string]::IsNullOrWhiteSpace($plannedCarrierToken) -and $currentCarrierText -notmatch [regex]::Escape($plannedCarrierToken)) {
        $carrierFamilyMatch = $false
        $expectedCarrierSource = 'FIRST_SLICE_PROOF_PLAN.selected_carrier'
        if (-not $planMismatchedFamilies.Contains('core_entry')) { $planMismatchedFamilies.Add('core_entry') | Out-Null }
        foreach ($flag in @('wrong_test_surface', 'carrier_plan_mismatch')) {
            if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
        }
        $warnings.Add('selected_carrier_plan_mismatch') | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($plannedFirstRedTest)) {
        $plannedClass = Get-TestClassNameFromBinding -Binding $plannedFirstRedTest
        $actualPlannedTestClasses = New-Object System.Collections.Generic.List[string]
        foreach ($match in [regex]::Matches($currentCarrierText, '(?i)-Dtest=([^\s]+)')) {
            foreach ($binding in @(([string]$match.Groups[1].Value) -split ',')) {
                $actualClass = Get-TestClassNameFromBinding -Binding $binding
                if (-not [string]::IsNullOrWhiteSpace($actualClass) -and -not $actualPlannedTestClasses.Contains($actualClass)) {
                    $actualPlannedTestClasses.Add($actualClass) | Out-Null
                }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($plannedClass) -and
            $actualPlannedTestClasses.Count -gt 0 -and
            @($actualPlannedTestClasses | Where-Object { [string]$_ -eq $plannedClass }).Count -eq 0) {
            $carrierFamilyMatch = $false
            $expectedCarrierSource = 'IMPLEMENTATION_CONTRACT.first_red_test'
            if (-not $planMismatchedFamilies.Contains('core_entry')) { $planMismatchedFamilies.Add('core_entry') | Out-Null }
            foreach ($flag in @('wrong_test_surface', 'planned_red_test_mismatch')) {
                if ($gapFlags -notcontains $flag) { $gapFlags += $flag }
            }
            $warnings.Add('planned_red_test_mismatch') | Out-Null
        }
    }
}

$actualProofTypes = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($proofKind)) { $actualProofTypes.Add($proofKind) | Out-Null }
if ($isCoreEntrySlice -and $productionImplementedFiles.Count -gt 0 -and -not $hasSubstituteProof) { $actualProofTypes.Add('real_entry_behavior') | Out-Null }
if ($transactionDepthLooksExecutable) { $actualProofTypes.Add('stateful_side_effect') | Out-Null; $actualProofTypes.Add('transaction') | Out-Null }
if ($deployCarrierLooksExecutable) { $actualProofTypes.Add('export_output') | Out-Null }
if ($wirePayloadShapeLooksExecutable) { $actualProofTypes.Add('wire_payload') | Out-Null; $actualProofTypes.Add('payload_shape') | Out-Null }
if ($resultEvidenceText -match '(?i)\b(persist|persistence|mapper|xml|insert|update|save|db|database|column|free_review_amount)\b') {
    $actualProofTypes.Add('persistence') | Out-Null
    $actualProofTypes.Add('db_persistence') | Out-Null
}
if ($artifactProofLooksComplete) { $actualProofTypes.Add('rendered_artifact') | Out-Null; $actualProofTypes.Add('template_render') | Out-Null }
if ($resultEvidenceText -match '(?i)\b(cleanup|retention|delete|remove|expire|lifecycle)\b') { $actualProofTypes.Add('lifecycle_cleanup') | Out-Null }
if ($resultEvidenceText -match '(?i)\b(integration|external|client|adapter|remote|http)\b') { $actualProofTypes.Add('integration') | Out-Null }
$actualProofTypes = @($actualProofTypes | Select-Object -Unique)

$requiredProofByFamily = [ordered]@{}
$actualProofByFamily = [ordered]@{}
$proofTypeMismatchFamilies = New-Object System.Collections.Generic.List[string]
foreach ($familyId in @(($touchedFamilies + $closedFamilies) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
    $requiredProof = @()
    if ($familyContracts.ContainsKey([string]$familyId)) {
        $contractFamily = $familyContracts[[string]$familyId]
        $requiredProof = @(Get-StringArray $contractFamily.required_proof_type)
    }
    if ($requiredProof.Count -eq 0) {
        $requiredProof = @(Get-DefaultRequiredProofTypes -FamilyId ([string]$familyId))
    }
    $requiredProofByFamily[[string]$familyId] = @($requiredProof)
    $actualProofByFamily[[string]$familyId] = @($actualProofTypes)
    $isOpportunisticExactFamily = (
        -not $exactContractRequiredForThisSlice -and
        $exactContractFamilies -contains [string]$familyId -and
        $closedExactAssertions.Count -eq 0 -and
        $closedMatrixRows.Count -eq 0
    )
    if ($isOpportunisticExactFamily) {
        # A stateful/core slice may mention a config or API family as supporting context.
        # Without explicit exact assertions, do not let that opportunistic over-claim
        # invalidate the behavior proof for the forced stateful family.
    } elseif ($planMismatchedFamilies.Contains([string]$familyId)) {
        $proofTypeMismatchFamilies.Add([string]$familyId) | Out-Null
    } elseif (($closedFamilies -contains [string]$familyId) -and -not (Test-ProofTypeMatch -Required $requiredProof -Actual $actualProofTypes)) {
        $proofTypeMismatchFamilies.Add([string]$familyId) | Out-Null
    }
}
if ($proofTypeMismatchFamilies.Count -gt 0) {
    $warnings.Add("proof_type_mismatch")
    foreach ($flag in @('wrong_test_surface', 'proof_type_gap')) {
        if ($gapFlags -notcontains $flag) {
            $gapFlags += $flag
        }
    }
}

$nonAuthorizingEvidenceFlags = @(
    'wrong_test_surface',
    'shallow_module',
    'synthetic_carrier_gap',
    'tooling_enforcement_stop',
    'mock_behavior_gap',
    'tdd_red_not_replayed',
    'no_progress_slice',
    'carrier_authorization_missing',
    'carrier_authorization_stop',
    'public_response_contract_missing',
    'deploy_surface_unproven',
    'exact_contract_assertion_missing',
    'exact_contract_boundary_proof_stop',
    'side_effect_evidence_missing',
    'side_effect_red_not_business_assertion',
    'exact_contract_not_closed',
    'behavior_carrier_gap',
    'facade_direction_gap',
    'test_contract_mismatch',
    'return_value_vs_exception_mismatch',
    'assertion_surface_mismatch',
    'behavior_test_charter_gap'
) | Where-Object { $gapFlags -contains $_ }
if ($hasRedPhaseDidNotFail -or $hasTddRedNotReplayed -or $hasImplementationAfterBlockedRed -or $hasNoProgressSignal -or
    $hasSubstituteProof -or $nonAuthorizingEvidenceFlags.Count -gt 0 -or $proofTypeMismatchFamilies.Count -gt 0) {
    $hasBehaviorEvidence = $false
}

$hasExactGap = @('exact_contract_gap') | Where-Object { $gapFlags -contains $_ }

$verificationStatus = 'PASS'
if ($issues.Count -gt 0) {
    $verificationStatus = 'FAIL'
} elseif ($sliceStatus -match 'BLOCKED|INVALID') {
    $verificationStatus = 'BLOCKED'
} elseif ($sliceStatus -eq 'PARTIAL') {
    $verificationStatus = 'PARTIAL'
} elseif (-not $hasBehaviorEvidence) {
    $verificationStatus = 'PARTIAL'
} elseif ($sliceStatus -eq 'DONE' -and $redTests.Count -eq 0) {
    $verificationStatus = 'PARTIAL'
} elseif ($hasRedPhaseDidNotFail) {
    $verificationStatus = 'PARTIAL'
} elseif ($hasTddRedNotReplayed) {
    $verificationStatus = 'PARTIAL'
} elseif ($hasImplementationAfterBlockedRed) {
    $verificationStatus = 'PARTIAL'
} elseif ($hasGeneratedArtifactGap.Count -gt 0) {
    $verificationStatus = 'PARTIAL'
} elseif ($hasSiblingSurfaceGap.Count -gt 0 -or $hasWrongSurfaceGap.Count -gt 0 -or $hasShallowModuleGap.Count -gt 0 -or $hasSyntheticCarrierGap.Count -gt 0 -or $hasDependencySpyGap.Count -gt 0) {
    $verificationStatus = 'PARTIAL'
} elseif ($hasDeployCarrierGap.Count -gt 0 -or $hasWirePayloadGap.Count -gt 0 -or $hasTransactionDepthGap.Count -gt 0) {
    $verificationStatus = 'PARTIAL'
} elseif ($proofTypeMismatchFamilies.Count -gt 0) {
    $verificationStatus = 'PARTIAL'
} elseif ($hasExactGap.Count -gt 0) {
    $verificationStatus = 'PARTIAL'
} elseif ($hasStatefulGap.Count -gt 0 -or $hasSurfaceGap.Count -gt 0 -or ($gapFlags -contains 'tracer_bullet_only')) {
    $verificationStatus = 'PARTIAL'
}

$coverageCap = 100
if (-not $hasBehaviorEvidence) { $coverageCap = [Math]::Min($coverageCap, 45) }
if ($sliceStatus -eq 'PARTIAL') { $coverageCap = [Math]::Min($coverageCap, 70) }
if ($gapFlags -contains 'tracer_bullet_only') { $coverageCap = [Math]::Min($coverageCap, 40) }
if ($hasStatefulGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 60) }
if ($hasSurfaceGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 70) }
if ($hasExactGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 75) }
if ($gapFlags -contains 'exact_contract_not_closed') { $coverageCap = [Math]::Min($coverageCap, 25) }
if ($hasGeneratedArtifactGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 60) }
if ($hasSiblingSurfaceGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 65) }
if ($hasWrongSurfaceGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 50) }
if ($hasShallowModuleGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 55) }
if ($hasSyntheticCarrierGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 35) }
if ($gapFlags -contains 'behavior_carrier_gap') { $coverageCap = [Math]::Min($coverageCap, 10) }
if ($gapFlags -contains 'facade_direction_gap') { $coverageCap = [Math]::Min($coverageCap, 10) }
if ($hasDependencySpyGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 45) }
if ($hasDeployCarrierGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 65) }
if ($hasWirePayloadGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 60) }
if ($hasTransactionDepthGap.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 60) }
if ($proofTypeMismatchFamilies.Count -gt 0) { $coverageCap = [Math]::Min($coverageCap, 55) }
if ($gapFlags -contains 'mock_behavior_gap') { $coverageCap = [Math]::Min($coverageCap, 35) }
if ($gapFlags -contains 'behavior_test_charter_gap') { $coverageCap = [Math]::Min($coverageCap, 10) }
if ($sliceStatus -eq 'DONE' -and $redTests.Count -eq 0) { $coverageCap = [Math]::Min($coverageCap, 55) }
if ($hasRedPhaseDidNotFail) { $coverageCap = [Math]::Min($coverageCap, 10) }
if ($hasTddRedNotReplayed) { $coverageCap = [Math]::Min($coverageCap, 10) }
if ($hasImplementationAfterBlockedRed) { $coverageCap = [Math]::Min($coverageCap, 0) }
if ($isCoreEntrySlice -and $hasTddRedNotReplayed) { $coverageCap = [Math]::Min($coverageCap, 10) }
if ($isCoreEntrySlice -and $hasRedPhaseDidNotFail) { $coverageCap = [Math]::Min($coverageCap, 10) }
if ($hasSubstituteProof) { $coverageCap = [Math]::Min($coverageCap, 10) }
if (@('carrier_authorization_missing', 'carrier_authorization_stop', 'exact_contract_assertion_missing', 'exact_contract_boundary_proof_stop', 'side_effect_evidence_missing', 'side_effect_red_not_business_assertion') | Where-Object { $gapFlags -contains $_ }) { $coverageCap = [Math]::Min($coverageCap, 10) }
if ($hasNoProgressSignal) { $coverageCap = [Math]::Min($coverageCap, 40) }
if ($warnings -contains 'target_subsurface_missing' -or
    $warnings -contains 'production_boundary_missing' -or
    $warnings -contains 'proof_kind_missing' -or
    $warnings -contains 'red_expectation_missing' -or
    $warnings -contains 'static_contract_cannot_close_family_alone') {
    $coverageCap = [Math]::Min($coverageCap, 75)
}

$adjustedCoverageDelta = $coverageDelta
if ($coverageDelta -ne $null) {
    if ($sliceStatus -eq 'PARTIAL' -and -not $alreadyImplementedEvidenceSlice) {
        $adjustedCoverageDelta = [Math]::Min([int]$adjustedCoverageDelta, 5)
    }
    if ($sliceStatus -eq 'DONE' -and $redTests.Count -eq 0) {
        $adjustedCoverageDelta = [Math]::Min([int]$adjustedCoverageDelta, 3)
    }
    if ($hasRedPhaseDidNotFail) {
        $adjustedCoverageDelta = 0
    }
    if ($hasTddRedNotReplayed) {
        $adjustedCoverageDelta = 0
    }
    if ($hasImplementationAfterBlockedRed) {
        $adjustedCoverageDelta = 0
    }
    if ($hasSubstituteProof) {
        $adjustedCoverageDelta = 0
    }
    if (@('carrier_authorization_missing', 'carrier_authorization_stop', 'exact_contract_assertion_missing', 'exact_contract_boundary_proof_stop', 'side_effect_evidence_missing', 'side_effect_red_not_business_assertion') | Where-Object { $gapFlags -contains $_ }) {
        $adjustedCoverageDelta = 0
    }
    if ($gapFlags -contains 'behavior_carrier_gap' -or $gapFlags -contains 'facade_direction_gap') {
        $adjustedCoverageDelta = 0
    }
    if ($gapFlags -contains 'behavior_test_charter_gap') {
        $adjustedCoverageDelta = 0
    }
    if ($isCoreEntrySlice -and $hasRedPhaseDidNotFail) {
        $adjustedCoverageDelta = 0
    }
    if ($hasNoProgressSignal) {
        $adjustedCoverageDelta = 0
    }
    if ($hasGeneratedArtifactGap.Count -gt 0) {
        $adjustedCoverageDelta = [Math]::Min([int]$adjustedCoverageDelta, 3)
    }
    if ($gapFlags -contains 'exact_contract_not_closed') {
        $adjustedCoverageDelta = 0
    }
    if ($hasSiblingSurfaceGap.Count -gt 0) {
        $adjustedCoverageDelta = [Math]::Min([int]$adjustedCoverageDelta, 3)
    }
    if ($hasWrongSurfaceGap.Count -gt 0 -or $hasShallowModuleGap.Count -gt 0 -or $hasSyntheticCarrierGap.Count -gt 0) {
        $adjustedCoverageDelta = 0
    }
    if ($hasDependencySpyGap.Count -gt 0) {
        $adjustedCoverageDelta = [Math]::Min([int]$adjustedCoverageDelta, 8)
    }
    if ($hasDeployCarrierGap.Count -gt 0 -or $hasWirePayloadGap.Count -gt 0 -or $hasTransactionDepthGap.Count -gt 0) {
        $adjustedCoverageDelta = [Math]::Min([int]$adjustedCoverageDelta, 3)
    }
    if ($proofTypeMismatchFamilies.Count -gt 0) {
        $adjustedCoverageDelta = 0
    }
}
if ($null -ne $adjustedCoverageDelta) {
    $adjustedCoverageDelta = [Math]::Min([int]$adjustedCoverageDelta, [int]$coverageCap)
}

$nonAuthorizingReasons = New-Object System.Collections.Generic.List[string]
if ($issues.Count -gt 0) { $nonAuthorizingReasons.Add('issues_present') | Out-Null }
if ($verificationStatus -eq 'FAIL' -or $verificationStatus -eq 'BLOCKED') { $nonAuthorizingReasons.Add('verification_failed_or_blocked') | Out-Null }
if (-not $hasBehaviorEvidence) { $nonAuthorizingReasons.Add('behavior_evidence_missing') | Out-Null }
if ($sliceStatus -eq 'DONE' -and $redTests.Count -eq 0) { $nonAuthorizingReasons.Add('red_phase_missing') | Out-Null }
if ($hasRedPhaseDidNotFail) { $nonAuthorizingReasons.Add('red_phase_did_not_fail') | Out-Null }
if ($hasTddRedNotReplayed) { $nonAuthorizingReasons.Add('tdd_red_not_replayed') | Out-Null }
if ($hasImplementationAfterBlockedRed) { $nonAuthorizingReasons.Add('implementation_after_blocked_red') | Out-Null }
if ($hasSubstituteProof) { $nonAuthorizingReasons.Add('substitute_or_shallow_proof') | Out-Null }
if ($hasWrongSurfaceGap.Count -gt 0) { $nonAuthorizingReasons.Add('wrong_test_surface') | Out-Null }
if ($hasShallowModuleGap.Count -gt 0) { $nonAuthorizingReasons.Add('shallow_module') | Out-Null }
if ($hasSyntheticCarrierGap.Count -gt 0) { $nonAuthorizingReasons.Add('synthetic_carrier') | Out-Null }
if ($proofTypeMismatchFamilies.Count -gt 0) { $nonAuthorizingReasons.Add('proof_type_mismatch') | Out-Null }
foreach ($flag in @('carrier_authorization_missing', 'carrier_authorization_stop', 'exact_contract_assertion_missing', 'exact_contract_boundary_proof_stop', 'side_effect_evidence_missing', 'side_effect_red_not_business_assertion')) {
    if ($gapFlags -contains $flag) { $nonAuthorizingReasons.Add($flag) | Out-Null }
}
if ($gapFlags -contains 'behavior_test_charter_gap') { $nonAuthorizingReasons.Add('behavior_test_charter_gap') | Out-Null }
foreach ($flag in @('public_response_contract_missing', 'deploy_surface_unproven')) {
    if ($gapFlags -contains $flag) { $nonAuthorizingReasons.Add($flag) | Out-Null }
}
if ($gapFlags -contains 'exact_contract_not_closed') { $nonAuthorizingReasons.Add('exact_contract_not_closed') | Out-Null }
# v414 TODO Blocker: TODO placeholders in production code now block slice authorization
if ($gapFlags -contains 'todo_placeholder_exists') { $nonAuthorizingReasons.Add('todo_placeholder_exists') | Out-Null }
$nonAuthorizingReasons = @($nonAuthorizingReasons | Select-Object -Unique)
$authorizedForNextSlice = $nonAuthorizingReasons.Count -eq 0 -and $verificationStatus -ne 'FAIL' -and $verificationStatus -ne 'BLOCKED'
$authorizedForSynthesis = $authorizedForNextSlice -and $verificationStatus -eq 'PASS' -and $sliceStatus -eq 'DONE' -and $hasDependencySpyGap.Count -eq 0

$shouldContinue = $true
if ($verificationStatus -eq 'FAIL' -or $verificationStatus -eq 'BLOCKED') { $shouldContinue = $false }
if ($sliceStatus -match 'PASS') { $shouldContinue = $false }
if ($hasTddRedNotReplayed) { $shouldContinue = $false }
if ($hasRedPhaseDidNotFail) { $shouldContinue = $false }
if ($hasImplementationAfterBlockedRed) { $shouldContinue = $false }
if ($hasSubstituteProof) { $shouldContinue = $false }
if (-not $authorizedForNextSlice) { $shouldContinue = $false }

$verify = [ordered]@{
    slice_index = $SliceIndex
    slice_result = $sliceResultFull
    verification_status = $verificationStatus
    slice_status = $sliceStatus
    slice_type = $sliceType
    coverage_delta = $coverageDelta
    adjusted_coverage_delta = $adjustedCoverageDelta
    coverage_cap = $coverageCap
    should_continue = $shouldContinue
    authorized_for_next_slice = $authorizedForNextSlice
    authorized_for_synthesis = $authorizedForSynthesis
    authorization_blockers = @($nonAuthorizingReasons)
    required_proof_type = $requiredProofByFamily
    actual_proof_type = $actualProofByFamily
    proof_type_mismatch_families = @($proofTypeMismatchFamilies)
    carrier_family_match = $carrierFamilyMatch
    expected_carrier_source = $expectedCarrierSource
    planned_first_red_test = $plannedFirstRedTest
    planned_selected_carrier = $plannedSelectedCarrier
    planned_selected_entry = $plannedSelectedEntry
    has_behavior_evidence = $hasBehaviorEvidence
    implementation_allowed = (-not $hasImplementationAfterBlockedRed)
    red_blocked = $redBlocked
    implementation_after_blocked_red = $hasImplementationAfterBlockedRed
    behavior_test_charter_required = $behaviorCharterRequired
    behavior_test_charter_ready = $behaviorCharterReady
    has_diff = $hasTrackedOrUntrackedDiff
    changed_files = @($currentSliceChangedFiles)
    round_changed_files_snapshot = @($roundChangedFilesSnapshot)
    implemented_files = @($implementedFiles)
    test_commands = @($testCommands)
    gap_flags = @($gapFlags)
    issues = @($issues)
    warnings = @($warnings)
    next_recommended_slice_type = $nextRecommended
    carrier_start = $carrierStart
    carrier_origin = $carrierOrigin
    next_required_slice = $nextRequiredSlice
}

$verify | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $verifyPath -Encoding UTF8
Get-Content -LiteralPath $verifyPath -Encoding UTF8
