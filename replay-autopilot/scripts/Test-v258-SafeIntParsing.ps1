$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRoot = Join-Path $env:TEMP ('replay-v258-safe-int-test-{0}' -f ([guid]::NewGuid().ToString('N')))

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Assert-Null {
    param(
        $Value,
        [string]$Message
    )
    if ($null -ne $Value) {
        throw "FAIL: $Message (got '$Value' of type $($Value.GetType().Name))"
    }
}

# Inline copy of Get-SafeInt from Run-SliceLoop.ps1 for direct testing
function Get-SafeInt {
    param(
        [AllowNull()]
        $Value,
        $Default = $null
    )
    if ($null -eq $Value) { return $Default }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double]) { return [int]$Value }
    if ($Value -is [string] -and $Value -match '^\d+$') { return [int]$Value }
    return $Default
}

# Inline copy of Invoke-WithRetry from Run-ReplayLoop.ps1
function Invoke-WithRetry {
    param(
        [scriptblock]$Action,
        [string]$Label = 'executor',
        [int]$MaxRetries = 2,
        [int]$DelaySeconds = 30
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            & $Action
            if ($LASTEXITCODE -eq 0) { return $true }
            if ($attempt -le $MaxRetries) {
                Write-Host "WARNING: $Label failed (exit=$LASTEXITCODE, attempt $attempt/$MaxRetries). Retrying in ${DelaySeconds}s..."
                Start-Sleep -Seconds $DelaySeconds
                continue
            }
            return $false
        } catch {
            if ($attempt -le $MaxRetries) {
                Write-Host "WARNING: $Label threw exception (attempt $attempt/$MaxRetries): $_. Retrying in ${DelaySeconds}s..."
                Start-Sleep -Seconds $DelaySeconds
                continue
            }
            throw
        }
    }
}

$passCount = 0

try {
    # =========================================================================
    # Test 1: Get-SafeInt returns null for "file_presence_only" (the crash value)
    # =========================================================================
    Write-Host 'Test 1: Get-SafeInt("file_presence_only") -> null'
    $result = Get-SafeInt 'file_presence_only'
    Assert-Null $result 'Get-SafeInt should return null for "file_presence_only"'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 2: Get-SafeInt returns correct int for integer input
    # =========================================================================
    Write-Host 'Test 2: Get-SafeInt(60) -> 60'
    $result = Get-SafeInt 60
    Assert-True ($result -eq 60) "Get-SafeInt(60) should return 60, got $result"
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 3: Get-SafeInt returns correct int for string "60"
    # =========================================================================
    Write-Host 'Test 3: Get-SafeInt("60") -> 60'
    $result = Get-SafeInt '60'
    Assert-True ($result -eq 60) "Get-SafeInt('60') should return 60, got $result"
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 4: Get-SafeInt returns null for null input
    # =========================================================================
    Write-Host 'Test 4: Get-SafeInt($null) -> null'
    $result = Get-SafeInt $null
    Assert-Null $result 'Get-SafeInt should return null for null input'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 5: Get-SafeInt returns default for non-numeric string
    # =========================================================================
    Write-Host 'Test 5: Get-SafeInt("not_a_number", -1) -> -1'
    $result = Get-SafeInt 'not_a_number' -Default (-1)
    Assert-True ($result -eq -1) "Get-SafeInt('not_a_number', -1) should return -1, got $result"
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 6: Get-SafeInt handles empty string
    # =========================================================================
    Write-Host 'Test 6: Get-SafeInt("") -> null'
    $result = Get-SafeInt ''
    Assert-Null $result 'Get-SafeInt should return null for empty string'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 7: Get-SafeInt handles decimal (JSON float)
    # =========================================================================
    Write-Host 'Test 7: Get-SafeInt(30.5) -> 30'
    $result = Get-SafeInt 30.5
    Assert-True ($result -eq 30) "Get-SafeInt(30.5) should return 30, got $result"
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 8: Get-SafeInt handles "0"
    # =========================================================================
    Write-Host 'Test 8: Get-SafeInt("0") -> 0'
    $result = Get-SafeInt '0'
    Assert-True ($result -eq 0) "Get-SafeInt('0') should return 0, got $result"
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 9: Get-SafeInt handles "BLOCKED" (another LLM artifact)
    # =========================================================================
    Write-Host 'Test 9: Get-SafeInt("BLOCKED") -> null'
    $result = Get-SafeInt 'BLOCKED'
    Assert-Null $result 'Get-SafeInt should return null for "BLOCKED"'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 10: Simulate the exact crash path - FAMILY_CONTRACT parsing
    #   Verify that the coverage_cap_if_open field from LLM-generated JSON
    #   doesn't crash when processed through the ledger initialization
    # =========================================================================
    Write-Host 'Test 10: Simulate FAMILY_CONTRACT coverage_cap_if_open parsing'
    $jsonText = '{"families":[{"id":"core_entry","required":true,"weight":100,"coverage_cap_if_open":null},{"id":"deploy_export_page","required":false,"weight":30,"coverage_cap_if_open":"file_presence_only"}]}'
    $contract = $jsonText | ConvertFrom-Json
    foreach ($family in $contract.families) {
        $cap = Get-SafeInt $family.coverage_cap_if_open
        # Should not throw for any value
    }
    $deployCap = Get-SafeInt ($contract.families | Where-Object { $_.id -eq 'deploy_export_page' }).coverage_cap_if_open
    Assert-Null $deployCap 'deploy_export_page coverage_cap should be null (not crash)'
    $coreCap = Get-SafeInt ($contract.families | Where-Object { $_.id -eq 'core_entry' }).coverage_cap_if_open
    Assert-Null $coreCap 'core_entry coverage_cap should be null'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 11: Verify v257 regression still holds
    # =========================================================================
    Write-Host 'Test 11: v257 forbidden_substitute_check regression'
    $t11Root = Join-Path $tempRoot 'test11-v257-regression'
    New-Item -ItemType Directory -Force -Path $t11Root | Out-Null
    $planFiles = @(
        'PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md',
        'PLAN_RESULT.md', 'PLAN_SELECTION.md', 'REPLAY_PLAN.md',
        'IMPLEMENTATION_CONTRACT.md', 'EXPECTED_DIFF_MATRIX.md',
        'SIDE_EFFECT_LEDGER.md', 'TEST_CHARTER.md', 'FIRST_SLICE_PROOF_PLAN.md'
    )
    foreach ($file in $planFiles) {
        Set-Content -LiteralPath (Join-Path $t11Root $file) -Value '' -Encoding UTF8
    }
    @"
- plan_status: PROCEED
- selected_strategy: core_path
- first_slice: S1
- first_red_test: T1
"@ | Set-Content -LiteralPath (Join-Path $t11Root 'PLAN_RESULT.md') -Encoding UTF8
    @"
## Selected Real Entry

Primary Entry: SomeFacade.someMethod(SomeParam)
"@ | Set-Content -LiteralPath (Join-Path $t11Root 'IMPLEMENTATION_CONTRACT.md') -Encoding UTF8
    @"
- forbidden_substitute_check: Must verify no Mock/Stub is used
- proof_kind: real_entry_behavior
- real_carrier_kind: production_entry_or_service
"@ | Set-Content -LiteralPath (Join-Path $t11Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8
    @{families=@(@{id='core_entry';required=$true})} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t11Root 'FAMILY_CONTRACT.json') -Encoding UTF8

    $result11 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t11Root -Stage Plan 2>&1
    $verify11 = $result11 | ConvertFrom-Json
    $hasFsc = @($verify11.issues | Where-Object { $_ -like '*forbidden_substitute_check_not_passed*' }).Count -gt 0
    Assert-True ($hasFsc) 'v257 forbidden_substitute_check must still catch descriptive text after v258 changes'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 12: Invoke-WithRetry retries on transient failure and succeeds
    # =========================================================================
    Write-Host 'Test 12: Invoke-WithRetry retries transient failure'
    $retryCount = 0
    $retryResult = Invoke-WithRetry -Label 'test-retry' -MaxRetries 2 -DelaySeconds 1 -Action {
        $script:retryCount++
        if ($script:retryCount -lt 2) {
            # Simulate transient failure
            & cmd /c 'exit 1'
        } else {
            & cmd /c 'exit 0'
        }
    }
    Assert-True ($retryResult -eq $true) 'Invoke-WithRetry should return true after retry succeeds'
    Assert-True ($retryCount -ge 2) "Invoke-WithRetry should have retried, got $retryCount attempts"
    Write-Host "  PASS (attempts=$retryCount)"
    $passCount++

    # =========================================================================
    # Test 13: Invoke-WithRetry returns false when all retries exhausted
    # =========================================================================
    Write-Host 'Test 13: Invoke-WithRetry returns false after max retries'
    $failCount = 0
    $failResult = Invoke-WithRetry -Label 'test-fail' -MaxRetries 1 -DelaySeconds 1 -Action {
        $script:failCount++
        & cmd /c 'exit 1'
    }
    Assert-True ($failResult -eq $false) 'Invoke-WithRetry should return false when all retries fail'
    Assert-True ($failCount -ge 2) "Invoke-WithRetry should have tried at least twice (1 initial + 1 retry), got $failCount"
    Write-Host "  PASS (attempts=$failCount)"
    $passCount++

    # =========================================================================
    # Test 14: real_carrier_kind: production_entity -> rejected by verifier
    #   This was the v258 canary failure - LLM invented production_entity
    # =========================================================================
    Write-Host 'Test 14: real_carrier_kind: production_entity -> verifier rejects'
    $t14Root = Join-Path $tempRoot 'test14-invalid-carrier'
    New-Item -ItemType Directory -Force -Path $t14Root | Out-Null
    $planFiles = @(
        'PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md',
        'PLAN_RESULT.md', 'PLAN_SELECTION.md', 'REPLAY_PLAN.md',
        'IMPLEMENTATION_CONTRACT.md', 'EXPECTED_DIFF_MATRIX.md',
        'SIDE_EFFECT_LEDGER.md', 'TEST_CHARTER.md', 'FIRST_SLICE_PROOF_PLAN.md'
    )
    foreach ($file in $planFiles) {
        Set-Content -LiteralPath (Join-Path $t14Root $file) -Value '' -Encoding UTF8
    }
    @"
- plan_status: PROCEED
- selected_strategy: core_path
- first_slice: S1
- first_red_test: T1
"@ | Set-Content -LiteralPath (Join-Path $t14Root 'PLAN_RESULT.md') -Encoding UTF8
    @"
## Selected Real Entry

Primary Entry: SomeFacade.someMethod(SomeParam)
"@ | Set-Content -LiteralPath (Join-Path $t14Root 'IMPLEMENTATION_CONTRACT.md') -Encoding UTF8
    @"
- forbidden_substitute_check: passed
- proof_kind: real_entry_behavior
- real_carrier_kind: production_entity
- minimum_side_effect_or_blocker: facade call triggers service method
"@ | Set-Content -LiteralPath (Join-Path $t14Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8
    @{families=@(@{id='core_entry';required=$true})} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t14Root 'FAMILY_CONTRACT.json') -Encoding UTF8

    $result14 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t14Root -Stage Plan 2>&1
    $verify14 = $result14 | ConvertFrom-Json
    $hasCarrierIssue = @($verify14.issues | Where-Object { $_ -like '*real_carrier_kind*' }).Count -gt 0
    Assert-True ($hasCarrierIssue) 'real_carrier_kind: production_entity MUST trigger real_carrier_kind issue'
    Write-Host '  PASS'
    $passCount++
    Write-Host ''
    Write-Host "Test-v258-SafeIntParsing: $passCount passed, all passed"

} catch {
    Write-Host "UNEXPECTED ERROR: $_"
    Write-Host "Test-v258-SafeIntParsing: $passCount passed, 1 failed"
    exit 1
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
