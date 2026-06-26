param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [string]$SliceResultPath,
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

function Get-StringValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return '' }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        return [string]$Object.$Name
    }
    return ''
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktreeFull = Resolve-AbsolutePath $Worktree
$sliceResultPath = Resolve-AbsolutePath $SliceResultPath

$outputPath = Join-Path $replayRootFull ('EXECUTABLE_EVIDENCE_GATE_{0:D2}.json' -f $SliceIndex)
if ($ValidateOnly) {
    [ordered]@{
        stage = 'executable_evidence_gate'
        validation_status = 'PASS'
        mode = 'ValidateOnly'
        replay_root = $replayRootFull
        worktree = $worktreeFull
        slice_result = $sliceResultPath
        output_path = $outputPath
    } | ConvertTo-Json -Depth 8
    exit 0
}

$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

# Read slice result
$slice = Read-JsonObject -Path $sliceResultPath
$normalizerScript = Join-Path $PSScriptRoot 'SliceResultSchemaNormalizer.ps1'
if (Test-Path -LiteralPath $normalizerScript) {
    . $normalizerScript
    $schemaNormalization = Invoke-SliceResultSchemaNormalization -Slice $slice
    foreach ($normalizationWarning in @($schemaNormalization.warnings)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$normalizationWarning)) {
            $warnings.Add([string]$normalizationWarning) | Out-Null
        }
    }
}
$sliceStatus = [string]$slice.slice_status
$sliceType = [string]$slice.slice_type
$targetSubsurface = [string]$slice.target_subsurface_or_carrier
$productionBoundary = [string]$slice.production_boundary
$proofKind = [string]$slice.proof_kind
$touchedFamilies = @(Get-StringArray $slice.touched_requirement_families)
$closedFamilies = @(Get-StringArray $slice.closed_requirement_families)
$implementedFiles = @(Get-StringArray $slice.implemented_files)
$changedFiles = @(
    (Get-StringArray $slice.current_slice_changed_files) +
    (Get-StringArray $slice.round_changed_files_snapshot) +
    (Get-StringArray $slice.changed_files)
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
$effectiveFiles = @($implementedFiles + $changedFiles) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
$gapFlags = @(Get-StringArray $slice.gap_flags)

# Read supporting artifacts
$sideEffectLedgerPath = Join-Path $replayRootFull 'SIDE_EFFECT_LEDGER.md'
$testCharterPath = Join-Path $replayRootFull 'TEST_CHARTER.md'
$sideEffectText = Read-TextIfExists -Path $sideEffectLedgerPath
$testCharterText = Read-TextIfExists -Path $testCharterPath

# ===== v281 VALIDATION 1: Wrong Test Surface Detection =====

# Check if slice claims to close a family but only tests helpers/DTOs.
# Leading \b is intentionally omitted so suffix-style carriers such as
# RequestTaskProcessor still count as real processor entries.
$hasRealEntryBinding = (
    $targetSubsurface -match '(?i)(Facade(?:Impl)?|Controller(?:Impl)?|Service|Processor|Handler|Task|Route|Endpoint)\b' -or
    $targetSubsurface -match '\.java#\w+\(' -or
    $productionBoundary -match '(?i)(entry|service|process|handle|execute)\b'
)

$hasHelperOnlyBinding = (
    $targetSubsurface -match '(?i)\b(Util|Helper|DTO|Mapper|Dao|Repository|Constant|Enum|Config|Property)\b' -or
    $targetSubsurface -match '(?i)(helper[-_]only|dto[-_]only|static[-_]only|mapper[-_]only)' -or
    $proofKind -match '(?i)(static_contract|helper_only|dto_only|compile_only|file_presence_only)'
)

$hasSyntheticBinding = (
    $targetSubsurface -match '(?i)\b(Noop|Stub|Fake|Dummy|Placeholder|Mock|InMemory|TestOnly|Scaffold)\b' -or
    $proofKind -match '(?i)(mock_only|test_stub|synthetic)'
)

# Check if the slice only changed test files. Agents sometimes report production
# files in current_slice_changed_files or round_changed_files_snapshot instead of
# implemented_files, so use the effective union before falling back to git.
$testOnlyFiles = @($effectiveFiles | Where-Object { $_ -match '(^|/)src/test/|(^|\\)src\\test\\|Test\.java$' })
$hasProductionFiles = @($effectiveFiles | Where-Object { $_ -notmatch '(^|/)src/test/|(^|\\)src\\test\\|Test\.java$' }).Count -gt 0

# v555: Fallback to git status in worktree when SLICE_RESULT file lists are
# incomplete. Worktree status is authoritative for tracked and untracked files.
if (-not $hasProductionFiles -and (Test-Path -LiteralPath $worktreeFull -PathType Container)) {
    try {
        $statusLines = @(& git -C $worktreeFull status --short --untracked-files=all 2>$null)
        if ($LASTEXITCODE -eq 0 -and $statusLines.Count -gt 0) {
            $foundProduction = $false
            foreach ($line in $statusLines) {
                $text = ([string]$line).TrimEnd()
                if ([string]::IsNullOrWhiteSpace($text)) { continue }
                $pathText = ''
                if ($text -match '^(.{2})\s+(.+)$') {
                    $pathText = $matches[2].Trim()
                } else {
                    $pathText = $text.Trim()
                }
                if ($pathText -match '\s+->\s+(.+)$') {
                    $pathText = $matches[1].Trim()
                }
                if ($pathText -match '(^|/)src/main/' -and $pathText -notmatch '(?i)Test\.java$') {
                    $foundProduction = $true
                    break
                }
            }
            if ($foundProduction) {
                $hasProductionFiles = $true
                $warnings.Add('Production files detected via git-status fallback (not listed in SLICE_RESULT file fields)') | Out-Null
            }
        }
    } catch {
        # git-status fallback is best-effort; silent on failure.
    }
}

# Wrong test surface: closing family without testing real production entry
if (($closedFamilies.Count -gt 0 -or $touchedFamilies.Count -gt 0) -and
    $sliceStatus -eq 'DONE' -and
    -not $hasRealEntryBinding -and
    ($hasHelperOnlyBinding -or $hasSyntheticBinding)) {

    if ($gapFlags -notcontains 'wrong_test_surface') {
        $issues.Add('wrong_test_surface:helper_only_closure_claim') | Out-Null
    }
    $warnings.Add('Slice claims family closure but only tests helper/DTO/synthetic carriers') | Out-Null
}

# Wrong test surface: closing family with only test files, no production diff
if ($closedFamilies.Count -gt 0 -and -not $hasProductionFiles -and $testOnlyFiles.Count -gt 0) {
    if ($gapFlags -notcontains 'wrong_test_surface') {
        $issues.Add('wrong_test_surface:test_only_production_missing') | Out-Null
    }
    $warnings.Add('Slice claims family closure but implemented only test files, no production carrier') | Out-Null
}

# Wrong test surface: public entry claimed but helper-only carrier bound
$publicEntryPattern = '(?i)(Facade(?:Impl)?|Controller(?:Impl)?|Api|Endpoint|Route)\b'
$hasPublicEntryInTarget = $targetSubsurface -match $publicEntryPattern
$hasPublicEntryInBoundary = $productionBoundary -match $publicEntryPattern

if ($hasPublicEntryInTarget -or $hasPublicEntryInBoundary) {
    # Public entry is claimed - check if carrier is actually a public entry
    $carrierLooksLikePublicEntry = (
        $targetSubsurface -match '(Facade|Controller|Api|Endpoint|Route)\b' -or
        ($targetSubsurface -match '\.java#' -and $targetSubsurface -notmatch '(Util|Helper|DTO|Mapper|Dao|Repository)\.java#')
    )

    if (-not $carrierLooksLikePublicEntry -and ($hasHelperOnlyBinding -or $hasSyntheticBinding)) {
        if ($gapFlags -notcontains 'wrong_test_surface') {
            $issues.Add('wrong_test_surface:public_entry_mismatch') | Out-Null
        }
        $warnings.Add('Public entry family claimed but carrier is helper-only/synthetic') | Out-Null
    }
}

# ===== v281 VALIDATION 2: Side-Effect Executable Evidence Requirement =====

# For stateful_side_effect family, require executable evidence
$touchesStatefulFamily = $touchedFamilies -contains 'stateful_side_effect' -or $closedFamilies -contains 'stateful_side_effect'
$touchesCoreEntryFamily = $touchedFamilies -contains 'core_entry' -or $closedFamilies -contains 'core_entry'
$touchesLifecycleFamily = $touchedFamilies -contains 'lifecycle_cleanup_retention' -or $closedFamilies -contains 'lifecycle_cleanup_retention'

# Check if slice has side-effect ledger evidence
$hasStateChangeKeywords = $sideEffectText -match '(?i)(insert|update|delete|save|persist|commit|rollback|transaction|state|status|progress|log|task|complete|expire)'
$hasTransactionTest = $sideEffectText -match '(?i)(transaction|rollback|@Transactional|@Test|expected.*exception)'
$hasDbAssertion = $sideEffectText -match '(?i)(assert.*count|verify.*insert|verify.*update|assertEquals.*\d+)'

# Check test charter for business assertion
$hasBusinessAssertion = $testCharterText -match '(?i)(business assertion|state change|db.*state|verify.*insert|verify.*update|transaction.*rollback)'
$hasRedPhase = $sliceStatus -eq 'DONE' -or (@($slice.tests) -and (@($slice.tests | Where-Object { $_.phase -eq 'RED' }).Count -gt 0))

# Read test evidence for RED phase validation
$testEvidenceShowsStateChange = $false
$testEvidenceShowsDbOperation = $false
if ($null -ne $slice.tests) {
    foreach ($test in $slice.tests) {
        if ($test.phase -eq 'RED' -and $test.result -eq 'fail') {
            $evidence = [string]$test.evidence
            if ($evidence -match '(?i)(insert|update|delete|commit|transaction)') {
                $testEvidenceShowsDbOperation = $true
            }
            if ($evidence -match '(?i)(assert.*count|verify.*save|verify.*insert|assertEquals)') {
                $testEvidenceShowsStateChange = $true
            }
        }
    }
}

# Side-effect ledger gap: stateful family touched without executable state evidence
if ($touchesStatefulFamily -or $touchesLifecycleFamily) {
    $requiresExecutableEvidence = $true

    # Check if proof kind is static-only
    if ($proofKind -match '(?i)(static_contract|helper_only|dto_only|compile_only|file_presence_only)') {
        $issues.Add('side_effect_ledger_gap:static_proof_for_stateful_family') | Out-Null
        $warnings.Add('Stateful/side-effect family touched but proof_kind is static-only') | Out-Null
    }

    # Check if side-effect ledger is missing state keywords
    if (-not $hasStateChangeKeywords) {
        $issues.Add('side_effect_ledger_gap:missing_state_change_keywords') | Out-Null
        $warnings.Add('SIDE_EFFECT_LEDGER.md does not document state change (insert/update/delete/transaction)') | Out-Null
    }

    # Check if RED test validates business state change
    if ($hasRedPhase -and -not $testEvidenceShowsStateChange -and -not $hasBusinessAssertion) {
        $issues.Add('side_effect_ledger_gap:red_no_business_assertion') | Out-Null
        $warnings.Add('RED test exists but does not validate business state change') | Out-Null
    }

    # Check if only file-presence or compilation evidence
    if ($gapFlags -contains 'shallow_module' -or $targetSubsurface -match '(?i)(compile|file.*presence|exists)') {
        $issues.Add('side_effect_ledger_gap:file_presence_only') | Out-Null
        $warnings.Add('State change evidence is file-presence-only, not executable') | Out-Null
    }
}

# For core_entry family with stateful behavior, also require executable evidence
if ($touchesCoreEntryFamily -and $hasStateChangeKeywords) {
    # Core entry that has stateful side effects needs proper evidence
    if ($proofKind -match '(?i)(static_contract|compile_only)') {
        $issues.Add('side_effect_ledger_gap:static_proof_for_core_entry_with_state') | Out-Null
        $warnings.Add('Core entry with state change requires real_entry_behavior proof_kind, not static_contract') | Out-Null
    }
}

# ===== v303 VALIDATION: Executable Assertion Gate =====

$closedAssertions = @(Get-StringArray $slice.closed_assertions)
$sideEffectObj = $slice.side_effect_evidence
$sideEffectStatus = Get-StringValue $sideEffectObj 'status'
$sideEffectEntryCall = Get-StringValue $sideEffectObj 'entry_call'
$sideExpectedWrites = @(Get-StringArray $sideEffectObj.expected_writes_or_outputs)
$sideGreenResult = Get-StringValue $sideEffectObj 'green_result'
$sideRedResult = Get-StringValue $sideEffectObj 'red_result'
$testsEvidence = ''
if ($null -ne $slice.tests) {
    $testsEvidence = (@($slice.tests | ForEach-Object { "$($_.phase) $($_.result) $($_.evidence)" }) -join "`n")
}

$structuralAssertionPattern = '(?i)(class exists|method exists|annotation|method accepts|can be called|executes successfully|does not throw|no exception|constructor exists|field exists|compiles?)'
$meaningfulAssertionPattern = '(?i)(insert|update|delete|save|persist|status|state|progress|task|log|transaction|rollback|payload|request|response|return value|display|template|image|upload|download|export|message|queue|event|wire|db)'
$structuralOnlyAssertions = $closedAssertions.Count -gt 0 -and @($closedAssertions | Where-Object { $_ -notmatch $structuralAssertionPattern }).Count -eq 0
$hasMeaningfulClosedAssertion = @($closedAssertions | Where-Object { $_ -match $meaningfulAssertionPattern }).Count -gt 0
$hasMeaningfulSideEffectClosure = (
    $sideEffectStatus -match '(?i)CLOSED' -or
    ($sideGreenResult -match '(?i)(BUSINESS_ASSERTION_PASSED|STATE_ASSERTION_PASSED|DB_ASSERTION_PASSED|PAYLOAD_ASSERTION_PASSED)' ) -or
    ($testsEvidence -match $meaningfulAssertionPattern -and $testsEvidence -match '(?i)(assert|verify)')
)
$hasOnlyStructuralRed = $testsEvidence -match '(?i)(ClassNotFoundException|method does not exist|class does not exist|compilation failed)' -and $testsEvidence -notmatch $meaningfulAssertionPattern

if ($touchesCoreEntryFamily -and $sliceStatus -eq 'DONE') {
    if ($structuralOnlyAssertions -or (-not $hasMeaningfulClosedAssertion -and -not $hasMeaningfulSideEffectClosure)) {
        $issues.Add('shallow_module:core_entry_structural_only') | Out-Null
        $issues.Add('side_effect_ledger_gap:core_entry_no_executable_assertion') | Out-Null
        $warnings.Add('Core entry DONE used structural assertions only; executable behavior/state/output assertion is required') | Out-Null
    }
    if ($sideExpectedWrites.Count -gt 0 -and ($sideEffectStatus -match '(?i)^(READY|PARTIAL|TODO|PENDING)?$' -or [string]::IsNullOrWhiteSpace($sideEffectStatus)) -and -not $hasMeaningfulSideEffectClosure) {
        $issues.Add('side_effect_ledger_gap:expected_writes_not_closed') | Out-Null
        $warnings.Add('Core entry lists expected writes/outputs but side_effect_evidence is not CLOSED with executable assertions') | Out-Null
    }
    if ($hasOnlyStructuralRed) {
        $issues.Add('wrong_test_surface:structural_red_only') | Out-Null
        $warnings.Add('RED phase only proves missing class/method, not business behavior against the selected carrier') | Out-Null
    }
    if ($sideEffectEntryCall -match '(?i)(TODO|placeholder|none|null)' -or [string]::IsNullOrWhiteSpace($sideEffectEntryCall)) {
        $issues.Add('side_effect_ledger_gap:entry_call_missing') | Out-Null
    }
}

# ===== v555+v616 VALIDATION: Executable Evidence Capture =====
# Require machine-readable test commands for any success-shaped slice. The
# prompt contract says DONE, but older agents have emitted COMPLETED; treat both
# as authorizing claims so natural-language GREEN summaries cannot bypass this
# gate by using a synonym.
$successSliceStatus = @('DONE', 'COMPLETED') -contains $sliceStatus
$testExecCommand = Get-StringValue $slice 'test_execution_command'
$testExecExitCode = $slice.test_execution_exit_code
$testCompileCommand = Get-StringValue $slice 'test_compilation_command'
$testCompileExitCode = $slice.test_compilation_exit_code

if ($successSliceStatus) {
    $hasExecutableTestCommand = -not [string]::IsNullOrWhiteSpace($testExecCommand)
    $hasExecutableTestExitCode = ($null -ne $testExecExitCode -and $testExecExitCode -eq 0)

    # Some agents encode the executable target entirely in tests[].command.
    # v630: Also fall through when top-level test_execution_command exists but
    # test_execution_exit_code is missing — the tests[] fallback can supply a
    # machine-verifiable Maven test selector that implies exit code 0.
    if (-not $hasExecutableTestCommand -or -not $hasExecutableTestExitCode) {
        foreach ($test in @($slice.tests)) {
            if ($null -ne $test -and ($test -is [System.Management.Automation.PSCustomObject])) {
                $testCommand = [string]$test.command
                $testResult = [string]$test.result
                $testPhase = [string]$test.phase
                if (-not [string]::IsNullOrWhiteSpace($testCommand) -and
                    $testPhase -match '(?i)^(GREEN|VERIFY)$' -and
                    $testResult -match '(?i)^(pass|success)$') {
                    $hasExecutableTestCommand = $true
                    if ($testCommand -match '(?i)\bmvn(?:\.cmd)?\b' -and $testCommand -match '(?i)(?:^|\s)-D(?:it\.)?test\s*=') {
                        $hasExecutableTestExitCode = $true
                    }
                    break
                }
            }
        }
    }

    if (-not $hasExecutableTestCommand -or -not $hasExecutableTestExitCode) {
        $issues.Add('behavior_evidence_missing:no_executable_command_evidence') | Out-Null
        $warnings.Add('Success-shaped slice missing test_execution_command/exit_code; use machine-verifiable Maven commands instead of natural-language summaries') | Out-Null
    }
}

# ===== v281 VALIDATION 3: Feedback Loop Blocker Detection =====

# Detect if RED phase was blocked but implementation proceeded anyway
$redBlocked = $false
$redPassedBeforeImplementation = $false
$implementationAfterBlockedRed = $false

if ($null -ne $slice.tests) {
    foreach ($test in $slice.tests) {
        if ($test.phase -eq 'RED') {
            if ($test.result -eq 'blocked') {
                $redBlocked = $true
            }
            if ($test.result -eq 'pass') {
                $redPassedBeforeImplementation = $true
            }
        }
    }
}

# Check if implementation happened after blocked RED
if ($redBlocked -and $implementedFiles.Count -gt 0) {
    $issues.Add('feedback_loop_blocker:implementation_after_blocked_red') | Out-Null
    $warnings.Add('RED phase was BLOCKED but implementation proceeded - violates TDD') | Out-Null
    if ($gapFlags -notcontains 'feedback_loop_blocker') { $gapFlags += 'feedback_loop_blocker' }
}

# Check if implementation happened without failing RED
if ($redPassedBeforeImplementation -and $implementedFiles.Count -gt 0 -and -not $redBlocked) {
    $issues.Add('feedback_loop_blocker:red_passed_before_implementation') | Out-Null
    $warnings.Add('RED phase PASSED before implementation - invalid TDD workflow') | Out-Null
    if ($gapFlags -notcontains 'feedback_loop_blocker') { $gapFlags += 'feedback_loop_blocker' }
}

# v289: Test harness placement validation. claim-core has no test dependency
# harness in this repository; RED/VERIFY tests must be authored and executed
# through claim-server, without modifying POM dependencies.
$allChangedForHarness = @(
    $implementedFiles +
    (Get-StringArray $slice.current_slice_changed_files) +
    (Get-StringArray $slice.round_changed_files_snapshot)
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
if (@($allChangedForHarness | Where-Object { $_ -match '(?i)claim-core[/\\]src[/\\]test' }).Count -gt 0) {
    $issues.Add('wrong_test_surface:claim_core_test_harness') | Out-Null
    $warnings.Add('Tests were placed under claim-core/src/test even though this replay requires claim-server test harness') | Out-Null
}
foreach ($test in @($slice.tests)) {
    $commandText = [string]$test.command
    if ($commandText -match '(?i)-pl\s+claim-core\b') {
        $issues.Add('wrong_test_surface:claim_core_maven_module') | Out-Null
        $warnings.Add('RED/GREEN command used -pl claim-core; use -pl claim-server -am for replay tests') | Out-Null
    }
}
if (@($allChangedForHarness | Where-Object { $_ -match '(?i)(^|[/\\])pom\.xml$' }).Count -gt 0) {
    $issues.Add('unauthorized_test_dependency_change:pom_xml') | Out-Null
    $warnings.Add('Replay slice changed pom.xml; test dependencies must not be added to satisfy RED') | Out-Null
}

# ===== v340 Experiments Integration =====

$scriptDir = Split-Path -Parent $PSCommandPath
$v340ExperimentsEnabled = $false
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
}

# Check if v340 experiments should be enabled (knowledge version check)
$configPath = Join-Path (Split-Path $scriptDir -Parent) 'config.yaml'
if (Test-Path -LiteralPath $configPath) {
    $configContent = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    if ($configContent -match '(?im)^\s*knowledge_version\s*:\s*(v\d+)') {
        $knowledgeVersion = $matches[1]
        # Parse version number
        if ($knowledgeVersion -match 'v(\d+)') {
            $versionNum = [int]$matches[1]
            if ($versionNum -ge 340) {
                $v340ExperimentsEnabled = $true
            }
        }
    }
}

if ($v340ExperimentsEnabled -and $pythonCmd) {
    Write-Host "v340 experiments enabled - running enhanced validation..."

    # E1: Executable Evidence Gate (enhanced)
    $e1Script = Join-Path $scriptDir 'verifier\executable_evidence.py'
    $requirementLedgerPath = Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json'

    if ((Test-Path -LiteralPath $e1Script) -and (Test-Path -LiteralPath $requirementLedgerPath)) {
        try {
            $sliceResultJson = Get-Content -LiteralPath $sliceResultPath -Raw -Encoding UTF8
            $ledgerJson = Get-Content -LiteralPath $requirementLedgerPath -Raw -Encoding UTF8

            # Create temp files for Python script input
            $tempSlicePath = [System.IO.Path]::GetTempFileName()
            $tempLedgerPath = [System.IO.Path]::GetTempFileName()
            $sliceResultJson | Set-Content -LiteralPath $tempSlicePath -Encoding UTF8
            $ledgerJson | Set-Content -LiteralPath $tempLedgerPath -Encoding UTF8

            $e1ResultJson = & $pythonCmd.Path $e1Script validate $tempSlicePath $tempLedgerPath 2>&1
            Remove-Item -LiteralPath $tempSlicePath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempLedgerPath -Force -ErrorAction SilentlyContinue

            if ($LASTEXITCODE -eq 0) {
                $e1Result = $e1ResultJson | ConvertFrom-Json
                if (-not $e1Result.valid) {
                    $issues.Add("v340_e1:$($e1Result.reason)") | Out-Null
                    $warnings.Add("v340 E1 failed: $($e1Result.message)") | Out-Null
                }
            }
        } catch {
            Write-Warning "v340 E1 validation error: $_"
        }
    }

    # E2: TODO Penalty Enforcement
    $e2Script = Join-Path $scriptDir 'coverage\calculate_coverage.py'
    if (Test-Path -LiteralPath $e2Script) {
        try {
            $sliceResultJson = Get-Content -LiteralPath $sliceResultPath -Raw -Encoding UTF8

            $tempSlicePath = [System.IO.Path]::GetTempFileName()
            $sliceResultJson | Set-Content -LiteralPath $tempSlicePath -Encoding UTF8

            # Use a base coverage of 100% for penalty calculation (will be adjusted later)
            $e2ResultJson = & $pythonCmd.Path $e2Script todo-penalty $tempSlicePath 100 $worktreeFull 2>&1
            Remove-Item -LiteralPath $tempSlicePath -Force -ErrorAction SilentlyContinue

            if ($LASTEXITCODE -eq 0) {
                $e2Result = $e2ResultJson | ConvertFrom-Json
                if ($e2Result.total_markers -gt 0) {
                    $warnings.Add("v340 E2: Found $($e2Result.total_markers) TODO/STUB markers (penalty: $($e2Result.penalty)%)") | Out-Null
                    # Add gap flag if too many markers
                    if ($e2Result.total_markers -gt 2) {
                        $issues.Add("v340_e2:excessive_todo_markers:$($e2Result.total_markers)") | Out-Null
                    }
                }
            }
        } catch {
            Write-Warning "v340 E2 validation error: $_"
        }
    }

    Write-Host "v340 experiments validation complete"
}

# ===== Build Result =====

$result = [ordered]@{
    stage = 'executable_evidence_gate'
    replay_root = $replayRootFull
    slice_index = $SliceIndex
    slice_result = $sliceResultPath
    validation_status = if ($issues.Count -gt 0) { 'FAIL' } else { 'PASS' }
    issues = @($issues | Select-Object -Unique)
    warnings = @($warnings | Select-Object -Unique)
    touched_families = @($touchedFamilies)
    closed_families = @($closedFamilies)
    has_real_entry_binding = $hasRealEntryBinding
    has_helper_only_binding = $hasHelperOnlyBinding
    has_synthetic_binding = $hasSyntheticBinding
    has_production_files = $hasProductionFiles
    touches_stateful_family = $touchesStatefulFamily
    has_state_change_evidence = $hasStateChangeKeywords -or $testEvidenceShowsStateChange
    red_was_blocked = $redBlocked
    implementation_after_blocked_red = $redBlocked -and $implementedFiles.Count -gt 0
    generated_at = (Get-Date).ToString('s')
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding UTF8

if ($issues.Count -gt 0) {
    exit 1
}

exit 0
