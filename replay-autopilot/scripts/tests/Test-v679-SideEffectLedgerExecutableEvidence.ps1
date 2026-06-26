param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

function Write-Json {
    param([string]$Path, $Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function New-ReplayFixture {
    param([string]$Root, [bool]$ExecutableEvidence)

    $replayRoot = Join-Path $Root 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null

    Write-Utf8 -Path (Join-Path $replayRoot 'SIDE_EFFECT_LEDGER.md') -Value @'
# Side Effect Ledger

Family: stateful side effect

The executable proof captures persisted domain objects and service boundary calls.
The ledger intentionally uses prose because the executable test source owns exact assertions.
'@

    $testPath = 'demo-server/src/test/java/demo/RealEntrySideEffectTest.java'
    if ($ExecutableEvidence) {
        Write-Utf8 -Path (Join-Path $worktree $testPath) -Value @'
package demo;

import org.junit.Assert;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

public class RealEntrySideEffectTest {
    @Test
    public void shouldCaptureStatefulWritesFromRealEntry() {
        DemoMapper demoMapper = Mockito.mock(DemoMapper.class);
        StatusService statusService = Mockito.mock(StatusService.class);

        new RealEntry(demoMapper, statusService).complete("case-1");

        ArgumentCaptor<DemoRow> rowCaptor = ArgumentCaptor.forClass(DemoRow.class);
        Mockito.verify(demoMapper).insert(rowCaptor.capture());
        Assert.assertEquals("DONE", rowCaptor.getValue().getStatus());
        Mockito.verify(statusService).updateStatus(Mockito.eq("case-1"), Mockito.contains("done"));
    }
}
'@
    }

    $slice = [ordered]@{
        slice_status = 'PARTIAL'
        matched_test_count = if ($ExecutableEvidence) { 1 } else { 0 }
        real_entry_invoked = $ExecutableEvidence
        green_exit_code = if ($ExecutableEvidence) { 0 } else { 1 }
        test_execution_exit_code = if ($ExecutableEvidence) { 0 } else { 1 }
        side_effect_assertions = if ($ExecutableEvidence) {
            @('DemoMapper.insert captured persisted row', 'StatusService.updateStatus captured state transition')
        } else {
            @()
        }
        behavior_test_charter = [ordered]@{
            proof_kind = 'real_entry_behavior'
            production_entry = 'demo.RealEntry.complete'
            state_or_output = 'persisted row and status update'
            must_not = 'No helper-only, static-only, DTO-only, terminal-payload-only, or mock-only carrier substitute'
            RED_command = 'mvn -Dtest=RealEntrySideEffectTest test'
            expected_RED_failure = 'insert/status side effect missing'
            GREEN_command = 'mvn -Dtest=RealEntrySideEffectTest test'
            evidence_files = @($testPath)
        }
        side_effect_evidence = [ordered]@{
            test_name = $testPath
            expected_writes_or_outputs = @('DemoMapper.insert', 'StatusService.updateStatus')
        }
    }
    $slicePath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    Write-Json -Path $slicePath -Value $slice

    return [pscustomobject]@{
        ReplayRoot = $replayRoot
        SliceResult = $slicePath
        Worktree = $worktree
    }
}

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$verifySlice = Join-Path $scriptsRoot 'verify-slice.ps1'
$verifyClosure = Join-Path $scriptsRoot 'Verify-SliceClosure.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v679-' + [guid]::NewGuid().ToString('N'))

try {
    $valid = New-ReplayFixture -Root (Join-Path $tempRoot 'valid') -ExecutableEvidence $true
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifySlice -ReplayRoot $valid.ReplayRoot -SliceResultPath $valid.SliceResult *> (Join-Path $tempRoot 'valid.out.log')
    $validExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    Assert-True ($validExit -eq 0) "Executable side-effect evidence should pass verify-slice, got exit $validExit."
    $validResult = Read-Json -Path (Join-Path $valid.ReplayRoot 'SIDE_EFFECT_VERIFICATION_RESULT.json')
    Assert-True ([string]$validResult.validation_status -eq 'PASS') 'Executable side-effect evidence result must be PASS.'
    Assert-True ([string]$validResult.reason -eq 'executable_side_effect_evidence_verified') 'Result must disclose executable evidence fallback.'
    Assert-True ([string]$validResult.verification_source -eq 'SLICE_RESULT_and_test_source') 'Result must disclose verification source.'
    Assert-True (@($validResult.evidence_files).Count -eq 1) 'Result must record executable evidence files.'

    $invalid = New-ReplayFixture -Root (Join-Path $tempRoot 'invalid') -ExecutableEvidence $false
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifySlice -ReplayRoot $invalid.ReplayRoot -SliceResultPath $invalid.SliceResult *> (Join-Path $tempRoot 'invalid.out.log')
    $invalidExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    Assert-True ($invalidExit -ne 0) 'Ledger prose without executable evidence must still fail.'
    $invalidResult = Read-Json -Path (Join-Path $invalid.ReplayRoot 'SIDE_EFFECT_VERIFICATION_RESULT.json')
    Assert-True ([string]$invalidResult.validation_status -eq 'FAIL') 'Missing executable evidence result must be FAIL.'

    $closureText = Get-Content -LiteralPath $verifyClosure -Raw -Encoding UTF8
    Assert-True ($closureText.Contains('$behaviorCharterAuthorizingText')) 'Verify-SliceClosure must scan only authorizing behavior charter fields.'
    Assert-True (-not $closureText.Contains('$charterText -match')) 'Verify-SliceClosure must not scan the full behavior charter JSON for forbidden proof words.'
    $authorizingBlock = [regex]::Match($closureText, '(?s)\$behaviorCharterAuthorizingText\s*=\s*@\((.*?)\)\s*-join').Groups[1].Value
    Assert-True (-not ($authorizingBlock -match 'must_not')) 'Behavior charter authorizing scan must exclude must_not text.'

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($verifySlice, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-True (-not $parseErrors -or $parseErrors.Count -eq 0) ('verify-slice parse errors: ' + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($verifyClosure, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-True (-not $parseErrors -or $parseErrors.Count -eq 0) ('Verify-SliceClosure parse errors: ' + (($parseErrors | ForEach-Object { $_.Message }) -join '; '))

    Write-Host 'Test-v679-SideEffectLedgerExecutableEvidence PASS'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
