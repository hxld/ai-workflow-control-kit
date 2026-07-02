param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "ASSERT FAILED: $Name" }
        throw "ASSERT FAILED: $Name - $Details"
    }
    Write-Host "PASS: $Name"
}

function Write-JsonFile {
    param([string]$Path, $Value, [int]$Depth = 12)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-TextFile {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Import-RunSliceLoopFunctions {
    $runSliceLoop = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-SliceLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }

    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($functionAst in @($functionAsts)) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v536-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    $testRel = 'example-server/src/test/java/acme/PolicyNumRebuildPathTest.java'
    $testAbs = Join-Path $worktree ($testRel -replace '/', '\')
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null
    Write-TextFile $testAbs @'
package acme;

public class PolicyNumRebuildPathTest {
    @org.junit.Test
    public void testRebuildTaskDataSourceChainAssignment() {
        org.junit.Assert.assertEquals("A", "A");
    }
}
'@
    Write-TextFile (Join-Path $worktree 'TEST_CHARTER.md') 'Entry: rebuildTaskData'
    Write-JsonFile (Join-Path $replayRoot 'AUTOPILOT_RUN.json') ([ordered]@{
        replay_root = $replayRoot
        worktree = $worktree
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        implemented_files = @(
            'example-core/src/main/java/acme/ApplyProcessor.java',
            'example-core/src/main/java/acme/CalcProcessor.java'
        )
        tests = @(
            [ordered]@{ phase = 'RED'; command = 'test-compile'; result = 'pass'; evidence = 'Test class compiled successfully' },
            [ordered]@{ phase = 'RED'; command = 'test execution'; result = 'pass'; evidence_file = $testRel; evidence = 'Tests ran but with failures indicating missing source-chain assignments' }
        )
        behavior_test_charter = [ordered]@{
            evidence_file = $testRel
        }
    })
    $runnerContract = Join-Path $replayRoot 'RUNNER_ENFORCEMENT_CONTRACT.md'
    Write-TextFile $runnerContract '# contract'

    Import-RunSliceLoopFunctions
    $script:RunSliceLoopScriptRootOverride = $PSScriptRoot
    $result = Invoke-IncrementalVerificationGate -Phase RED -ReplayRoot $replayRoot -SliceResultPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -SliceIndex 1 -RunnerContractPath $runnerContract
    Assert-True 'RED incremental gate succeeds with named -Files splat' ([bool]$result.CanProceed) ($result | ConvertTo-Json -Depth 12)
    $gate = Read-JsonFile (Join-Path $replayRoot 'INCREMENTAL_VERIFICATION_RED_01.json')
    Assert-True 'RED incremental gate uses worktree as working directory' ([string]$gate.work_dir -eq $worktree) ($gate | ConvertTo-Json -Depth 12)
    Assert-True 'RED incremental gate checks test evidence file, not production files' (@($gate.files_checked) -contains $testRel -and @($gate.files_checked | Where-Object { [string]$_ -match 'example-core' }).Count -eq 0) ($gate | ConvertTo-Json -Depth 12)

    Write-Host 'v536 incremental verification gate args regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
