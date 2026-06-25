# v646: selected_carrier_from_search may be concrete path evidence.
# The verifier must validate the Java class leaf, not the module/path prefix.
param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$verifier = Join-Path (Split-Path -Parent $PSScriptRoot) 'Verify-PlanContract.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v646-carrier-path-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$assertions = 0
try {
    $validRoot = Join-Path $tmp 'valid-path-carrier'
    $validWorktree = Join-Path $validRoot 'worktree'
    $carrierFile = Join-Path $validWorktree 'app-core\src\main\java\com\example\GenericTaskProcessor.java'
    Write-Utf8 $carrierFile @'
package com.example;

public class GenericTaskProcessor {
    public void handleTaskResponse() {
    }
}
'@
    Write-Utf8 (Join-Path $validRoot 'PLAN_RESULT.md') @'
# Plan Result

plan_status: PROCEED
carrier_search: performed
carrier_search_queries: rg -n "class GenericTaskProcessor" app-core/src/main/java --glob "*.java"; rg -n "handleTaskResponse\(" app-core/src/main/java --glob "*.java"; rg -n "TaskProcessor" app-core/src/main/java --glob "*.java"
existing_production_carriers: app-core/src/main/java/com/example/GenericTaskProcessor.java:7 GenericTaskProcessor.handleTaskResponse
selected_carrier_from_search: app-core/src/main/java/com/example/GenericTaskProcessor.java:7 GenericTaskProcessor.handleTaskResponse
new_service_proposed: false
first_slice: S1_core_entry
first_red_test: ExampleTest#red
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $validRoot -Stage Plan -Worktree $validWorktree -ErrorAction SilentlyContinue | Out-Null
    $validVerify = Get-Content -LiteralPath (Join-Path $validRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($validVerify.issues) -notcontains 'carrier_search_selected_carrier_not_found_in_codebase') "Path-shaped carrier should resolve to class leaf, issues=$(@($validVerify.issues) -join ';')"
    $assertions++
    Assert-True ((@($validVerify.warnings) -join "`n") -match "GenericTaskProcessor'.*found") "Warning should show resolved class leaf, warnings=$(@($validVerify.warnings) -join ';')"
    $assertions++

    $missingRoot = Join-Path $tmp 'missing-path-carrier'
    $missingWorktree = Join-Path $missingRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $missingWorktree | Out-Null
    Write-Utf8 (Join-Path $missingRoot 'PLAN_RESULT.md') @'
# Plan Result

plan_status: PROCEED
carrier_search: performed
carrier_search_queries: rg -n "class MissingCarrier" app-core/src/main/java --glob "*.java"; rg -n "handle\(" app-core/src/main/java --glob "*.java"; rg -n "TaskProcessor" app-core/src/main/java --glob "*.java"
existing_production_carriers: app-core/src/main/java/com/example/MissingCarrier.java:7 MissingCarrier.handle
selected_carrier_from_search: app-core/src/main/java/com/example/MissingCarrier.java:7 MissingCarrier.handle
new_service_proposed: false
first_slice: S1_core_entry
first_red_test: ExampleTest#red
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $missingRoot -Stage Plan -Worktree $missingWorktree -ErrorAction SilentlyContinue | Out-Null
    $missingVerify = Get-Content -LiteralPath (Join-Path $missingRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($missingVerify.issues) -contains 'carrier_search_selected_carrier_not_found_in_codebase') "Missing path-shaped carrier should still fail closed"
    $assertions++
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PASS: v646 carrier path existence normalization - $assertions assertions"
[ordered]@{
    status = 'PASS'
    assertions = $assertions
    cases = @(
        'path_shaped_selected_carrier_resolves_java_class_leaf',
        'missing_path_shaped_selected_carrier_still_fails_closed'
    )
} | ConvertTo-Json -Depth 5
