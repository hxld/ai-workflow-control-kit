param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Text {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$verifier = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v391-test-" + [guid]::NewGuid().ToString('N'))
$testRoot2 = $null
$testRoot3 = $null

New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
try {
    $worktree = Join-Path $testRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null

    # Test 1: new_service_proposed=true should NOT trigger carrier_not_found issue
    $planResultPath = Join-Path $testRoot 'PLAN_RESULT.md'
    Write-Text $planResultPath @'
# Plan Result - New Service

- plan_status: PROCEED
- carrier_search: performed
- carrier_search_queries: Grep "class.*AutoFlow.*Service" type=java; Glob **/*Service.java under example-core; Grep "auto.*claim|auto.*flow" type=java -i; Grep "class.*Flow.*\{" type=java
- existing_production_carriers: ExampleCalculatorService; ExampleModuleConfigService; ExamineFlowFacadeImpl; AiOcrService; AiReviewMaterialService; AiDetermineLiabilityService
- selected_carrier_from_search: NEW_SERVICE_ExampleFlowService
- new_service_proposed: true
- new_service_justification: orphan_feature_no_existing_domain
- first_slice: S1 - Auto-flow core path
'@

    # Create FIRST_SLICE_PROOF_PLAN.md
    $firstSlicePath = Join-Path $testRoot 'FIRST_SLICE_PROOF_PLAN.md'
    Write-Text $firstSlicePath @'
# First Slice Proof Plan

- first_slice: S1
- first_red_test: ExampleFlowServiceTest.testExecuteAutoFlow_FlashCase_Success
- selected_carrier: ExampleFlowService
'@

    # Run verifier - the key assertion is that carrier_not_found issue should NOT be present
    $verifyJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Stage Plan -Worktree $worktree -ErrorAction SilentlyContinue | ConvertFrom-Json
    Assert-True ($verifyJson.issues -notcontains 'carrier_search_selected_carrier_not_found_in_codebase') "Should NOT have carrier_not_found issue when new_service_proposed=true (this was the v391 fix)"
    Write-Host "PASS: Test 1 - new_service_proposed=true skips carrier existence check"

    # Test 2: new_service_proposed=false with non-existent carrier SHOULD trigger issue
    $testRoot2 = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v391-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $testRoot2 | Out-Null
    $worktree2 = Join-Path $testRoot2 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree2 | Out-Null

    $planResultPath2 = Join-Path $testRoot2 'PLAN_RESULT.md'
    Write-Text $planResultPath2 @'
# Plan Result - Non-existent Carrier (not marked as new)

- plan_status: PROCEED
- carrier_search: performed
- carrier_search_queries: Grep "class.*TestService.*Service" type=java; Grep "class.*Another.*Service" type=java; Grep "class.*Third.*Service" type=java
- existing_production_carriers: ExampleCalculatorService
- selected_carrier_from_search: SyntheticCarrierService
- new_service_proposed: false
'@

    $verifyJson2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot2 -Stage Plan -Worktree $worktree2 -ErrorAction SilentlyContinue | ConvertFrom-Json
    Assert-True ($verifyJson2.issues -contains 'carrier_search_selected_carrier_not_found_in_codebase') "Should have carrier_not_found issue for synthetic carrier when new_service_proposed=false"
    Write-Host "PASS: Test 2 - new_service_proposed=false still validates carrier existence"

    # Test 3: new_service_proposed=true without justification should fail with unjustified issue
    $testRoot3 = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v391-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $testRoot3 | Out-Null
    $worktree3 = Join-Path $testRoot3 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree3 | Out-Null

    $planResultPath3 = Join-Path $testRoot3 'PLAN_RESULT.md'
    Write-Text $planResultPath3 @'
# Plan Result - New Service without Justification

- plan_status: PROCEED
- carrier_search: performed
- carrier_search_queries: Grep "class.*TestService.*Service" type=java; Grep "class.*Another.*Service" type=java; Grep "class.*Third.*Service" type=java
- existing_production_carriers: ExampleCalculatorService
- selected_carrier_from_search: NEW_SERVICE_MyNewService
- new_service_proposed: true
- new_service_justification: weak_reason
'@

    $verifyJson3 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot3 -Stage Plan -Worktree $worktree3 -ErrorAction SilentlyContinue | ConvertFrom-Json
    Assert-True ($verifyJson3.issues -contains 'carrier_search_new_service_unjustified') "Should have new_service_unjustified issue when justification is weak"
    Assert-True ($verifyJson3.issues -notcontains 'carrier_search_selected_carrier_not_found_in_codebase') "Should NOT have carrier_not_found issue even when justification is weak (existence check is still skipped)"
    Write-Host "PASS: Test 3 - new_service_proposed=true requires justification but still skips existence check"

    Write-Host "`nPASS: All v391 new service existence skip tests passed"
    [ordered]@{ status = 'PASS' } | ConvertTo-Json -Depth 4
    exit 0
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    if ($testRoot2) { Remove-Item -LiteralPath $testRoot2 -Recurse -Force -ErrorAction SilentlyContinue }
    if ($testRoot3) { Remove-Item -LiteralPath $testRoot3 -Recurse -Force -ErrorAction SilentlyContinue }
}
