#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for forbidden dependency drift fail-closed behavior.

.DESCRIPTION
Builds a minimal replay fixture where a DONE slice reports pom.xml in
current_slice_changed_files. The real Verify-SliceClosure and SliceVerifier
scripts must reject the slice, zero its coverage delta, cap coverage at 10,
and emit remediation metadata.
#>

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ReplayRoot = Join-Path $RepoRoot '.tmp\v625-forbidden-dependency-drift-guard'
$Worktree = Join-Path $ReplayRoot 'worktree'
$SliceResultPath = Join-Path $ReplayRoot 'SLICE_RESULT_01.json'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function Assert-Contains {
    param(
        $Actual,
        [string]$Expected,
        [string]$Message
    )
    $values = @($Actual | ForEach-Object { [string]$_ })
    if ($values -notcontains $Expected) {
        throw "Assertion failed: $Message. Missing '$Expected'. Actual: $($values -join ', ')"
    }
}

function Read-JsonObject {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

Write-Host "========================================"
Write-Host "Test v625: Forbidden Dependency Drift Guard"
Write-Host "========================================"

if (Test-Path -LiteralPath $ReplayRoot) {
    Remove-Item -LiteralPath $ReplayRoot -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path (Join-Path $Worktree 'src\main\java\com\example') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Worktree 'src\test\java\com\example') | Out-Null

Set-Content -LiteralPath (Join-Path $Worktree 'pom.xml') -Encoding UTF8 -Value @'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>fixture</artifactId>
  <version>1.0-SNAPSHOT</version>
</project>
'@
Set-Content -LiteralPath (Join-Path $Worktree 'src\main\java\com\example\ExampleProcessor.java') -Encoding UTF8 -Value @'
package com.example;

public class ExampleProcessor {
    public String handle(String value) {
        return value == null ? "missing" : value.trim();
    }
}
'@
Set-Content -LiteralPath (Join-Path $Worktree 'src\test\java\com\example\ExampleProcessorTest.java') -Encoding UTF8 -Value @'
package com.example;

public class ExampleProcessorTest {
    public void trimsInput() {
        if (!"ok".equals(new ExampleProcessor().handle(" ok "))) {
            throw new AssertionError("expected trimmed value");
        }
    }
}
'@

& git -C $Worktree init | Out-Null
if ($LASTEXITCODE -ne 0) { throw "git init failed" }

$sliceChangedFiles = @(
    'src/main/java/com/example/ExampleProcessor.java',
    'src/test/java/com/example/ExampleProcessorTest.java',
    'pom.xml'
)
$sliceResult = [ordered]@{
    slice_index = 1
    slice_status = 'DONE'
    slice_type = 'stateful_success_slice'
    target_subsurface_or_carrier = 'ExampleProcessor.handle'
    production_boundary = 'ExampleProcessor#handle'
    proof_kind = 'stateful_side_effect'
    red_expectation = 'RED test fails before the production behavior is fixed'
    touched_requirement_families = @('core_entry')
    closed_requirement_families = @('core_entry')
    implemented_files = @($sliceChangedFiles)
    current_slice_changed_files = @($sliceChangedFiles)
    round_changed_files_snapshot = @($sliceChangedFiles)
    gap_flags = @()
    coverage_delta = 40
    test_compilation_exit_code = 0
    test_execution_exit_code = 0
    tests = @(
        [ordered]@{
            phase = 'RED'
            result = 'fail'
            command = 'mvn -f worktree/pom.xml -Dtest=ExampleProcessorTest#trimsInput test'
            evidence = 'AssertionError before production fix'
        },
        [ordered]@{
            phase = 'GREEN'
            result = 'pass'
            command = 'mvn -f worktree/pom.xml -Dtest=ExampleProcessorTest#trimsInput test'
            evidence = 'BUILD SUCCESS'
        }
    )
}
$sliceResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SliceResultPath -Encoding UTF8

Write-Host "[1/4] Running Verify-SliceClosure fixture..."
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\Verify-SliceClosure.ps1') `
    -ReplayRoot $ReplayRoot `
    -Worktree $Worktree `
    -SliceResult $SliceResultPath `
    -SliceIndex 1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Verify-SliceClosure.ps1 failed with exit code $LASTEXITCODE" }

$verifyPath = Join-Path $ReplayRoot 'SLICE_VERIFY_01.json'
$verify = Read-JsonObject -Path $verifyPath
Assert-Contains -Actual $verify.gap_flags -Expected 'forbidden_dependency_drift_gap' -Message 'Verify gap flags must include forbidden dependency drift'
Assert-Contains -Actual $verify.gap_flags -Expected 'tooling_enforcement_stop' -Message 'Verify gap flags must include tooling enforcement stop'
Assert-Contains -Actual $verify.blocking_gap_flags -Expected 'forbidden_dependency_drift_gap' -Message 'Forbidden dependency drift must be a blocking gap'
Assert-True -Condition (-not [bool]$verify.authorized_for_next_slice) -Message 'Slice must not be authorized for next slice'
Assert-True -Condition (-not [bool]$verify.authorized_for_synthesis) -Message 'Slice must not be authorized for synthesis'
Assert-True -Condition (-not [bool]$verify.has_behavior_evidence) -Message 'Forbidden dependency drift must revoke behavior evidence'
Assert-True -Condition ([int]$verify.adjusted_coverage_delta -eq 0) -Message 'Adjusted coverage delta must be zero'
Assert-True -Condition ([int]$verify.coverage_cap -le 10) -Message 'Coverage cap must be at most 10'

Write-Host "[2/4] Running SliceVerifier fixture..."
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\SliceVerifier.ps1') `
    -ReplayRoot $ReplayRoot `
    -Worktree $Worktree `
    -SliceResult $SliceResultPath `
    -SliceIndex 1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "SliceVerifier.ps1 failed with exit code $LASTEXITCODE" }

$authorizationPath = Join-Path $ReplayRoot 'SLICE_AUTHORIZATION_01.json'
$authorization = Read-JsonObject -Path $authorizationPath
Assert-True -Condition ([string]$authorization.status -eq 'PASS') -Message 'SliceVerifier validation should pass after fail-closed enforcement'
Assert-True -Condition ([bool]$authorization.must_fail_closed) -Message 'SliceVerifier must mark drift slice as must-fail-closed'
Assert-True -Condition ([bool]$authorization.requires_cap_ten) -Message 'SliceVerifier must require coverage cap ten'
Assert-Contains -Actual $authorization.must_fail_reasons -Expected 'forbidden_dependency_drift_gap' -Message 'Must-fail reasons must include forbidden dependency drift'
Assert-True -Condition ($null -ne $authorization.remediation_map.PSObject.Properties['forbidden_dependency_drift_gap']) -Message 'Remediation map must include forbidden dependency drift'

Write-Host "[3/4] Checking Invoke-AgentPrompt hard rule..."
$agentPromptContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts\Invoke-AgentPrompt.ps1') -Raw -Encoding UTF8
Assert-True -Condition ($agentPromptContent -match 'Editing `pom\.xml` or any dependency configuration file during slice execution is FORBIDDEN') -Message 'Agent prompt must contain explicit dependency-edit prohibition'

Write-Host "[4/4] Parsing modified PowerShell scripts..."
foreach ($relativePath in @(
    'scripts\Verify-SliceClosure.ps1',
    'scripts\SliceVerifier.ps1',
    'scripts\Invoke-AgentPrompt.ps1'
)) {
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot $relativePath), [ref]$null, [ref]$parseErrors) | Out-Null
    Assert-True -Condition ($parseErrors.Count -eq 0) -Message "$relativePath must parse without errors"
}

Remove-Item -LiteralPath $ReplayRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "PASS: forbidden dependency drift guard fails closed and is verifier-consumable"
