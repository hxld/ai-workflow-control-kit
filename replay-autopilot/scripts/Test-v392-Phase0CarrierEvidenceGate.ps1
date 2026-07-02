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

$verifier = Join-Path $PSScriptRoot 'Verify-Phase0CarrierEvidence.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v392-test-" + [guid]::NewGuid().ToString('N'))
$testRoot2 = $null

New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
try {
    $worktree = Join-Path $testRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null

    # Test 1: Hallucinated carrier claim should trigger issue
    $phase0ResultPath = Join-Path $testRoot 'PHASE0_RESULT.md'
    Write-Text $phase0ResultPath @'
# Phase 0 Result

- selected_real_entry: ExampleFlowService.handle(Long caseId, ExampleApplyClaimApiTask task)
- carrier_class: com.example.project.core.ai.service.ExampleFlowService
- carrier_status: EXISTING

## Verified from Current Worktree

**Verified from Current Worktree**:
- `ExampleFlowService.java` exists at example-core/src/main/java/com/example/project/core/ai/service/
- Method signature: `public void handle(Long caseId, ExampleApplyClaimApiTask task)`

## Search Commands Used

```
rg "ExampleAutoClaim" --include "*.java" → Found 6 files including service
```
'@

    $verifyJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Worktree $worktree -ErrorAction SilentlyContinue | ConvertFrom-Json
    Assert-True ($verifyJson.issues -contains 'phase0_selected_real_entry_not_found') "Should detect hallucinated selected_real_entry"
    Assert-True ($verifyJson.issues -contains 'phase0_carrier_claim_hallucinated') "Should detect hallucinated carrier claim"
    Write-Host "PASS: Test 1 - Hallucinated carrier claims detected"

    # Test 2: Missing search commands should trigger issue
    $testRoot2 = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v392-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $testRoot2 | Out-Null
    $worktree2 = Join-Path $testRoot2 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree2 | Out-Null

    $phase0ResultPath2 = Join-Path $testRoot2 'PHASE0_RESULT.md'
    Write-Text $phase0ResultPath2 @'
# Phase 0 Result

- selected_real_entry: SomeService.handle()

## Verified from Current Worktree

**Verified from Current Worktree**:
- `SomeService.java` exists
'@

    $verifyJson2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot2 -Worktree $worktree2 -ErrorAction SilentlyContinue | ConvertFrom-Json
    Assert-True ($verifyJson2.issues -contains 'phase0_carrier_search_commands_missing') "Should detect missing search commands"
    Write-Host "PASS: Test 2 - Missing search commands detected"

    # Test 3: Existing carrier with real file should pass
    $testRoot3 = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v392-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $testRoot3 | Out-Null
    $worktree3 = Join-Path $testRoot3 'worktree\com\example'
    New-Item -ItemType Directory -Force -Path $worktree3 | Out-Null

    # Create a real Java file
    $javaFile = Join-Path $worktree3 'RealService.java'
    Set-Content -LiteralPath $javaFile -Value @'
package com.example;

public class RealService {
    public void handle(Long id) {
        // implementation
    }
}
'@ -Encoding UTF8

    $phase0ResultPath3 = Join-Path $testRoot3 'PHASE0_RESULT.md'
    Write-Text $phase0ResultPath3 @'
# Phase 0 Result

- selected_real_entry: RealService.handle(Long id)
- carrier_class: com.example.RealService
- carrier_status: EXISTING

## Verified from Current Worktree

**Verified from Current Worktree**:
- `RealService.java` exists

## Search Commands Used

```
rg "class RealService" --type java → Found 1 file
```
'@

    $verifyJson3 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot3 -Worktree (Join-Path $testRoot3 'worktree') -ErrorAction SilentlyContinue | ConvertFrom-Json
    Assert-True ($verifyJson3.verification_status -eq 'PASS') "Should pass when carrier exists and search commands recorded"
    Assert-True ($verifyJson3.issues.Count -eq 0) "Should have no issues when all conditions met"
    Write-Host "PASS: Test 3 - Valid carrier evidence passes verification"

    Write-Host "`nPASS: All v392 Phase 0 carrier evidence gate tests passed"
    [ordered]@{ status = 'PASS' } | ConvertTo-Json -Depth 4
    exit 0
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    if ($testRoot2) { Remove-Item -LiteralPath $testRoot2 -Recurse -Force -ErrorAction SilentlyContinue }
    if ($testRoot3) { Remove-Item -LiteralPath $testRoot3 -Recurse -Force -ErrorAction SilentlyContinue }
}
