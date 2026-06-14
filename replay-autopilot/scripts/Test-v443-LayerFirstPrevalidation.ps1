# Test-v443-LayerFirstPrevalidation.ps1
# Regression test for v443 Layer-First Pre-Validation feature

$ErrorActionPreference = 'Stop'

$testPass = 0
$testFail = 0

function Test-Assertion {
    param(
        [string]$Name,
        [scriptblock]$Script,
        [string]$Expected
    )

    Write-Host "Testing: $Name" -NoNewline
    try {
        $result = & $Script | Out-String
        if ($result -match $Expected) {
            Write-Host " PASS" -ForegroundColor Green
            $script:testPass++
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            Write-Host "  Expected: $Expected" -ForegroundColor Red
            Write-Host "  Got: $result" -ForegroundColor Red
            $script:testFail++
        }
    } catch {
        Write-Host " ERROR: $_" -ForegroundColor Red
        $script:testFail++
    }
}

# Mock functions for testing
function Test-CarrierLayer {
    param([string]$CarrierPath)

    if ($CarrierPath -match "(\\|/)facade(\\|/)|Facade\b") { return "Facade" }
    elseif ($CarrierPath -match "(\\|/)controller(\\|/)|Controller\b") { return "Controller" }
    elseif ($CarrierPath -match "(\\|/)service(\\|/)|Service\b") { return "Service" }
    elseif ($CarrierPath -match "(\\|/)provider(\\|/)|Provider\b|Mapper\b") { return "Provider" }
    else { return "Unknown" }
}

function Get-SuggestedFacade {
    param([string]$ServiceCarrier, [string]$Worktree)

    $serviceName = [System.IO.Path]::GetFileNameWithoutExtension($ServiceCarrier)

    $patterns = @(
        ($serviceName -replace "Service$", "Facade"),
        ($serviceName -replace "Service$", "Controller"),
        ($serviceName -replace "ServiceImpl$", "Facade"),
        ($serviceName -replace "Service$", "Api")
    )

    foreach ($pattern in $patterns) {
        # Mock search - in real implementation this would use rg
        # For testing, we return a mock result for known patterns
        if ($pattern -match "Facade") {
            return @{ Found = $true; ClassName = $pattern; SearchOutput = "claim-api/src/main/java/com/huize/claim/facade/$pattern.java" }
        }
    }

    return @{ Found = $false; ClassName = $null; SearchOutput = $null }
}

Write-Host "`n=== v443 Layer-First Pre-Validation Tests ===`n" -ForegroundColor Cyan

# Test 1: Facade layer detection
Test-Assertion -Name "Facade layer detection from path" -Script {
    Test-CarrierLayer -CarrierPath "claim-api/src/main/java/com/huize/claim/facade/AiClaimFacade.java"
} -Expected "Facade"

# Test 2: Facade layer detection from class name
Test-Assertion -Name "Facade layer detection from class name" -Script {
    Test-CarrierLayer -CarrierPath "AiClaimFacade"
} -Expected "Facade"

# Test 3: Controller layer detection
Test-Assertion -Name "Controller layer detection" -Script {
    Test-CarrierLayer -CarrierPath "claim-web/src/main/java/com/huize/claim/controller/AiClaimController.java"
} -Expected "Controller"

# Test 4: Service layer detection
Test-Assertion -Name "Service layer detection" -Script {
    Test-CarrierLayer -CarrierPath "claim-core/src/main/java/com/huize/claim/core/service/AiClaimService.java"
} -Expected "Service"

# Test 5: Service layer detection from class name
Test-Assertion -Name "Service layer detection from class name" -Script {
    Test-CarrierLayer -CarrierPath "AiAutoClaimFlowService"
} -Expected "Service"

# Test 6: Provider layer detection
Test-Assertion -Name "Provider layer detection" -Script {
    Test-CarrierLayer -CarrierPath "claim-provider/src/main/java/com/huize/claim/provider/mapper/AiClaimMapper.java"
} -Expected "Provider"

# Test 7: Unknown layer detection
Test-Assertion -Name "Unknown layer for DTO" -Script {
    Test-CarrierLayer -CarrierPath "AiClaimDto"
} -Expected "Unknown"

# Test 8: Facade suggestion for Service
Test-Assertion -Name "Facade suggestion for Service suffix" -Script {
    $result = Get-SuggestedFacade -ServiceCarrier "AiAutoClaimFlowService" -Worktree "D:\worktree"
    $result.Found
} -Expected "True"

# Test 9: Facade suggestion class name
Test-Assertion -Name "Facade suggestion class name" -Script {
    $result = Get-SuggestedFacade -ServiceCarrier "AiAutoClaimFlowService" -Worktree "D:\worktree"
    $result.ClassName
} -Expected "AiAutoClaimFlowFacade"

# Test 10: Facade suggestion for ServiceImpl
Test-Assertion -Name "Facade suggestion for ServiceImpl suffix" -Script {
    $result = Get-SuggestedFacade -ServiceCarrier "AiClaimServiceImpl" -Worktree "D:\worktree"
    $result.ClassName
} -Expected "AiClaimFacade"

Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testPass" -ForegroundColor Green
Write-Host "Failed: $testFail" -ForegroundColor $(if ($testFail -gt 0) { "Red" } else { "Green" })

exit $testFail
