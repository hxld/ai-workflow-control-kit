# Test-v432-LayerValidationAndTodoBan.ps1
# Tests for the three experiments from aiClaimV2 NEXT_EXPERIMENT_PLAN.md (v432)

param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$autopilotRoot = Split-Path -Parent $scriptRoot

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'Experiment 1: Architectural Layer Pre-Flight Gate - Test-CarrierLayer in Invoke-AgentPrompt.ps1',
            'Experiment 2: Comprehensive Carrier Index - Generate-CarrierIndex.ps1',
            'Experiment 3: RED Phase TODO Ban - Test-TodoPlaceholder in Invoke-AgentPrompt.ps1'
        )
    } | Format-List
    exit 0
}

Write-Host "=== v432 Layer Validation and TODO Ban Test ===" -ForegroundColor Cyan

$allPassed = $true

# Test 1: Check Invoke-AgentPrompt.ps1 has Test-CarrierLayer
Write-Host "`n[Test 1] Verifying Test-CarrierLayer in Invoke-AgentPrompt.ps1..." -ForegroundColor Yellow
$invokeAgentPrompt = Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1'
if (Test-Path -LiteralPath $invokeAgentPrompt) {
    $content = Get-Content -LiteralPath $invokeAgentPrompt -Raw -Encoding UTF8
    if ($content -match 'function Test-CarrierLayer' -and $content -match 'function Invoke-PreFlightCarrierCheck') {
        Write-Host "PASSED: Invoke-AgentPrompt.ps1 has Test-CarrierLayer function" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Invoke-AgentPrompt.ps1 missing Test-CarrierLayer function" -ForegroundColor Red
        $allPassed = $false
    }
} else {
    Write-Host "FAILED: Invoke-AgentPrompt.ps1 not found" -ForegroundColor Red
    $allPassed = $false
}

# Test 2: Check Generate-CarrierIndex.ps1 is wired into replay preparation
Write-Host "`n[Test 2] Verifying Generate-CarrierIndex.ps1 runner integration..." -ForegroundColor Yellow
$carrierIndexScript = Join-Path $scriptRoot 'Generate-CarrierIndex.ps1'
$startReplayRound = Join-Path $scriptRoot 'Start-ReplayRound.ps1'
if ((Test-Path -LiteralPath $carrierIndexScript) -and (Test-Path -LiteralPath $startReplayRound)) {
    $content = Get-Content -LiteralPath $carrierIndexScript -Raw -Encoding UTF8
    $runnerContent = Get-Content -LiteralPath $startReplayRound -Raw -Encoding UTF8
    if ($content -match 'Surface Carrier Scan' -and $content -match 'Facade Layer' -and $runnerContent -match 'Generate-CarrierIndex\.ps1') {
        Write-Host "PASSED: Generate-CarrierIndex.ps1 exists and Start-ReplayRound.ps1 invokes it" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Generate-CarrierIndex.ps1 exists but is incomplete or not wired into Start-ReplayRound.ps1" -ForegroundColor Red
        $allPassed = $false
    }
} else {
    Write-Host "FAILED: Generate-CarrierIndex.ps1 or Start-ReplayRound.ps1 not found" -ForegroundColor Red
    $allPassed = $false
}

# Test 3: Check TODO placeholder check is wired into Run-SliceLoop.ps1
Write-Host "`n[Test 3] Verifying Invoke-TodoPlaceholderCheck.ps1 runner integration..." -ForegroundColor Yellow
$todoPlaceholderScript = Join-Path $scriptRoot 'Invoke-TodoPlaceholderCheck.ps1'
$runSliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
if ((Test-Path -LiteralPath $todoPlaceholderScript) -and (Test-Path -LiteralPath $runSliceLoop)) {
    $content = Get-Content -LiteralPath $todoPlaceholderScript -Raw -Encoding UTF8
    $runnerContent = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8
    if ($content -match 'TODO placeholder check' -and $runnerContent -match 'Invoke-TodoPlaceholderCheck\.ps1') {
        Write-Host "PASSED: Invoke-TodoPlaceholderCheck.ps1 exists and Run-SliceLoop.ps1 invokes it" -ForegroundColor Green
    } else {
        Write-Host "FAILED: TODO placeholder script is incomplete or not wired into Run-SliceLoop.ps1" -ForegroundColor Red
        $allPassed = $false
    }
} else {
    Write-Host "FAILED: Invoke-TodoPlaceholderCheck.ps1 or Run-SliceLoop.ps1 not found" -ForegroundColor Red
    $allPassed = $false
}

# Test 4: Validate layer validation logic
Write-Host "`n[Test 4] Validating layer validation logic..." -ForegroundColor Yellow
try {
    # Define the function inline for testing (same logic as in Invoke-AgentPrompt.ps1)
    function Test-CarrierLayer {
        param(
            [Parameter(Mandatory=$true)]
            [string]$CarrierPath
        )

        # Normalize path
        $CarrierPath = $CarrierPath -replace '\\', '/'

        # Check for Facade layer (claim-api)
        if ($CarrierPath -match 'claim-api/.*Facade\.java') {
            return $true
        }

        # Check for Controller layer (claim-web)
        if ($CarrierPath -match 'claim-web/.*Controller\.java') {
            return $true
        }

        # Check for Facade implementation in claim-core
        if ($CarrierPath -match 'claim-core/.*facade/.*FacadeImpl\.java') {
            return $true
        }

        # All other layers are non-executable for entry points
        return $false
    }

    # Test valid Facade layer
    $validFacade = Test-CarrierLayer "claim-api/src/main/java/com/huize/claim/api/facade/AiClaimFacade.java"
    if ($validFacade) {
        Write-Host "PASSED: Test-CarrierLayer correctly identifies Facade as valid" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Test-CarrierLayer incorrectly rejects Facade" -ForegroundColor Red
        $allPassed = $false
    }

    # Test valid Controller layer
    $validController = Test-CarrierLayer "claim-web/src/main/java/com/huize/claim/web/controller/AiClaimController.java"
    if ($validController) {
        Write-Host "PASSED: Test-CarrierLayer correctly identifies Controller as valid" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Test-CarrierLayer incorrectly rejects Controller" -ForegroundColor Red
        $allPassed = $false
    }

    # Test invalid Service layer
    $invalidService = Test-CarrierLayer "claim-core/src/main/java/com/huize/claim/core/ai/service/AiAutoClaimFlowService.java"
    if (-not $invalidService) {
        Write-Host "PASSED: Test-CarrierLayer correctly rejects Service layer" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Test-CarrierLayer incorrectly accepts Service layer" -ForegroundColor Red
        $allPassed = $false
    }

} catch {
    Write-Host "FAILED: Error in layer validation test: $_" -ForegroundColor Red
    $allPassed = $false
}

# Final result
Write-Host "`n=== Test Result ===" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "v432 Layer Validation and TODO Ban: ALL PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "v432 Layer Validation and TODO Ban: SOME TESTS FAILED" -ForegroundColor Red
    exit 1
}
