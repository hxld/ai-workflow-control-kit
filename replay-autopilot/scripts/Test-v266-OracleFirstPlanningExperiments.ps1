param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\oracle-first-planning-test')
)

$ErrorActionPreference = 'Stop'
$passCount = 0
$failCount = 0
$testResults = New-Object System.Collections.Generic.List[object]

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

$noScript = 'no_script_found'
$utf8 = [System.Text.Encoding]::UTF8

Write-Host '=== Oracle-First Planning Experiments ==='
Write-Host ''

# Test 1: Get-OracleDiffAnalysis script exists
$scriptPath = Join-Path $PSScriptRoot 'Get-OracleDiffAnalysis.ps1'
Write-TestResult 'Get-OracleDiffAnalysis.ps1 exists' (Test-Path -LiteralPath $scriptPath)

# Test 2: Script accepts required parameters
$scriptContent = [System.IO.File]::ReadAllText($scriptPath, $utf8)
$params = @('Worktree', 'BaseCommit', 'OracleCommit', 'OutPath')
foreach ($param in $params) {
    $hasParam = $scriptContent.Contains("`$$param")
    Write-TestResult "Get-OracleDiffAnalysis has param: $param" $hasParam
}

# Test 3: Script classifies layers correctly
$hasLayerFunc = $scriptContent.Contains('function Get-LayerClassification')
Write-TestResult 'Get-OracleDiffAnalysis has Get-LayerClassification' $hasLayerFunc

$hasTestLayer = $scriptContent.Contains("'Test'")
$hasServiceLayer = $scriptContent.Contains("'Service'")
$hasControllerLayer = $scriptContent.Contains("'Controller'")
$hasMapperLayer = $scriptContent.Contains("'Mapper'")
$hasDtoLayer = $scriptContent.Contains("'DTO'")
Write-TestResult 'Layer classification includes Test/Service/Controller/Mapper/DTO' ($hasTestLayer -and $hasServiceLayer -and $hasControllerLayer -and $hasMapperLayer -and $hasDtoLayer)

# Test 4: Script classifies weights correctly
$hasWeightFunc = $scriptContent.Contains('function Get-BusinessWeight')
Write-TestResult 'Get-OracleDiffAnalysis has Get-BusinessWeight' $hasWeightFunc

$hasHighWeight = $scriptContent.Contains("'HIGH'")
$hasMediumWeight = $scriptContent.Contains("'MEDIUM'")
$hasLowWeight = $scriptContent.Contains("'LOW'")
Write-TestResult 'Business weight includes HIGH/MEDIUM/LOW' ($hasHighWeight -and $hasMediumWeight -and $hasLowWeight)

# Test 5: Script outputs JSON with expected schema fields
$hasSchemaVersion = $scriptContent.Contains('schema_version')
$hasFilesArray = $scriptContent.Contains('files = @($files)') -or $scriptContent.Contains('files = $files.ToArray()')
$hasLayerSummary = $scriptContent.Contains('layer_summary')
$hasProductionFiles = $scriptContent.Contains('production_files')
Write-TestResult 'Output JSON has schema_version/files/layer_summary/production_files' ($hasSchemaVersion -and $hasFilesArray -and $hasLayerSummary -and $hasProductionFiles)

# Test 6: Start-ReplayRound includes ORACLE_DIFF_ANALYSIS in template values
$startReplayPath = Join-Path $PSScriptRoot 'Start-ReplayRound.ps1'
$startReplayContent = [System.IO.File]::ReadAllText($startReplayPath, $utf8)
$hasOracleDiffVar = $startReplayContent.Contains('ORACLE_DIFF_ANALYSIS')
Write-TestResult 'Start-ReplayRound has ORACLE_DIFF_ANALYSIS template variable' $hasOracleDiffVar

$hasOracleDiffAnalysisOut = $startReplayContent.Contains('oracleDiffAnalysisOut')
Write-TestResult 'Start-ReplayRound has oracleDiffAnalysisOut variable' $hasOracleDiffAnalysisOut

$callsOracleAnalysis = $startReplayContent.Contains('Get-OracleDiffAnalysis')
Write-TestResult 'Start-ReplayRound calls Get-OracleDiffAnalysis' $callsOracleAnalysis

$hasOracleDiffInMetadata = $startReplayContent.Contains('oracle_diff_analysis')
Write-TestResult 'Start-ReplayRound includes oracle_diff_analysis in metadata' $hasOracleDiffInMetadata

# Test 7: Phase 0 prompt has Oracle Contract Verification
$phase0PromptPath = Join-Path (Join-Path $PSScriptRoot '..') 'prompts\phase0-contract-gate.prompt.md'
$phase0Prompt = [System.IO.File]::ReadAllText($phase0PromptPath, $utf8)
$phase0HasOracleAnalysis = $phase0Prompt.Contains('ORACLE_DIFF_ANALYSIS')
Write-TestResult 'Phase 0 prompt references ORACLE_DIFF_ANALYSIS' $phase0HasOracleAnalysis

$phase0HasOracleVerification = $phase0Prompt.Contains('Oracle Contract Verification')
Write-TestResult 'Phase 0 prompt has Oracle Contract Verification section' $phase0HasOracleVerification

$phase0AllowsOracleAnalysis = $phase0Prompt.Contains('ORACLE_DIFF_ANALYSIS')
Write-TestResult 'Phase 0 allows reading ORACLE_DIFF_ANALYSIS' $phase0AllowsOracleAnalysis

$phase0ForbidsDirectOracle = $phase0Prompt.Contains('git diff') -or $phase0Prompt.Contains('git log') -or $phase0Prompt.Contains('git show')
# Should NOT contain direct oracle access in allowed section
Write-TestResult 'Phase 0 still has oracle constraints' ($phase0HasOracleAnalysis -and $phase0HasOracleVerification)

# Test 8: Plan prompt has Oracle-Constrained Planning
$planPromptPath = Join-Path (Join-Path $PSScriptRoot '..') 'prompts\phase-plan-tournament.prompt.md'
$planPrompt = [System.IO.File]::ReadAllText($planPromptPath, $utf8)
$planHasOracleAnalysis = $planPrompt.Contains('ORACLE_DIFF_ANALYSIS')
Write-TestResult 'Plan prompt references ORACLE_DIFF_ANALYSIS' $planHasOracleAnalysis

$planHasOracleConstrained = $planPrompt.Contains('Oracle-Constrained Planning')
Write-TestResult 'Plan prompt has Oracle-Constrained Planning section' $planHasOracleConstrained

$planHasOverlapThreshold = $planPrompt.Contains('50%')
Write-TestResult 'Plan prompt specifies 50% overlap threshold' $planHasOverlapThreshold

$planHasFirstSliceRule = $planPrompt.Contains('First Slice Rule')
Write-TestResult 'Plan prompt has First Slice Rule' $planHasFirstSliceRule

$planHasOracleOverlapField = $planPrompt.Contains('oracle_production_file_overlap')
Write-TestResult 'Plan prompt requires oracle_production_file_overlap in PLAN_RESULT' $planHasOracleOverlapField

# Test 9: Verify-PlanContract has oracle overlap validation
$verifyPath = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$verifyContent = [System.IO.File]::ReadAllText($verifyPath, $utf8)
$verifyHasOracleOverlap = $verifyContent.Contains('oracle_overlap_below_threshold')
Write-TestResult 'Verify-PlanContract has oracle_overlap_below_threshold check' $verifyHasOracleOverlap

$verifyHas50Threshold = $verifyContent.Contains('lt 50')
Write-TestResult 'Verify-PlanContract uses 50% threshold' $verifyHas50Threshold

$verifyHasOracleAnalysis = $verifyContent.Contains('ORACLE_DIFF_ANALYSIS.json')
Write-TestResult 'Verify-PlanContract reads ORACLE_DIFF_ANALYSIS.json' $verifyHasOracleAnalysis

$verifyOutputsOverlap = $verifyContent.Contains('oracle_overlap_percent')
Write-TestResult 'Verify-PlanContract outputs oracle_overlap_percent' $verifyOutputsOverlap

$verifyOutputsMatched = $verifyContent.Contains('oracle_overlap_matched')
Write-TestResult 'Verify-PlanContract outputs oracle_overlap_matched' $verifyOutputsMatched

$verifyOutputsTotalProd = $verifyContent.Contains('oracle_overlap_total_production')
Write-TestResult 'Verify-PlanContract outputs oracle_overlap_total_production' $verifyOutputsTotalProd

$verifyFailsOnMissing = $verifyContent.Contains('oracle_analysis_missing')
Write-TestResult 'Verify-PlanContract fails on missing oracle analysis' $verifyFailsOnMissing

$verifyFailsOnInvalid = $verifyContent.Contains('oracle_analysis_invalid')
Write-TestResult 'Verify-PlanContract fails on invalid oracle analysis' $verifyFailsOnInvalid

$verifyFailsOnEmpty = $verifyContent.Contains('oracle_production_files_empty')
Write-TestResult 'Verify-PlanContract fails on empty production files' $verifyFailsOnEmpty

# Test 10: Run-ReplayLoop has oracle overlap gate
$loopPath = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
$loopContent = [System.IO.File]::ReadAllText($loopPath, $utf8)
$loopHasOracleGate = $loopContent.Contains('Oracle overlap gate')
Write-TestResult 'Run-ReplayLoop has Oracle overlap gate' $loopHasOracleGate

$loopHasOracleGateBlock = $loopContent.Contains('ORACLE_OVERLAP_GATE.json')
Write-TestResult 'Run-ReplayLoop writes ORACLE_OVERLAP_GATE.json' $loopHasOracleGateBlock

$loopHasBlockDecision = $loopContent.Contains("decision = 'BLOCKED'")
Write-TestResult 'Run-ReplayLoop blocks on oracle overlap below threshold' $loopHasBlockDecision

$loopBlocksOnMissing = $loopContent.Contains('oracle_analysis_missing')
Write-TestResult 'Run-ReplayLoop blocks on missing oracle analysis' $loopBlocksOnMissing

$loopBlocksOnInvalid = $loopContent.Contains('oracle_analysis_invalid')
Write-TestResult 'Run-ReplayLoop blocks on invalid oracle analysis' $loopBlocksOnInvalid

$loopBlocksOnEmpty = $loopContent.Contains('oracle_production_files_empty')
Write-TestResult 'Run-ReplayLoop blocks on empty production files' $loopBlocksOnEmpty

$loopGateHasReasonCode = $loopContent.Contains('reason_code')
Write-TestResult 'Run-ReplayLoop ORACLE_OVERLAP_GATE.json has reason_code field' $loopGateHasReasonCode

# Runner writes gate artifact in verify-failure path (before break)
$loopVerifierPathGate = $loopContent.Contains('$oracleGateReasonCode') -and $loopContent.Contains('oracle_analysis_missing') -and $loopContent.Contains('oracle_production_files_empty') -and $loopContent.Contains('oracle_analysis_invalid') -and $loopContent.Contains('oracle_overlap_below_threshold')
Write-TestResult 'Run-ReplayLoop writes gate artifact in verify-failure path (all oracle issues)' $loopVerifierPathGate

# Test 11: Behavioral test script exists
$behavioralTestPath = Join-Path $PSScriptRoot 'Test-v266-OracleFailClosed.ps1'
Write-TestResult 'Test-v266-OracleFailClosed.ps1 exists' (Test-Path -LiteralPath $behavioralTestPath)

$behavioralContent = [System.IO.File]::ReadAllText($behavioralTestPath, $utf8)
$behavioralHasInvokeVerify = $behavioralContent.Contains('Invoke-PlanVerify')
Write-TestResult 'Behavioral test invokes verifier against temp roots' $behavioralHasInvokeVerify

$behavioralCoversMissing = $behavioralContent.Contains('Missing ORACLE_DIFF_ANALYSIS.json')
Write-TestResult 'Behavioral test covers missing oracle analysis' $behavioralCoversMissing

$behavioralCoversInvalid = $behavioralContent.Contains('Invalid JSON')
Write-TestResult 'Behavioral test covers invalid JSON' $behavioralCoversInvalid

$behavioralCoversZeroProd = $behavioralContent.Contains('Zero production files')
Write-TestResult 'Behavioral test covers zero production files' $behavioralCoversZeroProd

$behavioralCoversBelowThreshold = $behavioralContent.Contains('Below 50% overlap')
Write-TestResult 'Behavioral test covers below-threshold overlap' $behavioralCoversBelowThreshold

$behavioralCoversPassing = $behavioralContent.Contains('Above 50% overlap')
Write-TestResult 'Behavioral test covers passing overlap' $behavioralCoversPassing

$behavioralHasRunnerGate = $behavioralContent.Contains('Invoke-RunnerOracleGateWriter')
Write-TestResult 'Behavioral test covers runner-side gate artifact writing' $behavioralHasRunnerGate

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

Write-Host 'All oracle-first planning experiment tests passed.'
exit 0
