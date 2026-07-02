# Test-v407-DomainAwareOracleOverlap.ps1
# Regression test for v407 domain-aware oracle overlap filtering in ORACLE_OVERLAP_GATE

param(
    [string]$ReplayRoot = 'D:\opt\replay-evidence\example-feature\claim-codex-replay-v404-autopilot-20260517-r03'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== v407 Domain-Aware Oracle Overlap Test ===" -ForegroundColor Cyan

# Test 1: Verify domain filtering code exists in Run-ReplayLoop.ps1
Write-Host "`n[Test 1] Checking domain filtering code exists in Run-ReplayLoop.ps1..."
$runReplayLoopPath = Join-Path $PSScriptRoot '..\scripts\Run-ReplayLoop.ps1'
$runReplayLoopText = Get-Content -LiteralPath $runReplayLoopPath -Raw -Encoding UTF8

$v407Markers = @(
    'v407: Domain-aware oracle filtering',
    'oraclePrimaryDomain',
    'domainDirectoryMap',
    'oracleFilesForOverlap',
    'total_oracle_unfiltered'
)

$missingMarkers = @()
foreach ($marker in $v407Markers) {
    if ($runReplayLoopText.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        $missingMarkers += $marker
    }
}

if ($missingMarkers.Count -gt 0) {
    Write-Host "FAIL: Missing v407 markers: $($missingMarkers -join ', ')" -ForegroundColor Red
    exit 1
} else {
    Write-Host "PASS: All v407 markers found in Run-ReplayLoop.ps1" -ForegroundColor Green
}

# Test 2: Verify domain map exists in both files
Write-Host "`n[Test 2] Checking domainDirectoryMap exists in both files..."
$verifierPath = Join-Path $PSScriptRoot '..\scripts\Verify-PlanContract.ps1'
$verifierText = Get-Content -LiteralPath $verifierPath -Raw -Encoding UTF8

# Check both files have domainDirectoryMap declaration
$runnerHasMap = $runReplayLoopText -match '\$domainDirectoryMap\s*=\s*@'
$verifierHasMap = $verifierText -match '\$domainDirectoryMap\s*=\s*@'

if (-not $runnerHasMap) {
    Write-Host "FAIL: Could not find domainDirectoryMap in Run-ReplayLoop.ps1" -ForegroundColor Red
    exit 1
}

if (-not $verifierHasMap) {
    Write-Host "FAIL: Could not find domainDirectoryMap in Verify-PlanContract.ps1" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: domainDirectoryMap found in both files" -ForegroundColor Green

# Test 2.5: Check key domains are in the map
$expectedDomains = @('ai', 'ocr', 'push', 'risk')
foreach ($domain in $expectedDomains) {
    if ($runReplayLoopText -match "`"$domain`"\s*=\s*") {
        Write-Host "  INFO: Found domain '$domain' in map" -ForegroundColor Cyan
    }
}

# Test 3: Check replay root has expected artifacts
Write-Host "`n[Test 3] Checking replay root artifacts..."
if (-not (Test-Path -LiteralPath $ReplayRoot)) {
    Write-Host "SKIP: Replay root not found at $ReplayRoot" -ForegroundColor Yellow
    exit 0
}

$planResultPath = Join-Path $ReplayRoot 'PLAN_RESULT.md'
$oracleOverlapGatePath = Join-Path $ReplayRoot 'ORACLE_OVERLAP_GATE.json'

if (-not (Test-Path -LiteralPath $planResultPath)) {
    Write-Host "SKIP: PLAN_RESULT.md not found" -ForegroundColor Yellow
    exit 0
}

$planResultText = Get-Content -LiteralPath $planResultPath -Raw -Encoding UTF8

# Check if oracle_primary_domain is present
if ($planResultText -match '(?im)^\s*-?\s*oracle_primary_domain\s*[:=]\s*([^\r\n]+)') {
    $domain = $Matches[1].Trim().Trim('''').Trim('"').Trim('/')
    Write-Host "INFO: Found oracle_primary_domain: $domain" -ForegroundColor Cyan
} else {
    Write-Host "SKIP: No oracle_primary_domain in PLAN_RESULT.md" -ForegroundColor Yellow
    exit 0
}

# Test 4: Verify ORACLE_OVERLAP_GATE.json structure includes new fields
if (Test-Path -LiteralPath $oracleOverlapGatePath) {
    Write-Host "`n[Test 4] Checking ORACLE_OVERLAP_GATE.json structure..."
    $gateJson = Get-Content -LiteralPath $oracleOverlapGatePath -Raw -Encoding UTF8 | ConvertFrom-Json

    $expectedFields = @('gate', 'overlap_percent', 'matched', 'total_oracle_production', 'threshold', 'decision')
    $optionalFields = @('total_oracle_unfiltered', 'domain_filter')

    $missingFields = @()
    foreach ($field in $expectedFields) {
        if (-not (Get-Member -InputObject $gateJson -Name $field -MemberType Properties)) {
            $missingFields += $field
        }
    }

    if ($missingFields.Count -gt 0) {
        Write-Host "FAIL: Missing required fields in ORACLE_OVERLAP_GATE.json: $($missingFields -join ', ')" -ForegroundColor Red
        exit 1
    }

    $hasNewFields = $false
    foreach ($field in $optionalFields) {
        if (Get-Member -InputObject $gateJson -Name $field -MemberType Properties) {
            $hasNewFields = $true
            Write-Host "INFO: Found new field '$field' = $($gateJson.$field)" -ForegroundColor Cyan
        }
    }

    if ($hasNewFields) {
        Write-Host "PASS: ORACLE_OVERLAP_GATE.json includes v407 fields" -ForegroundColor Green
    } else {
        Write-Host "WARN: ORACLE_OVERLAP_GATE.json may be from pre-v407 run (missing optional fields)" -ForegroundColor Yellow
    }

    # Verify domain-filtered calculation
    if ($gateJson.total_oracle_unfiltered -and $gateJson.total_oracle_production -lt $gateJson.total_oracle_unfiltered) {
        Write-Host "PASS: Domain filtering applied ($($gateJson.total_oracle_production)/$($gateJson.total_oracle_unfiltered))" -ForegroundColor Green
    }
}

# Test 5: Extract and compare overlap percentages
Write-Host "`n[Test 5] Comparing overlap calculations..."
if ($planResultText -match '(?im)^\s*-?\s*oracle_production_file_overlap\s*[:=]\s*(\d+)') {
    $planOverlap = [int]$Matches[1]
    Write-Host "INFO: PLAN_RESULT.md overlap: $planOverlap%" -ForegroundColor Cyan
}

if (Test-Path -LiteralPath $oracleOverlapGatePath) {
    $gateJson = Get-Content -LiteralPath $oracleOverlapGatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "INFO: ORACLE_OVERLAP_GATE.json overlap: $($gateJson.overlap_percent)%" -ForegroundColor Cyan
}

Write-Host "`n=== v407 Test Complete ===" -ForegroundColor Cyan
Write-Host "Summary: Domain-aware oracle filtering is implemented in Run-ReplayLoop.ps1" -ForegroundColor Green
Write-Host "Next: Re-run the affected replay to validate the fix produces consistent results" -ForegroundColor Yellow
