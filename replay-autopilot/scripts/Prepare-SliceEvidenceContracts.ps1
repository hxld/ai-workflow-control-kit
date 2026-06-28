param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [string]$RequirementFamilyLedger,
    [Parameter(Mandatory = $true)]
    [int]$SliceIndex,
    [string]$ForcedRequirementFamily = '',
    [string]$ForcedSliceType = '',
    [string]$ForcedSiblingSurface = '',
    [string]$SurfaceCarrierScan = '',
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
            return $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
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

function Get-DefaultEvidenceTarget {
    param([string]$FamilyId, [string]$SliceType)

    switch ($FamilyId) {
        'core_entry' { return 'real production entry plus at least one downstream side effect or output' }
        'stateful_side_effect' { return 'state/status/task/progress/log/persistence side effect through a real entry' }
        'deploy_export_page' { return 'deploy-facing endpoint/export/page output assertion' }
        'wire_payload_api_contract' { return 'request/response/payload/display exact contract assertion' }
        'config_policy_threshold' { return 'config add/edit/query validation and persistence round-trip assertion' }
        'generated_artifact_template_upload' { return 'rendered artifact plus upload/metadata assertion' }
        'external_integration' { return 'outbound or inbound integration payload assertion' }
        'automation_test_interface' { return 'API/interface response assertion from the production carrier' }
        'lifecycle_cleanup_retention' { return 'cleanup/idempotency/failure-isolation side effect assertion' }
        default {
            if ($SliceType -match 'stateful') { return 'stateful side effect assertion' }
            if ($SliceType -match 'deploy') { return 'deploy-facing output assertion' }
            if ($SliceType -match 'exact') { return 'exact contract assertion' }
            return 'real behavior assertion through the selected production carrier'
        }
    }
}

function Test-SyntheticCarrierText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return $Text -match '(?i)\b(Noop|Stub|Fake|Dummy|Placeholder|Mock|InMemory|TestOnly|Scaffold)\b'
}

function Test-HelperOnlyCarrierText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return $Text -match '(?i)\b(dto|constant|static|header-only|sql-only|file-presence-only|mapper-presence-only|helper-only|helper)'
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
    if ($value -match '^(claim-core|claim-server|claim-web|claim-api|claim-domain)$') { return $true }
    if ($value -match '^--%$|^-s$|^-f$|^-D') { return $true }
    if ($value -match '^(Noop|Stub|Fake|Dummy|Placeholder|Mock|InMemory|TestOnly|Scaffold)$') { return $true }
    if ($value -match '^[A-Z][A-Za-z0-9_]*(?:Test|Service|Controller|Mapper|Facade|Impl|Dto|DTO|VO|Vo|Request|Response|Query)?(?:#[A-Za-z0-9_]+)?$') { return $true }
    return $false
}

function Get-ExactLiteralsFromText {
    param([string]$Text, [int]$Limit = 60)

    $literals = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $matches = [regex]::Matches($Text, '`([^`\r\n]{1,100})`')
    foreach ($match in $matches) {
        $literal = [string]$match.Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($literal)) { continue }
        if (Test-MetadataLiteral -Literal $literal) { continue }
        if (-not $literals.Contains($literal)) {
            $literals.Add($literal) | Out-Null
        }
        if ($literals.Count -ge $Limit) { break }
    }
    return @($literals)
}

function Get-ContractBoundaryType {
    param([string]$Surface, [string]$Literal)
    $text = @($Surface, $Literal) -join ' '
    if ($text -match '(?i)\b(db|database|column|mapper|insert|update|delete|persist|save|table|row)\b|_id\b|_amount\b') { return 'db' }
    if ($text -match '(?i)\b(payload|wire|json|request|response|body|api|type|field|queue|exchange|mq|message)\b') { return 'wire' }
    if ($text -match '(?i)\b(display|view|page|screen|header|column|excel|export|download)\b') { return 'display' }
    if ($text -match '(?i)\b(callback|webhook|external|integration|adapter|client|provider|partner)\b') { return 'callback' }
    return 'behavior'
}

function New-ExactContractRow {
    param([string]$Literal, [string]$SelectedCarrier = '')

    $symbol = ''
    $surface = 'behavior'
    $assertion = ''
    $value = $Literal.Trim()

    if ($value -match '(?i)page[_ ]?no') {
        $symbol = 'page_no'
        $surface = 'wire_or_query'
    } elseif ($value -match '(?i)page[_ ]?size|15\s*-?>\s*150|15\s*->\s*150') {
        $symbol = 'page_size'
        $surface = 'wire_or_query'
    } elseif ($value -match '(?i)total|pageNo|pageSize|Pagination') {
        $symbol = 'pagination_response'
        $surface = 'response'
    } elseif ($value -match '(?i)reported|ongoingCaseAmount|haveEndedCase|endedCaseAmount') {
        $symbol = $value
        $surface = 'state_or_display'
    } elseif ($value -match '(?i)type|payload|json|field|column|header') {
        $symbol = $value
        $surface = 'wire_or_display'
    } else {
        $symbol = $value
    }

    $assertion = "assert '$value' through the selected production carrier"
    $boundaryType = Get-ContractBoundaryType -Surface $surface -Literal $value
    return [ordered]@{
        literal = $value
        symbol_or_field = $symbol
        db_or_wire_or_display = $surface
        boundary_type = $boundaryType
        production_boundary = $SelectedCarrier
        closure_proof = ''
        test_assertion = $assertion
        red_command = ''
        blocker_condition = 'missing executable exact-contract boundary proof'
        status = 'OPEN'
        touched = $false
        source_type = 'requirement'
    }
}

function New-SideEffectExactContractRow {
    param(
        [string]$Literal,
        [string]$SelectedCarrier = '',
        [string]$FamilyId = ''
    )

    $value = $Literal.Trim()
    $surface = if ($value -match '(?i)\b(payload|wire|json|request|response|api|mq|message|exchange)\b') {
        'wire'
    } elseif ($value -match '(?i)\b(display|page|screen|column|excel|export|download|image|png|jpg|pdf|render)\b') {
        'display'
    } elseif ($FamilyId -match '(?i)lifecycle|stateful|side_effect' -or $value -match '(?i)\b(row|log|status|operator|task|write|persist|save|insert|update|delete)\b') {
        'db'
    } else {
        'behavior'
    }
    $boundaryType = Get-ContractBoundaryType -Surface $surface -Literal $value
    if ($surface -eq 'db') { $boundaryType = 'db' }
    if ($surface -eq 'wire') { $boundaryType = 'wire' }
    if ($surface -eq 'display') { $boundaryType = 'display' }

    return [ordered]@{
        literal = $value
        symbol_or_field = $value
        db_or_wire_or_display = $surface
        boundary_type = $boundaryType
        production_boundary = $SelectedCarrier
        closure_proof = ''
        test_assertion = "assert '$value' through the selected production carrier"
        red_command = ''
        blocker_condition = 'missing executable exact-contract boundary proof'
        status = 'OPEN'
        touched = $false
        required_for_this_slice = $true
        source_type = 'family_proof_required'
    }
}

function Get-SlicePlannedTestName {
    param([string]$ReplayRoot, [int]$SliceIndex)
    $plan = Read-TextIfExists (Join-Path $ReplayRoot 'REPLAY_PLAN.md')
    if (-not [string]::IsNullOrWhiteSpace($plan)) {
        foreach ($line in ($plan -split "`r?`n")) {
            if ($line -notmatch '^\s*\|\s*S' + [regex]::Escape([string]$SliceIndex) + '\s*\|') { continue }
            $columns = @($line -split '\|')
            if ($columns.Count -gt 7) {
                $testsColumn = [string]$columns[7]
                $match = [regex]::Match($testsColumn, '(?i)(?:[A-Za-z0-9_.\-]+[/\\])*src[/\\]test[/\\]java[/\\][A-Za-z0-9_./\\]+Test\.java(?:[#.][A-Za-z_][A-Za-z0-9_]*)?|\b[A-Za-z_][A-Za-z0-9_$.]*Test(?:[#.][A-Za-z_][A-Za-z0-9_]*)?\b')
                if ($match.Success) { return $match.Value }
            }
        }
    }
    $charter = Read-TextIfExists (Join-Path $ReplayRoot 'TEST_CHARTER.md')
    if (-not [string]::IsNullOrWhiteSpace($charter)) {
        $sliceToken = 'S{0}' -f $SliceIndex
        foreach ($line in ($charter -split "`r?`n")) {
            if ($line -notmatch [regex]::Escape($sliceToken)) { continue }
            $match = [regex]::Match($line, '(?i)(?:[A-Za-z0-9_.\-]+[/\\])*src[/\\]test[/\\]java[/\\][A-Za-z0-9_./\\]+Test\.java(?:[#.][A-Za-z_][A-Za-z0-9_]*)?|\b[A-Za-z_][A-Za-z0-9_$.]*Test(?:[#.][A-Za-z_][A-Za-z0-9_]*)?\b')
            if ($match.Success) { return $match.Value }
        }
    }
    return ''
}

function Get-AnyPlannedTestName {
    param([string]$ReplayRoot)

    $textParts = New-Object System.Collections.Generic.List[string]
    foreach ($fileName in @('TEST_CHARTER.md', 'REPLAY_PLAN.md', 'IMPLEMENTATION_CONTRACT.md')) {
        $textParts.Add((Read-TextIfExists -Path (Join-Path $ReplayRoot $fileName))) | Out-Null
    }
    $texts = @($textParts.ToArray()) -join "`n"
    if ([string]::IsNullOrWhiteSpace($texts)) { return '' }

    $commandMatch = [regex]::Match($texts, '(?i)-Dtest=([A-Z][A-Za-z0-9_]*Test(?:[#.][A-Za-z_][A-Za-z0-9_]*)?)')
    if ($commandMatch.Success) { return $commandMatch.Groups[1].Value.Trim() }

    $methodMatch = [regex]::Match($texts, '\b([A-Z][A-Za-z0-9_]*Test\.[A-Za-z_][A-Za-z0-9_]*)\b')
    if ($methodMatch.Success) { return $methodMatch.Groups[1].Value.Trim() }

    $classMatch = [regex]::Match($texts, '\b([A-Z][A-Za-z0-9_]*Test)\b')
    if ($classMatch.Success) { return $classMatch.Groups[1].Value.Trim() }

    return ''
}

function Get-TestClassLeafFromCarrier {
    param([string]$Carrier)
    if ([string]::IsNullOrWhiteSpace($Carrier)) { return '' }
    $head = @(([string]$Carrier -split '\s*->\s*') | Select-Object -First 1)[0]
    $head = @(([string]$head -split '\(') | Select-Object -First 1)[0]
    $typedMatches = @([regex]::Matches($head, '\b(?<class>[A-Z][A-Za-z0-9_]*(?:Service|Controller|Facade|Processor|Handler|Task|Client|Provider|Repository|Mapper|Dao|DAO)(?:Impl)?)\b'))
    if ($typedMatches.Count -gt 0) {
        return [string]$typedMatches[$typedMatches.Count - 1].Groups['class'].Value
    }
    $methodMatches = @([regex]::Matches($head, '\b(?<class>[A-Z][A-Za-z0-9_]*)[.#][A-Za-z_][A-Za-z0-9_]*\b'))
    if ($methodMatches.Count -gt 0) {
        return [string]$methodMatches[$methodMatches.Count - 1].Groups['class'].Value
    }
    return ''
}

function Get-DefaultSliceTestName {
    param([string]$Carrier, [string]$FamilyId)
    $classLeaf = Get-TestClassLeafFromCarrier -Carrier $Carrier
    if ([string]::IsNullOrWhiteSpace($classLeaf)) { return '' }
    $familyToken = if ([string]::IsNullOrWhiteSpace($FamilyId)) { 'Slice' } else {
        [regex]::Replace($FamilyId.ToLowerInvariant(), '(^|_)([a-z])', {
            param($m)
            $m.Groups[2].Value.ToUpperInvariant()
        })
    }
    return "${classLeaf}Test#shouldCover$familyToken"
}

function Test-ClassOnlyCarrier {
    param([string]$Carrier)
    if ([string]::IsNullOrWhiteSpace($Carrier)) { return $false }
    $head = @(([string]$Carrier -split '\s*->\s*') | Select-Object -First 1)[0]
    $head = @(([string]$head -split '\(') | Select-Object -First 1)[0]
    $leaf = @(([string]$head -split '\.') | Select-Object -Last 1)[0]
    return ($leaf -match '^[A-Z][A-Za-z0-9_]*(?:Service|Controller|Facade|Processor|Handler|Task|Client|Provider|Repository|Mapper|Dao|DAO)(?:Impl)?$')
}

function Resolve-MethodCarrierFromProof {
    param(
        [string]$Carrier,
        [string[]]$ProofRequired,
        [string]$FamilyId
    )

    if (-not (Test-ClassOnlyCarrier -Carrier $Carrier)) { return $Carrier }
    $proofText = (@($ProofRequired) -join ' ')
    $proofTokenText = $proofText -replace '[_\-.]+', ' '
    $method = ''
    if ($proofTokenText -match '(?i)\b(persist|save|insert|update|delete|clear|reject|invalid|amount|config|threshold|free|review)\b') {
        $method = 'save'
    } elseif ($proofTokenText -match '(?i)\b(query|read|load|get|return|display|list|page)\b') {
        $method = 'queryById'
    } elseif ($proofTokenText -match '(?i)\b(gate|enabled|check|module)\b' -or [string]$FamilyId -eq 'config_policy_threshold') {
        $method = 'checkReviewModuleEnabled'
    }
    if ([string]::IsNullOrWhiteSpace($method)) { return $Carrier }
    return "$Carrier.$method"
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
$ledgerFull = Resolve-AbsolutePath $RequirementFamilyLedger
$surfaceCarrierScanFull = if ([string]::IsNullOrWhiteSpace($SurfaceCarrierScan)) { '' } else { Resolve-AbsolutePath $SurfaceCarrierScan }

$carrierPath = Join-Path $replayRootFull ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
$exactPath = Join-Path $replayRootFull ('EXACT_CONTRACT_ASSERTION_MATRIX_{0:D2}.json' -f $SliceIndex)
$sideEffectPath = Join-Path $replayRootFull ('SIDE_EFFECT_EVIDENCE_{0:D2}.json' -f $SliceIndex)
$sourceChainPath = Join-Path $replayRootFull 'SOURCE_CHAIN_CONTRACT.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $replayRootFull
        worktree = $worktreeFull
        slice_index = $SliceIndex
        carrier_authorization = $carrierPath
        exact_contract_assertion_matrix = $exactPath
        side_effect_evidence = $sideEffectPath
    } | ConvertTo-Json -Depth 8
    exit 0
}

if (-not (Test-Path -LiteralPath $ledgerFull)) {
    throw "Requirement family ledger not found: $ledgerFull"
}

$ledger = Read-JsonObject -Path $ledgerFull
$family = $null
if (-not [string]::IsNullOrWhiteSpace($ForcedRequirementFamily)) {
    $family = @($ledger.families | Where-Object { [string]$_.id -eq $ForcedRequirementFamily } | Select-Object -First 1)
    if ($family.Count -gt 0) { $family = $family[0] } else { $family = $null }
}

$proofRequired = if ($null -ne $family) { @(Get-StringArray $family.proof_required) } else { @() }
$forbiddenProof = if ($null -ne $family) { @(Get-StringArray $family.forbidden_proof) } else { @() }
$selectedCarrier = if ($null -ne $family) { [string]$family.first_executable_carrier } else { '' }
$selectedCarrier = Resolve-MethodCarrierFromProof -Carrier $selectedCarrier -ProofRequired $proofRequired -FamilyId $ForcedRequirementFamily
$realEntry = $selectedCarrier
$plannedTestName = ''
$plannedRedResult = 'PENDING'
$sourceChain = $null
if (Test-Path -LiteralPath $sourceChainPath) {
    try { $sourceChain = Read-JsonObject -Path $sourceChainPath } catch { $sourceChain = $null }
}
$firstSlicePlanText = Read-TextIfExists (Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md')
$implementationContractText = Read-TextIfExists (Join-Path $replayRootFull 'IMPLEMENTATION_CONTRACT.md')
$planText = @($firstSlicePlanText, $implementationContractText) -join "`n"
$firstPlannedTestName = Get-PlanField -Text $planText -Name 'first_red_test'
$firstPlannedCarrier = Get-PlanField -Text $planText -Name 'selected_carrier'
$firstPlannedEntry = Get-PlanField -Text $planText -Name 'selected_real_entry'

if ($SliceIndex -eq 1 -and $ForcedRequirementFamily -eq 'core_entry') {
    if (-not [string]::IsNullOrWhiteSpace($firstPlannedCarrier)) {
        $selectedCarrier = $firstPlannedCarrier
    }
    if (-not [string]::IsNullOrWhiteSpace($firstPlannedEntry)) {
        $realEntry = $firstPlannedEntry
    }
    if (-not [string]::IsNullOrWhiteSpace($firstPlannedTestName)) {
        $plannedTestName = $firstPlannedTestName
        $plannedRedResult = 'PENDING_BUSINESS_ASSERTION'
    }
}
if ([string]::IsNullOrWhiteSpace($plannedTestName)) {
    $plannedFromSlicePlan = Get-SlicePlannedTestName -ReplayRoot $replayRootFull -SliceIndex $SliceIndex
    if (-not [string]::IsNullOrWhiteSpace($plannedFromSlicePlan)) {
        $plannedTestName = $plannedFromSlicePlan
        $plannedRedResult = 'PENDING_BUSINESS_ASSERTION'
    }
}

$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
if ($null -ne $sourceChain -and [bool]$sourceChain.required_source_chain -and $null -ne $sourceChain.next_required_slice) {
    $sourceCarrier = [string]$sourceChain.next_required_slice.carrier
    $sourceEntry = [string]$sourceChain.next_required_slice.entry
    $sourceTestName = [string]$sourceChain.next_required_slice.test_name
    $sourceText = @($sourceCarrier, $sourceEntry, $sourceTestName) -join "`n"
    $plannedText = @($firstPlannedCarrier, $firstPlannedTestName) -join "`n"
    $firstSlicePlanLocksNonSourceCarrier = (
        $SliceIndex -eq 1 -and
        [string]$ForcedRequirementFamily -eq 'core_entry' -and
        -not [string]::IsNullOrWhiteSpace($firstPlannedCarrier) -and
        -not [string]::IsNullOrWhiteSpace($sourceText) -and
        $sourceText -notmatch [regex]::Escape($firstPlannedCarrier) -and
        $plannedText -notmatch '(?i)\b(rebuildTaskData|source_chain|source[-_\s]?chain|source field|wire field|input_data)\b'
    )
    $sourceApplies = (
        -not $firstSlicePlanLocksNonSourceCarrier -and
        [string]$ForcedSliceType -eq 'exact_contract_slice' -and
        (
            [string]$ForcedSiblingSurface -eq $sourceCarrier -or
            [string]$ForcedSiblingSurface -match '(?i)CaseRoute|Insure|RequestBuildContext|AiClaimBaseRequest|source' -or
            [string]$ForcedRequirementFamily -eq 'core_entry'
        )
    )
    if ($sourceApplies) {
        $selectedCarrier = [string]$sourceChain.next_required_slice.entry
        $proofRequired = @(Get-StringArray $sourceChain.next_required_slice.required_assertions)
        $forbiddenProof = @(Get-StringArray $sourceChain.next_required_slice.forbidden_proof)
        $plannedTestName = [string]$sourceChain.next_required_slice.test_name
        $plannedRedResult = 'PENDING_BUSINESS_ASSERTION'
    }
    if ($firstSlicePlanLocksNonSourceCarrier) {
        $warnings.Add('source_chain_contract_preserved_for_later_slice_plan_lock_kept') | Out-Null
    }
}
$downstreamTarget = if ($proofRequired.Count -gt 0) {
    (@($proofRequired | Select-Object -First 4) -join '; ')
} else {
    Get-DefaultEvidenceTarget -FamilyId $ForcedRequirementFamily -SliceType $ForcedSliceType
}

if ([string]::IsNullOrWhiteSpace($ForcedRequirementFamily)) {
    $warnings.Add('forced_requirement_family_missing') | Out-Null
}
if ($null -eq $family -and -not [string]::IsNullOrWhiteSpace($ForcedRequirementFamily)) {
    $issues.Add('forced_family_not_found_in_ledger') | Out-Null
}
if ([string]::IsNullOrWhiteSpace($selectedCarrier)) {
    $issues.Add('selected_carrier_missing') | Out-Null
}
if (Test-SyntheticCarrierText -Text $selectedCarrier) {
    $issues.Add('synthetic_carrier_selected') | Out-Null
}
if ($null -ne $family -and [bool]$family.required -and (Test-HelperOnlyCarrierText -Text $selectedCarrier)) {
    $issues.Add('helper_or_static_only_carrier_for_high_weight_family') | Out-Null
}
if ([string]::IsNullOrWhiteSpace($downstreamTarget)) {
    $issues.Add('downstream_side_effect_or_output_missing') | Out-Null
}
if ($selectedCarrier -match '(?i)\bplanned\b|\bcandidate\b|\bTBD\b|\bpending\b') {
    $issues.Add('carrier_is_planned_or_not_concrete') | Out-Null
}

$requiresSideEffectEvidence = (
    @('core_entry', 'stateful_side_effect', 'generated_artifact_template_upload', 'lifecycle_cleanup_retention') -contains $ForcedRequirementFamily -or
    [string]$ForcedSliceType -match '(?i)stateful'
)
$requiresExactContract = (
    @('wire_payload_api_contract', 'config_policy_threshold', 'deploy_export_page', 'generated_artifact_template_upload', 'automation_test_interface', 'external_integration', 'lifecycle_cleanup_retention') -contains $ForcedRequirementFamily -or
    (($proofRequired -join ' ') -match '(?i)exact|literal|field|wire|display|payload|header|column|copy|string|contract')
)
if ([string]::IsNullOrWhiteSpace($plannedTestName) -and $requiresExactContract) {
    $plannedTestName = if ($SliceIndex -eq 1) {
        Get-AnyPlannedTestName -ReplayRoot $replayRootFull
    } else {
        Get-DefaultSliceTestName -Carrier $selectedCarrier -FamilyId $ForcedRequirementFamily
    }
    if (-not [string]::IsNullOrWhiteSpace($plannedTestName)) {
        $plannedRedResult = 'PENDING_BUSINESS_ASSERTION'
        $warnings.Add("planned_test_name_inferred_for_exact_contract:$plannedTestName") | Out-Null
    }
}
if ([string]::IsNullOrWhiteSpace($plannedTestName) -and $requiresSideEffectEvidence) {
    $plannedTestName = Get-DefaultSliceTestName -Carrier $selectedCarrier -FamilyId $ForcedRequirementFamily
    if (-not [string]::IsNullOrWhiteSpace($plannedTestName)) {
        $plannedRedResult = 'PENDING_BUSINESS_ASSERTION'
        $warnings.Add("planned_test_name_inferred_for_forced_carrier:$plannedTestName") | Out-Null
    }
}
$preGuardWrites = @()
if ($requiresSideEffectEvidence -and [string]$ForcedSliceType -match '(?i)stateful|lifecycle') {
    $preGuardWrites = @(Find-PreGuardWriteCalls -WorktreeRoot $worktreeFull -Carrier $selectedCarrier)
}

$authorization = if ($issues.Count -eq 0) { 'ALLOW' } else { 'STOP' }
$redExpectation = if (-not [string]::IsNullOrWhiteSpace($plannedTestName)) {
    "business assertion should fail in $plannedTestName before production change"
} else {
    ''
}
$carrierObject = [ordered]@{
    schema_version = 1
    slice_index = $SliceIndex
    forced_requirement_family = $ForcedRequirementFamily
    forced_slice_type = $ForcedSliceType
    forced_sibling_surface = $ForcedSiblingSurface
    authorization = $authorization
    real_entry = $realEntry
    selected_carrier = $selectedCarrier
    production_boundary = $selectedCarrier
    downstream_side_effect_or_output = $downstreamTarget
    red_expectation = $redExpectation
    requires_side_effect_evidence = $requiresSideEffectEvidence
    requires_exact_contract_assertions = $requiresExactContract
    forbidden_synthetic_carrier = (Test-SyntheticCarrierText -Text $selectedCarrier)
    forbidden_helper_only_carrier = (Test-HelperOnlyCarrierText -Text $selectedCarrier)
    proof_required = @($proofRequired)
    forbidden_proof = @($forbiddenProof)
    issues = @($issues)
    warnings = @($warnings)
    gate = 'production_carrier_authorization'
}
$carrierObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $carrierPath -Encoding UTF8
$carrierObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $replayRootFull 'CARRIER_AUTHORIZATION.json') -Encoding UTF8

$exactSources = @(
    (Join-Path $replayRootFull 'IMPLEMENTATION_CONTRACT.md'),
    (Join-Path $replayRootFull 'ROUND_CONTRACT.md'),
    (Join-Path $replayRootFull 'EXPECTED_DIFF_MATRIX.md'),
    (Join-Path $replayRootFull 'TEST_CHARTER.md'),
    (Join-Path $replayRootFull 'FAMILY_CONTRACT.json')
)
$sideEffectExactScope = (
    $requiresExactContract -and
    $requiresSideEffectEvidence -and
    $proofRequired.Count -gt 0 -and
    (
        [string]$ForcedSliceType -match '(?i)stateful|lifecycle' -or
        @('generated_artifact_template_upload', 'lifecycle_cleanup_retention') -contains $ForcedRequirementFamily
    )
)
$familyProofExactScope = (
    $requiresExactContract -and
    -not $sideEffectExactScope -and
    $proofRequired.Count -gt 0 -and
    -not [string]::IsNullOrWhiteSpace($ForcedRequirementFamily) -and
    -not [string]::IsNullOrWhiteSpace($selectedCarrier)
)
$exactRowScope = if ($sideEffectExactScope) {
    'side_effect_proof_required'
} elseif ($familyProofExactScope) {
    'family_proof_required'
} else {
    'requirement_literals'
}
if ($sideEffectExactScope -or $familyProofExactScope) {
    if ($familyProofExactScope) {
        $warnings.Add('exact_contract_scope_from_family_proof_required') | Out-Null
    }
    $exactRows = @($proofRequired | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique | ForEach-Object {
        $row = New-SideEffectExactContractRow -Literal ([string]$_) -SelectedCarrier $selectedCarrier -FamilyId $ForcedRequirementFamily
        if (-not [string]::IsNullOrWhiteSpace($plannedTestName)) {
            $row.red_command = "run focused RED test: $plannedTestName"
        }
        $row
    })
} else {
    $exactText = (($exactSources | ForEach-Object { Read-TextIfExists -Path $_ }) -join "`n")
    $literals = @(Get-ExactLiteralsFromText -Text $exactText)
    $exactRows = @($literals | ForEach-Object {
        $row = New-ExactContractRow -Literal ([string]$_) -SelectedCarrier $selectedCarrier
        if (-not [string]::IsNullOrWhiteSpace($plannedTestName)) {
            $row.red_command = "run focused RED test: $plannedTestName"
        }
        $row
    })
}
[ordered]@{
    schema_version = 1
    slice_index = $SliceIndex
    forced_requirement_family = $ForcedRequirementFamily
    required_for_this_slice = $requiresExactContract
    row_scope = $exactRowScope
    rows = @($exactRows)
    gate = 'exact_contract_assertion_lock'
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $exactPath -Encoding UTF8
Copy-Item -LiteralPath $exactPath -Destination (Join-Path $replayRootFull 'EXACT_CONTRACT_ASSERTION_MATRIX.json') -Force

$sideEffectStatus = if ($requiresSideEffectEvidence -and -not [string]::IsNullOrWhiteSpace($realEntry) -and $proofRequired.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($plannedTestName)) {
    'READY'
} elseif ($requiresSideEffectEvidence) {
    'PLANNED'
} else {
    'NOT_REQUIRED'
}

[ordered]@{
    schema_version = 1
    slice_index = $SliceIndex
    forced_requirement_family = $ForcedRequirementFamily
    required_for_this_slice = $requiresSideEffectEvidence
    entry_call = $realEntry
    expected_writes_or_outputs = @($proofRequired | Select-Object -First 8)
    must_not_writes = @($preGuardWrites)
    test_name = $plannedTestName
    red_result = $plannedRedResult
    green_result = 'PENDING'
    status = $sideEffectStatus
    gate = 'stateful_side_effect_evidence_harness'
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sideEffectPath -Encoding UTF8
Copy-Item -LiteralPath $sideEffectPath -Destination (Join-Path $replayRootFull 'SIDE_EFFECT_EVIDENCE.json') -Force

$carrierObject | ConvertTo-Json -Depth 12
