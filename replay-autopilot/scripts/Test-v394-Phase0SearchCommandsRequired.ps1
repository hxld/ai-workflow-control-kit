param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Text {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID'; suite = 'v394_phase0_search_commands_required' } | ConvertTo-Json -Depth 4
    exit 0
}

$root = Split-Path -Parent $PSScriptRoot
$phase0Prompt = Join-Path $root 'prompts\phase0-contract-gate.prompt.md'
$runner = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
$verifier = Join-Path $PSScriptRoot 'Verify-Phase0CarrierEvidence.ps1'

$phase0PromptText = Get-Content -LiteralPath $phase0Prompt -Raw -Encoding UTF8
$runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8

Assert-True ($phase0PromptText.Contains('## Search Commands Used')) 'Phase0 prompt must require PHASE0_RESULT search command section'
Assert-True ($phase0PromptText.Contains('Phase0 carrier evidence gate')) 'Phase0 prompt must state runner enforcement'
Assert-True -Condition (([regex]::Matches($phase0PromptText, 'rg\s+-n')).Count -ge 3) -Message 'Phase0 prompt must require multiple rg commands'
Assert-True ($phase0PromptText.Contains('result_summary')) 'Phase0 prompt must require result_summary'
Assert-True ($runnerText.Contains('PHASE0_RESULT.md must contain an exact heading ## Search Commands Used')) 'Phase0 repair prompt must require exact Search Commands heading'
Assert-True ($runnerText.Contains('phase0_carrier_search_commands_missing')) 'Phase0 repair prompt must route the concrete verifier issue'
Assert-True ($runnerText.Contains('at least three reproducible rg commands')) 'Phase0 repair prompt must require reproducible rg commands'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v394-test-" + [guid]::NewGuid().ToString('N'))
try {
    $worktree = Join-Path $testRoot 'worktree\com\example'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    Write-Text (Join-Path $worktree 'RealService.java') @'
package com.example;

public class RealService {
    public void handle(Long id) {
    }
}
'@

    Write-Text (Join-Path $testRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

- phase0_status: PROCEED
- selected_real_entry: RealService.handle(Long id)
- carrier_class: com.example.RealService
- carrier_status: EXISTING

## Verified from Current Worktree

- `RealService.java` exists

## Search Commands Used

rg -n "class RealService" worktree --glob "*.java"
rg -n "void handle" worktree --glob "*.java"
rg -n "RealService.handle" worktree --glob "*.java"

- result_summary: class search found 1 Java carrier; method search found handle(Long id); selected RealService.handle and excluded none.
'@

    $verifyJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Worktree (Join-Path $testRoot 'worktree') | ConvertFrom-Json
    Assert-True ($verifyJson.verification_status -eq 'PASS') 'Verifier should pass when PHASE0_RESULT records rg commands and carrier exists'
    Assert-True ($verifyJson.issues.Count -eq 0) 'Verifier should have no issues for valid Phase0 carrier evidence'
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: v394 Phase0 search commands required tests passed'
[ordered]@{ status = 'PASS'; assertions = 9 } | ConvertTo-Json -Depth 4
