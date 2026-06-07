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

$scriptRoot = $PSScriptRoot
$verifier = Join-Path $scriptRoot 'Verify-Phase0CarrierEvidence.ps1'
$runner = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$prompt = Join-Path (Split-Path -Parent $scriptRoot) 'prompts\phase0-contract-gate.prompt.md'

$testRoots = [System.Collections.Generic.List[string]]::new()

try {
    # Test 1: NEW/oracle-added selected_real_entry is invalid even when the model records search commands.
    $testRoot1 = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v396-test-" + [guid]::NewGuid().ToString('N'))
    $testRoots.Add($testRoot1) | Out-Null
    $worktree1 = Join-Path $testRoot1 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree1 | Out-Null
    Write-Text (Join-Path $testRoot1 'PHASE0_RESULT.md') @'
# Phase 0 Result

- phase0_status: PROCEED
- selected_real_entry: FutureService.handle(Long id)

## Search Commands Used

```powershell
rg -n "FutureService" "{{WORKTREE}}" --glob "*.java"
# result_summary: 0 hits; FutureService not found in baseline (oracle addition)
rg -n "handle\\(" "{{WORKTREE}}" --glob "*.java"
# result_summary: candidate scan done
rg -n "Facade|Controller|Processor" "{{WORKTREE}}" --glob "*.java"
# result_summary: nearest existing entry not selected
```

## Selected Real Entry

Selected Real Entry: FutureService (NEW oracle addition)
'@

    $verify1 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot1 -Worktree $worktree1 | ConvertFrom-Json
    Assert-True ($verify1.issues -contains 'phase0_selected_real_entry_not_baseline_existing') "Should reject NEW/oracle selected_real_entry"
    Assert-True ($verify1.issues -contains 'phase0_selected_real_entry_not_found') "Should still require selected_real_entry to exist in baseline worktree"
    Write-Host "PASS: Test 1 - NEW/oracle selected_real_entry rejected"

    # Test 2: A real baseline worktree entry with search evidence still passes.
    $testRoot2 = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v396-test-" + [guid]::NewGuid().ToString('N'))
    $testRoots.Add($testRoot2) | Out-Null
    $worktree2 = Join-Path $testRoot2 'worktree\com\example'
    New-Item -ItemType Directory -Force -Path $worktree2 | Out-Null
    Write-Text (Join-Path $worktree2 'ExistingProcessor.java') @'
package com.example;

public class ExistingProcessor {
    public void handle(Long id) {
    }
}
'@
    Write-Text (Join-Path $testRoot2 'PHASE0_RESULT.md') @'
# Phase 0 Result

- phase0_status: PROCEED
- selected_real_entry: ExistingProcessor.handle(Long id)

## Search Commands Used

```powershell
rg -n "class ExistingProcessor" "{{WORKTREE}}" --glob "*.java"
# result_summary: 1 hit; ExistingProcessor.java selected
rg -n "handle\\(" "{{WORKTREE}}" --glob "*.java"
# result_summary: 1 method hit
rg -n "Processor" "{{WORKTREE}}" --glob "*.java"
# result_summary: existing processor candidate selected
```
'@

    $verify2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot2 -Worktree (Join-Path $testRoot2 'worktree') | ConvertFrom-Json
    Assert-True ($verify2.verification_status -eq 'PASS') "Existing baseline selected_real_entry should pass"
    Assert-True ($verify2.issues.Count -eq 0) "Existing baseline selected_real_entry should have no issues"
    Write-Host "PASS: Test 2 - Existing baseline selected_real_entry passes"

    # Test 3: Phase0 prompt explicitly separates selected_real_entry from planned new carriers.
    $promptText = Get-Content -LiteralPath $prompt -Raw -Encoding UTF8
    Assert-True ($promptText -match 'baseline worktree') "Prompt should require baseline worktree selected_real_entry"
    Assert-True ($promptText -match 'planned_new_carrier') "Prompt should route new carriers to planned_new_carrier/family scope"
    Assert-True ($promptText -match 'not found in baseline') "Prompt should reject not-found-in-baseline selected entries"
    Write-Host "PASS: Test 3 - Phase0 prompt has baseline/new-carrier split"

    # Test 4: Runner has a carrier-evidence repair pass before blocking.
    $runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
    Assert-True ($runnerText -match 'PHASE0_CARRIER_EVIDENCE_REPAIR_PROMPT.md') "Runner should create carrier evidence repair prompt"
    Assert-True ($runnerText -match 'phase0_selected_real_entry_not_baseline_existing') "Runner repair prompt should mention baseline-existing issue"
    Assert-True ($runnerText -match 'baseline-worktree existing production entry') "Runner repair prompt should force baseline-worktree existing entry"
    Write-Host "PASS: Test 4 - Runner carrier evidence repair pass present"

    Write-Host "`nPASS: All v396 Phase0 baseline selected entry tests passed"
    [ordered]@{ status = 'PASS' } | ConvertTo-Json -Depth 4
    exit 0
} finally {
    foreach ($root in $testRoots) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
