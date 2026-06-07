param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\oracle-fail-closed-test')
)

$ErrorActionPreference = 'Stop'
$passCount = 0
$failCount = 0
$testResults = New-Object System.Collections.Generic.List[object]
$utf8 = [System.Text.Encoding]::UTF8

function Write-TestResult {
    param([string]$Name, [bool]$Pass, [string]$Detail = '')
    $script:passCount += [int]$Pass
    $script:failCount += [int](-not $Pass)
    $status = if ($Pass) { 'PASS' } else { 'FAIL' }
    $line = "[$status] $Name"
    if (-not [string]::IsNullOrWhiteSpace($Detail)) { $line += " - $Detail" }
    Write-Host $line
    $script:testResults.Add([ordered]@{ name = $Name; pass = $Pass; detail = $Detail })
}

function New-MinimalPlanReplayRoot {
    param([string]$Root)
    if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    New-Item -ItemType Directory -Path $Root -Force | Out-Null

    # Minimal PLAN_RESULT.md with PROCEED status and required fields
    $planResult = @"
# Plan Result

- plan_status: PROCEED
- first_slice: ClaimService
- first_red_test: testClaimCreation
- selected_strategy: top_down
- oracle_production_file_overlap: 80%
"@
    Set-Content -LiteralPath (Join-Path $Root 'PLAN_RESULT.md') -Value $planResult -Encoding UTF8

    # Minimal files to avoid missing_file issues crowding out oracle issues
    $planFiles = @(
        'PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md',
        'PLAN_SELECTION.md', 'REPLAY_PLAN.md', 'IMPLEMENTATION_CONTRACT.md',
        'EXPECTED_DIFF_MATRIX.md', 'SIDE_EFFECT_LEDGER.md', 'TEST_CHARTER.md',
        'FIRST_SLICE_PROOF_PLAN.md'
    )
    foreach ($f in $planFiles) {
        Set-Content -LiteralPath (Join-Path $Root $f) -Value "# $f" -Encoding UTF8
    }

    # Minimal FAMILY_CONTRACT.json
    $familyContract = @{
        selected_real_entry = 'ClaimService'
        first_executable_slice = 'S1'
        families = @(
            @{ id = 'core_entry'; required = $true; proof_required = @('entry exists') }
            @{ id = 'stateful_side_effect'; required = $true; proof_required = @('side effect') }
            @{ id = 'deploy_export_page'; required = $true; proof_required = @('deploy') }
            @{ id = 'wire_payload_api_contract'; required = $true; proof_required = @('api') }
            @{ id = 'config_policy_threshold'; required = $true; proof_required = @('config') }
            @{ id = 'generated_artifact_template_upload'; required = $true; proof_required = @('artifact') }
            @{ id = 'external_integration'; required = $true; proof_required = @('external') }
            @{ id = 'automation_test_interface'; required = $true; proof_required = @('test') }
            @{ id = 'lifecycle_cleanup_retention'; required = $true; proof_required = @('lifecycle') }
        )
    } | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath (Join-Path $Root 'FAMILY_CONTRACT.json') -Value $familyContract -Encoding UTF8
}

function New-ValidOracleAnalysis {
    param([string]$Root)
    $oracle = @{
        schema_version = '1.0'
        files = @(
            @{ path = 'src/main/java/com/example/ClaimService.java'; layer = 'Service'; weight = 'HIGH'; is_production = $true }
            @{ path = 'src/main/java/com/example/ClaimController.java'; layer = 'Controller'; weight = 'HIGH'; is_production = $true }
            @{ path = 'src/main/java/com/example/ClaimMapper.java'; layer = 'Mapper'; weight = 'MEDIUM'; is_production = $true }
            @{ path = 'src/test/java/com/example/ClaimServiceTest.java'; layer = 'Test'; weight = 'LOW'; is_production = $false }
        )
        layer_summary = @{ Service = 1; Controller = 1; Mapper = 1; Test = 1 }
        production_files = @('src/main/java/com/example/ClaimService.java', 'src/main/java/com/example/ClaimController.java', 'src/main/java/com/example/ClaimMapper.java')
    } | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') -Value $oracle -Encoding UTF8
}

function Invoke-PlanVerify {
    param([string]$Root)
    $verifyScript = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ReplayRoot $Root -Stage 'Plan' 2>&1
    $outputText = $result | Out-String
    $verifyJsonPath = Join-Path $Root 'PLAN_CONTRACT_VERIFY.json'
    if (Test-Path -LiteralPath $verifyJsonPath) {
        $verifyJson = Get-Content -LiteralPath $verifyJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return $verifyJson
    }
    return $null
}

Write-Host '=== Oracle Fail-Closed Behavioral Tests ==='
Write-Host ''

# -------------------------------------------------------
# Test 1: Missing ORACLE_DIFF_ANALYSIS.json -> FAIL
# -------------------------------------------------------
$root1 = Join-Path $TestRoot 'missing-oracle'
New-MinimalPlanReplayRoot -Root $root1
# No ORACLE_DIFF_ANALYSIS.json created
$verify1 = Invoke-PlanVerify -Root $root1
$hasOracleMissing = $false
if ($null -ne $verify1 -and $null -ne $verify1.issues) {
    $hasOracleMissing = @($verify1.issues | Where-Object { $_ -eq 'oracle_analysis_missing' }).Count -gt 0
}
$statusIsFail = ($null -ne $verify1 -and [string]$verify1.verification_status -eq 'FAIL')
Write-TestResult 'Missing ORACLE_DIFF_ANALYSIS.json -> has oracle_analysis_missing issue' $hasOracleMissing
Write-TestResult 'Missing ORACLE_DIFF_ANALYSIS.json -> verification_status is FAIL' $statusIsFail

# -------------------------------------------------------
# Test 2: Invalid JSON in ORACLE_DIFF_ANALYSIS.json -> FAIL
# -------------------------------------------------------
$root2 = Join-Path $TestRoot 'invalid-json'
New-MinimalPlanReplayRoot -Root $root2
Set-Content -LiteralPath (Join-Path $root2 'ORACLE_DIFF_ANALYSIS.json') -Value '{{invalid json!!!' -Encoding UTF8
$verify2 = Invoke-PlanVerify -Root $root2
$hasOracleInvalid = $false
if ($null -ne $verify2 -and $null -ne $verify2.issues) {
    $hasOracleInvalid = @($verify2.issues | Where-Object { $_ -like 'oracle_analysis_invalid:*' }).Count -gt 0
}
$statusIsFail2 = ($null -ne $verify2 -and [string]$verify2.verification_status -eq 'FAIL')
Write-TestResult 'Invalid JSON -> has oracle_analysis_invalid issue' $hasOracleInvalid
Write-TestResult 'Invalid JSON -> verification_status is FAIL' $statusIsFail2

# -------------------------------------------------------
# Test 3: Valid JSON but no "files" property -> FAIL
# -------------------------------------------------------
$root3 = Join-Path $TestRoot 'no-files-property'
New-MinimalPlanReplayRoot -Root $root3
Set-Content -LiteralPath (Join-Path $root3 'ORACLE_DIFF_ANALYSIS.json') -Value '{"schema_version":"1.0"}' -Encoding UTF8
$verify3 = Invoke-PlanVerify -Root $root3
$hasNoFiles = $false
if ($null -ne $verify3 -and $null -ne $verify3.issues) {
    $hasNoFiles = @($verify3.issues | Where-Object { $_ -like 'oracle_analysis_invalid:*' }).Count -gt 0
}
$statusIsFail3 = ($null -ne $verify3 -and [string]$verify3.verification_status -eq 'FAIL')
Write-TestResult 'No files property -> has oracle_analysis_invalid issue' $hasNoFiles
Write-TestResult 'No files property -> verification_status is FAIL' $statusIsFail3

# -------------------------------------------------------
# Test 4: Valid JSON but zero production files -> FAIL
# -------------------------------------------------------
$root4 = Join-Path $TestRoot 'zero-prod-files'
New-MinimalPlanReplayRoot -Root $root4
$oracle4 = @{
    schema_version = '1.0'
    files = @(
        @{ path = 'src/test/java/com/example/Test.java'; layer = 'Test'; weight = 'LOW'; is_production = $false }
    )
    layer_summary = @{ Test = 1 }
    production_files = @()
} | ConvertTo-Json -Depth 6
Set-Content -LiteralPath (Join-Path $root4 'ORACLE_DIFF_ANALYSIS.json') -Value $oracle4 -Encoding UTF8
$verify4 = Invoke-PlanVerify -Root $root4
$hasEmptyProd = $false
if ($null -ne $verify4 -and $null -ne $verify4.issues) {
    $hasEmptyProd = @($verify4.issues | Where-Object { $_ -eq 'oracle_production_files_empty' }).Count -gt 0
}
$statusIsFail4 = ($null -ne $verify4 -and [string]$verify4.verification_status -eq 'FAIL')
Write-TestResult 'Zero production files -> has oracle_production_files_empty issue' $hasEmptyProd
Write-TestResult 'Zero production files -> verification_status is FAIL' $statusIsFail4

# -------------------------------------------------------
# Test 5: Below 50% overlap -> FAIL with oracle_overlap_below_threshold
# -------------------------------------------------------
$root5 = Join-Path $TestRoot 'below-threshold'
New-MinimalPlanReplayRoot -Root $root5
New-ValidOracleAnalysis -Root $root5
# Plan mentions nothing about the oracle files, so overlap should be low
# Override PLAN_RESULT with content that does NOT mention oracle file names
Set-Content -LiteralPath (Join-Path $root5 'PLAN_RESULT.md') -Value @'
# Plan Result

- plan_status: PROCEED
- first_slice: SomeRandomThing
- first_red_test: testRandom
- selected_strategy: bottom_up
- oracle_production_file_overlap: 10%

We will modify CompletelyUnrelated.java and OtherUnrelated.java.
'@ -Encoding UTF8
$verify5 = Invoke-PlanVerify -Root $root5
$hasBelowThreshold = $false
if ($null -ne $verify5 -and $null -ne $verify5.issues) {
    $hasBelowThreshold = @($verify5.issues | Where-Object { $_ -like 'oracle_overlap_below_threshold:*' }).Count -gt 0
}
$overlapRecorded = ($null -ne $verify5 -and $null -ne $verify5.oracle_overlap_percent -and $verify5.oracle_overlap_percent -lt 50)
Write-TestResult 'Below 50% overlap -> has oracle_overlap_below_threshold issue' $hasBelowThreshold
Write-TestResult 'Below 50% overlap -> oracle_overlap_percent is recorded and < 50' $overlapRecorded

# -------------------------------------------------------
# Test 6: Above 50% overlap -> no oracle overlap issue (may have other issues but not oracle)
# -------------------------------------------------------
$root6 = Join-Path $TestRoot 'passing-overlap'
New-MinimalPlanReplayRoot -Root $root6
New-ValidOracleAnalysis -Root $root6
# Plan mentions ClaimService and ClaimController (2 of 3 production files = 66%)
Set-Content -LiteralPath (Join-Path $root6 'PLAN_RESULT.md') -Value @'
# Plan Result

- plan_status: PROCEED
- first_slice: ClaimService
- first_red_test: testClaimCreation
- selected_strategy: top_down
- oracle_production_file_overlap: 66%

We will modify ClaimService.java and ClaimController.java.
'@ -Encoding UTF8
$verify6 = Invoke-PlanVerify -Root $root6
$hasNoOracleOverlapIssue = $true
if ($null -ne $verify6 -and $null -ne $verify6.issues) {
    $hasNoOracleOverlapIssue = @($verify6.issues | Where-Object { $_ -like 'oracle_overlap_below_threshold:*' -or $_ -eq 'oracle_analysis_missing' -or $_ -like 'oracle_analysis_invalid:*' -or $_ -eq 'oracle_production_files_empty' }).Count -eq 0
}
$overlapIsAbove50 = ($null -ne $verify6 -and $null -ne $verify6.oracle_overlap_percent -and $verify6.oracle_overlap_percent -ge 50)
Write-TestResult 'Above 50% overlap -> no oracle overlap fail issue' $hasNoOracleOverlapIssue
Write-TestResult 'Above 50% overlap -> oracle_overlap_percent >= 50' $overlapIsAbove50

# -------------------------------------------------------
# Runner-side oracle gate artifact behavioral tests
# These simulate the exact path Run-ReplayLoop.ps1 takes when
# Verify-PlanContract.ps1 fails on oracle analysis issues.
# -------------------------------------------------------

# Helper: simulates the runner's oracle gate artifact writer.
# Takes the verifier output (PLAN_CONTRACT_VERIFY.json text), determines
# reason_code using the same matching logic as Run-ReplayLoop.ps1, and
# writes ORACLE_OVERLAP_GATE.json. Returns the parsed gate object.
function Invoke-RunnerOracleGateWriter {
    param([string]$Root)
    $verifyJsonPath = Join-Path $Root 'PLAN_CONTRACT_VERIFY.json'
    $verifyText = if (Test-Path -LiteralPath $verifyJsonPath) {
        Get-Content -LiteralPath $verifyJsonPath -Raw -Encoding UTF8
    } else { '' }

    $oracleGateReasonCode = $null
    $oracleGateOverlapPercent = $null
    $oracleGateMatched = 0
    $oracleGateTotalProd = 0
    try {
        $verifyData = $verifyText | ConvertFrom-Json
        foreach ($issue in $verifyData.issues) {
            if ($issue -eq 'oracle_analysis_missing') {
                $oracleGateReasonCode = 'oracle_analysis_missing'
                break
            } elseif ($issue -eq 'oracle_production_files_empty') {
                $oracleGateReasonCode = 'oracle_production_files_empty'
                break
            } elseif ($issue -match '^oracle_analysis_invalid') {
                $oracleGateReasonCode = 'oracle_analysis_invalid'
                break
            } elseif ($issue -match '^oracle_overlap_below_threshold:') {
                $oracleGateReasonCode = 'oracle_overlap_below_threshold'
                if ($null -ne $verifyData.oracle_overlap_percent) {
                    $oracleGateOverlapPercent = [int]$verifyData.oracle_overlap_percent
                }
                # Use exact counts from verifier output
                if ($null -ne $verifyData.oracle_overlap_matched) {
                    $oracleGateMatched = [int]$verifyData.oracle_overlap_matched
                }
                if ($null -ne $verifyData.oracle_overlap_total_production) {
                    $oracleGateTotalProd = [int]$verifyData.oracle_overlap_total_production
                }
                if ($oracleGateMatched -eq 0 -and $oracleGateTotalProd -eq 0) {
                    $localOraclePath = Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json'
                    if (Test-Path -LiteralPath $localOraclePath) {
                        try {
                            $localOracle = Get-Content -LiteralPath $localOraclePath -Raw -Encoding UTF8 | ConvertFrom-Json
                            $localProdFiles = @($localOracle.files | Where-Object { [bool]$_.is_production })
                            $oracleGateTotalProd = $localProdFiles.Count
                        } catch { }
                    }
                }
                break
            }
        }
    } catch { }

    if ($null -ne $oracleGateReasonCode) {
        $gatePath = Join-Path $Root 'ORACLE_OVERLAP_GATE.json'
        [ordered]@{
            gate = 'oracle_overlap'
            reason_code = $oracleGateReasonCode
            overlap_percent = $oracleGateOverlapPercent
            matched = $oracleGateMatched
            total_oracle_production = $oracleGateTotalProd
            threshold = 50
            decision = 'BLOCKED'
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $gatePath -Encoding UTF8
        return Get-Content -LiteralPath $gatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

# --- Runner Test A: Missing oracle analysis -> runner writes gate artifact ---
$rootA = Join-Path $TestRoot 'runner-missing-oracle'
New-MinimalPlanReplayRoot -Root $rootA
$verifyA = Invoke-PlanVerify -Root $rootA
$gateA = Invoke-RunnerOracleGateWriter -Root $rootA
$gateAExists = ($null -ne $gateA)
$gateADecision = ($null -ne $gateA -and [string]$gateA.decision -eq 'BLOCKED')
$gateAReason = ($null -ne $gateA -and [string]$gateA.reason_code -eq 'oracle_analysis_missing')
Write-TestResult 'Runner: missing oracle -> ORACLE_OVERLAP_GATE.json exists' $gateAExists
Write-TestResult 'Runner: missing oracle -> decision is BLOCKED' $gateADecision
Write-TestResult 'Runner: missing oracle -> reason_code is oracle_analysis_missing' $gateAReason

# --- Runner Test B: Invalid JSON -> runner writes gate artifact ---
$rootB = Join-Path $TestRoot 'runner-invalid-json'
New-MinimalPlanReplayRoot -Root $rootB
Set-Content -LiteralPath (Join-Path $rootB 'ORACLE_DIFF_ANALYSIS.json') -Value '{{broken' -Encoding UTF8
$verifyB = Invoke-PlanVerify -Root $rootB
$gateB = Invoke-RunnerOracleGateWriter -Root $rootB
$gateBExists = ($null -ne $gateB)
$gateBDecision = ($null -ne $gateB -and [string]$gateB.decision -eq 'BLOCKED')
$gateBReason = ($null -ne $gateB -and [string]$gateB.reason_code -eq 'oracle_analysis_invalid')
Write-TestResult 'Runner: invalid JSON -> ORACLE_OVERLAP_GATE.json exists' $gateBExists
Write-TestResult 'Runner: invalid JSON -> decision is BLOCKED' $gateBDecision
Write-TestResult 'Runner: invalid JSON -> reason_code is oracle_analysis_invalid' $gateBReason

# --- Runner Test C: No-files property -> runner writes gate artifact ---
$rootC = Join-Path $TestRoot 'runner-no-files'
New-MinimalPlanReplayRoot -Root $rootC
Set-Content -LiteralPath (Join-Path $rootC 'ORACLE_DIFF_ANALYSIS.json') -Value '{"schema_version":"1.0"}' -Encoding UTF8
$verifyC = Invoke-PlanVerify -Root $rootC
$gateC = Invoke-RunnerOracleGateWriter -Root $rootC
$gateCExists = ($null -ne $gateC)
$gateCReason = ($null -ne $gateC -and [string]$gateC.reason_code -eq 'oracle_analysis_invalid')
Write-TestResult 'Runner: no files property -> ORACLE_OVERLAP_GATE.json exists' $gateCExists
Write-TestResult 'Runner: no files property -> reason_code is oracle_analysis_invalid' $gateCReason

# --- Runner Test D: Zero production files -> runner writes gate artifact ---
$rootD = Join-Path $TestRoot 'runner-zero-prod'
New-MinimalPlanReplayRoot -Root $rootD
$oracleD = @{
    schema_version = '1.0'
    files = @(
        @{ path = 'src/test/Foo.java'; layer = 'Test'; weight = 'LOW'; is_production = $false }
    )
    layer_summary = @{ Test = 1 }
    production_files = @()
} | ConvertTo-Json -Depth 6
Set-Content -LiteralPath (Join-Path $rootD 'ORACLE_DIFF_ANALYSIS.json') -Value $oracleD -Encoding UTF8
$verifyD = Invoke-PlanVerify -Root $rootD
$gateD = Invoke-RunnerOracleGateWriter -Root $rootD
$gateDExists = ($null -ne $gateD)
$gateDDecision = ($null -ne $gateD -and [string]$gateD.decision -eq 'BLOCKED')
$gateDReason = ($null -ne $gateD -and [string]$gateD.reason_code -eq 'oracle_production_files_empty')
Write-TestResult 'Runner: zero production files -> ORACLE_OVERLAP_GATE.json exists' $gateDExists
Write-TestResult 'Runner: zero production files -> decision is BLOCKED' $gateDDecision
Write-TestResult 'Runner: zero production files -> reason_code is oracle_production_files_empty' $gateDReason

# --- Runner Test E: Gate artifact has required structural fields ---
$gateEHasGate = ($null -ne $gateA -and [string]$gateA.gate -eq 'oracle_overlap')
$gateEHasThreshold = ($null -ne $gateA -and $gateA.threshold -eq 50)
$gateEOverlapNull = ($null -ne $gateA -and $null -eq $gateA.overlap_percent)
$gateEMatchedZero = ($null -ne $gateA -and $gateA.matched -eq 0)
Write-TestResult 'Runner: gate artifact has gate=oracle_overlap' $gateEHasGate
Write-TestResult 'Runner: gate artifact has threshold=50' $gateEHasThreshold
Write-TestResult 'Runner: gate artifact has overlap_percent=null' $gateEOverlapNull
Write-TestResult 'Runner: gate artifact has matched=0' $gateEMatchedZero

# --- Runner Test F: No oracle gate artifact when verifier passes ---
$rootF = Join-Path $TestRoot 'runner-passing'
New-MinimalPlanReplayRoot -Root $rootF
New-ValidOracleAnalysis -Root $rootF
Set-Content -LiteralPath (Join-Path $rootF 'PLAN_RESULT.md') -Value @'
# Plan Result

- plan_status: PROCEED
- first_slice: ClaimService
- first_red_test: testClaimCreation
- selected_strategy: top_down
- oracle_production_file_overlap: 66%

We will modify ClaimService.java and ClaimController.java.
'@ -Encoding UTF8
$verifyF = Invoke-PlanVerify -Root $rootF
$gateF = Invoke-RunnerOracleGateWriter -Root $rootF
$gateFNull = ($null -eq $gateF)
$gateFNotWritten = -not (Test-Path -LiteralPath (Join-Path $rootF 'ORACLE_OVERLAP_GATE.json'))
Write-TestResult 'Runner: passing verification -> no gate artifact written by verifier-path writer' $gateFNull

# --- Runner Test G: Below-threshold overlap -> runner writes gate artifact with overlap data ---
$rootG = Join-Path $TestRoot 'runner-below-threshold'
New-MinimalPlanReplayRoot -Root $rootG
New-ValidOracleAnalysis -Root $rootG
Set-Content -LiteralPath (Join-Path $rootG 'PLAN_RESULT.md') -Value @'
# Plan Result

- plan_status: PROCEED
- first_slice: SomeRandomThing
- first_red_test: testRandom
- selected_strategy: bottom_up
- oracle_production_file_overlap: 0%

We will modify CompletelyUnrelated.java and OtherUnrelated.java.
'@ -Encoding UTF8
$verifyG = Invoke-PlanVerify -Root $rootG
$gateG = Invoke-RunnerOracleGateWriter -Root $rootG
$gateGExists = ($null -ne $gateG)
$gateGDecision = ($null -ne $gateG -and [string]$gateG.decision -eq 'BLOCKED')
$gateGReason = ($null -ne $gateG -and [string]$gateG.reason_code -eq 'oracle_overlap_below_threshold')
$gateGOverlap = ($null -ne $gateG -and $null -ne $gateG.overlap_percent -and $gateG.overlap_percent -lt 50)
$gateGThreshold = ($null -ne $gateG -and $gateG.threshold -eq 50)
$gateGTotalProd = ($null -ne $gateG -and $gateG.total_oracle_production -gt 0)
Write-TestResult 'Runner: below-threshold overlap -> ORACLE_OVERLAP_GATE.json exists' $gateGExists
Write-TestResult 'Runner: below-threshold overlap -> decision is BLOCKED' $gateGDecision
Write-TestResult 'Runner: below-threshold overlap -> reason_code is oracle_overlap_below_threshold' $gateGReason
Write-TestResult 'Runner: below-threshold overlap -> overlap_percent is recorded and < 50' $gateGOverlap
Write-TestResult 'Runner: below-threshold overlap -> threshold is 50' $gateGThreshold
Write-TestResult 'Runner: below-threshold overlap -> total_oracle_production > 0' $gateGTotalProd


# --- Runner Test H: 1-of-3 below-threshold overlap -> exact matched count preserved ---
# This is the key lossy-reverse-engineering bug fix: 1 of 3 = 33%, and matched must be 1 not 0.
$rootH = Join-Path $TestRoot 'runner-below-threshold-1of3'
New-MinimalPlanReplayRoot -Root $rootH
New-ValidOracleAnalysis -Root $rootH
# Plan mentions only ClaimMapper (1 of 3 production files = 33%)
Set-Content -LiteralPath (Join-Path $rootH 'PLAN_RESULT.md') -Value @'
# Plan Result

- plan_status: PROCEED
- first_slice: ClaimMapper
- first_red_test: testMapper
- selected_strategy: bottom_up
- oracle_production_file_overlap: 33%

We will modify ClaimMapper.java to add mapping logic.
'@ -Encoding UTF8
$verifyH = Invoke-PlanVerify -Root $rootH
$gateH = Invoke-RunnerOracleGateWriter -Root $rootH
$gateHExists = ($null -ne $gateH)
$gateHDecision = ($null -ne $gateH -and [string]$gateH.decision -eq 'BLOCKED')
$gateHReason = ($null -ne $gateH -and [string]$gateH.reason_code -eq 'oracle_overlap_below_threshold')
$gateHOverlap = ($null -ne $gateH -and $null -ne $gateH.overlap_percent -and $gateH.overlap_percent -eq 33)
$gateHMatched = ($null -ne $gateH -and $gateH.matched -eq 1)
$gateHTotalProd = ($null -ne $gateH -and $gateH.total_oracle_production -eq 3)
$gateHThreshold = ($null -ne $gateH -and $gateH.threshold -eq 50)
Write-TestResult 'Runner: 1-of-3 overlap -> ORACLE_OVERLAP_GATE.json exists' $gateHExists
Write-TestResult 'Runner: 1-of-3 overlap -> decision is BLOCKED' $gateHDecision
Write-TestResult 'Runner: 1-of-3 overlap -> reason_code is oracle_overlap_below_threshold' $gateHReason
Write-TestResult 'Runner: 1-of-3 overlap -> overlap_percent is 33' $gateHOverlap
Write-TestResult 'Runner: 1-of-3 overlap -> matched is 1 (exact, not floor-derived)' $gateHMatched
Write-TestResult 'Runner: 1-of-3 overlap -> total_oracle_production is 3' $gateHTotalProd
Write-TestResult 'Runner: 1-of-3 overlap -> threshold is 50' $gateHThreshold

# -------------------------------------------------------
# Cleanup
# -------------------------------------------------------
if (Test-Path -LiteralPath $TestRoot) {
    Remove-Item -LiteralPath $TestRoot -Recurse -Force
}

# Summary
Write-Host ''
Write-Host '=== Results ==='
Write-Host "PASS: $passCount"
Write-Host "FAIL: $failCount"
Write-Host "Total: $($passCount + $failCount)"

if ($failCount -gt 0) {
    Write-Host ''
    Write-Host 'Failed tests:'
    foreach ($r in $testResults) {
        if (-not $r.pass) {
            Write-Host "  - $($r.name): $($r.detail)"
        }
    }
    exit 1
}

Write-Host 'All oracle fail-closed behavioral tests passed.'
exit 0
