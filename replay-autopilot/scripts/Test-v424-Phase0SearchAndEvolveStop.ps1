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
$controller = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v424-test-" + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $testRoot 'worktree'
    $serviceDir = Join-Path $worktree 'example-core\src\main\java\com\example'
    New-Item -ItemType Directory -Force -Path $serviceDir | Out-Null

    Write-Text (Join-Path $serviceDir 'RealService.java') @'
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

```powershell
# Search for selected_real_entry
rg "class RealService|void handle\(Long id\)" worktree --glob "*.java"
# result_summary: FOUND - example-core/src/main/java/com/example/RealService.java

# Search related carriers
rg -i "RealService" worktree --glob "*.java"
# result_summary: FOUND 1 file

# Search sibling services
rg -i "class .*Service" worktree --glob "*.java"
# result_summary: FOUND RealService
```

## Next Actions

- Continue to Plan.
'@

    $verifyJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Worktree $worktree | ConvertFrom-Json
    Assert-True ($verifyJson.issues -notcontains 'phase0_carrier_search_commands_missing') 'Verifier must not stop Search Commands Used at shell comments inside a fenced block'
    Assert-True ($verifyJson.verification_status -eq 'PASS') 'Verifier should pass with fenced rg commands and an existing carrier'

    $controllerText = Get-Content -LiteralPath $controller -Raw -Encoding UTF8
    Assert-True ($controllerText -match '\$evolveWithoutVersionAdvance\s*=') 'Controller should compute evolveWithoutVersionAdvance'
    Assert-True ($controllerText -match 'EVOLVE_REQUIRED_WITHOUT_VERSION_ADVANCE') 'Controller should expose a stop status for EVOLVE without version advance'
    Assert-True ($controllerText -match '\-not \$evolveWithoutVersionAdvance') 'Controller should block continuation when EVOLVE did not advance knowledge version'

    Write-Host 'PASS: v424 Phase0 search command parsing and EVOLVE no-version stop tests passed'
    [ordered]@{ status = 'PASS'; assertions = 5 } | ConvertTo-Json -Depth 4
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
