param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [ValidateSet('Phase0', 'Plan')]
    [string]$Stage = 'Phase0',
    [switch]$ValidateOnly,
    [switch]$SkipCarrierAndOracleChecks,
    [string]$Worktree = ''
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

function Repair-EscapedLineBreaks {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $literalNewline = [char]96 + 'n'
    $literalCarriageReturn = [char]96 + 'r'
    $literalCrLf = $literalCarriageReturn + $literalNewline

    $literalNewlineCount = [regex]::Matches($Text, [regex]::Escape($literalNewline)).Count
    $actualNewlineCount = [regex]::Matches($Text, "`n").Count
    if ($literalNewlineCount -lt 2) { return $Text }

    $fixed = $Text
    $lineLeadingLiteralCount = [regex]::Matches($fixed, '(?m)^[ \t]*' + [regex]::Escape($literalNewline)).Count
    if ($actualNewlineCount -le 2) {
        $fixed = $fixed.Replace("`r$literalNewline", "`r`n")
        $fixed = $fixed.Replace($literalCrLf, "`r`n")
        $fixed = $fixed.Replace($literalNewline, "`r`n")
        $fixed = [regex]::Replace($fixed, "`r(?!`n)", "`r`n")
    } elseif ($lineLeadingLiteralCount -ge 2) {
        $fixed = [regex]::Replace($fixed, '(?m)^([ \t]*)' + [regex]::Escape($literalNewline), '$1')
    }
    return $fixed
}

function Repair-PlanArtifactLineBreaks {
    param(
        [string]$Path,
        [string]$ArtifactName,
        [System.Collections.Generic.List[string]]$Warnings
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $fixed = Repair-EscapedLineBreaks -Text $content
    if ($fixed -ne $content) {
        Set-Content -LiteralPath $Path -Value $fixed -Encoding UTF8
        $Warnings.Add("plan_artifact_linebreaks_normalized:$ArtifactName") | Out-Null
    }
}

function Get-FirstText {
    param([string]$Text, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }
    return ''
}

# v460/v596: Get-KeyValueField supports table format and Markdown bold-bullet
# key lines such as "- **field**: value". Agents often produce that shape even
# when prompts ask for key:value lines, so the verifier should parse it rather
# than report false schema-missing issues.
function Get-KeyValueField {
    param([string]$Text, [string]$Field)
    $escapedField = [regex]::Escape($Field)
    foreach ($line in ($Text -split "\r?\n")) {
        $lineMatch = [regex]::Match($line.Trim(), '^(?:[-*]\s*)?(?:\*{0,2}\s*)?' + $escapedField + '\s*\*{0,2}\s*[:=|][ \t]*(.+?)\s*$')
        if ($lineMatch.Success) {
            return $lineMatch.Groups[1].Value.Trim()
        }
    }
    # v460: Table format pattern at end handles Markdown tables (| **field** | value |)
    # v460: Fixed array syntax - wrap complex expressions in parentheses
    $patterns = @(
        ('(?im)^\s*(?:[-*]\s*)?(?:\*{0,2}\s*)?' + $escapedField + '\s*\*{0,2}\s*[:=|][ \t]*([^\r\n]+?)\s*$'),
        ('(?im)^\s*(?:[-*]\s*)?(?:\*{0,2}\s*)?' + $escapedField + '\s*\*{0,2}\s*[:=|][ \t]*\r?\n\s*:\s*([^\r\n]+?)\s*$'),
        ('(?im)\|\s*\*{0,2}' + $escapedField + '\*{0,2}\s*\|\s*`?([^\r\n|]+?)`?\s*\|')
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Text, $pattern)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }
    return ''
}

function Normalize-Phase0Status {
    param([string]$Status, [string]$Phase0Text)
    $normalized = ([string]$Status).Trim().Trim('`').Trim('*').Trim()
    if ($normalized -eq 'Status' -or $normalized -eq 'Summary') {
        $statusLabelPattern = '(?mi)^##\s*Phase\s*0\s*Status\s*\r?\n\s*(?:\r?\n)?\s*\*{0,2}Status\*{0,2}\s*[:=]\s*`?([A-Z_]+)`?'
        $match = [regex]::Match($Phase0Text, $statusLabelPattern)
        if ($match.Success) { $normalized = $match.Groups[1].Value.Trim() }
    }
    # Backward-compatible observed variants covered by the generic rules:
    # CAVEATS|CAVIETS|CAVETS and GREEN_PROCEED / READY_PROCEED style values.
    if ($normalized -match '^PROCEED_WITH_[A-Z_]+$') { return 'PROCEED' }
    if ($normalized -match '^[A-Z_]+_PROCEED$') { return 'PROCEED' }
    return $normalized
}

function Convert-SelectedRealEntryToText {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return ([string]$Value).Trim() }

    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        if ($item -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace($item)) { $entries.Add(([string]$item).Trim()) | Out-Null }
            continue
        }

        $carrierClass = [string]$item.carrier_class
        if ([string]::IsNullOrWhiteSpace($carrierClass)) { $carrierClass = [string]$item.processor }
        $method = [string]$item.method
        if (-not [string]::IsNullOrWhiteSpace($carrierClass) -and -not [string]::IsNullOrWhiteSpace($method)) {
            $classLeaf = ($carrierClass -split '\.')[-1]
            $entries.Add("$classLeaf.$method") | Out-Null
            continue
        }

        $carrier = [string]$item.carrier
        if (-not [string]::IsNullOrWhiteSpace($carrier)) {
            $entries.Add($carrier.Trim()) | Out-Null
            continue
        }

        $candidate = [string]$item.selected_real_entry
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $entries.Add($candidate.Trim()) | Out-Null
        }
    }
    return (@($entries.ToArray()) -join ', ')
}

function Test-PolicySpringHarnessResidue {
    param([string]$Text)

    $inNegativeList = $false
    foreach ($line in ($Text -split "\r?\n")) {
        $trimmed = $line.Trim()
        $negativeSection = $trimmed -match '(?i)^(?:#{1,6}\s*)?(?:\*\*)?\s*(avoid|forbidden|forbidden paths|do\s+not\s+use|do\s+not|must\s+not|not\s+allowed|no[-\s]?spring|non[-\s]?spring|禁止|不得|不要)\b'
        if ($negativeSection) {
            $inNegativeList = $true
        } elseif ($trimmed -match '^(?:#{1,6}\s+|\*\*[^*]+:\*\*)' -and $trimmed -notmatch '(?i)(avoid|forbidden|do\s+not|must\s+not|not\s+allowed|禁止|不得|不要)') {
            $inNegativeList = $false
        }

        if ($line -notmatch '(?i)(AbstractTestClass|@SpringBootTest|SpringJUnit4ClassRunner|@ContextConfiguration|@Resource|\bSpring\s+context\b)') {
            continue
        }
        if ($inNegativeList) {
            continue
        }
        if ($line -match '(?i)(no[-\s]?spring|\bno\s+@|\bno\s+AbstractTestClass\b|\bno\s+Spring\s+context\b|do\s+not|don''t|without|not\s+use|must\s+not|forbid|forbidden|禁止|不得|不要|不使用)') {
            continue
        }
        return $true
    }

    return $false
}

function Add-MissingFileIssue {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Root,
        [string]$Name
    )
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Name))) {
        $Issues.Add("missing_file:$Name") | Out-Null
    }
}

function Add-MissingTokenIssue {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Text,
        [string]$Token,
        [string]$Issue
    )
    if ($Text.IndexOf($Token, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        $Issues.Add($Issue) | Out-Null
    }
}

function Add-MissingAnyTokenIssue {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Text,
        [string[]]$Tokens,
        [string]$Issue
    )
    foreach ($token in $Tokens) {
        if ($Text.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return
        }
    }
    $Issues.Add($Issue) | Out-Null
}

function Add-RegexIssueWithEvidence {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [System.Collections.Generic.List[object]]$Evidence,
        [string]$Issue,
        [string]$Pattern,
        [object[]]$Artifacts
    )

    $matched = $false
    foreach ($artifact in @($Artifacts)) {
        if ($null -eq $artifact -or [string]::IsNullOrWhiteSpace([string]$artifact.text)) {
            continue
        }

        $text = [string]$artifact.text
        $match = [regex]::Match($text, $Pattern)
        if (-not $match.Success) {
            continue
        }

        $matched = $true
        $start = [Math]::Max(0, $match.Index - 80)
        $length = [Math]::Min(260, $text.Length - $start)
        $snippet = $text.Substring($start, $length) -replace '\s+', ' '
        $Evidence.Add([ordered]@{
            issue = $Issue
            artifact = [string]$artifact.name
            pattern = $Pattern
            snippet = $snippet.Trim()
        }) | Out-Null
    }

    if ($matched) {
        $Issues.Add($Issue) | Out-Null
    }
}

function Add-LineRegexIssueWithEvidence {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [System.Collections.Generic.List[object]]$Evidence,
        [string]$Issue,
        [string]$Pattern,
        [object[]]$Artifacts
    )

    $matched = $false
    foreach ($artifact in @($Artifacts)) {
        if ($null -eq $artifact -or [string]::IsNullOrWhiteSpace([string]$artifact.text)) {
            continue
        }

        $lineNumber = 0
        foreach ($line in ([string]$artifact.text -split "\r?\n")) {
            $lineNumber++
            if ($line -notmatch $Pattern) { continue }
            $matched = $true
            $Evidence.Add([ordered]@{
                issue = $Issue
                artifact = [string]$artifact.name
                line = $lineNumber
                pattern = $Pattern
                snippet = $line.Trim()
            }) | Out-Null
        }
    }

    if ($matched) {
        $Issues.Add($Issue) | Out-Null
    }
}

function Add-FixedCaseIdIssueWithEvidence {
    param(
        [System.Collections.Generic.List[string]]$Issues,
        [System.Collections.Generic.List[object]]$Evidence,
        [object[]]$Artifacts
    )

    $pattern = '(?i)(fixed\s+(database\s+)?caseId|fixed\s+DB\s+caseId|real\s+database\s+caseId|external\s+test\s+data|\b(?:caseId|mockContext|ctx)\b[^\r\n]{0,80}\b(?:12345L|67890L)\b|\bLong\s+caseId\s*=\s*(?:12345L|67890L)\b)'
    $negativeContextPattern = '(?i)\b(not|no|without|avoid(?:ing)?|forbid(?:den)?|禁止|不使用|非)\b[^\r\n]{0,80}\b(fixed\s+(database\s+)?caseId|fixed\s+DB\s+caseId|real\s+database\s+caseId|external\s+test\s+data)\b|symbolic\s+fixture[^\r\n]{0,80}\bnot\s+fixed\s+database\s+caseId\b'
    $matched = $false

    foreach ($artifact in @($Artifacts)) {
        if ($null -eq $artifact -or [string]::IsNullOrWhiteSpace([string]$artifact.text)) {
            continue
        }

        $lineNumber = 0
        foreach ($line in ([string]$artifact.text -split "\r?\n")) {
            $lineNumber++
            if ($line -notmatch $pattern) { continue }
            if ($line -match $negativeContextPattern -and $line -notmatch '(?i)\b(?:caseId|mockContext|ctx)\b[^\r\n]{0,80}\b(?:12345L|67890L)\b|\bLong\s+caseId\s*=\s*(?:12345L|67890L)\b') {
                continue
            }

            $matched = $true
            $Evidence.Add([ordered]@{
                issue = 'policy_rebuild_plan_invalid:fixed_db_caseid'
                artifact = [string]$artifact.name
                line = $lineNumber
                pattern = $pattern
                snippet = $line.Trim()
            }) | Out-Null
        }
    }

    if ($matched) {
        $Issues.Add('policy_rebuild_plan_invalid:fixed_db_caseid') | Out-Null
    }
}

# v443: Layer-First Pre-Validation - Detect layer from carrier path or class name
function Test-CarrierLayer {
    param([string]$CarrierPath)

    $cleanPath = ([string]$CarrierPath).Trim().Trim('`').Trim('*').Trim()

    if ($cleanPath -match "(\\|/)facade(\\|/)|Facade\b") { return "Facade" }
    elseif ($cleanPath -match "(\\|/)controller(\\|/)|Controller\b") { return "Controller" }
    elseif ($cleanPath -match "(\\|/)service(\\|/)|Service\b") { return "Service" }
    elseif ($cleanPath -match "(\\|/)provider(\\|/)|Provider\b|Mapper\b") { return "Provider" }
    else { return "Unknown" }
}

# v443: Get-SuggestedFacade - Search for corresponding Facade when Service layer is detected
function Get-SuggestedFacade {
    param(
        [string]$ServiceCarrier,
        [string]$Worktree
    )

    if ([string]::IsNullOrWhiteSpace($ServiceCarrier)) {
        return @{ Found = $false; ClassName = $null; SearchOutput = $null }
    }

    $serviceName = [System.IO.Path]::GetFileNameWithoutExtension($ServiceCarrier)
    $serviceName = $serviceName.Trim('`', '*', ',', ';', ':')

    # Generate facade search patterns
    $patterns = @(
        ($serviceName -replace "Service$", "Facade"),
        ($serviceName -replace "Service$", "Controller"),
        ($serviceName -replace "ServiceImpl$", "Facade"),
        ($serviceName -replace "Service$", "Api")
    )

    $rgWrapper = Join-Path $PSScriptRoot '..\tools\rg-wrapper.ps1'
    if (-not (Test-Path -LiteralPath $rgWrapper)) {
        $rgWrapper = Join-Path $PSScriptRoot 'tools\rg-wrapper.ps1'
    }

    foreach ($pattern in $patterns) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }

        $searchPattern = "class\s+$pattern\s"
        try {
            if (Test-Path -LiteralPath $rgWrapper) {
                $rgOutput = & $rgWrapper @(
                    '--type', 'java',
                    '-l',
                    $searchPattern
                ) 2>&1
                if ($LASTEXITCODE -eq 0 -and $rgOutput) {
                    $outputLines = @($rgOutput -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    if ($outputLines.Count -gt 0) {
                        return @{
                            Found = $true
                            ClassName = $pattern
                            SearchOutput = $outputLines[0]
                        }
                    }
                }
            }
        } catch {
            # Silently fall through if rg fails
        }
    }

    return @{ Found = $false; ClassName = $null; SearchOutput = $null }
}

function Get-PlanBindingCandidates {
    param([string]$Value)
    $clean = ([string]$Value).Trim().Trim('`').Trim('*').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return @() }
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add($clean) | Out-Null
    $beforeDash = [regex]::Split($clean, '\s+-\s+')[0].Trim()
    if (-not [string]::IsNullOrWhiteSpace($beforeDash)) { $candidates.Add($beforeDash) | Out-Null }
    $firstToken = ($clean -split '\s+')[0].Trim('`', '*', ',', ';', ':')
    if (-not [string]::IsNullOrWhiteSpace($firstToken)) { $candidates.Add($firstToken) | Out-Null }
    if ($firstToken -match '^(?i)S(\d+)$') {
        $sliceNumber = [int]$Matches[1]
        $candidates.Add("slice $sliceNumber") | Out-Null
        $candidates.Add("slice_$sliceNumber") | Out-Null
        $candidates.Add("SLICE_INDEX=$sliceNumber") | Out-Null
        if ($sliceNumber -eq 1) {
            $candidates.Add('first slice') | Out-Null
            $candidates.Add('first_slice') | Out-Null
        }
    }
    $methodToken = [regex]::Match($clean, '[A-Za-z0-9_.$]+#[A-Za-z0-9_.$]+')
    if ($methodToken.Success) { $candidates.Add($methodToken.Value) | Out-Null }
    return @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$verifyPath = Join-Path $replayRootFull ('{0}_CONTRACT_VERIFY.json' -f $Stage.ToUpperInvariant())

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $replayRootFull
        stage = $Stage
        verify_path = $verifyPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$issueEvidence = New-Object System.Collections.Generic.List[object]

# Default required families; override with FAMILY_CONTRACT.json if present
$defaultRequiredFamilies = @(
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
$familyContractPath = Join-Path $replayRootFull 'FAMILY_CONTRACT.json'
$declaredFamilyIds = @()
if (Test-Path -LiteralPath $familyContractPath) {
    try {
        $familyJson = Get-Content -LiteralPath $familyContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $declaredFamilyIds = @($familyJson.families | ForEach-Object { [string]$_.id })
    } catch {}
}
# If FAMILY_CONTRACT.json declares families, validate against those instead of the hardcoded list
$requiredFamilies = if ($declaredFamilyIds.Count -gt 0) { $declaredFamilyIds } else { $defaultRequiredFamilies }

if (-not (Test-Path -LiteralPath $replayRootFull)) {
    throw "Replay root not found: $replayRootFull"
}

if ($Stage -eq 'Phase0') {
    foreach ($file in @('EXPLORATION_REPORT.md', 'ROUND_CONTRACT.md', 'FAMILY_CONTRACT.json', 'PHASE0_RESULT.md')) {
        Add-MissingFileIssue -Issues $issues -Root $replayRootFull -Name $file
    }

    $phase0Text = Read-TextIfExists (Join-Path $replayRootFull 'PHASE0_RESULT.md')
    $contractText = Read-TextIfExists (Join-Path $replayRootFull 'ROUND_CONTRACT.md')
    $explorationText = Read-TextIfExists (Join-Path $replayRootFull 'EXPLORATION_REPORT.md')
    $familyContractPath = Join-Path $replayRootFull 'FAMILY_CONTRACT.json'
    $familyContract = $null
    if (Test-Path -LiteralPath $familyContractPath) {
        try {
            $familyContract = Get-Content -LiteralPath $familyContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            $issues.Add('family_contract_json_invalid') | Out-Null
            $warnings.Add($_.Exception.Message) | Out-Null
        }
    }

    $phase0StatusRaw = Get-FirstText $phase0Text @(
        '(?m)^\s*-?\s*phase0_status\s*[:=]\s*[`*]*([A-Z_]+)[`*]*',
        '(?m)\bphase0_status\b[^\nA-Z_]*([A-Z_]{3,})',
        '(?mi)^##\s*Decision\s*[:=]*\s*[^A-Z_\r\n]*([A-Z_]+)',
        '(?mi)^##\s*Phase\s+0\s+Decision\s*[:=]*\s*[^A-Z_\r\n]*([A-Z_]+)',
        '(?mi)^\s*\*{0,2}Phase\s*0\s*Status\*{0,2}\s*[:=]\s*`?([A-Z_]+)`?',
        '(?mi)^##\s*Phase\s*0\s*Status\s*\r?\n\s*(?:\r?\n)?\s*\*{0,2}Status\*{0,2}\s*[:=]\s*`?([A-Z_]+)`?',
        '(?mi)^##\s*Phase\s*0\s*Status\s*[:=]*\s*[^A-Z_\r\n]*([A-Z_]+)',
        '(?mi)^##\s*Phase\s+0\s+Result\s*[:=]\s*`?([A-Z_]+)`?',
        '(?mi)^##\s*Status\s*[:=]\s*`?([A-Z_]+)`?',
        '(?m)\*\*phase0_status\*\*\s*[:=]\s*[`*]*([A-Z_]+)',
        '(?mi)^##\s*Phase\s*0\s*Status\s*\r?\n\s*\*{0,2}\s*([A-Z_]+)',
        '(?m)^\s*-?\s*status\s*[:=]\s*[`*]*([A-Z_]+)[`*]*'
    )
    $phase0StatusCandidate = ([string]$phase0StatusRaw).Trim().Trim('`').Trim('*').Trim()
    if ([string]::IsNullOrWhiteSpace($phase0StatusCandidate) -or $phase0StatusCandidate -eq 'Summary') {
        $phase0StatusRaw = Get-FirstText $contractText @(
            '(?m)^\s*-?\s*phase0_status\s*[:=]\s*[`*]*([A-Z_]+)[`*]*',
            '(?m)\bphase0_status\b[^\nA-Z_]*([A-Z_]{3,})'
        )
        $phase0StatusCandidate = ([string]$phase0StatusRaw).Trim().Trim('`').Trim('*').Trim()
    }
    if (([string]::IsNullOrWhiteSpace($phase0StatusCandidate) -or $phase0StatusCandidate -eq 'Summary') -and $null -ne $familyContract) {
        $phase0StatusRaw = [string]$familyContract.phase0_status
    }
    $phase0StatusOriginal = ([string]$phase0StatusRaw).Trim().Trim('`').Trim('*').Trim()
    if (-not [string]::IsNullOrWhiteSpace($phase0StatusOriginal) -and
        @('PROCEED', 'INVALID_PLAN', 'BLOCKED') -notcontains $phase0StatusOriginal) {
        $issues.Add("phase0_status_noncanonical:$phase0StatusOriginal") | Out-Null
    }
    $phase0Status = Normalize-Phase0Status -Status $phase0StatusRaw -Phase0Text $phase0Text
    if ($phase0Status -ne 'PROCEED') {
        $issues.Add("phase0_status_not_proceed:$phase0Status") | Out-Null
    }

    $combinedPhase0 = "$phase0Text`n$explorationText`n$contractText"
    # Try text patterns first, then fall back to FAMILY_CONTRACT.json
    $selectedRealEntry = Get-FirstText $combinedPhase0 @(
        '(?m)^\s*-?\s*selected_real_entry\s*[:=]\s*(.+?)\s*$',
        '(?m)\|\s*\*{0,2}selected_real_entry\*{0,2}\s*\|\s*`?([^\r\n|]+?)`?\s*\|',
        '(?m)\*\*Selected Real Entry\*\*[^\n:]*[:=]?\s*`?([^`*\n]+)`?'
    )
    $firstExecutableSlice = Get-FirstText $combinedPhase0 @(
        '(?m)^\s*-?\s*first_executable_slice\s*[:=]\s*(.+?)\s*$',
        '(?m)\|\s*\*{0,2}first_executable_slice\*{0,2}\s*\|\s*`?([^\r\n|]+?)`?\s*\|',
        '(?m)\*\*First Executable Slice\*\*[^\n:]*[:=]?\s*`?([^`*\n]+)`?'
    )
    $firstSliceType = Get-FirstText $combinedPhase0 @(
        '(?m)^\s*-?\s*first_slice_type\s*[:=]\s*[`*]*([A-Za-z_]+)[`*]*',
        '(?m)\|\s*first_slice_type\s*\|\s*`?([A-Za-z_]+)',
        '(?m)\*\*`?first_slice_type`?\*\*[^A-Za-z_]*([A-Za-z_]+)',
        '(?m)^\s*-?\s*slice_type\s*[:=]\s*[`*]*([A-Za-z_]+)[`*]*',
        '(?m)\*\*`?slice_type`?\*\*[^A-Za-z_]*([A-Za-z_]+)',
        '(?m)\*\*Type:?\*\*:?\s*[`*]*([A-Za-z_]+)',
        '(?m)^\s*-?\s*type\s*[:=]\s*[`*]*([A-Za-z_]+)[`*]*'
    )
    # Heuristic: if no pattern matched, infer core_path from context signals
    if ([string]::IsNullOrWhiteSpace($firstSliceType)) {
        $firstSliceIdx = $combinedPhase0.IndexOf('First Executable Slice', [System.StringComparison]::OrdinalIgnoreCase)
        if ($firstSliceIdx -lt 0) { $firstSliceIdx = $combinedPhase0.IndexOf('First Slice', [System.StringComparison]::OrdinalIgnoreCase) }
        if ($firstSliceIdx -lt 0) { $firstSliceIdx = $combinedPhase0.IndexOf('first_slice_type', [System.StringComparison]::OrdinalIgnoreCase) }
        if ($firstSliceIdx -ge 0) {
            $tail = $combinedPhase0.Substring($firstSliceIdx, [Math]::Min(600, $combinedPhase0.Length - $firstSliceIdx))
            if ($tail.IndexOf('core_path', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $tail.IndexOf('core_entry', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $tail.IndexOf('Core Path', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $tail.IndexOf('Core path', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $tail.IndexOf('Enum', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $tail.IndexOf('Service', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $tail.IndexOf('production', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $firstSliceType = 'core_path'
            }
        }
    }
    # Fallback to FAMILY_CONTRACT.json for selected_real_entry
    if ([string]::IsNullOrWhiteSpace($selectedRealEntry) -and $null -ne $familyJson) {
        $selectedRealEntry = Convert-SelectedRealEntryToText $familyJson.selected_real_entry
    }
    if ([string]::IsNullOrWhiteSpace($firstExecutableSlice) -and $null -ne $familyJson) {
        $firstExecutableSlice = [string]$familyJson.first_executable_slice
    }
    if ([string]::IsNullOrWhiteSpace($selectedRealEntry)) { $issues.Add('selected_real_entry_missing') | Out-Null }
    $placeholderPattern = '(?i)(\bTBD\b|\bunknown\b|\bN\s*/\s*A\b|\bplaceholder\b|' + ([char]0x5F85 + [char]0x786E + [char]0x8BA4) + '|' + ([char]0x5F85 + '\s*Oracle\s*' + [char]0x5BF9 + [char]0x6BD4 + [char]0x786E + [char]0x8BA4) + '|' + ([char]0x540E + [char]0x7EED + [char]0x786E + [char]0x8BA4) + '|' + ([char]0x672A + [char]0x786E + [char]0x8BA4) + ')'
    if (-not [string]::IsNullOrWhiteSpace($selectedRealEntry) -and $selectedRealEntry -match $placeholderPattern) {
        $issues.Add('selected_real_entry_placeholder') | Out-Null
    }
    $selectedEntryOracleAuthorityPatterns = @(
        '(?im)^\s*-?\s*\*{0,2}selected[_ ]real[_ ]entry\*{0,2}\s*[:=|][^\r\n]{0,240}(inferred from Oracle|based on Oracle metadata|based on Oracle Evidence|Oracle Evidence\s+as\s+selected-entry\s+authority|oracle additions|oracle line count|oracle new service|post-hoc\s+(result|implementation|diff)\s+as\s+selected-entry\s+authority)',
        '(?im)^\s*\*{0,2}Selected Real Entry\*{0,2}[^\r\n]{0,240}(inferred from Oracle|based on Oracle metadata|based on Oracle Evidence|Oracle Evidence\s+as\s+selected-entry\s+authority|oracle additions|oracle line count|oracle new service|post-hoc\s+(result|implementation|diff)\s+as\s+selected-entry\s+authority)'
    )
    foreach ($pattern in $selectedEntryOracleAuthorityPatterns) {
        if ($combinedPhase0 -match $pattern) {
            $issues.Add('phase0_oracle_inferred_selected_entry') | Out-Null
            break
        }
    }
    # v438: Refine pattern to distinguish between oracle-wait blockers and blind replay constraint descriptions
    # Allow "without Oracle access", "cannot verify", and descriptive constraint language
    # Block explicit wait conditions like "next action: await Oracle", "waiting for Oracle to provide"
    $manualOracleWaitPattern = '(?is)((?<!without\s)Oracle\s+Post-Hoc\s*(->|required|pending|(before|after)\s+implementation)|(?<!cannot\sverify\.)\s*Oracle\s+commit\s+(pending|required|needed|before\s+(implementation|planning))|next (step|action):\s*(await|wait|pending).*\bOracle\b|awaiting\s+Oracle\s+(verification|access|branch)\s+(to\s+(provide|verify)|before\s+(implementation|planning)|required|pending)|waiting\s+for\s+Oracle\s+(to\s+(provide|verify)|verification\s+(required|needed))|AWAIT_ORACLE_VERIFICATION_OR_WAIVER|Provide\s+oracle\s+branch\s+access|Coverage\s+Cap\s+Waiver|waive\s+coverage\s+caps|(?<!no\s)manual\s+oracle\s+verification\s+(required|needed|pending)|(?<!constraint\s)awaiting\s+oracle\s+verification|wait(?:ing)?\s+for\s+oracle\s+verification)'
    if ($phase0Text -match $manualOracleWaitPattern) {
        $issues.Add('phase0_manual_oracle_wait') | Out-Null
    }
    if ($phase0Text -match '(?is)(schema verification pending|awaiting schema|wait for schema)') {
        $warnings.Add('schema_verification_pending_disclosed') | Out-Null
    }
    if ([string]::IsNullOrWhiteSpace($firstExecutableSlice)) { $issues.Add('first_executable_slice_missing') | Out-Null }
    $schemaExactGapPattern = '(?i)\b(schema_verification_gap|new_table_structure_gap|exact_contract_gap|interface_contract_gap|schema_gap|schema verification gap|new table structure gap|exact contract gap|interface contract gap)\b'
    $hasSchemaExactGap = $combinedPhase0 -match $schemaExactGapPattern
    if ($hasSchemaExactGap) {
        if ($explorationText -notmatch '(?im)^##\s*Schema and Exact Contract Discovery Ledger\s*$') {
            $issues.Add('schema_exact_discovery_ledger_missing') | Out-Null
        }
        if ($explorationText -notmatch '(?is)(\brg\b|grep|findstr|mapper|entity|dto|facade|controller|service|xml|sql|enum|constant|payload|template|jsp|js)') {
            $issues.Add('schema_exact_discovery_evidence_missing') | Out-Null
        }
        if ($phase0Status -eq 'BLOCKED' -and
            -not [string]::IsNullOrWhiteSpace($selectedRealEntry) -and
            -not [string]::IsNullOrWhiteSpace($firstExecutableSlice)) {
            $issues.Add('phase0_blocked_on_oracle_or_schema_uncertainty') | Out-Null
        }
    }
    if ($phase0Status -eq 'BLOCKED' -and
        -not [string]::IsNullOrWhiteSpace($selectedRealEntry) -and
        -not [string]::IsNullOrWhiteSpace($firstExecutableSlice) -and
        $combinedPhase0 -match $manualOracleWaitPattern) {
        $issues.Add('phase0_blocked_on_oracle_or_schema_uncertainty') | Out-Null
    }
    $corePathAliases = @('core_path', 'Core', 'core', 'CORE_PATH', 'corePath', 'Core Path', 'core path', 'RPC', 'rpc', 'api_entry', 'facade_entry', 'core', 'Cross', 'cross', 'Cross-feature', 'integration')
    if ($corePathAliases -notcontains $firstSliceType) { $warnings.Add("first_slice_type_weak:$firstSliceType") | Out-Null }

    foreach ($token in @(
        'source boundary',
        'requirement literal inventory',
        'candidate surface map',
        'uncertainty ledger'
    )) {
        Add-MissingTokenIssue -Issues $issues -Text $explorationText -Token $token -Issue "exploration_missing:$token"
    }

    foreach ($token in @(
        'Requirement Family Ledger',
        'Real Entry Discovery Matrix',
        'Behavior Test Charter',
        'Critical Surface Allocation Plan',
        'side-effect ledger',
        'coverage cap'
    )) {
        Add-MissingTokenIssue -Issues $warnings -Text $contractText -Token $token -Issue "round_contract_weak:$token"
    }
    Add-MissingTokenIssue -Issues $warnings -Text $contractText -Token 'Expected Diff Matrix' -Issue 'round_contract_expected_diff_matrix_deferred_to_plan'

    # Only check families that are required=true in FAMILY_CONTRACT.json
    $requiredTrueFamilies = @()
    if ($null -ne $familyJson -and $null -ne $familyJson.families) {
        $requiredTrueFamilies = @($familyJson.families | Where-Object { [bool]$_.required } | ForEach-Object { [string]$_.id })
    }
    if ($requiredTrueFamilies.Count -eq 0) { $requiredTrueFamilies = $requiredFamilies }
    foreach ($family in $requiredTrueFamilies) {
        if ($contractText.IndexOf($family, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
        $prefix = $family -replace '_[^_]+$', ''
        if ($prefix -ne $family -and $prefix.Length -ge 5 -and $contractText.IndexOf($prefix, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
        # If FAMILY_CONTRACT.json declares this family, accept it as documented even if not in text
        if ($null -ne $familyContract) {
            $match = @($familyContract.families | Where-Object { [string]$_.id -eq $family })
            if ($match.Count -gt 0) { continue }
        }
        $issues.Add("family_missing:$family") | Out-Null
    }
    if ($null -ne $familyContract) {
        $fcSelectedEntry = Convert-SelectedRealEntryToText $familyContract.selected_real_entry
        if ([string]::IsNullOrWhiteSpace($fcSelectedEntry) -or $fcSelectedEntry -match $placeholderPattern) {
            $issues.Add('family_contract_selected_real_entry_missing') | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace([string]$familyContract.first_executable_slice)) {
            $issues.Add('family_contract_first_executable_slice_missing') | Out-Null
        }
        $contractFamilies = @($familyContract.families)
        foreach ($family in $requiredTrueFamilies) {
            $match = @($contractFamilies | Where-Object { [string]$_.id -eq $family })
            if ($match.Count -eq 0) {
                $issues.Add("family_contract_missing:$family") | Out-Null
            }
        }
        $weakProof = @($contractFamilies | Where-Object {
            [bool]$_.required -and
            (-not $_.proof_required -or @($_.proof_required).Count -eq 0) -and
            [string]::IsNullOrWhiteSpace([string]$_.blocker)
        })
        if ($weakProof.Count -gt 0) {
            $warnings.Add("family_contract_proof_required_missing:$((@($weakProof | ForEach-Object { $_.id }) -join ','))") | Out-Null
        }
    }
} else {
    $planFiles = @(
        'PLAN_CANDIDATE_1.md',
        'PLAN_CANDIDATE_2.md',
        'PLAN_CANDIDATE_3.md',
        'PLAN_RESULT.md',
        'FAMILY_CONTRACT.json',
        'PLAN_SELECTION.md',
        'REPLAY_PLAN.md',
        'IMPLEMENTATION_CONTRACT.md',
        'EXPECTED_DIFF_MATRIX.md',
        'SIDE_EFFECT_LEDGER.md',
        'TEST_CHARTER.md',
        'FIRST_SLICE_PROOF_PLAN.md'
    )
    foreach ($file in $planFiles) {
        Add-MissingFileIssue -Issues $issues -Root $replayRootFull -Name $file
    }

    foreach ($file in $planFiles) {
        Repair-PlanArtifactLineBreaks -Path (Join-Path $replayRootFull $file) -ArtifactName $file -Warnings $warnings
    }

    # v408: Auto-repair FIRST_SLICE_PROOF_PLAN.md format BEFORE reading content
    # Normalize common AI deviations like **Test:** to first_red_test:
    $firstSliceProofPath = Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md'
    if (Test-Path -LiteralPath $firstSliceProofPath) {
        $proofContent = Get-Content -LiteralPath $firstSliceProofPath -Raw -Encoding UTF8
        $originalProofContent = $proofContent
        $needsProofRepair = $false

        # Check if first_red_test is missing and **Test:** exists
        if ($proofContent -notmatch '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?first_red_test\s*\*{0,2}\s*[:=|]') {
            # Try to extract from **Test:** pattern (with or without leading dash)
            $testValue = Get-FirstText $proofContent @(
                '(?m)^\s*(?:\*{0,2}\s*)?Test\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(?:\*{0,2}\s*)?(.+?)\s*$',
                '(?m)^\s*#{3,4}\s*RED\s+Expectation\s*\r?\n(?:[^\r\n]{0,200}\r?\n){0,5}?\*{0,2}\s*Test\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(?:\*{0,2}\s*)?(.+?)\s*$'
            )
            if (-not [string]::IsNullOrWhiteSpace($testValue)) {
                # Clean up the extracted value to remove any leading/trailing **
                $testValue = $testValue.Trim('`').Trim('*').Trim()
                # Replace **Test:** with first_red_test: (handle both with and without leading dash)
                # Pattern matches: (whitespace)(optional dash)(optional *)Test*(separators)(value)
                $proofContent = $proofContent -replace '(?m)^(\s*)(-?)\*{0,2}Test\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(?:\*{0,2}\s*)?.*?$', "${1}$([char]0x2D) first_red_test: $testValue"
                $needsProofRepair = $true
                $warnings.Add("first_slice_proof_auto_repaired:Test_to_first_red_test") | Out-Null
            }
        }

        if ($needsProofRepair) {
            Set-Content -LiteralPath $firstSliceProofPath -Value $proofContent -Encoding UTF8
        }
    }

    $planText = Read-TextIfExists (Join-Path $replayRootFull 'PLAN_RESULT.md')
    $planJsonText = Read-TextIfExists (Join-Path $replayRootFull 'PLAN_RESULT.json')
    $replayPlanText = Read-TextIfExists (Join-Path $replayRootFull 'REPLAY_PLAN.md')
    $implementationContractText = Read-TextIfExists (Join-Path $replayRootFull 'IMPLEMENTATION_CONTRACT.md')
    $expectedDiffText = Read-TextIfExists (Join-Path $replayRootFull 'EXPECTED_DIFF_MATRIX.md')
    $sideEffectText = Read-TextIfExists (Join-Path $replayRootFull 'SIDE_EFFECT_LEDGER.md')
    $testCharterText = Read-TextIfExists (Join-Path $replayRootFull 'TEST_CHARTER.md')
    $firstSliceProofText = Read-TextIfExists (Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md')
    $goldenDeliverySliceText = ''
    foreach ($goldenPath in @(
            (Join-Path $replayRootFull 'GOLDEN_DELIVERY_SLICE_PROMPT_SNAPSHOT.md'),
            (Join-Path $replayRootFull 'NEXT_GOLDEN_DELIVERY_SLICE.md'),
            (Join-Path $replayRootFull '_golden-samples\GOLDEN_DELIVERY_SLICE_PROMPT.md')
        )) {
        if (Test-Path -LiteralPath $goldenPath) {
            $goldenDeliverySliceText += "`n" + (Read-TextIfExists $goldenPath)
        }
    }
    $hasGoldenDeliverySlice = $goldenDeliverySliceText -match '(?i)(Golden Delivery Slice|First Slice Contract|positive first-slice)'

    # v350: Track plan status but defer issue addition until after oracle overlap auto-repair
    $planStatusForLaterCheck = Get-FirstText $planText @(
        '(?m)^\s*-?\s*plan_status\s*[:=]\s*[`*]*([A-Z_]+)[`*]*',
        '(?m)\bplan_status\b[^\nA-Z_]*([A-Z_]{3,})',
        '(?m)^\s*-?\s*status\s*[:=]\s*[`*]*([A-Z_]+)[`*]*',
        '(?mi)^##\s*Plan\s*Status\s*[:=]*\s*[^A-Z_\r\n]*([A-Z_]+)',
        '(?mi)\*\*Plan\s+Status\*\*\s*[:=]\s*[`*]*([A-Z_]+)[`*]*',
        '(?m)\*\*plan_status\*\*[^A-Z]*(PROCEED|BLOCKED|INVALID_PLAN)',
        '(?m)\*\*plan_status\*\*\s*[:=]\s*[`*]*([A-Z_]+)',
        '(?mi)^##\s*Plan\s*Status\s*\r?\n\s*\*{0,2}\s*([A-Z_]+)'
    )
    $planStatusCheckDeferred = $true

    # v374: Auto-repair missing first_slice and first_red_test in PLAN_RESULT.md
    # Extract from FIRST_SLICE_PROOF_PLAN.md if missing in PLAN_RESULT.md
    # This must happen BEFORE field extraction so extracted fields are found
    $planResultPath = Join-Path $replayRootFull 'PLAN_RESULT.md'
    $needsPlanRepair = $false
    $planContent = $planText

    if (Test-Path -LiteralPath $planResultPath) {
        $planContent = Get-Content -LiteralPath $planResultPath -Raw -Encoding UTF8
        $originalPlanContent = $planContent

        # Auto-repair first_slice if missing (check $planContent directly, not $planFields)
        $firstSliceInPlan = Get-KeyValueField -Text $planContent -Field 'first_slice'
        if ([string]::IsNullOrWhiteSpace($firstSliceInPlan)) {
            $firstSliceFromProof = Get-FirstText $firstSliceProofText @(
                '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?first_slice\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$',
                '(?m)\|\s*first_slice\s*\|\s*`?([^\r\n|]+?)`?\s*\|'
            )
            if (-not [string]::IsNullOrWhiteSpace($firstSliceFromProof)) {
                # Try to find a pattern to insert after, or append at the end of the fields section
                if ($planContent -match '(?m)^(\s*-\s*first_red_test\s*\*{0,2}\s*[:=|].*)$') {
                    $planContent = $planContent -replace '(?m)^(\s*-\s*first_red_test\s*\*{0,2}\s*[:=|].*)$', "`$1`r`n- first_slice: $firstSliceFromProof`r`n"
                    $needsPlanRepair = $true
                } elseif ($planContent -match '(?m)^(\s*-\s*plan_status\s*\*{0,2}\s*[:=|].*)$') {
                    # Insert after plan_status if first_red_test not found
                    $planContent = $planContent -replace '(?m)^(\s*-\s*plan_status\s*\*{0,2}\s*[:=|].*)$', "`$1`r`n- first_slice: $firstSliceFromProof`r`n"
                    $needsPlanRepair = $true
                }
            }
        }

        # v408: Auto-repair first_red_test if missing (check $planContent directly, not $planFields)
        $firstRedInPlan = Get-KeyValueField -Text $planContent -Field 'first_red_test'
        if ([string]::IsNullOrWhiteSpace($firstRedInPlan)) {
            $firstRedFromProof = Get-FirstText $firstSliceProofText @(
                '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?first_red_test\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$',
                '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?first_RED_test\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$',
                '(?m)\|\s*first_red_test\s*\|\s*`?([^\r\n|]+?)`?\s*\|',
                '(?m)\|\s*first_RED_test\s*\|\s*`?([^\r\n|]+?)`?\s*\|',
                '(?m)^\s*(?:\*{0,2}\s*)?Test\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(?:\*{0,2}\s*)?(.+?)\s*$',  # v408: Handle **Test:** deviation with optional ** in value
                '(?m)^\s*#{3,4}\s*RED\s+Expectation\s*\r?\n(?:[^\r\n]{0,200}\r?\n){0,5}?\*{0,2}\s*Test\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(?:\*{0,2}\s*)?(.+?)\s*$'  # v408: Handle ### RED Expectation ... **Test:**
            )
            if (-not [string]::IsNullOrWhiteSpace($firstRedFromProof)) {
                # Clean up the extracted value to remove any leading/trailing **
                $firstRedFromProof = $firstRedFromProof.Trim('`').Trim('*').Trim()
                if ($planContent -match '(?m)^(\s*-\s*first_slice\s*\*{0,2}\s*[:=|].*)$') {
                    $planContent = $planContent -replace '(?m)^(\s*-\s*first_slice\s*\*{0,2}\s*[:=|].*)$', "`$1`r`n- first_red_test: $firstRedFromProof`r`n"
                    $needsPlanRepair = $true
                } elseif ($planContent -match '(?m)^(\s*-\s*plan_status\s*\*{0,2}\s*[:=|].*)$') {
                    $planContent = $planContent -replace '(?m)^(\s*-\s*plan_status\s*\*{0,2}\s*[:=|].*)$', "`$1`r`n- first_red_test: $firstRedFromProof`r`n- first_slice: <extract from FIRST_SLICE_PROOF_PLAN.md>`r`n"
                    $needsPlanRepair = $true
                }
            }
        }

        # Normalize first_RED_test to first_red_test if the variant exists
        $normalizedFirstRed = $planContent -replace '(?m)^(\s*)first_RED_test(\s*\*{0,2}\s*[:=|])', '${1}first_red_test${2}'
        if ($normalizedFirstRed -ne $planContent) {
            $planContent = $normalizedFirstRed
            $needsPlanRepair = $true
        }

        if ($needsPlanRepair) {
            Set-Content -LiteralPath $planResultPath -Value $planContent -Encoding UTF8
            # Update $planText so field extraction uses repaired content
            $planText = $planContent
            $warnings.Add("plan_result_auto_repaired:first_slice_or_first_red_test") | Out-Null
        }
    }

    # v374b: Extract plan fields from (possibly repaired) PLAN_RESULT.md
    # This happens AFTER repair so missing fields added by repair are found
    $planFieldAliases = @{
        'first_slice' = @('first_slice', 'First Slice', 'first slice')
        'first_red_test' = @('first_red_test', 'First RED Test', 'first red test')
        'selected_strategy' = @('selected_strategy', 'Strategy', 'selected strategy')
    }
    $planFields = @{}
    foreach ($field in @('first_slice', 'first_red_test', 'selected_strategy')) {
        $value = Get-KeyValueField -Text $planText -Field $field
        if ([string]::IsNullOrWhiteSpace($value)) {
            # Try aliases for backward compatibility
            foreach ($alias in $planFieldAliases[$field]) {
                $value = Get-KeyValueField -Text $planText -Field $alias
                if (-not [string]::IsNullOrWhiteSpace($value)) { break }
            }
        }
        if ([string]::IsNullOrWhiteSpace($value)) {
            # v440: Robust Auto-infer selected_strategy from PLAN_SELECTION.md if missing
            if ($field -eq 'selected_strategy') {
                $planSelectionPath = Join-Path $replayRootFull 'PLAN_SELECTION.md'
                if (Test-Path -LiteralPath $planSelectionPath) {
                    $selectionText = Get-Content -LiteralPath $planSelectionPath -Raw -Encoding UTF8

                    # Method 1: Direct strategy_name field (preferred, most reliable)
                    $strategyNameMatch = [regex]::Match($selectionText, '(?im)\*{0,2}\s*strategy_name\s*\*{0,2}\s*[:=]\s*([^\r\n]+)')
                    if ($strategyNameMatch.Success) {
                        $strategyName = $strategyNameMatch.Groups[1].Value.Trim()
                        if (-not [string]::IsNullOrWhiteSpace($strategyName)) {
                            $value = $strategyName
                            $warnings.Add("plan_result_field_inferred:selected_strategy from strategy_name field") | Out-Null
                        }
                    }

                    # Method 2: Selected Candidate line with "Candidate X - Strategy Name" format
                    if ([string]::IsNullOrWhiteSpace($value)) {
                        $selectedCandidateMatch = [regex]::Match($selectionText, '(?im)\*{0,2}\s*Selected\s+Candidate\*{0,2}\s*[:=]\s*(?:Candidate\s*)?([0-9]+)\s*-\s*([^\r\n]+)')
                        if ($selectedCandidateMatch.Success) {
                            $strategyName = $selectedCandidateMatch.Groups[2].Value.Trim()
                            # Remove common suffixes like "Strategy" to get clean name
                            $strategyName = $strategyName -replace '\s+Strategy$', ''
                            if (-not [string]::IsNullOrWhiteSpace($strategyName)) {
                                $value = $strategyName
                                $warnings.Add("plan_result_field_inferred:selected_strategy from Selected Candidate line") | Out-Null
                            }
                        }
                    }

                    # Method 3: Legacy format - just the candidate number with dashes
                    if ([string]::IsNullOrWhiteSpace($value)) {
                        $legacyMatch = [regex]::Match($selectionText, '(?im)\*{0,2}\s*Selected\s+Candidate\*{0,2}\s*[:=]\s*([0-9]+)')
                        if ($legacyMatch.Success) {
                            $candidateNum = $legacyMatch.Groups[1].Value
                            # Try to find strategy name from table/paragraph nearby
                            $tableMatch = [regex]::Match($selectionText, "(?im)(?:Candidate\s+$candidateNum.*?Strategy\s*[:=]\s*([^\r\n]+))")
                            if ($tableMatch.Success) {
                                $strategyName = $tableMatch.Groups[1].Value.Trim()
                                if (-not [string]::IsNullOrWhiteSpace($strategyName)) {
                                    $value = $strategyName
                                    $warnings.Add("plan_result_field_inferred:selected_strategy from table lookup") | Out-Null
                                }
                            }
                        }
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($value)) {
                $issues.Add("plan_result_field_missing:$field") | Out-Null
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $planFields[$field] = $value.Trim('`').Trim('*').Trim()
        }
    }

    # v383: Auto-repair IMPLEMENTATION_CONTRACT.md format
    # The contract should have simple machine-readable key-value lines at the top:
    # selected_real_entry: ClassName.method
    # first_slice: S1
    # first_red_test: TestClass.testMethod
    $contractPath = Join-Path $replayRootFull 'IMPLEMENTATION_CONTRACT.md'
    $needsContractRepair = $false

    if (Test-Path -LiteralPath $contractPath) {
        $contractContent = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8
        $originalContractContent = $contractContent

        # Check if selected_real_entry is missing (simple format check)
        if ($contractContent -notmatch '(?m)^selected_real_entry:\s') {
            # Try to extract from FIRST_SLICE_PROOF_PLAN.md or other plan artifacts
            $selectedEntryFromProof = Get-FirstText $firstSliceProofText @(
                '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?selected_real_entry\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$',
                '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?selected_carrier\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$',
                '(?m)\|\s*selected_real_entry\s*\|\s*`?([^\r\n|]+?)`?\s*\|'
            )
            # Also try from implementationContractText itself (might have it in a different format)
            if ([string]::IsNullOrWhiteSpace($selectedEntryFromProof)) {
                $selectedEntryFromProof = Get-FirstText $contractContent @(
                    '(?im)### Primary Entry Point\s*\r?\n\s*```java\s*(?:public\s+)?(?:static\s+)?(?:void\s+)?([A-Za-z0-9_.#$\s()]+)\(',
                    '(?im)Primary Entry Point.*?```\s*([A-Za-z0-9_.#$\s()]+)\(',
                    '(?im)- \*\*carrier_class\*\*:\s*`([A-Za-z0-9_.$]+)`'
                )
            }

            if (-not [string]::IsNullOrWhiteSpace($selectedEntryFromProof)) {
                # Clean up the extracted value
                $selectedEntryFromProof = $selectedEntryFromProof.Trim('`').Trim('*').Trim()
                # Insert at the beginning after the header (if header exists)
                if ($contractContent -match '(?m)^#\s+') {
                    # Find the first empty line after the header and insert there
                    $contractContent = $contractContent -replace '(?m)(^#\s+.*\r?\n)(\r?\n)', "`$1`r`nselected_real_entry: $selectedEntryFromProof`r`n`$2"
                } else {
                    # No header, prepend at the very beginning
                    $contractContent = "selected_real_entry: $selectedEntryFromProof`r`n`r`n" + $contractContent
                }
                $needsContractRepair = $true
            }
        }

        # Check if first_slice is missing
        if ($contractContent -notmatch '(?m)^first_slice:\s' -and $planFields.ContainsKey('first_slice')) {
            $firstSliceValue = $planFields['first_slice']
            if (-not [string]::IsNullOrWhiteSpace($firstSliceValue)) {
                # Insert after selected_real_entry or at the beginning
                if ($contractContent -match '(?m)^selected_real_entry:') {
                    $contractContent = $contractContent -replace '(?m)(^selected_real_entry:.*\r?\n)', "`$1first_slice: $firstSliceValue`r`n`r`n"
                } elseif ($contractContent -match '(?m)^#\s+') {
                    $contractContent = $contractContent -replace '(?m)(^#\s+.*\r?\n)(\r?\n)', "`$1`r`nfirst_slice: $firstSliceValue`r`n`$2"
                } else {
                    $contractContent = "first_slice: $firstSliceValue`r`n`r`n" + $contractContent
                }
                $needsContractRepair = $true
            }
        }

        # Check if first_red_test is missing
        if ($contractContent -notmatch '(?m)^first_red_test:\s' -and $planFields.ContainsKey('first_red_test')) {
            $firstRedValue = $planFields['first_red_test']
            if (-not [string]::IsNullOrWhiteSpace($firstRedValue)) {
                # Insert after first_slice or at the beginning
                if ($contractContent -match '(?m)^first_slice:') {
                    $contractContent = $contractContent -replace '(?m)(^first_slice:.*\r?\n)', "`$1first_red_test: $firstRedValue`r`n`r`n"
                } elseif ($contractContent -match '(?m)^selected_real_entry:') {
                    $contractContent = $contractContent -replace '(?m)(^selected_real_entry:.*\r?\n)', "`$1first_red_test: $firstRedValue`r`n`r`n"
                } elseif ($contractContent -match '(?m)^#\s+') {
                    $contractContent = $contractContent -replace '(?m)(^#\s+.*\r?\n)(\r?\n)', "`$1`r`nfirst_red_test: $firstRedValue`r`n`$2"
                } else {
                    $contractContent = "first_red_test: $firstRedValue`r`n`r`n" + $contractContent
                }
                $needsContractRepair = $true
            }
        }

        if ($needsContractRepair) {
            Set-Content -LiteralPath $contractPath -Value $contractContent -Encoding UTF8
            $warnings.Add("implementation_contract_auto_repaired:added_missing_key_value_lines") | Out-Null
            # Re-read the updated content for subsequent checks
            $implementationContractText = $contractContent
        }
    }

    # v270: Production Carrier Search Gate. Existing workflow gates already
    # require real carriers; this makes the Plan stage prove the search before
    # a slice can create or target a new service.
    $combinedPlanArtifacts = "$planText`n$planJsonText`n$replayPlanText`n$implementationContractText`n$expectedDiffText`n$firstSliceProofText"

    # v477: policyNum/insureNum rebuild source-chain plan gate. This bug class
    # is easy to fake by checking downstream TaskData setters or DTO accessors.
    # Plan-stage evidence must name the upstream RequestBuildFunction contract,
    # the deterministic RequestBuildContext test, the claim-server harness, and
    # the two production processor diffs before Phase 1 is authorized.
    $sourceChainContractText = Read-TextIfExists (Join-Path $replayRootFull 'SOURCE_CHAIN_CONTRACT.json')
    $sourceAwarePlanText = "$combinedPlanArtifacts`n$testCharterText`n$sourceChainContractText"
    $sourceAwareArtifacts = @(
        [pscustomobject]@{ name = 'PLAN_RESULT.md'; text = $planText },
        [pscustomobject]@{ name = 'PLAN_RESULT.json'; text = $planJsonText },
        [pscustomobject]@{ name = 'REPLAY_PLAN.md'; text = $replayPlanText },
        [pscustomobject]@{ name = 'IMPLEMENTATION_CONTRACT.md'; text = $implementationContractText },
        [pscustomobject]@{ name = 'EXPECTED_DIFF_MATRIX.md'; text = $expectedDiffText },
        [pscustomobject]@{ name = 'SIDE_EFFECT_LEDGER.md'; text = $sideEffectText },
        [pscustomobject]@{ name = 'TEST_CHARTER.md'; text = $testCharterText },
        [pscustomobject]@{ name = 'FIRST_SLICE_PROOF_PLAN.md'; text = $firstSliceProofText },
        [pscustomobject]@{ name = 'SOURCE_CHAIN_CONTRACT.json'; text = $sourceChainContractText }
    )
    $sourceChainRequired = $sourceChainContractText -match '(?i)"required_source_chain"\s*:\s*true'
    $planMachineContract = $null
    if (-not [string]::IsNullOrWhiteSpace($planJsonText)) {
        try { $planMachineContract = $planJsonText | ConvertFrom-Json } catch { $planMachineContract = $null }
    }
    $isPolicyRebuildSourceChainPlan = (
        ($sourceChainRequired -or $sourceAwarePlanText -match '(?i)(rebuildTaskData|TaskProcessor)') -and
        $sourceAwarePlanText -match '(?i)(policyNum|policy_num)' -and
        $sourceAwarePlanText -match '(?i)(insureNum|insure_num)'
    )
    if ($isPolicyRebuildSourceChainPlan) {
        $warnings.Add('policy_rebuild_source_chain_plan_gate_active') | Out-Null

        $policyOracleHasProductionAdditions = $false
        $policyOracleAnalysisPath = Join-Path $replayRootFull 'ORACLE_DIFF_ANALYSIS.json'
        if (Test-Path -LiteralPath $policyOracleAnalysisPath -PathType Leaf) {
            try {
                $policyOracleAnalysis = Get-Content -LiteralPath $policyOracleAnalysisPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($file in @($policyOracleAnalysis.files)) {
                    $additionsText = [string]$file.additions
                    if ([bool]$file.is_production -and $additionsText -match '^\d+$' -and [int]$additionsText -gt 0) {
                        $policyOracleHasProductionAdditions = $true
                        break
                    }
                }
            } catch { }
        }

        foreach ($requiredToken in @(
                'AiClaimDataAssemblyHelper.buildRequestCommon',
                'AiClaimDataAssemblyHelper.RequestBuildFunction',
                'RequestBuildContext'
            )) {
            if ($sourceAwarePlanText.IndexOf($requiredToken, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                $issues.Add("policy_rebuild_plan_missing:$requiredToken") | Out-Null
            }
        }

        $machineTestModule = ''
        $machineTestCommand = ''
        $machineExpectedTestClass = ''
        if ($null -ne $planMachineContract) {
            $machineExpectedTestClass = [string]$planMachineContract.expected_test_class
            if ($null -ne $planMachineContract.test_infrastructure_check) {
                $machineTestModule = [string]$planMachineContract.test_infrastructure_check.test_module_for_target
                $machineTestCommand = [string]$planMachineContract.test_infrastructure_check.compilation_dry_run_command
            }
        }
        $machineHarnessUsesClaimServer = (
            $machineTestModule -eq 'claim-server' -and
            $machineTestCommand -match '(?i)-pl\s+claim-server\b' -and
            $machineTestCommand -match '(?i)\s-am\b' -and
            ($machineExpectedTestClass -match '(?i)claim-server[/\\]src[/\\]test|^[A-Za-z0-9_]+$')
        )
        if (($sourceAwarePlanText -notmatch '(?i)claim-server[/\\]src[/\\]test[/\\]java') -and -not $machineHarnessUsesClaimServer) {
            $issues.Add('policy_rebuild_plan_missing:claim_server_test_harness') | Out-Null
        }
        if (-not $machineHarnessUsesClaimServer -and $sourceAwarePlanText -match '(?i)claim-core[/\\]src[/\\]test|-pl\s+claim-core\b|claim-core\s+-Dtest') {
            $issues.Add('policy_rebuild_plan_invalid:test_harness_claim_core') | Out-Null
        }
        if ($sourceAwarePlanText -notmatch '(?i)-pl\s+claim-server\b' -or $sourceAwarePlanText -notmatch '(?i)\s-am\b') {
            $issues.Add('policy_rebuild_plan_invalid:maven_missing_claim_server_am') | Out-Null
        }
        Add-FixedCaseIdIssueWithEvidence `
            -Issues $issues `
            -Evidence $issueEvidence `
            -Artifacts $sourceAwareArtifacts
        Add-RegexIssueWithEvidence `
            -Issues $issues `
            -Evidence $issueEvidence `
            -Issue 'policy_rebuild_plan_invalid:null_taskdata_pass_path' `
            -Pattern '(?i)(taskData\s*==\s*null|result\s*==\s*null|null\s+then\s+(pass|warn|print)|returns?\s+null.*pass)' `
            -Artifacts $sourceAwareArtifacts
        $hasPolicyAssignmentDiff = $sourceAwarePlanText -match '(?i)req\.setPolicyNum\s*\(\s*buildContext\.getPolicyNum\s*\(\s*\)\s*\)'
        $hasInsureAssignmentDiff = $sourceAwarePlanText -match '(?i)req\.setInsureNum\s*\(\s*buildContext\.getInsureNum\s*\(\s*\)\s*\)'
        $hasDownstreamOnlyPolicySignal = (
            $sourceAwarePlanText -match '(?i)taskData\.setPolicyNum\s*\(\s*request\.getPolicyNum\s*\(\s*\)\s*\)' -and
            -not ($hasPolicyAssignmentDiff -and $hasInsureAssignmentDiff)
        )
        $hasPolicyDtoOnlySignal = (
            $sourceAwarePlanText -match '(?i)(DTO\s+getter|getter/setter|accessor\s+methods|hasPolicyNumAndInsureNumFields|field\s+existence|DTO\s+field|Request\s+DTO\s+field|compile-time\s+validation\s+only)' -or
            $sourceAwarePlanText -match '(?i)(DTO|Request\s+DTO|compile-time\s+validation\s+only|Tests\s*-\s*None)[^\r\n]{0,160}\bFIELD_ADD\b|\bFIELD_ADD\b[^\r\n]{0,160}(DTO|Request\s+DTO|compile-time\s+validation\s+only|Tests\s*-\s*None)' -or
            $sourceAwarePlanText -match '(?im)^\s*"?first_slice"?\s*[:=]\s*"?[^\r\n]*(Contract\s+Definition|DTO|field\s+additions)' -or
            $sourceAwarePlanText -match '(?im)^\s*"?target_carrier_file_path"?\s*[:=]\s*"?claim-domain[/\\][^\r\n]*[/\\]dto[/\\][^\r\n]*Request\.java' -or
            $sourceAwarePlanText -match '(?is)##\s*Slice\s+1\s*:\s*[^\r\n]*(DTO|field\s+additions?|Request\s+DTO\s+field|FIELD_ADD|compile-time\s+validation\s+only)' -or
            $sourceAwarePlanText -match '(?is)##\s*Slice\s+1\b.{0,1200}(Request\s+DTO\s+field|DTO\s+field|compile-time\s+validation\s+only|Tests\s*-\s*None)' -or
            $hasDownstreamOnlyPolicySignal
        )
        if ($hasPolicyDtoOnlySignal -and -not ($hasPolicyAssignmentDiff -and $hasInsureAssignmentDiff)) {
            $issues.Add('policy_rebuild_plan_invalid:dto_or_downstream_only') | Out-Null
        }
        if ($policyOracleHasProductionAdditions) {
            $hasNoProductionChangeSignal = (
                $sourceAwarePlanText -match '(?i)(baseline\s+already\s+contains\s+the\s+complete\s+implementation|complete\s+implementation\s+already\s+present|production\s+verified\s+present|Total\s+Production\s+Changes\s*:\s*0|Production\s+Code\s*:\s*No\s+changes|0\s+lines\s*\([^)]*verified\s+present|only\s+test\s+changes|test-only\s+completion\s*:\s*(?!not\s+applicable)(?![^\r\n]*production\s+code\s+changes\s+required))' -or
                $sourceAwarePlanText -match '(?is)\bNO_CHANGE\b.{0,120}\bVERIFIED_PRESENT\b|\bVERIFIED_PRESENT\b.{0,120}\bNO_CHANGE\b'
            )
            if ($hasNoProductionChangeSignal) {
                $issues.Add('policy_rebuild_plan_invalid:no_production_change_against_oracle_additions') | Out-Null
            }
            if ($sourceAwarePlanText -match '(?im)^\s*"?core_closure_required"?\s*[:=]\s*"?false\b') {
                $issues.Add('policy_rebuild_plan_invalid:core_closure_false_against_oracle') | Out-Null
            }
            if ($sourceAwarePlanText -match '(?im)^\s*"?highest_weight_open_gate"?\s*[:=]\s*"?wire_payload_api_contract\b') {
                $issues.Add('policy_rebuild_plan_invalid:highest_weight_gate_not_core_entry') | Out-Null
            }
        }
        if (Test-PolicySpringHarnessResidue -Text $sourceAwarePlanText) {
            $issues.Add('policy_rebuild_plan_invalid:spring_context_harness') | Out-Null
        }

        $hasApplySibling = $sourceAwarePlanText -match '(?i)AiApplyClaimApiTaskProcessor\.rebuildTaskData'
        $hasCalculateSibling = $sourceAwarePlanText -match '(?i)AiCalculateLossApiTaskProcessor\.rebuildTaskData'
        if (-not ($hasApplySibling -and $hasCalculateSibling)) {
            $issues.Add('policy_rebuild_plan_missing:apply_and_calculate_siblings') | Out-Null
        }

        if (-not ($hasPolicyAssignmentDiff -and $hasInsureAssignmentDiff)) {
            $issues.Add('policy_rebuild_plan_missing:upstream_request_assignment_diff') | Out-Null
            $missingAssignments = New-Object System.Collections.Generic.List[string]
            if (-not $hasPolicyAssignmentDiff) {
                $missingAssignments.Add('req.setPolicyNum(buildContext.getPolicyNum())') | Out-Null
            }
            if (-not $hasInsureAssignmentDiff) {
                $missingAssignments.Add('req.setInsureNum(buildContext.getInsureNum())') | Out-Null
            }
            $issueEvidence.Add([ordered]@{
                issue = 'policy_rebuild_plan_missing:upstream_request_assignment_diff'
                artifact = 'plan_artifacts'
                pattern = 'exact upstream RequestBuildFunction assignment literals'
                snippet = 'Missing exact literal(s): ' + (@($missingAssignments.ToArray()) -join '; ')
            }) | Out-Null
        }
    }
    $carrierPlaceholderPattern = '(?i)^(TBD|unknown|N/A|placeholder|TODO|none)$'
    # v337: Add colon pattern for table cell format "| key: value | |"
    $carrierSearchStatus = Get-FirstText $planText @(
        '(?m)^\s*-?\s*\*{0,2}\s*carrier_search\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*carrier_search\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)\|\s*\*{0,2}\s*carrier_search\s*\*{0,2}\s*:\s*(.+?)\s*\|',
        '(?m)\|\s*carrier_search\s*\|\s*`?([^\r\n|]+?)`?\s*\|'
    )
    $carrierSearchQueries = Get-FirstText $combinedPlanArtifacts @(
        # v606: YAML | literal block captures all subsequent indented lines.
        '(?m)^\s*-?\s*\*{0,2}\s*carrier_search_queries\s*\*{0,2}\s*[:=]\s*\|\s*\r?\n((?:\s{2,}[^\r\n]*(?:\r?\n|$))+)',
        '(?m)^\s*-?\s*\*{0,2}\s*carrier_search_queries\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*carrier_search_queries\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*\*{0,2}\s*search_queries\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*search_queries\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)\|\s*\*{0,2}\s*carrier_search_queries\s*\*{0,2}\s*:\s*(.+?)\s*\|',
        '(?m)\|\s*carrier_search_queries\s*\|\s*`?([^\r\n|]+?)`?\s*\|'
    )
    # v445: Enhanced to detect table format for existing production carriers
    # Matches both key-value format and table format like:
    # ### Existing Production Carriers Found
    # | Carrier | Location | Method/Signature | Purpose |
    # | AiAutoClaimFlowService | ... | ... | ... |
    $existingProductionCarriers = Get-FirstText $combinedPlanArtifacts @(
        '(?m)^\s*-?\s*\*{0,2}\s*existing_production_carriers\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*existing_production_carriers\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*\*{0,2}\s*existing_carriers\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*existing_carriers\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)\|\s*\*{0,2}\s*existing_production_carriers\s*\*{0,2}\s*:\s*(.+?)\s*\|',
        '(?m)\|\s*existing_production_carriers\s*\|\s*`?([^\r\n|]+?)`?\s*\|',
        '(?m)^\s*-?\s*\*{0,2}\s*carrier_existing_production_carriers\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*carrier_existing_production_carriers\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*\*{0,2}\s*carrier_existing_carriers\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*carrier_existing_carriers\s*[:=]\s*([^\r\n]+?)\s*$'
        # v445: Table format is handled separately in validation logic below
    )
    $selectedCarrierFromSearch = Get-FirstText $combinedPlanArtifacts @(
        '(?m)^\s*-?\s*\*{0,2}\s*selected_carrier_from_search\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*selected_carrier_from_search\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)\|\s*\*{0,2}\s*selected_carrier_from_search\s*\*{0,2}\s*:\s*(.+?)\s*\|',
        '(?m)\|\s*selected_carrier_from_search\s*\|\s*`?([^\r\n|]+?)`?\s*\|',
        '(?m)^\s*-?\s*\*{0,2}\s*carrier_selected_carrier_from_search\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*carrier_selected_carrier_from_search\s*[:=]\s*([^\r\n]+?)\s*$'
    )
    $newServiceProposed = Get-FirstText $combinedPlanArtifacts @(
        '(?m)^\s*-?\s*\*{0,2}\s*new_service_proposed\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*new_service_proposed\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)\|\s*\*{0,2}\s*new_service_proposed\s*\*{0,2}\s*:\s*(.+?)\s*\|',
        '(?m)\|\s*new_service_proposed\s*\|\s*`?([^\r\n|]+?)`?\s*\|',
        '(?m)^\s*-?\s*\*{0,2}\s*new_service_created\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*new_service_created\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)\|\s*\*{0,2}\s*new_service_created\s*\*{0,2}\s*:\s*(.+?)\s*\|',
        '(?m)\|\s*new_service_created\s*\|\s*`?([^\r\n|]+?)`?\s*\|'
    )
    $newServiceJustification = Get-FirstText $combinedPlanArtifacts @(
        # YAML folded blocks put the real justification on following indented lines.
        # v602_evolved: handles `> ` continuation syntax
        '(?m)^\s*-?\s*\*{0,2}\s*new_service_justification\s*\*{0,2}\s*[:=]\s*>\s*\r?\n((?:\s{2,}[^\r\n]*(?:\r?\n|$))+)',
        # v606: also handle `|` literal block syntax (same indented continuation).
        '(?m)^\s*-?\s*\*{0,2}\s*new_service_justification\s*\*{0,2}\s*[:=]\s*\|\s*\r?\n((?:\s{2,}[^\r\n]*(?:\r?\n|$))+)',
        '(?m)^\s*-?\s*\*{0,2}\s*new_service_justification\s*\*{0,2}\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)^\s*-?\s*new_service_justification\s*[:=]\s*([^\r\n]+?)\s*$',
        '(?m)\|\s*\*{0,2}\s*new_service_justification\s*\*{0,2}\s*:\s*(.+?)\s*\|',
        '(?m)\|\s*new_service_justification\s*\|\s*`?([^\r\n|]+?)`?\s*\|'
    )
    if ([string]::IsNullOrWhiteSpace($carrierSearchStatus) -or $carrierSearchStatus.Trim().Trim('`').Trim() -match $carrierPlaceholderPattern) {
        $issues.Add('carrier_search_missing') | Out-Null
    }
    if ([string]::IsNullOrWhiteSpace($carrierSearchQueries) -or $carrierSearchQueries.Trim().Trim('`').Trim() -match $carrierPlaceholderPattern) {
        $issues.Add('carrier_search_queries_missing') | Out-Null
    } else {
        $queryEvidenceCount = ([regex]::Matches($carrierSearchQueries, '(?i)\b(rg|grep|findstr|search|query|select-string)\b')).Count
        $querySeparatorCount = ([regex]::Matches($carrierSearchQueries, '[,;|]')).Count + 1
        if ([Math]::Max($queryEvidenceCount, $querySeparatorCount) -lt 3) {
            $issues.Add('carrier_search_queries_too_few') | Out-Null
        }
    }
    # v445: Enhanced validation for existing production carriers
    # First check if key-value format has content
    if ([string]::IsNullOrWhiteSpace($existingProductionCarriers) -or $existingProductionCarriers.Trim().Trim('`').Trim() -match $carrierPlaceholderPattern) {
        # Key-value format failed - check for table format
        # Table format: ### Existing Production Carriers Found followed by table rows

        # Use a simpler approach: search for section header and then check for table rows
        $sectionHeaderMatch = [regex]::Match($combinedPlanArtifacts, '^#{1,6}\s*Existing.*Carriers', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($sectionHeaderMatch.Success) {
            # Get the text after the header (next 2000 chars or until next section)
            $headerIndex = $sectionHeaderMatch.Index + $sectionHeaderMatch.Length
            $textAfterHeader = if ($headerIndex + 2000 -lt $combinedPlanArtifacts.Length) {
                $combinedPlanArtifacts.Substring($headerIndex, 2000)
            } else {
                $combinedPlanArtifacts.Substring($headerIndex)
            }

            # Find the end of this section (next # header or end of text)
            $nextSectionMatch = [regex]::Match($textAfterHeader, '\n\s*#{1,6}\s')
            if ($nextSectionMatch.Success) {
                $tableContent = $textAfterHeader.Substring(0, $nextSectionMatch.Index)
            } else {
                $tableContent = $textAfterHeader
            }

            # Check if table has at least one data row (pattern like | ClassName | ... |)
            $hasTableRows = [regex]::Match($tableContent, '^\|[^\n\r]+\|[^\n\r]+\|[^\n\r]+\|', [System.Text.RegularExpressions.RegexOptions]::Multiline).Success
            # Also check for service class names in table (case-insensitive for Service/Service.java)
            $hasServicePattern = [regex]::Match($tableContent, '\|\s*[A-Z]\w*Service\s*\|', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Success
            if (-not ($hasTableRows -or $hasServicePattern)) {
                $issues.Add('carrier_search_existing_carriers_missing') | Out-Null
            }
        } else {
            $issues.Add('carrier_search_existing_carriers_missing') | Out-Null
        }
    }
    if ([string]::IsNullOrWhiteSpace($selectedCarrierFromSearch) -or $selectedCarrierFromSearch.Trim().Trim('`').Trim() -match $carrierPlaceholderPattern) {
        $issues.Add('carrier_search_selected_carrier_missing') | Out-Null
    }
    $newServiceIsTrue = $newServiceProposed.Trim().Trim('`').Trim() -match '^(?i:true|yes|1)$'
    if ($newServiceIsTrue -and ($newServiceJustification.Trim().Trim('`').Trim() -notmatch '(?i)(orphan_feature|new_external_boundary|incompatible_existing_carriers|new_domain|no_existing_domain|no\s+existing\s+(carrier|domain|service|orchestration)|oracle.*new|new\s+service\s+in\s+oracle|full\s+flow|complete\s+workflow|separate\s+orchestration|1502)')) {
        $issues.Add('carrier_search_new_service_unjustified') | Out-Null
    }
    # v406: Normalize carrier name for matching - strip method names like ".save", ".update" etc.
    # This handles cases like "AiClaimModuleConfigService.save" matching "AiClaimModuleConfigService.java"
    $carrierBaseNameForMatch = if (-not [string]::IsNullOrWhiteSpace($selectedCarrierFromSearch)) {
        if ($selectedCarrierFromSearch -match '^([A-Za-z0-9_$]+)') {
            $matches[1]
        } else {
            ($selectedCarrierFromSearch -split '[#(\s\.]')[0].Trim()
        }
    } else { '' }

    if (-not $newServiceIsTrue -and
        -not [string]::IsNullOrWhiteSpace($existingProductionCarriers) -and
        -not [string]::IsNullOrWhiteSpace($selectedCarrierFromSearch) -and
        -not [string]::IsNullOrWhiteSpace($carrierBaseNameForMatch) -and
        $existingProductionCarriers -notmatch [regex]::Escape($carrierBaseNameForMatch)) {
        $issues.Add('carrier_search_selected_carrier_not_in_results') | Out-Null
    }

    # v381: Carrier Existence Verification - selected carrier must exist in codebase
    # This prevents synthetic carriers like AiAutoClaimFlowService from being selected
    # v382: Enhanced with retry logic and Get-ChildItem fallback for robustness
    # v391: Skip existence check for new services (new_service_proposed=true)
    $carrierNameForExistenceCheck = if (-not [string]::IsNullOrWhiteSpace($selectedCarrierFromSearch)) {
        # Extract carrier name before first delimiter (#, ., (, or whitespace)
        if ($selectedCarrierFromSearch -match '^([A-Za-z0-9_$]+)') {
            $matches[1]
        } else {
            ($selectedCarrierFromSearch -split '[#(\s\.]')[0].Trim()
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($planFields['first_slice'])) {
        # Try to extract carrier from first_slice if selected_carrier_from_search is missing
        $firstSliceValue = $planFields['first_slice']
        if ($firstSliceValue -match '([A-Za-z0-9_.$]+)[#\.]') {
            $matches[1]
        } else {
            $firstSliceValue
        }
    } else {
        ''
    }

    # v391: Skip carrier existence check when new_service_proposed=true
    # New services are expected NOT to exist in the codebase yet
    $shouldCheckCarrierExistence = -not $newServiceIsTrue

    if (-not $SkipCarrierAndOracleChecks -and -not [string]::IsNullOrWhiteSpace($carrierNameForExistenceCheck) -and $carrierNameForExistenceCheck -notmatch '^(TBD|unknown|N/A|placeholder|NONE_FOUND)' -and $shouldCheckCarrierExistence) {
        $worktreePathForCarrierCheck = if ([string]::IsNullOrWhiteSpace($Worktree)) { Join-Path $replayRootFull 'worktree' } else { Resolve-AbsolutePath $Worktree }

        # v395: Check if carrier exists in oracle diff before searching codebase
        $oracleDiffPath = Join-Path $replayRootFull 'ORACLE_DIFF_ANALYSIS.json'
        $carrierInOracle = $false
        if (Test-Path -LiteralPath $oracleDiffPath) {
            try {
                $oracleDiff = Get-Content -LiteralPath $oracleDiffPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($file in $oracleDiff.files) {
                    if ($file.path -like "*$carrierNameForExistenceCheck.java" -and $file.is_production -eq $true) {
                        $carrierInOracle = $true
                        $warnings.Add("carrier_existence_check: '$carrierNameForExistenceCheck' found in ORACLE_DIFF_ANALYSIS.json (oracle addition: $($file.additions) lines)") | Out-Null
                        break
                    }
                }
            } catch {
                # Oracle diff parsing failed, continue with codebase search
            }
        }

        $carrierFound = $carrierInOracle
        $searchPaths = @($worktreePathForCarrierCheck)

        # v395: Add project root as fallback search path if carrier not in oracle
        if (-not $carrierInOracle) {
            # Try to get project root from environment or common locations
            $projectRoot = $env:PROJECT_ROOT
            if ([string]::IsNullOrWhiteSpace($projectRoot)) {
                $projectRoot = $env:AI_WORKFLOW_PROJECT_ROOT
            }
            if ([string]::IsNullOrWhiteSpace($projectRoot)) {
                $replayRootParent = Split-Path $replayRootFull -Parent
                $projectRootCandidates = @()
                # Add inferred parent if valid
                if (-not [string]::IsNullOrWhiteSpace($replayRootParent)) {
                    $inferredParent = Split-Path $replayRootParent -Parent
                    if (-not [string]::IsNullOrWhiteSpace($inferredParent)) {
                        $projectRootCandidates += $inferredParent
                    }
                }
                foreach ($candidate in $projectRootCandidates) {
                    if (Test-Path -LiteralPath $candidate) {
                        $projectRoot = $candidate
                        break
                    }
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($projectRoot) -and (Test-Path -LiteralPath $projectRoot)) {
                $searchPaths += $projectRoot
            }
        }

        foreach ($searchPath in $searchPaths) {
            if (-not (Test-Path -LiteralPath $searchPath)) { continue }
            if ($carrierFound) { break }

            $rgCarrierPattern = 'class\s+' + [regex]::Escape($carrierNameForExistenceCheck) + '\b'
            $rgStdout = ''
            $rgExitCode = 1

            # v382: Try up to 3 times with short delays to handle transient filesystem issues
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    $rgStdout = rg $rgCarrierPattern --type java $searchPath 2>&1
                    $rgExitCode = $LASTEXITCODE

                    if ($rgExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($rgStdout)) {
                        $carrierFound = $true
                        $searchPathType = if ($searchPath -eq $worktreePathForCarrierCheck) { 'worktree' } else { 'project root' }
                        $warnings.Add("carrier_existence_check: '$carrierNameForExistenceCheck' found in $searchPathType") | Out-Null
                        break
                    }
                } catch {
                    # Ignore rg errors and try again or fall back to Get-ChildItem
                }

                if ($attempt -lt 3) {
                    Start-Sleep -Milliseconds 200
                }
            }

            # v382: Fallback to Get-ChildItem if rg failed or not available
            if (-not $carrierFound) {
                try {
                    $javaFiles = Get-ChildItem -LiteralPath $searchPath -Recurse -Filter "$carrierNameForExistenceCheck.java" -ErrorAction SilentlyContinue
                    if ($javaFiles.Count -gt 0) {
                        # Verify the file contains "class <CarrierName>"
                        foreach ($file in $javaFiles) {
                            $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                            if ($content -match "class\s+$carrierNameForExistenceCheck\b") {
                                $carrierFound = $true
                                $searchPathType = if ($searchPath -eq $worktreePathForCarrierCheck) { 'worktree' } else { 'project root' }
                                $warnings.Add("carrier_existence_check: '$carrierNameForExistenceCheck' found in $searchPathType via Get-ChildItem fallback") | Out-Null
                                break
                            }
                        }
                    }
                } catch {
                    # Get-ChildItem fallback also failed
                }
            }
        }

        if (-not $carrierFound) {
            # Carrier not found in codebase - this is a synthetic carrier
            $issues.Add('carrier_search_selected_carrier_not_found_in_codebase') | Out-Null
            $warnings.Add("carrier_existence_check: '$carrierNameForExistenceCheck' not found in codebase (searched: $($searchPaths -join ', '))") | Out-Null
        }
    }

    # v352: Integrate carrier search verification to validate carrier exists in codebase
    # Only run if carrier search fields are present (no missing field issues yet)
    $carrierFieldIssues = @($issues | Where-Object { $_ -like 'carrier_search*' })
    $worktreePath = if ([string]::IsNullOrWhiteSpace($Worktree)) { Join-Path $replayRootFull 'worktree' } else { Resolve-AbsolutePath $Worktree }
    $oracleCommitPath = Join-Path $replayRootFull 'ORACLE_COMMIT.txt'
    $oracleCommit = if (Test-Path -LiteralPath $oracleCommitPath) { (Get-Content -LiteralPath $oracleCommitPath -Raw -Encoding UTF8).Trim() } else { '' }
    $oracleDiffPath = Join-Path $replayRootFull 'ORACLE_DIFF_ANALYSIS.json'

    if (-not $SkipCarrierAndOracleChecks -and $carrierFieldIssues.Count -eq 0 -and (Test-Path -LiteralPath $worktreePath) -and $oracleCommit) {
        $carrierVerifyScript = Join-Path $PSScriptRoot 'Invoke-PlanCarrierSearchVerification.ps1'
        if (Test-Path -LiteralPath $carrierVerifyScript) {
            $planResultPathForCarrier = Join-Path $replayRootFull 'PLAN_RESULT.md'
            if (-not (Test-Path -LiteralPath $planResultPathForCarrier)) {
                $planResultPathForCarrier = Join-Path $replayRootFull 'PLAN_CANDIDATE_1.md'
            }

            if (Test-Path -LiteralPath $planResultPathForCarrier) {
                $carrierVerifyStdout = Join-Path $replayRootFull 'CARRIER_SEARCH_VERIFY.stdout.log'
                $carrierVerifyStderr = Join-Path $replayRootFull 'CARRIER_SEARCH_VERIFY.stderr.log'
                $carrierVerifyExit = & powershell -NoProfile -ExecutionPolicy Bypass -File $carrierVerifyScript -PlanResultPath $planResultPathForCarrier -Worktree $worktreePath -OracleCommit $oracleCommit -OracleDiffPath $oracleDiffPath > $carrierVerifyStdout 2> $carrierVerifyStderr
                $carrierVerifyExitCode = $LASTEXITCODE

                $carrierVerifyResultPath = if ($planResultPathForCarrier -match '\.(json|md)$') {
                    $planResultPathForCarrier -replace '\.(json|md)$', '_CARRIER_SEARCH_VERIFY.json'
                } else {
                    "$planResultPathForCarrier`_CARRIER_SEARCH_VERIFY.json"
                }

                if ($carrierVerifyExitCode -ne 0 -and (Test-Path -LiteralPath $carrierVerifyResultPath)) {
                    # Parse verification result to extract issues
                    try {
                        $carrierVerifyResult = Get-Content -LiteralPath $carrierVerifyResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($carrierVerifyResult.status -eq 'FAIL') {
                            foreach ($issue in $carrierVerifyResult.issues) {
                                $issues.Add("carrier_search_verify:$($issue.code)") | Out-Null
                            }
                        } elseif ($carrierVerifyResult.status -eq 'WARN') {
                            foreach ($warning in $carrierVerifyResult.warnings) {
                                $warnings.Add("carrier_search_verify:$($warning.code)") | Out-Null
                            }
                        }
                    } catch {
                        $warnings.Add("carrier_search_verify:parse_error:$($_.Exception.Message)") | Out-Null
                    }
                }
            }
        }
    }

    # Only check required=true families in REPLAY_PLAN
    foreach ($family in $requiredTrueFamilies) {
        Add-MissingTokenIssue -Issues $issues -Text $replayPlanText -Token $family -Issue "replay_plan_family_missing:$family"
    }
    $hasSelectedRealEntry = (
        $implementationContractText.IndexOf('selected real entry', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $implementationContractText.IndexOf('selected_real_entry', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $implementationContractText.IndexOf('selected real entries', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $implementationContractText.IndexOf('selected_real_entries', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    )
    if (-not $hasSelectedRealEntry) {
        $issues.Add('implementation_contract_missing:selected real entry') | Out-Null
    }
    $hasShallowGreenBan = $implementationContractText -match '(?i)shallow|static[-_]only|helper[-_]only|test[-_]only|helper/static|static\s+artifact|GREEN\s+Cannot\s+Claim\s+Core\s+DONE|core_tracer_green|cannot\s+close\s+(any\s+required\s+family|a\s+requirement\s+family|family|core)|does\s+not\s+close\s+(core|family|requirement)|not\s+close\s+(core|family|requirement)|helper.*GREEN.*(cannot|does\s+not|not).*close|GREEN.*helper.*(cannot|does\s+not|not).*close|claim\s+GREEN\s+without|No\s+Substitute|Forbidden\s+Substitute|forbidden.*test|Do\s+NOT\s+claim\s+GREEN|GREEN\s+without\s+running\s+test|FORBIDDEN.+(?:Mock|Stub|InMemory|TestOnly|Placeholder)|GREEN\s+Phase\s+Definition|GREEN\s+Phase\s+Requirements|slice\s+is\s+GREEN\s+when|core.*closure.*required.*YES|Core\s+Closure\s+Required.*YES'
    if (-not $hasShallowGreenBan) {
        $warnings.Add('implementation_contract_weak:shallow-green-ban') | Out-Null
    }
    Add-MissingTokenIssue -Issues $issues -Text $expectedDiffText -Token 'validation' -Issue 'expected_diff_missing:validation'
    # v449: Accept both "closure" and "status" keywords for backwards compatibility
    $hasClosureKeyword = $expectedDiffText.IndexOf('closure', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    $hasStatusKeyword = $expectedDiffText.IndexOf('status', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    if (-not $hasClosureKeyword -and -not $hasStatusKeyword) {
        $issues.Add('expected_diff_missing:closure_or_status') | Out-Null
    }
    foreach ($token in @('state', 'task', 'progress', 'log', 'transaction')) {
        Add-MissingTokenIssue -Issues $warnings -Text $sideEffectText -Token $token -Issue "side_effect_ledger_weak:$token"
    }
    Add-MissingTokenIssue -Issues $issues -Text $testCharterText -Token 'RED' -Issue 'test_charter_missing:RED'
    # Plan-stage GREEN detail is advisory. Slice execution enforces the
    # executable TEST_CHARTER contract before RED/test implementation starts.
    Add-MissingTokenIssue -Issues $warnings -Text $testCharterText -Token 'GREEN' -Issue 'test_charter_missing:GREEN'

    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('target family', 'target_family', 'highest_weight_open_gate', 'target subsurface', 'Target Subsurface') -Issue 'first_slice_proof_missing:target family'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('existing production carrier', 'existing_production_carrier', 'selected_carrier', 'selected carrier', 'target_subsurface_or_carrier', 'target subsurface') -Issue 'first_slice_proof_missing:existing production carrier'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('real_carrier_kind', 'Real Carrier Kind', 'real carrier kind') -Issue 'first_slice_proof_missing:real_carrier_kind'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('minimum_side_effect_or_blocker', 'Minimum Side Effect', 'minimum side effect') -Issue 'first_slice_proof_missing:minimum_side_effect_or_blocker'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('forbidden_substitute_check', 'Forbidden Substitute Check', 'forbidden substitute') -Issue 'first_slice_proof_missing:forbidden_substitute_check'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('production boundary', 'production_boundary') -Issue 'first_slice_proof_missing:production boundary'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('expected production diff', 'expected_production_diff') -Issue 'first_slice_proof_missing:expected production diff'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('RED', 'red_expectation') -Issue 'first_slice_proof_missing:RED'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('GREEN', 'green_minimum_implementation') -Issue 'first_slice_proof_missing:GREEN'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('proof_kind', 'Proof Kind', 'proof kind') -Issue 'first_slice_proof_missing:proof_kind'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('forbidden substitute proof', 'forbidden_substitute_proof', 'Forbidden Substitute') -Issue 'first_slice_proof_missing:forbidden substitute proof'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('fail-closed', 'fail_closed', 'fail_closed_condition', 'Fail-Closed') -Issue 'first_slice_proof_missing:fail-closed'
    Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens @('coverage cap', 'coverage_cap_if_not_closed') -Issue 'first_slice_proof_missing:coverage cap'
    if ($planFields.ContainsKey('first_slice')) {
        $sliceCandidates = @(Get-PlanBindingCandidates -Value $planFields['first_slice'])
        Add-MissingAnyTokenIssue -Issues $warnings -Text $firstSliceProofText -Tokens $sliceCandidates -Issue 'first_slice_proof_weak:first_slice'
    }
    if ($planFields.ContainsKey('first_red_test')) {
        $redCandidates = @(Get-PlanBindingCandidates -Value $planFields['first_red_test'] | Where-Object { $_ -match '#' })
        $hasFirstRedFieldInProof = (
            $firstSliceProofText.IndexOf('first_red_test', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $firstSliceProofText.IndexOf('first red test', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $firstSliceProofText.IndexOf('First RED Test', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        )
        if ($redCandidates.Count -gt 0 -and $hasFirstRedFieldInProof) {
            Add-MissingAnyTokenIssue -Issues $issues -Text $firstSliceProofText -Tokens $redCandidates -Issue 'first_slice_proof_mismatch:first_red_test'
        } elseif (-not $hasFirstRedFieldInProof -and $firstSliceProofText.IndexOf('red_expectation', [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and $firstSliceProofText.IndexOf('RED Expectation', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $issues.Add('first_slice_proof_mismatch:first_red_test') | Out-Null
        }
    }
    $hasSelectedRealEntryInProof = (
        $firstSliceProofText.IndexOf('selected real entry', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $firstSliceProofText.IndexOf('selected_real_entry', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $firstSliceProofText.IndexOf('selected_carrier', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $firstSliceProofText.IndexOf('target_subsurface_or_carrier', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    )
    if (-not $hasSelectedRealEntryInProof) {
        $issues.Add('first_slice_proof_missing:selected real entry') | Out-Null
    }
    $proofKindLinePattern = '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?(?:proof_kind|Proof\s+Kind)\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?[^\r\n]{0,240}(real_entry_behavior|stateful_side_effect|route_export_behavior|payload_shape_behavior|generated_artifact_behavior)'
    $proofKindHeadingPattern = '(?im)#+\s*(?:proof_kind|Proof\s+Kind)\s*\r?\n(?:[^\r\n]{0,200}\r?\n){0,3}[^\r\n]{0,240}(real_entry_behavior|stateful_side_effect|route_export_behavior|payload_shape_behavior|generated_artifact_behavior)'
    $proofKindTablePattern = '(?im)\|\s*proof_kind\s*\|\s*`?([^\r\n]*?(?:real_entry_behavior|stateful_side_effect|route_export_behavior|payload_shape_behavior|generated_artifact_behavior))'
    $hasExecutableProofKind = ($firstSliceProofText -match $proofKindLinePattern) -or ($firstSliceProofText -match $proofKindHeadingPattern) -or ($firstSliceProofText -match $proofKindTablePattern)
    if (-not $hasExecutableProofKind) {
        $issues.Add('first_slice_proof_missing:executable_proof_kind') | Out-Null
    }
    if ((-not $hasExecutableProofKind) -and $firstSliceProofText -match '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?proof_kind\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?[^\r\n]{0,240}(static_presence|helper_only|dto_only|compile_only)') {
        $issues.Add('first_slice_proof_invalid:static_or_helper_proof_kind') | Out-Null
    }
    $realCarrierKindLinePattern = '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?(?:real_carrier_kind|Real\s+Carrier\s+Kind)\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?[^\r\n]{0,240}(production_entry_or_service|production_controller_or_route|production_mapper_or_query|production_payload_builder|production_template_or_artifact_renderer|production_lifecycle_cleanup|production_service_method|production_service|production_enum|production_dto)'
    $realCarrierKindHeadingPattern = '(?im)#+\s*(?:real_carrier_kind|Real\s+Carrier\s+Kind)\s*\r?\n(?:[^\r\n]{0,200}\r?\n){0,3}[^\r\n]{0,240}(production_entry_or_service|production_controller_or_route|production_mapper_or_query|production_payload_builder|production_template_or_artifact_renderer|production_lifecycle_cleanup|production_service_method|production_service|production_enum|production_dto)'
    $realCarrierKindTablePattern = '(?im)\|\s*real_carrier_kind\s*\|\s*`?([^\r\n]*?(?:production_entry_or_service|production_controller_or_route|production_mapper_or_query|production_payload_builder|production_template_or_artifact_renderer|production_lifecycle_cleanup|production_service_method|production_service|production_enum|production_dto))'
    if (($firstSliceProofText -notmatch $realCarrierKindLinePattern) -and ($firstSliceProofText -notmatch $realCarrierKindHeadingPattern) -and ($firstSliceProofText -notmatch $realCarrierKindTablePattern)) {
        $issues.Add('first_slice_proof_invalid:real_carrier_kind') | Out-Null
    }
    if ($firstSliceProofText -match '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?real_carrier_kind\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?[^\r\n]{0,240}(protected_hook|test_subclass|helper_only|dto_only|static_presence|mock_only)') {
        $issues.Add('first_slice_proof_invalid:substitute_real_carrier_kind') | Out-Null
    }
    $forbiddenSubstitutePattern = '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:#{1,4}\s*)?(?:forbidden_substitute_check|Forbidden\s+Substitute\s+Check)\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*passed\b'
    $forbiddenSubstituteHeadingPattern = '(?im)#+\s*(?:forbidden_substitute_check|Forbidden\s+Substitute\s+Check)\s*\r?\n(?:[^\r\n]{0,200}\r?\n){0,5}[^\r\n]{0,200}PASSED'
    $forbiddenSubstituteResultPattern = '(?im)Result.*:?\s*PASSED'
    $forbiddenSubstituteTablePattern = '(?im)\|\s*forbidden_substitute_check\s*\|\s*passed\b'
    if (($firstSliceProofText -notmatch $forbiddenSubstitutePattern) -and ($firstSliceProofText -notmatch $forbiddenSubstituteHeadingPattern) -and ($firstSliceProofText -notmatch $forbiddenSubstituteResultPattern) -and ($firstSliceProofText -notmatch $forbiddenSubstituteTablePattern)) {
        $issues.Add('first_slice_proof_invalid:forbidden_substitute_check_not_passed') | Out-Null
    }
    if ($firstSliceProofText -match '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?minimum_side_effect_or_blocker\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(?:`?PLAN_BLOCKED_REAL_CARRIER`?|\s*blocked\s*:?\s*PLAN_BLOCKED_REAL_CARRIER)\s*$') {
        $issues.Add('first_slice_proof_blocked:real_carrier_missing') | Out-Null
    }

    # v261: Validate key:value schema fields exist with non-empty, non-placeholder values
    $requiredProofFields = @(
        'highest_weight_open_gate',
        'selected_real_entry',
        'selected_carrier',
        'target_subsurface_or_carrier',
        'production_boundary',
        'proof_kind',
        'real_carrier_kind',
        'first_red_test',
        'public_entry_contract_coverage',
        'forbidden_substitute_check',
        'required_sibling_surfaces',
        'minimum_side_effect_or_blocker',
        'expected_production_diff',
        'red_expectation',
        'green_minimum_implementation',
        'fail_closed_condition'
    )
    foreach ($fieldName in $requiredProofFields) {
        $fieldValue = Get-KeyValueField -Text $firstSliceProofText -Field $fieldName
        $fieldEmptyPattern = '(?im)^\s*(?:[-*]\s*)?(?:\*{0,2}\s*)?' + [regex]::Escape($fieldName) + '\s*\*{0,2}\s*[:=|][ \t]*$'
        $isEmptyMatch = [regex]::Match($firstSliceProofText, $fieldEmptyPattern)
        if ($isEmptyMatch.Success -and [string]::IsNullOrWhiteSpace($fieldValue)) {
            $issues.Add("first_slice_proof_schema_empty:$fieldName") | Out-Null
        } elseif ([string]::IsNullOrWhiteSpace($fieldValue)) {
            $issues.Add("first_slice_proof_schema_missing:$fieldName") | Out-Null
        } else {
            $fieldValue = $fieldValue.Trim()
            if ([string]::IsNullOrWhiteSpace($fieldValue)) {
                $issues.Add("first_slice_proof_schema_empty:$fieldName") | Out-Null
            } elseif ($fieldValue -match '(?i)^(TBD|unknown|N/A|placeholder|' + ([char]0x5F85 + [char]0x786E + [char]0x8BA4) + '|' + ([char]0x672A + [char]0x786E + [char]0x8BA4) + '|' + ([char]0x540E + [char]0x7EED + [char]0x786E + [char]0x8BA4) + ')$') {
                $issues.Add("first_slice_proof_schema_placeholder:$fieldName") | Out-Null
            }
        }
    }

    # v460: Fix v457 validation to support table format via Get-KeyValueField
    # v457: Experiment 3 - Plan Contract Hard Requirements
    # Validate first_slice_proof has complete TDD evidence fields
    $v457RequiredFields = @(
        'target_carrier_file_path',
        'target_carrier_line_number',
        'expected_test_class',
        'expected_test_method'
    )
    foreach ($fieldName in $v457RequiredFields) {
        $fieldValue = Get-KeyValueField -Text $firstSliceProofText -Field $fieldName
        if ([string]::IsNullOrWhiteSpace($fieldValue)) {
            $issues.Add("first_slice_proof_v457_missing:$fieldName") | Out-Null
        } else {
            $cleanValue = $fieldValue.Trim('`').Trim('*').Trim()
            if ([string]::IsNullOrWhiteSpace($cleanValue)) {
                $issues.Add("first_slice_proof_v457_empty:$fieldName") | Out-Null
            } elseif ($cleanValue -match '(?i)^(TBD|unknown|N/A|placeholder|' + ([char]0x5F85 + [char]0x786E + [char]0x8BA4) + '|' + ([char]0x672A + [char]0x786E + [char]0x8BA4) + '|' + ([char]0x540E + [char]0x7EED + [char]0x786E + [char]0x8BA4) + ')$') {
                $issues.Add("first_slice_proof_v457_placeholder:$fieldName") | Out-Null
            }
        }
    }

    # v457: Validate target_carrier_line_number is numeric
    # v461: Allow NEW_SERVICE pattern - line number will be determined during implementation
    # v464: Generalize to allow any value starting with NEW (e.g., "NEW (oracle +1502 lines...)")
    $lineNumberValue = Get-KeyValueField -Text $firstSliceProofText -Field 'target_carrier_line_number'
    if (-not [string]::IsNullOrWhiteSpace($lineNumberValue)) {
        $cleanLineNumber = $lineNumberValue.Trim('`').Trim('*').Trim()
        # v464: Allow any NEW pattern - line number not known for new services
        # Matches: "NEW", "NEW_SERVICE", "NEW (oracle +1502 lines...)", "NEW - line determined during implementation"
        # Note: Use ^NEW\s|^NEW$ to match NEW followed by space or end, plus backward compat with NEW_SERVICE
        if ($cleanLineNumber -match '^NEW\s|^NEW$|^NEW_SERVICE') {
            # Valid - the line number will be determined during implementation
        }
        # v464: Extract numeric part if it has description
        elseif ($cleanLineNumber -notmatch '^\d+') {
            $issues.Add("first_slice_proof_v457_invalid_line_number:$cleanLineNumber") | Out-Null
        }
    }

    # v457: Validate target_carrier_file_path is a valid .java path
    $carrierFilePathValue = Get-KeyValueField -Text $firstSliceProofText -Field 'target_carrier_file_path'
    if (-not [string]::IsNullOrWhiteSpace($carrierFilePathValue)) {
        $carrierFilePathCandidates = @(
            $carrierFilePathValue -split '\s*(?:;|,|\|)\s*' |
                ForEach-Object { ([string]$_).Trim('`').Trim('*').Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        foreach ($cleanPath in $carrierFilePathCandidates) {
            if ($cleanPath -notmatch '\.java$') {
                $issues.Add("first_slice_proof_v457_invalid_file_path:$cleanPath") | Out-Null
            } elseif (-not [string]::IsNullOrWhiteSpace($worktreePath) -and (Test-Path -LiteralPath $worktreePath)) {
                $carrierPathFull = if ([System.IO.Path]::IsPathRooted($cleanPath)) {
                    [System.IO.Path]::GetFullPath($cleanPath)
                } else {
                    [System.IO.Path]::GetFullPath((Join-Path $worktreePath $cleanPath))
                }
                if (-not (Test-Path -LiteralPath $carrierPathFull -PathType Leaf)) {
                    $issues.Add("first_slice_proof_v457_file_not_found:$cleanPath") | Out-Null
                }
            }
        }
    }

    # v457: Validate expected_assertions has at least 3 items
    $expectedAssertionsValue = Get-KeyValueField -Text $firstSliceProofText -Field 'expected_assertions'
    if ([string]::IsNullOrWhiteSpace($expectedAssertionsValue)) {
        $issues.Add("first_slice_proof_v457_assertions_missing") | Out-Null
    } else {
        # Try to parse as array-like content (comma-separated, list items, or JSON array)
        $cleanAssertions = $expectedAssertionsValue.Trim('`').Trim('*').Trim()
        $assertionCount = 0
        if ($cleanAssertions -match '^\[.*\]$') {
            # JSON array format
            try {
                $parsed = $cleanAssertions | ConvertFrom-Json
                if ($parsed -is [array]) {
                    $assertionCount = $parsed.Count
                }
            } catch { }
        } else {
            # Count list items or comma-separated values
            $assertionCount = ($cleanAssertions -split '(?m)^\s*[-*]\s*|\s*,\s*').Where({ -not [string]::IsNullOrWhiteSpace($_) }).Count
            if ($assertionCount -eq 1 -and $cleanAssertions -match '[,;\n]') {
                # Might be multi-line but not properly formatted, try alternative split
                $assertionCount = ($cleanAssertions -split '[,;\n]').Where({ -not [string]::IsNullOrWhiteSpace($_) }).Count
            }
        }
        if ($assertionCount -lt 3) {
            $issues.Add("first_slice_proof_v457_assertions_insufficient:$assertionCount/3") | Out-Null
        }
    }

    # v457: Validate expected_side_effects has at least 1 item
    $expectedSideEffectsValue = Get-KeyValueField -Text $firstSliceProofText -Field 'expected_side_effects'
    if ([string]::IsNullOrWhiteSpace($expectedSideEffectsValue)) {
        $issues.Add("first_slice_proof_v457_side_effects_missing") | Out-Null
    } else {
        $cleanSideEffects = $expectedSideEffectsValue.Trim('`').Trim('*').Trim()
        $sideEffectCount = 0
        if ($cleanSideEffects -match '^\[.*\]$') {
            try {
                $parsed = $cleanSideEffects | ConvertFrom-Json
                if ($parsed -is [array]) {
                    $sideEffectCount = $parsed.Count
                }
            } catch { }
        } else {
            $sideEffectCount = ($cleanSideEffects -split '(?m)^\s*[-*]\s*|\s*,\s*').Where({ -not [string]::IsNullOrWhiteSpace($_) }).Count
        }
        if ($sideEffectCount -lt 1) {
            $issues.Add("first_slice_proof_v457_side_effects_insufficient:$sideEffectCount/1") | Out-Null
        }
    }

    # v295: A PROCEED plan cannot make the first slice a contract-only or
    # RED-only staging pass. The first executable slice must include RED,
    # minimum GREEN implementation, and a concrete production side effect,
    # payload, route, generated artifact, or state proof in the same slice.
    $firstSliceValue = Get-KeyValueField -Text $firstSliceProofText -Field 'first_slice'
    $minimumSideEffectValue = Get-KeyValueField -Text $firstSliceProofText -Field 'minimum_side_effect_or_blocker'
    $productionBoundaryValue = Get-KeyValueField -Text $firstSliceProofText -Field 'production_boundary'
    $expectedProductionDiffValue = Get-KeyValueField -Text $firstSliceProofText -Field 'expected_production_diff'
    $greenMinimumValue = Get-KeyValueField -Text $firstSliceProofText -Field 'green_minimum_implementation'
    $highestWeightOpenGateValue = Get-KeyValueField -Text $firstSliceProofText -Field 'highest_weight_open_gate'
    $firstSliceFamilyValue = Get-KeyValueField -Text $firstSliceProofText -Field 'first_slice_family'
    if ([string]::IsNullOrWhiteSpace($firstSliceFamilyValue)) {
        $firstSliceFamilyValue = Get-KeyValueField -Text $firstSliceProofText -Field 'target_family'
    }
    if ([string]::IsNullOrWhiteSpace($firstSliceFamilyValue)) {
        $firstSliceFamilyValue = Get-KeyValueField -Text $firstSliceProofText -Field 'slice_family'
    }
    if ([string]::IsNullOrWhiteSpace($firstSliceFamilyValue)) {
        $firstSliceFamilyValue = $highestWeightOpenGateValue
    }
    $selectedCarrierValueForFirstSlice = Get-KeyValueField -Text $firstSliceProofText -Field 'selected_carrier'
    $proofKindValueForFirstSlice = Get-KeyValueField -Text $firstSliceProofText -Field 'proof_kind'
    $realCarrierKindValueForFirstSlice = Get-KeyValueField -Text $firstSliceProofText -Field 'real_carrier_kind'
    $goldenSliceBindingPlanValue = Get-KeyValueField -Text $planText -Field 'golden_slice_binding'
    $goldenSliceBindingProofValue = Get-KeyValueField -Text $firstSliceProofText -Field 'golden_slice_binding'
    # v331: Fixed contract-only pattern to avoid false positive on "Core Implementation with RED Tests"
    # v439: Refined pattern to avoid false positive on "Schema & Contract Definition" style slice names
    # Only matches true contract-only/RED-only scenarios:
    # - CONTRACT_ONLY, contract & RED (without GREEN), contract definition/classes ONLY
    # - RED-only, tests-only (explicit "only" keyword without implementation)
    # - no production code, defer to later slice
    # Note: "Schema & Contract Definition" with RED+GREEN+side effect is NOT contract-only
    $contractOnlyPattern = '(?i)(CONTRACT_ONLY|contract\s*(?:&|and)\s*RED(?!\s*(?:&|and)\s*GREEN)|\bcontract\s+definition\s+only\b|\bcontract\s+classes?\s+only\b|\btests?\s+only\b(?!\s+with\s+implementation)|\bRED[-\s]*only\b(?!\s+with\s+GREEN)|\bno\s+production\s+code\b(?!\s+planned)|\bdoes\s+not\s+touch\s+production\b(?!\s+in\s+this\s+slice)|\bproduces\s+no\s+production\b(?!\s+in\s+this\s+slice)|\bdefer(?:red)?\s+to\s+S\d\b(?!\s+with\s+earlier\s+implementation)|\bto\s+be\s+implemented\s+in\s+Slice\s+\d\b(?!\s+with\s+earlier\s+implementation))'
    $noneLikePattern = '(?i)^\s*(NONE|N/A|NOT_APPLICABLE|none_with_reason|PLAN_BLOCKED_[A-Z0-9_]+)\b'
    $planStatus = $planStatusForLaterCheck
    if ($planStatus -eq 'PROCEED') {
        if ($hasGoldenDeliverySlice) {
            $goldenPlaceholderPattern = '(?i)^\s*(NONE|N/A|TBD|TODO|unknown|placeholder|none_with_reason|PLAN_BLOCKED_[A-Z0-9_]+)\s*$'
            if ([string]::IsNullOrWhiteSpace($goldenSliceBindingPlanValue) -or $goldenSliceBindingPlanValue -match $goldenPlaceholderPattern) {
                $issues.Add('golden_slice_binding_missing:plan_result') | Out-Null
            } elseif ($goldenSliceBindingPlanValue -notmatch '(?i)(side_effect_ledger_gap|exact_contract_gap|schema_contract_discovery_gap|low_verification_cap|oracle_overlap|positive_first_slice|first_slice_contract|stateful_side_effect|literal_contract|real_entry)') {
                $issues.Add('golden_slice_binding_weak:plan_result') | Out-Null
                $warnings.Add("PLAN_RESULT.md golden_slice_binding must contain one of these fingerprint keywords: side_effect_ledger_gap, exact_contract_gap, schema_contract_discovery_gap, low_verification_cap, oracle_overlap, positive_first_slice, first_slice_contract, stateful_side_effect, literal_contract, real_entry. Current value: $goldenSliceBindingPlanValue") | Out-Null
            }
            if ([string]::IsNullOrWhiteSpace($goldenSliceBindingProofValue) -or $goldenSliceBindingProofValue -match $goldenPlaceholderPattern) {
                $issues.Add('golden_slice_binding_missing:first_slice_proof') | Out-Null
            } elseif ($goldenSliceBindingProofValue -notmatch '(?i)(side_effect_ledger_gap|exact_contract_gap|schema_contract_discovery_gap|low_verification_cap|oracle_overlap|positive_first_slice|first_slice_contract|stateful_side_effect|literal_contract|real_entry)') {
                $issues.Add('golden_slice_binding_weak:first_slice_proof') | Out-Null
                $warnings.Add("FIRST_SLICE_PROOF_PLAN.md golden_slice_binding must contain one of these fingerprint keywords: side_effect_ledger_gap, exact_contract_gap, schema_contract_discovery_gap, low_verification_cap, oracle_overlap, positive_first_slice, first_slice_contract, stateful_side_effect, literal_contract, real_entry. Current value: $goldenSliceBindingProofValue") | Out-Null
            }
        }
        if ([string]::IsNullOrWhiteSpace($minimumSideEffectValue) -or
            $minimumSideEffectValue -match $noneLikePattern -or
            $minimumSideEffectValue -match $contractOnlyPattern) {
            $issues.Add('first_slice_proof_invalid:minimum_side_effect_or_blocker') | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace($greenMinimumValue) -or
            $greenMinimumValue -match $noneLikePattern -or
            $greenMinimumValue -match '(?i)(to\s+be\s+implemented\s+in\s+Slice\s+\d|defer(?:red)?\s+to\s+S\d)') {
            $issues.Add('first_slice_proof_invalid:green_deferred_or_missing') | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace($productionBoundaryValue) -or
            $productionBoundaryValue -match $noneLikePattern -or
            $productionBoundaryValue -match $contractOnlyPattern) {
            $issues.Add('first_slice_proof_invalid:contract_only_first_slice') | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace($expectedProductionDiffValue) -or
            $expectedProductionDiffValue -match $noneLikePattern -or
            $expectedProductionDiffValue -match $contractOnlyPattern) {
            $issues.Add('first_slice_proof_invalid:expected_production_diff_none') | Out-Null
        }
        if ($firstSliceValue -match $contractOnlyPattern) {
            $issues.Add('first_slice_proof_invalid:contract_only_first_slice') | Out-Null
        }
        $firstSliceTargetsCoreEntry = $firstSliceFamilyValue -match '(?i)core_entry'
        if (($highestWeightOpenGateValue -match '(?i)core_entry') -and -not $firstSliceTargetsCoreEntry) {
            $warnings.Add("core_entry_deferred_by_prerequisite_slice:$firstSliceFamilyValue") | Out-Null
        }
        if ($firstSliceTargetsCoreEntry) {
            if ($proofKindValueForFirstSlice -match '(?i)payload_shape_behavior|generated_artifact_behavior|route_export_behavior') {
                $issues.Add('first_slice_proof_invalid:core_entry_static_carrier') | Out-Null
            }
            if ($realCarrierKindValueForFirstSlice -match '(?i)production_enum|production_dto' -or
                $selectedCarrierValueForFirstSlice -match '(?i)(Constant|DTO|Dto|Entity|Mapper|Config\s*\+)') {
                $issues.Add('first_slice_proof_invalid:core_entry_static_carrier') | Out-Null
            }
            # v459/v461/v464: Layer validation - core_entry family requires Facade/Controller entry point
            # v461: Extract actual carrier name (before first '(') to avoid false positives
            # Example: "AiApplyClaimApiTaskProcessor (EXISTING -> calls NEW AiAutoClaimFlowService)"
            # should extract "AiApplyClaimApiTaskProcessor" not match on "AiAutoClaimFlowService"
            # v464: Allow Service layer carriers if plan documents an existing Facade/Controller entry point
            # Example: NEW Service called from existing Facade/TaskProcessor is valid
            $actualCarrier = $selectedCarrierValueForFirstSlice.Split('(')[0].Trim()
            $hasServicePattern = $actualCarrier -match '(?i)Service'
            $hasFacadeOrControllerPattern = $actualCarrier -match '(?i)Facade|Controller'

            if ($hasServicePattern -and -not $hasFacadeOrControllerPattern) {
                # v464: Check if plan documents an existing entry point that can call this Service
                # Look for selected_real_entry or Facade layer documentation
                $selectedRealEntryMatch = [regex]::Match($firstSliceProofText, '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?selected_real_entry\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$')
                $hasExistingEntryPoint = $false

                if ($selectedRealEntryMatch.Success) {
                    $realEntryValue = $selectedRealEntryMatch.Groups[1].Value
                    # Check if real_entry references a Facade/Controller or existing TaskProcessor that can call the Service
                    if ($realEntryValue -match '(?i)Facade|Controller|TaskProcessor|Api') {
                        $hasExistingEntryPoint = $true
                    }
                }

                # v464: Also check Layer Validation Pre-Check section if present
                # Look for patterns like "Facade Layer Integration:" or "Layer Stack:"
                if ($firstSliceProofText -match '(?im)Facade.*Layer.*Integration|Layer.*Stack|Facade.*EXISTS') {
                    $hasExistingEntryPoint = $true
                }

                # v464: Only fail if Service layer carrier AND no existing entry point documented
                if (-not $hasExistingEntryPoint) {
                    $issues.Add('layer_validation_failed:core_entry_requires_facade_controller_no_facade_found') | Out-Null
                }
            }
        }
    }

    # Public entry carrier mismatch: if selected_real_entry is a public entry,
    # selected_carrier must also name a public entry type, not just Mapper/Entity/DTO
    $publicEntryPattern = '(?i)(Facade(?:Impl)?|Controller(?:Impl)?|Api|Endpoint|Route)\b'
    $selectedRealEntryMatch = [regex]::Match($firstSliceProofText, '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?selected_real_entry\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$')
    if ($firstSliceFamilyValue -match '(?i)core_entry' -and $selectedRealEntryMatch.Success -and $selectedRealEntryMatch.Groups[1].Value -match $publicEntryPattern) {
        $selectedCarrierMatch = [regex]::Match($firstSliceProofText, '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?selected_carrier\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$')
        if ($selectedCarrierMatch.Success -and $selectedCarrierMatch.Groups[1].Value -notmatch $publicEntryPattern) {
            $issues.Add('first_slice_proof_invalid:public_entry_carrier_mismatch') | Out-Null
        }
    }

    # v289: Test harness placement gate. In this claim replay workspace, claim-core
    # does not carry the test dependencies needed for JUnit/Mockito/Spring Test.
    # Planning a RED directly under claim-core creates an environment-blocked round,
    # not a business RED.
    $firstRedTestMatch = [regex]::Match($firstSliceProofText, '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?first_red_test\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$')
    if ($firstRedTestMatch.Success) {
        $firstRedValue = $firstRedTestMatch.Groups[1].Value.Trim()
        if ($firstRedValue -match '(?i)(claim-core[/\\]src[/\\]test|-pl\s+claim-core|claim-core\s+-Dtest)') {
            $issues.Add('first_slice_proof_invalid:test_harness_claim_core') | Out-Null
        }
        if ($firstRedValue -match '(?i)(dependency\s*:|add\s+JUnit|鏂板.*(JUnit|Mockito|Spring Test))') {
            $issues.Add('first_slice_proof_invalid:test_dependency_change') | Out-Null
        }

        # v376: Executable Evidence Gate - test file existence verification
        # NOTE: At Plan stage, test files don't exist yet. This check should only run at Phase 1
        # when RED tests are expected to be written. Skip this check at Plan stage.
        # The test file existence check is performed by Phase 1 verifiers (RED phase).
        #
        # If worktree is provided and first_red_test is specified, verify the test file exists
        # Only applicable at Phase 1, not at Plan stage
        # if ((Test-Path -LiteralPath $worktreePath) -and -not [string]::IsNullOrWhiteSpace($firstRedValue)) {
        #     # Parse first_red_test value to extract test file path
        #     # Expected formats:
        #     # - TestClass.java#testMethod
        #     # - path/to/TestClass.java#testMethod
        #     # - TestClass.testMethod
        #     # - TestClassTest.testMethod_HappyPath_DBEvidence
        #
        #     $testFileMatch = [regex]::Match($firstRedValue, '^([A-Za-z0-9_/\\\.]+\.java|[^#\.]+Test)(?:#|\.|$)')
        #     if ($testFileMatch.Success) {
        #         $testFileName = $testFileMatch.Groups[1].Value
        #
        #         # Construct full test file path
        #         # Try various locations:
        #         # 1. Direct path if already qualified
        #         # 2. Under claim-server/src/test/java/
        #         # 3. Under src/test/java/
        #         # 4. Search in worktree
        #
        #         $testFilePaths = @(
        #             if ($testFileName -match '[/\\]') { Join-Path $worktreePath $testFileName } else { $null }
        #             Join-Path $worktreePath "claim-server\src\test\java\com\huize\claim\core\ai\service\$testFileName"
        #             Join-Path $worktreePath "claim-server\src\test\java\$testFileName"
        #             Join-Path $worktreePath "src\test\java\$testFileName"
        #         ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        #
        #         $testFileFound = $false
        #         foreach ($candidatePath in $testFilePaths) {
        #             if (Test-Path -LiteralPath $candidatePath) {
        #                 $testFileFound = $true
        #                 break
        #             }
        #         }
        #
        #         # If not found in expected locations, try a broader search
        #         if (-not $testFileFound) {
        #             try {
        #                 $searchResult = Get-ChildItem -LiteralPath $worktreePath -Recurse -Filter "$testFileName" -ErrorAction SilentlyContinue | Select-Object -First 1
        #                 if ($searchResult) {
        #                     $testFileFound = $true
        #                 }
        #             } catch {}
        #         }
        #
        #         if (-not $testFileFound) {
        #             $issues.Add('first_slice_proof_mismatch:test_file_not_found') | Out-Null
        #             $warnings.Add("first_red_test claims '$testFileName' but file does not exist in worktree") | Out-Null
        #         }
        #     }
        # }
    }

    # --- Interface Contract Pre-Verification Gate (v267) ---
    # For public/external entries, require interface contract fields
    $interfaceContractPattern = '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:interface_contract_return_type|pattern_return_type)\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'
    $errorHandlingContractPattern = '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:interface_contract_error_handling|pattern_error_handling)\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'
    $placeholderContractPattern = '(?i)^(TBD|unknown|N/A|placeholder|' + ([char]0x5F85 + [char]0x786E + [char]0x8BA4) + '|' + ([char]0x672A + [char]0x786E + [char]0x8BA4) + ')$'
    if ($selectedRealEntryMatch.Success -and $selectedRealEntryMatch.Groups[1].Value -match '(?i)(Facade(?:Impl)?|Controller(?:Impl)?|Api|Endpoint|Route|Callback|Push|Notify|Receive|Send)\b') {
        $combinedProofAndExploration = "$firstSliceProofText`n$explorationText`n$planText"
        $returnTypeMatch = [regex]::Match($combinedProofAndExploration, $interfaceContractPattern)
        if (-not $returnTypeMatch.Success -or [string]::IsNullOrWhiteSpace($returnTypeMatch.Groups[1].Value)) {
            $issues.Add('interface_contract_return_type_missing') | Out-Null
        } elseif ($returnTypeMatch.Groups[1].Value.Trim().Trim('`').Trim() -match $placeholderContractPattern) {
            $issues.Add('interface_contract_return_type_placeholder') | Out-Null
        }
        $errorHandlingMatch = [regex]::Match($combinedProofAndExploration, $errorHandlingContractPattern)
        if (-not $errorHandlingMatch.Success -or [string]::IsNullOrWhiteSpace($errorHandlingMatch.Groups[1].Value)) {
            $issues.Add('interface_contract_error_handling_missing') | Out-Null
        } elseif ($errorHandlingMatch.Groups[1].Value.Trim().Trim('`').Trim() -match $placeholderContractPattern) {
            $issues.Add('interface_contract_error_handling_placeholder') | Out-Null
        }
    }

    # --- Pattern to Follow Check (v267) ---
    # For integration/callback features, require pattern_to_follow with concrete evidence
    $patternToFollowPattern = '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?pattern_to_follow\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'
    $patternEvidencePattern = '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?pattern_evidence_source\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'
    if ($selectedRealEntryMatch.Success -and $selectedRealEntryMatch.Groups[1].Value -match '(?i)(Facade(?:Impl)?|Callback|Push|Notify|Receive|Send|Api|Endpoint)\b') {
        $ptfMatch = [regex]::Match($firstSliceProofText, $patternToFollowPattern)
        if (-not $ptfMatch.Success -or [string]::IsNullOrWhiteSpace($ptfMatch.Groups[1].Value)) {
            $issues.Add('pattern_to_follow_missing') | Out-Null
        } elseif ($ptfMatch.Groups[1].Value.Trim().Trim('`').Trim() -match $placeholderContractPattern) {
            $issues.Add('pattern_to_follow_placeholder') | Out-Null
        }
        $peMatch = [regex]::Match($firstSliceProofText, $patternEvidencePattern)
        if (-not $peMatch.Success -or [string]::IsNullOrWhiteSpace($peMatch.Groups[1].Value)) {
            $issues.Add('pattern_evidence_source_missing') | Out-Null
        } else {
            $peValue = $peMatch.Groups[1].Value.Trim().Trim('`').Trim()
            if (-not [string]::IsNullOrWhiteSpace($peValue)) {
                $hasReproducibleEvidence = (
                    $peValue -match '(?i)(\brg\b|\bgrep\b|\bfindstr\b|\bag\b|\back\b|\bsift\b)\s' -or
                    $peValue -match '(?i)--include\s|--type\s' -or
                    $peValue -match '\w+\.(java|kt|py|ts|js|go|cs|rb|rs|scala|xml|yaml|yml|json|sql|groovy|gradle|md)' -or
                    $peValue -match '\w+[#.]\w+\('
                )
                if (-not $hasReproducibleEvidence) {
                    $issues.Add('pattern_evidence_source_narrative_only') | Out-Null
                }
            }
        }
    }

    # Oracle overlap validation (Experiment 1: Oracle-First Planning)
    # Fail-closed: any problem with oracle analysis is a blocking issue
    $oracleAnalysisPath = Join-Path $replayRootFull 'ORACLE_DIFF_ANALYSIS.json'
    $oracleAnalysisValid = $false
    $oracleProdFiles = @()
    $missingProdFiles = @()
    $missingHighWeightFiles = @()

    if (-not (Test-Path -LiteralPath $oracleAnalysisPath)) {
        $issues.Add('oracle_analysis_missing') | Out-Null
    } else {
        try {
            $oracleRaw = Get-Content -LiteralPath $oracleAnalysisPath -Raw -Encoding UTF8
            $oracleAnalysis = $oracleRaw | ConvertFrom-Json
            if ($null -eq $oracleAnalysis.files) {
                $issues.Add('oracle_analysis_invalid:no_files_property') | Out-Null
            } else {
                $oracleProdFiles = @($oracleAnalysis.files | Where-Object { [bool]$_.is_production } | ForEach-Object { [string]$_.path })
                if ($oracleProdFiles.Count -eq 0) {
                    $issues.Add('oracle_production_files_empty') | Out-Null
                } else {
                    $oracleAnalysisValid = $true
                }
            }
        } catch {
            $issues.Add("oracle_analysis_invalid:$($_.Exception.Message)") | Out-Null
        }
    }

    if ($oracleAnalysisValid) {
        $combinedPlanText = "$planText`n$replayPlanText`n$expectedDiffText`n$firstSliceProofText`n$implementationContractText"

        # v380: Fix oracle_out_of_scope_files parsing
        # Support both formats: [file1, file2] and "file1 (desc); file2 (desc)"
        $oracleOutOfScopeFiles = @()
        # Try bracket format first
        $outOfScopeMatch = $combinedPlanText -match '(?im)^\s*-?\s*oracle_out_of_scope_files\s*[:=]\s*\[(.+?)\]'
        if ($outOfScopeMatch) {
            $outOfScopeContent = $Matches[1]
            $outOfScopeParts = $outOfScopeContent -split '\s*,\s*'
            foreach ($part in $outOfScopeParts) {
                $fileName = $part.Trim().Trim('''').Trim('"').Trim('`')
                if (-not [string]::IsNullOrWhiteSpace($fileName)) {
                    $oracleOutOfScopeFiles += $fileName
                }
            }
        } else {
            # Try semicolon format: "File1 (desc); File2 (desc)"
            $outOfScopeMatch = $combinedPlanText -match '(?im)^\s*-?\s*oracle_out_of_scope_files\s*[:=]\s*(.+)'
            if ($outOfScopeMatch) {
                $outOfScopeContent = $Matches[1]
                # Split by semicolon
                $outOfScopeParts = $outOfScopeContent -split '\s*;\s*'
                foreach ($part in $outOfScopeParts) {
                    # Extract filename before parentheses (remove description)
                    if ($part -match '^\s*([A-Za-z0-9_$.]+)') {
                        $fileName = $Matches[1].Trim()
                        if (-not [string]::IsNullOrWhiteSpace($fileName)) {
                            $oracleOutOfScopeFiles += $fileName
                        }
                    }
                }
            }
        }

        # v380: Domain-aware oracle filtering for cross-feature oracles
        # When oracle spans multiple domains, filter by primary domain before calculating overlap
        $oraclePrimaryDomain = $null
        if ($planText -match '(?im)^\s*-?\s*oracle_primary_domain\s*[:=]\s*([^\r\n]+)') {
            $oraclePrimaryDomain = $Matches[1].Trim().Trim('''').Trim('"').Trim('/')
        }

        # v399/v400: Domain-to-directory mapping for common domains.
        # Keep this ASCII-safe; generated non-ASCII literals previously broke
        # the PowerShell hash literal and disabled this verifier.
        $domainDirectoryMap = @{
            'ai' = 'ai'
            'ai-claim' = 'ai'
            'ai-claim-auto' = 'ai'
            'aiclaim' = 'ai'
            'aiclaimv2' = 'ai'
            'auto-claim' = 'ai'
            'ocr' = 'ocr'
            'calculate' = 'calculate'
            'calculation' = 'calculate'
            'review' = 'review'
            'risk' = 'risk'
            'pay' = 'pay'
            'payment' = 'pay'
            'push' = 'push'
            'import' = 'import'
            'export' = 'export'
        }

        # Build list of directory patterns to try for this domain.
        $domainDirectoryPatterns = @()
        if (-not [string]::IsNullOrWhiteSpace($oraclePrimaryDomain)) {
            $domainDirectoryPatterns += $oraclePrimaryDomain
            $domainKey = $oraclePrimaryDomain.ToLowerInvariant()
            if ($domainDirectoryMap.ContainsKey($domainKey)) {
                $domainDirectoryPatterns += $domainDirectoryMap[$domainKey]
            }
            if ($domainKey -match 'ai|claim|auto') { $domainDirectoryPatterns += 'ai' }
            if ($domainKey -match 'ocr') { $domainDirectoryPatterns += 'ocr' }
            if ($domainKey -match 'risk') { $domainDirectoryPatterns += 'risk' }
            if ($domainKey -match 'push') { $domainDirectoryPatterns += 'push' }
        }
        $domainDirectoryPatterns = @($domainDirectoryPatterns | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

        # Domain filter: if primary domain is specified, filter oracle files to that domain only.
        # This makes overlap calculation meaningful when oracle includes cross-domain files.
        $domainFilteredOracleFiles = @($oracleProdFiles)
        if (-not [string]::IsNullOrWhiteSpace($oraclePrimaryDomain)) {
            $domainFilteredOracleFiles = @($oracleProdFiles | Where-Object {
                $oracleFile = $_ -replace '\\', '/'
                # Try each domain pattern (original domain name + mapped directory names).
                $matched = $false
                foreach ($pattern in $domainDirectoryPatterns) {
                    $safePattern = [regex]::Escape(([string]$pattern).Trim('/'))
                    if (-not [string]::IsNullOrWhiteSpace($safePattern) -and $oracleFile -match "/$safePattern/") {
                        $matched = $true
                        break
                    }
                }
                $matched
            })
            $domainFilteredCount = $domainFilteredOracleFiles.Count

            # v399/v400: Empty domain filters are warnings, not silent false passes.
            if ($domainFilteredCount -eq 0 -and $oracleProdFiles.Count -gt 0) {
                $warnings.Add("oracle_domain_filter_empty:no_files_matched_for_domain_`"$oraclePrimaryDomain`"_try_adding_to_domainDirectoryMap") | Out-Null
                # When filter results in 0 files, use all oracle files to avoid false 100% overlap.
                $domainFilteredOracleFiles = @($oracleProdFiles)
                $domainFilteredCount = $domainFilteredOracleFiles.Count
            } elseif ($domainFilteredCount -lt $oracleProdFiles.Count) {
                $warnings.Add("oracle_domain_filter:applied_$oraclePrimaryDomain($domainFilteredCount/$($oracleProdFiles.Count))") | Out-Null
            }
        }

        # v380: Fix oracle_out_of_scope_files filtering bug (now works on domain-filtered files)
        # Previous logic used substring match (-like "*$_*") which incorrectly excluded
        # files that contained the exclusion pattern as a substring (e.g., "Facade"
        # in exclusion list would match "AiAutoClaimFlowFacade" even though it's not
        # "InsureCompanyPushFacade"). Now use exact match on filename without extension.
        $filteredOracleProdFiles = @($domainFilteredOracleFiles | Where-Object {
            $oracleFile = $_
            $fileName = [System.IO.Path]::GetFileName($oracleFile)
            $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($oracleFile)
            # Check if this exact file (by name) is in the out-of-scope list
            -not ($oracleOutOfScopeFiles | Where-Object {
                $exclName = [System.IO.Path]::GetFileNameWithoutExtension($_)
                $fileName -eq $_ -or $fileNameWithoutExt -eq $exclName
            })
        })

        $matchedCount = 0
        foreach ($oracleFile in $filteredOracleProdFiles) {
            $fileName = [System.IO.Path]::GetFileName($oracleFile)
            if ($combinedPlanText.IndexOf($fileName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $combinedPlanText.IndexOf($oracleFile, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $matchedCount++
            } else {
                $missingProdFiles += $oracleFile
            }
        }
        $overlapPercent = if ($filteredOracleProdFiles.Count -gt 0) { [math]::Floor(($matchedCount / $filteredOracleProdFiles.Count) * 100) } else { 100 }

        # Check oracle_production_file_overlap field in PLAN_RESULT
        $declaredOverlap = Get-FirstText $planText @(
            '(?m)^\s*-?\s*\*{0,2}\s*oracle_production_file_overlap\s*[:=]\s*\*{0,2}\s*([0-9]+)\s*%?\s*\*{0,2}',
            '(?m)^\s*-?\s*\*{0,2}\s*oracle_production_file_overlap\s*\*{0,2}\s*[:=]\s*[`*]*([0-9]+)%?[`*]*',
            '(?m)^\s*-?\s*oracle_production_file_overlap\s*[:=]\s*[`*]*([0-9]+)%?[`*]*',
            '(?m)^\s*-?\s*\*{0,2}\s*oracle[_-]production[_-]file[_-]overlap\s*[:=]\s*\*{0,2}\s*([0-9]+)\s*%?\s*\*{0,2}',
            '(?m)^\s*-?\s*\*{0,2}\s*oracle[_-]production[_-]file[_-]overlap\s*\*{0,2}\s*[:=]\s*[`*]*([0-9]+)%?[`*]*',
            '(?m)^\s*-?\s*oracle[_-]production[_-]file[_-]overlap\s*[:=]\s*[`*]*([0-9]+)%?[`*]*'
        )

        $oracleHighWeightFiles = @($oracleAnalysis.files | Where-Object { [string]$_.weight -eq 'HIGH' -and [bool]$_.is_production } | ForEach-Object { [string]$_.path })
        # v380: Apply domain filter to HIGH-weight files as well
        # v399: Use domain-to-directory mapping for HIGH-weight files
        $domainFilteredHighWeightFiles = @($oracleHighWeightFiles)
        if (-not [string]::IsNullOrWhiteSpace($oraclePrimaryDomain)) {
            $domainFilteredHighWeightFiles = @($oracleHighWeightFiles | Where-Object {
                $oracleFile = $_ -replace '\\', '/'
                # Try each domain pattern (original domain name + mapped directory names)
                $matched = $false
                foreach ($pattern in $domainDirectoryPatterns) {
                    if ($oracleFile -match "/$pattern/") {
                        $matched = $true
                        break
                    }
                }
                $matched
            })
        }
        # v380: Fix oracle_out_of_scope_files filtering bug for HIGH-weight files (now on domain-filtered)
        # Use exact filename match instead of substring match to avoid false exclusions.
        $filteredHighWeightFiles = @($domainFilteredHighWeightFiles | Where-Object {
            $hwFile = $_
            $hwName = [System.IO.Path]::GetFileName($hwFile)
            $hwNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($hwFile)
            # Check if this exact file (by name) is in the out-of-scope list
            -not ($oracleOutOfScopeFiles | Where-Object {
                $exclName = [System.IO.Path]::GetFileNameWithoutExtension($_)
                $hwName -eq $_ -or $hwNameWithoutExt -eq $exclName
            })
        })
        $highWeightMatched = 0
        foreach ($hwFile in $filteredHighWeightFiles) {
            $hwName = [System.IO.Path]::GetFileName($hwFile)
            if ($combinedPlanText.IndexOf($hwName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $combinedPlanText.IndexOf($hwFile, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $highWeightMatched++
            } else {
                $missingHighWeightFiles += $hwFile
            }
        }

        # v398: Add high-weight oracle overlap threshold
        # High-weight files (core services, task processors, key facades) must have at least 70% coverage
        $highWeightOverlapPercent = if ($filteredHighWeightFiles.Count -gt 0) {
            [math]::Floor(($highWeightMatched / $filteredHighWeightFiles.Count) * 100)
        } else {
            100
        }

        # v451: Add domain-aware expansion guidance reference
        $domainExpansionGuidancePath = Join-Path $PSScriptRoot '..\prompts\PLAN_ORACLE_DOMAIN_EXPANSION.md'
        $hasDomainExpansionGuidance = Test-Path -LiteralPath $domainExpansionGuidancePath

        $highWeightThreshold = 70
        if ($highWeightOverlapPercent -lt $highWeightThreshold) {
            $issues.Add("oracle_high_weight_overlap_below_threshold:${highWeightOverlapPercent}%<${highWeightThreshold}%") | Out-Null

            # v442: Add explicit diagnostic for missing high-weight files
            if ($missingHighWeightFiles.Count -gt 0) {
                $missingFilesList = $missingHighWeightFiles -join ', '
                $warnings.Add("oracle_high_weight_missing_files:$missingFilesList") | Out-Null
            }

            # v451: Add guidance reference when domain expansion prompt exists
            if ($hasDomainExpansionGuidance) {
                $warnings.Add("oracle_high_weight_guidance_available:see_prompts/PLAN_ORACLE_DOMAIN_EXPANSION.md_for_domain_aware_expansion_by_priority") | Out-Null
            }

            # Require oracle repair ledger for high-weight gaps
            $hasHighWeightRepairLedger = (
                $combinedPlanText.IndexOf('Oracle Coverage Repair Ledger', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $combinedPlanText -match '(?im)^\s*-?\s*oracle_missing_high_weight_files\s*[:=]\s*\S' -or
                $combinedPlanText -match '(?im)^\s*-?\s*oracle_expansion_plan\s*[:=]\s*\S'
            )
            if (-not $hasHighWeightRepairLedger) {
                $issues.Add('oracle_high_weight_repair_ledger_missing') | Out-Null
            }
        }

        # v421: Domain-aware overlap exemption for honest architectural separation
        # When oracle contains LOW-weight DTO/Resource/UI files that require separate frontend replay,
        # and plan focuses on HIGH-weight backend services with reasonable coverage, allow proceeding with adjusted cap.
        $hasHonestOutOfScopeExplanation = $false
        $domainSeparationDetected = $false
        if ($overlapPercent -lt 50 -and $hasOracleOutOfScope) {
            # Extract oracle_out_of_scope_files content for analysis
            $outOfScopeContent = Get-FirstText $combinedPlanText @(
                '(?im)^\s*-?\s*oracle_out_of_scope_files\s*[:=]\s*(.+)',
                '(?im)^\s*oracle_out_of_scope_files\s*[:=]\s*(.+)'
            )
            # Also check expansion_plan for domain separation language
            $expansionPlanContent = Get-FirstText $combinedPlanText @(
                '(?im)^\s*-?\s*oracle_expansion_plan\s*[:=]\s*(.+)',
                '(?im)^\s*oracle_expansion_plan\s*[:=]\s*(.+)'
            )

            # Look for domain separation indicators
            $domainSeparationPatterns = @(
                'LOW-weight.*DTO.*Mapper.*Resource.*UI',
                'require.*separate.*frontend.*replay',
                'frontend.*backend.*separation',
                'domain.*compatibility.*compatibility',
                'foreign.*domain.*legitimate',
                'UI.*frontend.*files.*require.*separate'
            )
            foreach ($pattern in $domainSeparationPatterns) {
                if ($outOfScopeContent -match $pattern -or $expansionPlanContent -match $pattern) {
                    $domainSeparationDetected = $true
                    break
                }
            }

            # Check if out_of_scope lists specific LOW-weight file categories (not just TBD/placeholder)
            $hasLowWeightFileCategories = $outOfScopeContent -match '(?i)DTO|Mapper|Resource|UI|jsp|js|ftl|xml' -and
                                          $outOfScopeContent -notmatch '(?i)TBD|TODO|unknown|placeholder|none'

            # Check for honest "cannot reach threshold" language
            $hasCannotReachThresholdLanguage = $expansionPlanContent -match '(?i)cannot.*reach.*threshold|honest.*assessment|BLOCKED.*threshold|below.*threshold.*honest'

            $hasHonestOutOfScopeExplanation = $hasLowWeightFileCategories -and $hasCannotReachThresholdLanguage
        }

        # v350: Auto-repair stale PLAN_RESULT.md when overlap >= 50% but plan_status is BLOCKED
        # v467: Fixed stale blocker detection to check actual overlap >= 50% threshold
        # This eliminates staleness between verification result and plan status
        $planStatus = Get-FirstText $planText @(
            '(?m)^\s*-?\s*plan_status\s*[:=]\s*[`*]*([A-Z_]+)[`*]*',
            '(?m)\bplan_status\b[^\nA-Z_]*([A-Z_]{3,})'
        )
        $planBlocker = Get-FirstText $planText @(
            '(?m)^\s*-?\s*blocker\s*[:=]\s*(.+?)\s*$',
            '(?m)^\s*blocker\s*:\s*(.+?)\s*$',
            '(?m)\*?\*?Blocker\*?\*?\s*:\s*(.+?)\s*$',
            '(?i)\*\*?blocker\*?\*?\s*[:=]\s*(.+?)\s*$'
        )
        # v467: Fix stale blocker detection to require actual overlap >= 50%
        # Previously would auto-repair even when overlap was truly below threshold
        $isStaleBlocker = ($planStatus -eq 'BLOCKED') -and
            ($planBlocker -match 'oracle_overlap_below_threshold') -and
            ($overlapPercent -ge 50)
        # v409: Auto-repair stale high-weight blocker when coverage improves to >= 70%
        # v448: Also apply when honest out-of-scope files are documented (exemption for documented architectural separation)
        # v467: Fixed to be consistent with threshold checking - both conditions explicitly check the threshold
        $isStaleHighWeightBlocker = ($planStatus -eq 'BLOCKED') -and
            ($planBlocker -match 'oracle_high_weight_overlap_below_threshold') -and
            ($highWeightOverlapPercent -ge 70 -or ($hasHonestOutOfScopeExplanation -and $highWeightOverlapPercent -ge 40))

        # v451: Add domain-aware expansion guidance reference
        $domainExpansionGuidancePath = Join-Path $PSScriptRoot '..\prompts\PLAN_ORACLE_DOMAIN_EXPANSION.md'
        $hasDomainExpansionGuidance = Test-Path -LiteralPath $domainExpansionGuidancePath

        # Fail-closed: overlap < 50% is an issue
        if ($overlapPercent -lt 50) {
            $issues.Add("oracle_overlap_below_threshold:$overlapPercent%<50%") | Out-Null

            # v451: Add guidance reference when domain expansion prompt exists
            if ($hasDomainExpansionGuidance) {
                $warnings.Add("oracle_overlap_guidance_available:see_prompts/PLAN_ORACLE_DOMAIN_EXPANSION.md_for_domain_aware_expansion_strategy") | Out-Null
            }

            $hasOracleRepairLedger = (
                $combinedPlanText.IndexOf('Oracle Coverage Repair Ledger', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $combinedPlanText -match '(?im)^\s*-?\s*oracle_missing_high_weight_files\s*[:=]\s*\S' -or
                $combinedPlanText -match '(?im)^\s*-?\s*oracle_expansion_plan\s*[:=]\s*\S' -or
                $combinedPlanText -match '(?im)^\s*-?\s*oracle_out_of_scope_files\s*[:=]\s*\S'
            )
            $hasOracleExpansionPlan = $combinedPlanText -match '(?im)^\s*-?\s*oracle_expansion_plan\s*[:=]\s*(?!\s*$)(?!\s*(TBD|TODO|unknown|placeholder)\s*$).+'
            $hasOracleOutOfScope = $combinedPlanText -match '(?im)^\s*-?\s*oracle_out_of_scope_files\s*[:=]\s*(?!\s*$)(?!\s*(TBD|TODO|unknown|placeholder)\s*$).+'
            if (-not ($hasOracleRepairLedger -and ($hasOracleExpansionPlan -or $hasOracleOutOfScope))) {
                $issues.Add('oracle_overlap_repair_ledger_missing') | Out-Null
            }

            # v421: Domain-aware exemption - if honest out_of_scope with domain separation and reasonable high-weight coverage
            $shouldApplyDomainExemption = $hasHonestOutOfScopeExplanation -and ($highWeightOverlapPercent -ge 40)

            # v387: Auto-repair when overlap < 50% but plan_status is PROCEED or incorrectly set
            # This prevents plans with insufficient oracle coverage from proceeding to implementation
            # v421 update: Apply domain exemption when honest architectural separation is detected
            $needsBlockerRepair = ($planStatus -ne 'BLOCKED') -or ($planBlocker -notmatch 'oracle_overlap_below_threshold')
            if ($needsBlockerRepair) {
                $planResultPath = Join-Path $replayRootFull 'PLAN_RESULT.md'
                if (Test-Path -LiteralPath $planResultPath) {
                    $planContent = Get-Content -LiteralPath $planResultPath -Raw -Encoding UTF8
                    $repairedContent = $planContent

                    if ($shouldApplyDomainExemption) {
                        # v421: Apply domain exemption - set PROCEED with adjusted cap instead of BLOCKED
                        $warnings.Add("v421_domain_exemption_applied:overlap_${overlapPercent}%_high_weight_${highWeightOverlapPercent}%_architectural_separation_detected") | Out-Null

                        # Update plan_status: anything -> PROCEED
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*plan_status\s*[:=]\s*)\w+\s*$', '${1}PROCEED'
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?plan_status`?\s*[:|=|]\s*\w+\s*$', '${1}`plan_status`: PROCEED'

                        # Update or add domain_exemption field
                        if ($repairedContent -notmatch '(?m)^[\s`]*domain_exemption[\s`]*[:|=|]') {
                            if (-not $repairedContent.EndsWith("`n")) {
                                $repairedContent += "`n"
                            }
                            $repairedContent += "`domain_exemption`: applied (LOW-weight DTO/Resource/UI files require separate frontend replay)`n"
                        }

                        # Update blocker: anything -> none (exemption applied)
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*blocker\s*[:=]\s*).+?$', '${1}none'
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?blocker`?\s*[:|=|]\s*.+?$', '${1}`blocker`: none'
                        $repairedContent = $repairedContent -replace '(?m)(\*?\*?Blocker\*?\*?\s*:\s*).+?$', '${1}none'
                    } else {
                        # v387 original: hard BLOCKED for insufficient coverage without honest exemption
                        # Update plan_status: PROCEED/anything -> BLOCKED
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*plan_status\s*[:=]\s*)\w+\s*$', '${1}BLOCKED'
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?plan_status`?\s*[:|=|]\s*\w+\s*$', '${1}`plan_status`: BLOCKED'

                        # Update blocker: anything -> oracle_overlap_below_threshold
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*blocker\s*[:=]\s*).+?$', '${1}oracle_overlap_below_threshold'
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?blocker`?\s*[:|=|]\s*.+?$', '${1}`blocker`: oracle_overlap_below_threshold'
                        # v416: Handle markdown format **Blocker**: value
                        $repairedContent = $repairedContent -replace '(?m)(\*?\*?Blocker\*?\*?\s*:\s*).+?$', '${1}oracle_overlap_below_threshold'

                        # If blocker line doesn't exist, add it after plan_status line
                        if ($repairedContent -notmatch '(?m)^[\s`]*blocker[\s`]*[:|=|]' -and $repairedContent -notmatch '(?i)\*?\*?Blocker\*?\*?\s*:') {
                            # Append blocker line to the end of the content (only trim whitespace, not content)
                            if (-not $repairedContent.EndsWith("`n")) {
                                $repairedContent += "`n"
                            }
                            $repairedContent += "`blocker`: oracle_overlap_below_threshold`n"
                        }
                    }

                    # Update oracle_production_file_overlap: XX% -> calculated value
                    $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*oracle_production_file_overlap\s*[:=]\s*)\d+%\s*$', "${1}${overlapPercent}%"
                    $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?oracle_production_file_overlap`?\s*[:|=|]\s*\d+%\s*$', "${1}`oracle_production_file_overlap`: ${overlapPercent}%"

                    # Update oracle_missing_high_weight_files: none/anything -> actual missing files
                    if ($missingHighWeightFiles.Count -gt 0) {
                        $missingFilesList = $missingHighWeightFiles -join '; '
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*oracle_missing_high_weight_files\s*[:=]\s*).+?$', "${1}$missingFilesList"
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?oracle_missing_high_weight_files`?\s*[:|=|]\s*.+?$', "${1}`oracle_missing_high_weight_files`: $missingFilesList"
                    }

                    if ($repairedContent -ne $planContent) {
                        Set-Content -LiteralPath $planResultPath -Value $repairedContent -Encoding UTF8
                        if ($shouldApplyDomainExemption) {
                            $warnings.Add("plan_result_auto_repaired:v421_domain_exemption_overlap_${overlapPercent}%_plan_status_set_to_PROCEED") | Out-Null
                        } else {
                            $warnings.Add("plan_result_auto_repaired:oracle_overlap_below_threshold_${overlapPercent}%_plan_status_set_to_BLOCKED") | Out-Null
                        }
                        # Re-read plan text after repair for subsequent checks
                        $planText = $repairedContent
                        $combinedPlanText = "$planText`n$replayPlanText`n$expectedDiffText`n$firstSliceProofText`n$implementationContractText"
                    }
                }
            }
        } elseif ($isStaleBlocker) {
            # Auto-repair: overlap >= 50% but plan is still BLOCKED with stale oracle_overlap_below_threshold
            # Update PLAN_RESULT.md with correct values
            $planResultPath = Join-Path $replayRootFull 'PLAN_RESULT.md'
            if (Test-Path -LiteralPath $planResultPath) {
                $planContent = Get-Content -LiteralPath $planResultPath -Raw -Encoding UTF8
                $repairedContent = $planContent

                # Update plan_status: BLOCKED -> PROCEED
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*plan_status\s*[:=]\s*)BLOCKED\s*$', '${1}PROCEED'
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?plan_status`?\s*[:|=|]\s*BLOCKED\s*$', '${1}`plan_status`: PROCEED'

                # v405: Update blocker: oracle_overlap_below_threshold (with any trailing text) -> none
                # Fixed regex to match blocker text even when additional description follows
                # Note: PowerShell -replace doesn't support (?m) with ^ anchor, use line-by-line approach
                $lines = $repairedContent -split "`r?`n"
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match 'blocker\s*[:=|]\s*oracle_overlap_below_threshold') {
                        if ($lines[$i] -match '^\s*-\s*blocker\s*[:=]\s*') {
                            $lines[$i] = $lines[$i] -replace 'blocker\s*[:=]\s*oracle_overlap_below_threshold.*', 'blocker: none'
                        } elseif ($lines[$i] -match '\*?\*?Blocker\*?\*?\s*:\s*') {
                            # Handle markdown format: **Blocker**: oracle_overlap_below_threshold
                            $lines[$i] = $lines[$i] -replace '\*?\*?Blocker\*?\*?\s*:\s*oracle_overlap_below_threshold.*', '**Blocker**: none'
                        } else {
                            $lines[$i] = $lines[$i] -replace 'blocker\s*[:=|]\s*oracle_overlap_below_threshold.*', 'blocker: none'
                        }
                    }
                }
                $repairedContent = $lines -join "`r`n"

                # Update oracle_production_file_overlap: XX% -> calculated value
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*oracle_production_file_overlap\s*[:=]\s*)\d+%\s*$', "${1}${overlapPercent}%"
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?oracle_production_file_overlap`?\s*[:|=|]\s*\d+%\s*$', "${1}`oracle_production_file_overlap`: ${overlapPercent}%"

                # Update oracle_high_weight_coverage: XX% (N/M) -> calculated value
                $highWeightCovPercent = if ($filteredHighWeightFiles.Count -gt 0) { [math]::Floor(($highWeightMatched / $filteredHighWeightFiles.Count) * 100) } else { 100 }
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*oracle_high_weight_coverage\s*[:=]\s*)\d+%\s+\(\d+/\d+\)', "${1}${highWeightCovPercent}% ($highWeightMatched/$($filteredHighWeightFiles.Count))"
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?oracle_high_weight_coverage`?\s*[:|=|]\s*\d+%\s+\(\d+/\d+\)', "${1}`oracle_high_weight_coverage`: ${highWeightCovPercent}% ($highWeightMatched/$($filteredHighWeightFiles.Count))"

                if ($repairedContent -ne $planContent) {
                    Set-Content -LiteralPath $planResultPath -Value $repairedContent -Encoding UTF8
                    $warnings.Add("plan_result_auto_repaired:oracle_overlap_updated_from_stale_to_${overlapPercent}%") | Out-Null
                    # Re-read plan text after repair for subsequent checks
                    $planText = $repairedContent
                    $combinedPlanText = "$planText`n$replayPlanText`n$expectedDiffText`n$firstSliceProofText`n$implementationContractText"
                }
            }
        } elseif ($isStaleHighWeightBlocker) {
            # v409: Auto-repair stale high-weight blocker when coverage improves to >= 70%
            # Update PLAN_RESULT.md with correct values
            $planResultPath = Join-Path $replayRootFull 'PLAN_RESULT.md'
            if (Test-Path -LiteralPath $planResultPath) {
                $planContent = Get-Content -LiteralPath $planResultPath -Raw -Encoding UTF8
                $repairedContent = $planContent

                # Update plan_status: BLOCKED -> PROCEED
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*plan_status\s*[:=]\s*)BLOCKED\s*$', '${1}PROCEED'
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?plan_status`?\s*[:|=|]\s*BLOCKED\s*$', '${1}`plan_status`: PROCEED'

                # Update blocker: oracle_high_weight_overlap_below_threshold (with any trailing text) -> none
                $lines = $repairedContent -split "`r?`n"
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match 'blocker\s*[:=|]\s*oracle_high_weight_overlap_below_threshold') {
                        if ($lines[$i] -match '^\s*-\s*blocker\s*[:=]\s*') {
                            $lines[$i] = $lines[$i] -replace 'blocker\s*[:=]\s*oracle_high_weight_overlap_below_threshold.*', 'blocker: none'
                        } elseif ($lines[$i] -match '\*?\*?Blocker\*?\*?\s*:\s*') {
                            # Handle markdown format: **Blocker**: oracle_high_weight_overlap_below_threshold
                            $lines[$i] = $lines[$i] -replace '\*?\*?Blocker\*?\*?\s*:\s*oracle_high_weight_overlap_below_threshold.*', '**Blocker**: none'
                        } else {
                            $lines[$i] = $lines[$i] -replace 'blocker\s*[:=|]\s*oracle_high_weight_overlap_below_threshold.*', 'blocker: none'
                        }
                    }
                }
                $repairedContent = $lines -join "`r`n"

                # Update oracle_production_file_overlap: XX% -> calculated value
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*oracle_production_file_overlap\s*[:=]\s*)\d+%\s*$', "${1}${overlapPercent}%"
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?oracle_production_file_overlap`?\s*[:|=|]\s*\d+%\s*$', "${1}`oracle_production_file_overlap`: ${overlapPercent}%"

                # Update oracle_high_weight_coverage: XX% (N/M) -> calculated value
                $highWeightCovPercent = if ($filteredHighWeightFiles.Count -gt 0) { [math]::Floor(($highWeightMatched / $filteredHighWeightFiles.Count) * 100) } else { 100 }
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*oracle_high_weight_coverage\s*[:=]\s*)\d+%\s+\(\d+/\d+\)', "${1}${highWeightCovPercent}% ($highWeightMatched/$($filteredHighWeightFiles.Count))"
                $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?oracle_high_weight_coverage`?\s*[:|=|]\s*\d+%\s+\(\d+/\d+\)', "${1}`oracle_high_weight_coverage`: ${highWeightCovPercent}% ($highWeightMatched/$($filteredHighWeightFiles.Count))"

                if ($repairedContent -ne $planContent) {
                    Set-Content -LiteralPath $planResultPath -Value $repairedContent -Encoding UTF8
                    $warnings.Add("plan_result_auto_repaired:oracle_high_weight_overlap_updated_from_stale_to_${highWeightCovPercent}%") | Out-Null
                    # Re-read plan text after repair for subsequent checks
                    $planText = $repairedContent
                    $combinedPlanText = "$planText`n$replayPlanText`n$expectedDiffText`n$firstSliceProofText`n$implementationContractText"
                }
            }
        }

        # v448: HIGH-weight out-of-scope exemption when overlap >= 50% but high-weight < 70%
        # This handles the case where honest out-of-scope files (e.g., OCR services upstream of trigger point)
        # are documented but still counted against high-weight coverage percentage
        if ($overlapPercent -ge 50 -and $highWeightOverlapPercent -lt 70 -and $hasHonestOutOfScopeExplanation) {
            # v448: Apply exemption when honest architectural separation is documented
            # and reasonable high-weight coverage is achieved on in-scope files
            $shouldApplyHighWeightExemption = $hasHonestOutOfScopeExplanation -and ($highWeightOverlapPercent -ge 40)

            if ($shouldApplyHighWeightExemption) {
                # v448: Auto-repair high-weight blocker when exemption applies
                $isStaleHighWeightBlocker = ($planStatus -eq 'BLOCKED') -and ($planBlocker -match 'oracle_high_weight_overlap_below_threshold')

                if ($isStaleHighWeightBlocker) {
                    $planResultPath = Join-Path $replayRootFull 'PLAN_RESULT.md'
                    if (Test-Path -LiteralPath $planResultPath) {
                        $planContent = Get-Content -LiteralPath $planResultPath -Raw -Encoding UTF8
                        $repairedContent = $planContent

                        # v448: Update plan_status: BLOCKED -> PROCEED
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*plan_status\s*[:=]\s*)BLOCKED\s*$', '${1}PROCEED'
                        $repairedContent = $repairedContent -replace '(?m)^(\s*-?\s*)`?plan_status`?\s*[:|=|]\s*BLOCKED\s*$', '${1}`plan_status`: PROCEED'

                        # v448: Update blocker: oracle_high_weight_overlap_below_threshold -> none
                        $lines = $repairedContent -split "`r?`n"
                        for ($i = 0; $i -lt $lines.Count; $i++) {
                            if ($lines[$i] -match 'blocker\s*[:=|]\s*oracle_high_weight_overlap_below_threshold') {
                                if ($lines[$i] -match '^\s*-\s*blocker\s*[:=]\s*') {
                                    $lines[$i] = $lines[$i] -replace 'blocker\s*[:=]\s*oracle_high_weight_overlap_below_threshold.*', 'blocker: none'
                                } elseif ($lines[$i] -match '\*?\*?Blocker\*?\*?\s*:\s*') {
                                    $lines[$i] = $lines[$i] -replace '\*?\*?Blocker\*?\*?\s*:\s*oracle_high_weight_overlap_below_threshold.*', '**Blocker**: none'
                                } else {
                                    $lines[$i] = $lines[$i] -replace 'blocker\s*[:=|]\s*oracle_high_weight_overlap_below_threshold.*', 'blocker: none'
                                }
                            }
                        }
                        $repairedContent = $lines -join "`r`n"

                        # v448: Add domain_exemption field if not present
                        if ($repairedContent -notmatch '(?m)^[\s`]*domain_exemption[\s`]*[:|=|]') {
                            if (-not $repairedContent.EndsWith("`n")) {
                                $repairedContent += "`n"
                            }
                            $repairedContent += "`domain_exemption`: applied (HIGH-weight out-of-scope files documented: architectural separation)`n"
                        }

                        if ($repairedContent -ne $planContent) {
                            Set-Content -LiteralPath $planResultPath -Value $repairedContent -Encoding UTF8
                            $warnings.Add("v448_highweight_exemption_applied:highweight_${highWeightOverlapPercent}%_out_of_scope_files_excluded") | Out-Null
                            # Re-read plan text after repair
                            $planText = $repairedContent
                            $combinedPlanText = "$planText`n$replayPlanText`n$expectedDiffText`n$firstSliceProofText`n$implementationContractText"
                        }
                    }
                }
            }
        }

        # Warn if HIGH-weight files are not covered
        if ($filteredHighWeightFiles.Count -gt 0 -and $highWeightMatched -lt $filteredHighWeightFiles.Count) {
            $warnings.Add("oracle_high_weight_uncovered:$highWeightMatched/$($filteredHighWeightFiles.Count)") | Out-Null
        }
        # v270: fail closed if oracle_production_file_overlap is not declared.
        if ([string]::IsNullOrWhiteSpace($declaredOverlap)) {
            $issues.Add('plan_result_missing:oracle_production_file_overlap') | Out-Null
        }
    }
}

# v443: Layer-First Pre-Validation - Validate carrier layer for core_entry family
# This gate detects when plans select Service/Provider layer carriers for core_entry family
# and provides actionable Facade suggestions instead of blocking late in execution
$coreEntryCarrierPattern = '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?(?:first_executable_carrier|selected_carrier|selected_real_entry)\s*\*{0,2}\s*[:=|]\s*(?:\r?\n\s*:\s*)?\s*(.+?)\s*$'
$coreEntryCarrierMatch = [regex]::Match($combinedPlanArtifacts, $coreEntryCarrierPattern)

if ($coreEntryCarrierMatch.Success) {
    $coreEntryCarrier = $coreEntryCarrierMatch.Groups[1].Value.Trim().Trim('`').Trim('*').Trim()

    if (-not [string]::IsNullOrWhiteSpace($coreEntryCarrier)) {
        $carrierLayer = Test-CarrierLayer -CarrierPath $coreEntryCarrier

        # Check if this first slice is a core_entry slice. A replay may keep
        # core_entry as the highest pending gate while S1 is an explicit
        # prerequisite slice such as config_policy_threshold; layer validation
        # must apply to the actual first slice family, not the pending family.
        $firstSliceFamilyForLayerGate = Get-KeyValueField -Text $combinedPlanArtifacts -Field 'first_slice_family'
        if ([string]::IsNullOrWhiteSpace($firstSliceFamilyForLayerGate)) {
            $firstSliceFamilyForLayerGate = Get-KeyValueField -Text $combinedPlanArtifacts -Field 'target_family'
        }
        if ([string]::IsNullOrWhiteSpace($firstSliceFamilyForLayerGate)) {
            $firstSliceFamilyForLayerGate = Get-KeyValueField -Text $combinedPlanArtifacts -Field 'slice_family'
        }
        if ([string]::IsNullOrWhiteSpace($firstSliceFamilyForLayerGate)) {
            $firstSliceFamilyForLayerGate = Get-KeyValueField -Text $combinedPlanArtifacts -Field 'highest_weight_open_gate'
        }

        $isCoreEntryFamily = ($firstSliceFamilyForLayerGate -match '(?i)core_entry')

        if ($isCoreEntryFamily -and $carrierLayer -notin @("Facade", "Controller", "Unknown")) {
            # Try to find suggested Facade
            $suggestion = Get-SuggestedFacade -ServiceCarrier $coreEntryCarrier -Worktree $worktreePath

            if ($suggestion.Found) {
                $issues.Add('layer_validation_failed:core_entry_requires_facade_controller') | Out-Null
                $warnings.Add("layer_validation: Carrier '$coreEntryCarrier' is in $carrierLayer layer. core_entry requires Facade/Controller layer. Suggested Facade: $($suggestion.ClassName) at $($suggestion.SearchOutput)") | Out-Null
            } else {
                $issues.Add('layer_validation_failed:core_entry_requires_facade_controller_no_facade_found') | Out-Null
                $warnings.Add("layer_validation: Carrier '$coreEntryCarrier' is in $carrierLayer layer. core_entry requires Facade/Controller layer. No corresponding Facade found.") | Out-Null
            }
        }
    }
}

# v350: Deferred plan_status check after oracle overlap auto-repair
# If auto-repair changed plan_status to PROCEED, we should not add the issue
if ($planStatusCheckDeferred -and $Stage -eq 'Plan') {
    # Re-read plan status after potential auto-repair
    $finalPlanStatus = Get-FirstText $planText @(
        '(?m)^\s*-?\s*plan_status\s*[:=]\s*[`*]*([A-Z_]+)[`*]*',
        '(?m)\bplan_status\b[^\nA-Z_]*([A-Z_]{3,})',
        '(?m)^\s*-?\s*status\s*[:=]\s*[`*]*([A-Z_]+)[`*]*'
    )
    if ($finalPlanStatus -ne 'PROCEED') {
        $issues.Add("plan_status_not_proceed:$finalPlanStatus") | Out-Null
    }
}

$verificationStatus = if ($issues.Count -gt 0) { 'FAIL' } else { 'PASS' }
$oracleOverlapPercentValue = $null
if ($null -ne $overlapPercent) {
    $oracleOverlapPercentValue = $overlapPercent
}
$oracleOverlapMatchedValue = $null
if ($null -ne $matchedCount) {
    $oracleOverlapMatchedValue = $matchedCount
}
$oracleOverlapTotalProductionValue = $null
if ($null -ne $domainFilteredOracleFiles) {
    $oracleOverlapTotalProductionValue = @($domainFilteredOracleFiles).Count
}
$oracleHighWeightMatchedValue = $null
if ($null -ne $highWeightMatched) {
    $oracleHighWeightMatchedValue = $highWeightMatched
}
$oracleHighWeightTotalValue = $null
if ($null -ne $filteredHighWeightFiles) {
    $oracleHighWeightTotalValue = @($filteredHighWeightFiles).Count
}
$oracleMissingProductionFilesValue = @($missingProdFiles)
$oracleMissingHighWeightFilesValue = @($missingHighWeightFiles)
$issuesValue = @($issues.ToArray())
$issueEvidenceValue = @($issueEvidence.ToArray())
$warningsValue = @($warnings.ToArray())
$verify = [ordered]@{
    stage = $Stage
    replay_root = $replayRootFull
    verification_status = $verificationStatus
    oracle_overlap_percent = $oracleOverlapPercentValue
    oracle_overlap_matched = $oracleOverlapMatchedValue
    oracle_overlap_total_production = $oracleOverlapTotalProductionValue
    oracle_high_weight_matched = $oracleHighWeightMatchedValue
    oracle_high_weight_total = $oracleHighWeightTotalValue
    oracle_missing_production_files = $oracleMissingProductionFilesValue
    oracle_missing_high_weight_files = $oracleMissingHighWeightFilesValue
    issues = $issuesValue
    issue_evidence = $issueEvidenceValue
    warnings = $warningsValue
}

$verify | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $verifyPath -Encoding UTF8
Get-Content -LiteralPath $verifyPath -Encoding UTF8

if ($verificationStatus -ne 'PASS') {
    exit 1
}
exit 0
