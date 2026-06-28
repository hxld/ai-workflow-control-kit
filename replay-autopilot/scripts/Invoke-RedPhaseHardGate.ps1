# Invoke-RedPhaseHardGate.ps1
# FATAL RED phase enforcement gate.

param(
    [Parameter(Mandatory = $false)]
    [string]$Worktree,

    [Parameter(Mandatory = $false)]
    [string]$TestClass,

    [Parameter(Mandatory = $false)]
    [string]$ReplayRoot,

    [Parameter(Mandatory = $false)]
    [string]$MavenSettings,

    [Parameter(Mandatory = $false)]
    [string]$SliceResultPath,

    [Parameter(Mandatory = $false)]
    [int]$SliceIndex = 0,

    [switch]$WhatIf,

    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'

function Get-StringArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @($Value)
    }
    return @($Value)
}

function New-GateIssue {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    return [pscustomobject]@{ code = $Code; message = $Message }
}

function Read-JsonIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-GreenOnlyVerifierAuthorization {
    param(
        [string]$ReplayRootPath,
        [int]$Index
    )

    if ([string]::IsNullOrWhiteSpace($ReplayRootPath) -or $Index -le 0) {
        return $false
    }
    $verify = Read-JsonIfExists -Path (Join-Path $ReplayRootPath ('SLICE_VERIFY_{0:D2}.json' -f $Index))
    if ($null -eq $verify) { return $false }
    if ([string]$verify.verification_status -ne 'PASS') { return $false }
    if (-not [bool]$verify.authorized_for_synthesis) { return $false }

    $greenOnlyAccepted = $false
    if ($verify.PSObject.Properties.Name -contains 'verifier_adjustments_applied' -and $null -ne $verify.verifier_adjustments_applied) {
        if ($verify.verifier_adjustments_applied.PSObject.Properties.Name -contains 'green_only_evidence_accepted') {
            $greenOnlyAccepted = [bool]$verify.verifier_adjustments_applied.green_only_evidence_accepted
        }
    }
    if ((@($verify.warnings) -join ' ') -match 'green_only_evidence_accepted') {
        $greenOnlyAccepted = $true
    }

    $featureClassification = if ($verify.PSObject.Properties.Name -contains 'feature_classification') {
        [string]$verify.feature_classification
    } else {
        ''
    }

    return ($greenOnlyAccepted -and $featureClassification -eq 'narrow_backend_read_only_fix')
}

function Test-BehavioralTestCharter {
    <#
    .SYNOPSIS
    Validates that RED test contains behavioral assertions, not structural checks

    .DESCRIPTION
    Returns $false if test is structural-only (reflection, existence checks)
    Returns $true if test contains behavioral assertions (DB writes, state changes)
    #>
    param(
        [string]$TestFilePath,
        [string]$TestContent
    )

    # Structural assertion patterns (forbidden as primary test)
    $structuralPatterns = @(
        "assertFalse\(.+\.isInterface\(\)",
        "assertTrue\(.+\.hasMethod\(",
        "assertNotNull\(.+\.getDeclaredMethod\(",
        "Method\.exists\(",
        "Class\.forName\(",
        "clazz\.isInterface\(\)",
        "clazz\.hasMethod\("
    )

    # Behavioral assertion patterns (required) - EXPERIMENT_3 (v339): Expanded patterns
    $behavioralPatterns = @(
        "verify\(.+Mapper\).insert",
        "verify\(.+Mapper\).update",
        "verify\(.+Mapper\).delete",
        "verify\(.+Service\).update",
        "verify\(.+Service\).insert",
        "assertEquals\(.+status",
        "assertEquals\(.+Status\.",
        "assertThat\(.+greaterThan",
        "assertThat\(.+lessThan",
        "argThat\(.+->",
        # DB/state assertions
        "assertEquals\(.+,.+expected",
        "assertSame\(.+,",
        "assertNull\(.+\)",
        "assertNotNull\(.+\)",
        # assertTrue with condition (not literal true)
        "assertTrue\(.+.*\w+.*\)"
    )

    # EXPERIMENT_3 (v339): Exclude assertTrue(true) literal
    $literalTruePattern = "assertTrue\(true\)"

    $structuralCount = 0
    $behavioralCount = 0

    foreach ($pattern in $structuralPatterns) {
        $structuralCount += ([regex]::Matches($TestContent, $pattern)).Count
    }

    foreach ($pattern in $behavioralPatterns) {
        $behavioralCount += ([regex]::Matches($TestContent, $pattern)).Count
    }

    # Subtract assertTrue(true) from behavioral count
    $literalTrueCount = ([regex]::Matches($TestContent, $literalTruePattern)).Count
    $behavioralCount = [Math]::Max(0, $behavioralCount - $literalTrueCount)

    # EXPERIMENT_3 (v339): Minimum assertion count threshold
    $minAssertions = 3
    if ($behavioralCount -lt $minAssertions) {
        Write-Warning "Insufficient business assertions: found=$behavioralCount, required=$minAssertions"
        return @{
            IsValid = $false
            BehavioralRatio = 0
            Reason = "insufficient_business_assertions"
            StructuralCount = $structuralCount
            BehavioralCount = $behavioralCount
            RequiredAssertionCount = $minAssertions
        }
    }

    # Calculate ratio
    $totalAssertions = $structuralCount + $behavioralCount
    if ($totalAssertions -eq 0) {
        Write-Warning "No assertions found in test"
        return @{
            IsValid = $false
            BehavioralRatio = 0
            Reason = "no_assertions"
            StructuralCount = $structuralCount
            BehavioralCount = $behavioralCount
            RequiredAssertionCount = $minAssertions
        }
    }

    $behavioralRatio = $behavioralCount / $totalAssertions

    # Require behavioral assertions to be at least 50% of total
    if ($behavioralRatio -lt 0.5) {
        Write-Warning "Test is structural-only: behavioral_ratio=$behavioralRatio"
        return @{
            IsValid = $false
            BehavioralRatio = $behavioralRatio
            Reason = "structural_only_test"
            StructuralCount = $structuralCount
            BehavioralCount = $behavioralCount
            RequiredAssertionCount = $minAssertions
        }
    }

    Write-Host "Test charter valid: behavioral_ratio=$behavioralRatio, assertions=$behavioralCount"
    return @{
        IsValid = $true
        BehavioralRatio = $behavioralRatio
        Reason = "valid"
        StructuralCount = $structuralCount
        BehavioralCount = $behavioralCount
        RequiredAssertionCount = $minAssertions
    }
}

function Write-GateResult {
    param(
        [Parameter(Mandatory = $true)][object]$GateResult,
        [Parameter(Mandatory = $true)][string]$ReplayRootPath,
        [Parameter(Mandatory = $true)][int]$Index
    )
    $gatePath = if (-not [string]::IsNullOrWhiteSpace($ReplayRootPath)) {
        Join-Path $ReplayRootPath ('RED_PHASE_GATE_{0:D2}.json' -f $Index)
    } else {
        Join-Path (Get-Location) ('RED_PHASE_GATE_{0:D2}.json' -f $Index)
    }
    $GateResult | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $gatePath -Encoding UTF8
    Write-Host "Gate result written to: $gatePath"
    return $gatePath
}

function Exit-Gate {
    param(
        [Parameter(Mandatory = $true)][object]$GateResult,
        [Parameter(Mandatory = $true)][int]$ExitCode
    )
    [void](Write-GateResult -GateResult $GateResult -ReplayRootPath $ReplayRoot -Index $SliceIndex)
    if ($WhatIf) {
        Write-Host "[WhatIf] Would exit with code $ExitCode"
        return
    }
    exit $ExitCode
}

function Normalize-Result {
    param([object]$Value)
    return (([string]$Value).Trim().ToLowerInvariant())
}

function Test-CompileOnlyRedEvidence {
    param($Test)

    $text = @(
        [string]$Test.command,
        [string]$Test.result,
        [string]$Test.evidence
    ) -join "`n"
    return $text -match '(?i)\btest-compile\b|compile[ds]?\s+success|compilation\s+completed|test\s+class\s+compiled'
}

function Test-BusinessRedEvidence {
    param($Test)

    $text = @(
        [string]$Test.command,
        [string]$Test.result,
        [string]$Test.evidence
    ) -join "`n"
    return $text -match '(?i)\bfail(?:ed|ure|ures)?\b|missing|would\s+return\s+null|business\s+assertion|source-chain\s+assignment|assert(?:ion)?'
}

function Test-ClearRedFailureResult {
    param($Test)

    $result = Normalize-Result $Test.result
    if ([string]::IsNullOrWhiteSpace($result)) { return $false }
    if ($result -match 'pass|success|block|compile|error|inconclusive') { return $false }
    return $result -match 'fail|failure|failed|assert'
}

function Test-PassWithBusinessRedEvidence {
    param($Test)

    $result = Normalize-Result $Test.result
    if ($result -notmatch 'pass|success') { return $false }
    return (Test-BusinessRedEvidence -Test $Test)
}

function Select-AuthoritativeRedPhaseTest {
    param([object[]]$Tests)

    $redTests = @($Tests | Where-Object { ([string]$_.phase).Trim().ToUpperInvariant() -eq 'RED' })
    if ($redTests.Count -eq 0) { return $null }

    $assertionRedTests = @($redTests | Where-Object { -not (Test-CompileOnlyRedEvidence -Test $_) })
    if ($assertionRedTests.Count -eq 0) {
        $assertionRedTests = @($redTests)
    }

    $clearBusinessFailures = @($assertionRedTests | Where-Object {
        (Test-ClearRedFailureResult -Test $_) -and (Test-BusinessRedEvidence -Test $_)
    })
    if ($clearBusinessFailures.Count -gt 0) {
        return ($clearBusinessFailures | Select-Object -First 1)
    }

    $clearFailures = @($assertionRedTests | Where-Object { Test-ClearRedFailureResult -Test $_ })
    if ($clearFailures.Count -gt 0) {
        return ($clearFailures | Select-Object -First 1)
    }

    $businessPasses = @($assertionRedTests | Where-Object { Test-PassWithBusinessRedEvidence -Test $_ })
    if ($businessPasses.Count -gt 0) {
        return ($businessPasses | Select-Object -First 1)
    }

    $businessLikeRedTests = @($assertionRedTests | Where-Object { Test-BusinessRedEvidence -Test $_ })
    if ($businessLikeRedTests.Count -gt 0) {
        return ($businessLikeRedTests | Select-Object -First 1)
    }

    return ($assertionRedTests | Select-Object -First 1)
}

Write-Host "=== RED_PHASE_HARD_GATE ==="

if ($VerifyOnly) {
    if ([string]::IsNullOrWhiteSpace($SliceResultPath) -or -not (Test-Path -LiteralPath $SliceResultPath)) {
        $result = [ordered]@{
            gate = 'red_phase_hard_gate'
            mode = 'verify_only'
            slice_index = $SliceIndex
            can_proceed = $false
            block_green = $true
            reason = 'slice_result_missing'
            issues = @(New-GateIssue -Code 'slice_result_missing' -Message "Slice result not found: $SliceResultPath")
            warnings = @()
            verified_at = (Get-Date).ToString('s')
        }
        Write-Host 'RED_PHASE_HARD_GATE: FATAL'
        Exit-Gate -GateResult $result -ExitCode 1
    }

    Write-Host "VerifyOnly mode; reading slice result: $SliceResultPath"
    $sliceResult = Get-Content -LiteralPath $SliceResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $implementedFiles = @(Get-StringArray $sliceResult.implemented_files)
    $changedFiles = @(Get-StringArray $sliceResult.current_slice_changed_files)
    if ($changedFiles.Count -eq 0) { $changedFiles = @(Get-StringArray $sliceResult.changed_files) }
    $tests = @($sliceResult.tests)
    $redTests = @($tests | Where-Object { ([string]$_.phase).Trim().ToUpperInvariant() -eq 'RED' })
    $redPhaseTest = Select-AuthoritativeRedPhaseTest -Tests $tests
    $greenPhaseTest = $tests | Where-Object { ([string]$_.phase).Trim().ToUpperInvariant() -eq 'GREEN' } | Select-Object -First 1

    $result = [ordered]@{
        gate = 'red_phase_hard_gate'
        mode = 'verify_only'
        slice_index = $SliceIndex
        can_proceed = $true
        block_green = $false
        reason = 'red_phase_verified'
        issues = @()
        warnings = @()
        selected_red_command = if ($null -ne $redPhaseTest) { [string]$redPhaseTest.command } else { '' }
        selected_red_result = if ($null -ne $redPhaseTest) { [string]$redPhaseTest.result } else { '' }
        implemented_files = @($implementedFiles)
        changed_files = @($changedFiles)
        slice_result_path = $SliceResultPath
        verified_at = (Get-Date).ToString('s')
    }

    if ($tests.Count -eq 0) {
        $result.can_proceed = $false
        $result.block_green = $true
        $result.reason = 'red_phase_missing'
        $result.issues += @(New-GateIssue -Code 'red_phase_missing' -Message 'No tests found in slice result.')
    } elseif ($null -eq $redPhaseTest) {
        $result.can_proceed = $false
        $result.block_green = $true
        $result.reason = 'red_phase_missing'
        $result.issues += @(New-GateIssue -Code 'red_phase_missing' -Message 'No RED phase test entry found in slice result.')
    } elseif ($redTests.Count -gt 1 -and -not (Test-CompileOnlyRedEvidence -Test $redPhaseTest)) {
        $result.warnings += @("selected_authoritative_red_phase:$([string]$redPhaseTest.command)")
    }

    # Behavioral test charter validation (v334)
    if ($result.can_proceed -and $null -ne $redPhaseTest) {
        $testClass = $redPhaseTest.test_class
        if ([string]::IsNullOrWhiteSpace($testClass)) {
            # Try to derive test class from test name
            $testClass = $redPhaseTest.test_name -replace '\.java$', ''
        }

        if (-not [string]::IsNullOrWhiteSpace($testClass)) {
            # Search for test file in worktree or replay root
            $testFilePath = $null
            $searchPaths = @($Worktree, $ReplayRoot)

            foreach ($searchPath in $searchPaths) {
                if (-not [string]::IsNullOrWhiteSpace($searchPath)) {
                    $found = Get-ChildItem -LiteralPath $searchPath -Recurse -Filter "$testClass.java" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) {
                        $testFilePath = $found.FullName
                        break
                    }
                }
            }

            if ($testFilePath -and (Test-Path -LiteralPath $testFilePath)) {
                $testContent = Get-Content -LiteralPath $testFilePath -Raw -Encoding UTF8

                # Run behavioral charter validation
                $charterValidation = Test-BehavioralTestCharter -TestFilePath $testFilePath -TestContent $testContent

                # Add validation metrics to result (EXPERIMENT_3 v339)
                $result.behavioral_ratio = $charterValidation.BehavioralRatio
                $result.structural_count = $charterValidation.StructuralCount
                $result.behavioral_count = $charterValidation.BehavioralCount
                $result.required_assertion_count = if ($null -ne $charterValidation.RequiredAssertionCount) { $charterValidation.RequiredAssertionCount } else { 3 }

                if (-not $charterValidation.IsValid) {
                    $result.can_proceed = $false
                    $result.block_green = $true
                    if ($result.reason -eq 'red_phase_verified') {
                        $result.reason = $charterValidation.Reason
                    }
                    # EXPERIMENT_3 (v339): Enhanced assertion threshold error message
                    if ($charterValidation.Reason -eq 'insufficient_business_assertions') {
                        $result.issues += @(New-GateIssue -Code $charterValidation.Reason -Message "Test charter validation failed: found=$($charterValidation.BehavioralCount) assertions, required=$($charterValidation.RequiredAssertionCount)")
                    } else {
                        $result.issues += @(New-GateIssue -Code $charterValidation.Reason -Message "Test charter validation failed: behavioral_ratio=$($charterValidation.BehavioralRatio), required_ratio=0.5, assertions=$($charterValidation.BehavioralCount)")
                    }
                }
            }
        }
    }

    if ($result.can_proceed) {
        $redResult = Normalize-Result $redPhaseTest.result
        $redEvidence = [string]$redPhaseTest.evidence
        if ($redResult -match 'pass|success') {
            if (Test-BusinessRedEvidence -Test $redPhaseTest) {
                $result.warnings += @('red_phase_result_pass_with_business_failure_evidence')
            } else {
                $result.can_proceed = $false
                $result.block_green = $true
                $result.reason = 'red_phase_passed_before_fix'
                $result.issues += @(New-GateIssue -Code 'red_phase_passed_before_fix' -Message 'RED phase passed before implementation; this is structural or non-behavioral evidence.')
            }
        } elseif ($redResult -match 'block|compile|error|inconclusive') {
            $result.can_proceed = $false
            $result.block_green = $true
            $result.reason = 'red_phase_blocked'
            $result.issues += @(New-GateIssue -Code 'red_phase_blocked' -Message "RED phase was blocked or inconclusive: $redResult")
        } elseif ($redResult -notmatch 'fail|failure|failed|assert') {
            $result.can_proceed = $false
            $result.block_green = $true
            $result.reason = 'red_phase_result_unclear'
            $result.issues += @(New-GateIssue -Code 'red_phase_result_unclear' -Message "RED phase result is not a clear failure: $redResult")
        }

        if ($redEvidence -match 'class does(n''t| not) exist|method does(n''t| not) exist|not found as expected|ClassNotFoundException as expected') {
            $result.can_proceed = $false
            $result.block_green = $true
            $result.reason = 'structural_red_evidence'
            $result.issues += @(New-GateIssue -Code 'structural_red_evidence' -Message 'RED evidence proves structure/class existence instead of business behavior.')
        }
    }

    if ($implementedFiles.Count -eq 0) {
        $result.can_proceed = $false
        $result.block_green = $true
        if ($result.reason -eq 'red_phase_verified') { $result.reason = 'no_green_implementation' }
        $result.issues += @(New-GateIssue -Code 'no_green_implementation' -Message 'No production implementation files were reported after RED.')
    }

    if ($implementedFiles.Count -gt 0 -and $null -eq $greenPhaseTest) {
        $result.can_proceed = $false
        $result.block_green = $true
        if ($result.reason -eq 'red_phase_verified') { $result.reason = 'green_phase_missing' }
        $result.issues += @(New-GateIssue -Code 'green_phase_missing' -Message 'Implementation files exist but no GREEN phase test entry was recorded.')
    }

    if (-not [bool]$result.can_proceed -and (Test-GreenOnlyVerifierAuthorization -ReplayRootPath $ReplayRoot -Index $SliceIndex)) {
        $remainingIssues = @($result.issues | Where-Object {
            [string]$_.code -notin @('red_phase_missing', 'green_phase_missing')
        })
        if ($remainingIssues.Count -ne @($result.issues).Count) {
            $result.issues = @($remainingIssues)
            $result.warnings += @('green_only_verifier_authorized_missing_red_green_phase_entries')
            if ($remainingIssues.Count -eq 0) {
                $result.can_proceed = $true
                $result.block_green = $false
                $result.reason = 'verifier_authorized_green_only_read_only_slice'
            }
        }
    }

    if (-not [bool]$result.can_proceed) {
        Write-Host "RED_PHASE_HARD_GATE: VIOLATED"
        Exit-Gate -GateResult $result -ExitCode 1
    }

    Write-Host "RED_PHASE_HARD_GATE: PASSED"
    Exit-Gate -GateResult $result -ExitCode 0
}

if ([string]::IsNullOrWhiteSpace($Worktree) -or -not (Test-Path -LiteralPath (Join-Path $Worktree 'pom.xml'))) {
    throw "Worktree with pom.xml is required in execute mode. Worktree='$Worktree'"
}
if ([string]::IsNullOrWhiteSpace($MavenSettings) -or -not (Test-Path -LiteralPath $MavenSettings)) {
    throw "Maven settings file is required in execute mode. MavenSettings='$MavenSettings'"
}
if ([string]::IsNullOrWhiteSpace($ReplayRoot)) {
    throw 'ReplayRoot is required in execute mode.'
}
if ([string]::IsNullOrWhiteSpace($TestClass)) {
    throw 'TestClass is required in execute mode.'
}

# EXPERIMENT_1 (v352): Pre-flight test infrastructure validation
# Step 1a: Test file existence check (fast-fail before expensive Maven)
Write-Host 'Step 1a: Pre-flight test file existence check...'
$testFileName = "$TestClass.java"
$testFilePath = $null

# Search in standard test locations
$searchPaths = @(
    (Join-Path $Worktree "claim-server\src\test\java\com\huize\claim\core\ai\service"),
    (Join-Path $Worktree "claim-server\src\test\java\com\huize\claim\core\service"),
    (Join-Path $Worktree "claim-server\src\test\java")
)

foreach ($path in $searchPaths) {
    $candidate = Join-Path $path $testFileName
    if (Test-Path -LiteralPath $candidate) {
        $testFilePath = $candidate
        break
    }
}

if ([string]::IsNullOrWhiteSpace($testFilePath)) {
    Write-Host "PRE_FLIGHT_BLOCKER: Test class does not exist at $testFileName"
    Write-Host "RED_PHASE_HARD_GATE: FATAL"
    exit 1
}
Write-Host "Test file found: $testFilePath"

# Step 1b: Pre-flight dependency compilation. This is the pre-flight build check.
# If this fails, the entire slice is INVALID.
# FORBIDDEN: DO NOT write implementation while RED is blocked by compilation.
Write-Host 'Step 1b: Pre-flight dependency compilation...'
$preflightArgs = @(
    '-s', $MavenSettings,
    '-f', (Join-Path $Worktree 'pom.xml'),
    'clean', 'install',
    '-pl', 'claim-domain,claim-api,claim-common',
    '-DskipTests',
    '-q'
)
& mvn @preflightArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host 'PRE_FLIGHT_BLOCKER: Maven dependency compilation failed'
    Write-Host 'RED_PHASE_HARD_GATE: FATAL'
    exit 1
}

# EXPERIMENT_3 (v352): Behavioral assertion pre-validation before RED phase
Write-Host 'Step 1c: Behavioral assertion pre-validation...'
$testContent = Get-Content -LiteralPath $testFilePath -Raw -Encoding UTF8
$charterValidation = Test-BehavioralTestCharter -TestFilePath $testFilePath -TestContent $testContent

if (-not $charterValidation.IsValid) {
    Write-Host "BEHAVIORAL_ASSERTION_FAIL: $($charterValidation.Reason)"
    Write-Host "  Behavioral assertions found: $($charterValidation.BehavioralCount)"
    Write-Host "  Required minimum: $($charterValidation.RequiredAssertionCount)"
    if ($charterValidation.BehavioralRatio -gt 0) {
        Write-Host "  Behavioral ratio: $($charterValidation.BehavioralRatio.ToString('P2'))"
    }
    Write-Host 'RED_PHASE_HARD_GATE: FATAL'
    exit 1
}
Write-Host "Behavioral charter valid: $($charterValidation.BehavioralCount) assertions"

Write-Host 'Step 2: Running RED phase test...'
$redOutputFile = Join-Path $ReplayRoot 'red_phase_result.txt'
$redArgs = @(
    '-s', $MavenSettings,
    '-f', (Join-Path $Worktree 'pom.xml'),
    'test',
    '-pl', 'claim-server',
    '-am',
    "-Dtest=$TestClass",
    '-Dsurefire.failIfNoSpecifiedTests=false'
)
& mvn @redArgs *> $redOutputFile
$redExitCode = $LASTEXITCODE
$redOutput = Get-Content -LiteralPath $redOutputFile -Raw -Encoding UTF8

if ($redOutput -match 'COMPILATION ERROR' -or $redOutput -match 'cannot find symbol') {
    Write-Host 'RED_PHASE_HARD_GATE: FATAL'
    exit 1
}

if ($redExitCode -eq 0 -and $redOutput -match 'BUILD SUCCESS') {
    Write-Host 'RED_PHASE_HARD_GATE: VIOLATED'
    exit 1
}

if ($redExitCode -ne 0 -and $redOutput -match 'BUILD FAILURE' -and $redOutput -match 'Failures: [1-9]') {
    Write-Host 'RED_PHASE_HARD_GATE: PASSED'
    exit 0
}

Write-Host 'RED_PHASE_HARD_GATE: INCONCLUSIVE'
exit 1
