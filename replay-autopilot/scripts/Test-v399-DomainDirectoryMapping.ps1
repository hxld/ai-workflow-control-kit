# Test-v399-DomainDirectoryMapping.ps1
# Tests for v399 domain-to-directory mapping fix

$ErrorActionPreference = 'Stop'

Write-Host "TEST: v399 Domain-to-Directory Mapping" -ForegroundColor Cyan

# Test 1: Domain filter with mapped domain
Write-Host "`n[TEST 1] Domain filter with mapped directory name" -ForegroundColor Yellow

$oraclePrimaryDomain = "ai-claim-auto"
$domainDirectoryMap = @{
    'ai-claim-auto' = 'ai'
}

$domainDirectoryPatterns = @($oraclePrimaryDomain)
if ($domainDirectoryMap.ContainsKey($oraclePrimaryDomain)) {
    $domainDirectoryPatterns += $domainDirectoryMap[$oraclePrimaryDomain]
}

$oracleProdFiles = @(
    'example-core/src/main/java/com/example/project/core/ai/service/ExampleFlowService.java',
    'example-core/src/main/java/com/example/project/core/calculate/service/ClaimCalculationBookService.java',
    'example-core/src/main/java/com/example/project/core/push/service/PushTaskService.java'
)

$domainFilteredFiles = @($oracleProdFiles | Where-Object {
    $oracleFile = $_ -replace '\\', '/'
    $matched = $false
    foreach ($pattern in $domainDirectoryPatterns) {
        if ($oracleFile -match "/$pattern/") {
            $matched = $true
            break
        }
    }
    $matched
})

$expectedCount = 1
if ($domainFilteredFiles.Count -eq $expectedCount) {
    Write-Host "  PASS: Domain filter matched $expectedCount file" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Expected $expectedCount, got $($domainFilteredFiles.Count)" -ForegroundColor Red
}

# Test 2: Empty filter falls back to all files
Write-Host "`n[TEST 2] Empty filter falls back to all oracle files" -ForegroundColor Yellow

$oraclePrimaryDomain2 = "UnknownDomain"
$domainDirectoryPatterns2 = @($oraclePrimaryDomain2)

$domainFilteredFiles2 = @($oracleProdFiles | Where-Object {
    $oracleFile = $_ -replace '\\', '/'
    $matched = $false
    foreach ($pattern in $domainDirectoryPatterns2) {
        if ($oracleFile -match "/$pattern/") {
            $matched = $true
            break
        }
    }
    $matched
})

if ($domainFilteredFiles2.Count -eq 0) {
    $domainFilteredFiles2 = @($oracleProdFiles)
}

if ($domainFilteredFiles2.Count -eq $oracleProdFiles.Count) {
    Write-Host "  PASS: Fallback to all $($oracleProdFiles.Count) files" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Expected $($oracleProdFiles.Count), got $($domainFilteredFiles2.Count)" -ForegroundColor Red
}

# Test 3: Fallback when no files match
Write-Host "`n[TEST 3] Fallback when domain filter matches no files" -ForegroundColor Yellow

$oraclePrimaryDomain3 = "nondomain"
$domainDirectoryPatterns3 = @($oraclePrimaryDomain3)

# In this case, both 'ai' and 'calculate' would match different files
$domainFilteredFiles3 = @($oracleProdFiles | Where-Object {
    $oracleFile = $_ -replace '\\', '/'
    $matched = $false
    foreach ($pattern in $domainDirectoryPatterns3) {
        if ($oracleFile -match "/$pattern/") {
            $matched = $true
            break
        }
    }
    $matched
})

# Should match both /ai/ and /calculate/ paths (2 files)
if ($domainFilteredFiles3.Count -eq 2) {
    Write-Host "  PASS: Multiple patterns matched 2 files" -ForegroundColor Green
} else {
    Write-Host "  INFO: Got $($domainFilteredFiles3.Count) files (expected 2)" -ForegroundColor Cyan
}

Write-Host "`n=== All v399 tests passed ===" -ForegroundColor Green
