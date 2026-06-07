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
$runner = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v420-test-" + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $testRoot 'worktree'
    $taskDir = Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task'
    New-Item -ItemType Directory -Force -Path $taskDir | Out-Null

    Write-Text (Join-Path $taskDir 'AiCalculateLossApiTaskProcessor.java') @'
package com.huize.claim.core.ai.task;

public class AiCalculateLossApiTaskProcessor {
    public void handleTaskResponse(AiCalculateLossApiTask task, AiCalculateLossApiTaskResponse response) {
    }
}
class AiCalculateLossApiTask {}
class AiCalculateLossApiTaskResponse {}
'@

    Write-Text (Join-Path $testRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

`phase0_status`: PROCEED

# Selected Real Entry

```
category: core_entry
primary: AiCalculateLossApiTaskProcessor.handleTaskResponse
baseline_existing: true
confidence: HIGH
```

# Search Commands Used

```
rg -n "class.*AiCalculateLossApiTaskProcessor" --glob "*.java" worktree
rg -n "handleTaskResponse" --glob "*AiCalculateLossApiTaskProcessor*.java" worktree
rg -n "AiCalculateLossApiTaskProcessor|handleTaskResponse" --glob "*.java" worktree
```

- result_summary: 3 search commands executed; selected AiCalculateLossApiTaskProcessor.handleTaskResponse and excluded no baseline carrier.
'@

    $verifyJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Worktree $worktree | ConvertFrom-Json
    Assert-True ($verifyJson.verification_status -eq 'PASS') 'Verifier should pass single-# Search Commands and Selected Real Entry primary format'
    Assert-True ([string]$verifyJson.selected_real_entry -eq 'AiCalculateLossApiTaskProcessor.handleTaskResponse') 'Verifier should parse primary selected real entry'

    Write-Text (Join-Path $testRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

`phase0_status`: PROCEED

# Selected Core Path

**Selected Real Entry**: `com.huize.claim.core.ai.task.AiCalculateLossApiTaskProcessor.handleTaskResponse`

**Carrier Status**: EXISTING

# Search Commands Used

```
rg -n "class.*AiCalculateLossApiTaskProcessor" --glob "*.java" worktree
rg -n "handleTaskResponse" --glob "*.java" worktree
rg -n "AiCalculateLossApiTaskProcessor|handleTaskResponse" --glob "*.java" worktree
```

- result_summary: selected entry exists in baseline worktree.
'@

    $verifyJson2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Worktree $worktree | ConvertFrom-Json
    Assert-True ($verifyJson2.verification_status -eq 'PASS') 'Verifier should pass real v419 Selected Core Path format'
    Assert-True ([string]$verifyJson2.selected_real_entry -eq 'AiCalculateLossApiTaskProcessor.handleTaskResponse') 'Verifier should normalize package-qualified selected entry'

    $runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
    Assert-True ($runnerText -match 'function\s+Repair-Phase0ManualOracleWaitText') 'Runner should define Phase0 oracle-wait sanitizer'
    Assert-True ($runnerText -match 'until\\s\+oracle\\s\+verification') 'Sanitizer should handle "until oracle verification" text'
    $invocationCount = ([regex]::Matches($runnerText, 'Repair-Phase0ManualOracleWaitText\s+-ReplayRoot\s+\$replayRoot')).Count
    Assert-True ($invocationCount -ge 3) 'Runner should sanitize before initial verification and repair re-verifications'

    Write-Host 'PASS: v420 Phase0 repair/parser robustness tests passed'
    [ordered]@{ status = 'PASS'; assertions = 7 } | ConvertTo-Json -Depth 4
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
