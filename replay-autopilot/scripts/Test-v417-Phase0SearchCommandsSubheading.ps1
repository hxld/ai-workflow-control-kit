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
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v417-test-" + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $testRoot 'worktree'
    $serviceDir = Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\service'
    New-Item -ItemType Directory -Force -Path $serviceDir | Out-Null

    Write-Text (Join-Path $serviceDir 'ExampleModuleConfigService.java') @'
package com.example.project.core.ai.service;

public class ExampleModuleConfigService {
    public void save(ExampleModuleConfigDto example-featureModuleConfigDto) {
    }
}
'@

    Write-Text (Join-Path $testRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

- phase0_status: PROCEED
- selected_real_entry: ExampleModuleConfigService.save(ExampleModuleConfigDto)
- carrier_class: com.example.project.core.ai.service.ExampleModuleConfigService
- carrier_status: EXISTING

## Verified from Current Worktree

- `ExampleModuleConfigService.java` exists

## Search Commands Used

### Command 1: verify selected entry ```bash
rg "public void save\(ExampleModuleConfigDto example-featureModuleConfigDto\)" worktree --glob "*.java"
```
- result_summary: 1 match at example-core/src/main/java/com/example/project/core/ai/service/ExampleModuleConfigService.java:4

### Command 2: verify carrier class ```bash
rg "class ExampleModuleConfigService" worktree --glob "*.java"
```
- result_summary: 1 match at example-core/src/main/java/com/example/project/core/ai/service/ExampleModuleConfigService.java:3

### Command 3: search related config carriers ```bash
rg -i "ExampleModuleConfig" worktree --glob "*.java"
```
- result_summary: 1 file found; selected ExampleModuleConfigService.save and excluded no baseline carriers.

## Next Actions

- Continue to Plan.
'@

    $verifyJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Worktree $worktree | ConvertFrom-Json
    Assert-True ($verifyJson.issues -notcontains 'phase0_carrier_search_commands_missing') 'Verifier should not treat ### subheadings as end of Search Commands Used section'
    Assert-True ($verifyJson.verification_status -eq 'PASS') 'Verifier should pass when selected entry and rg commands are present'

    Write-Host 'PASS: v417 Phase0 search command subheading test passed'
    [ordered]@{ status = 'PASS'; assertions = 2 } | ConvertTo-Json -Depth 4
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
