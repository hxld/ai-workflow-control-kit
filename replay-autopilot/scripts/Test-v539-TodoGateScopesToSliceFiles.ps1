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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v539-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null
    Write-TextFile (Join-Path $worktree 'claim-core\src\main\java\acme\Legacy.java') @'
package acme;
public class Legacy {
    // TODO historical unrelated item
}
'@
    Write-TextFile (Join-Path $worktree 'claim-core\src\main\java\acme\Changed.java') @'
package acme;
public class Changed {
    public String value() { return "ok"; }
}
'@
    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_01.json') ([ordered]@{
        implemented_files = @('claim-core/src/main/java/acme/Changed.java')
        current_slice_changed_files = @('claim-core/src/main/java/acme/Changed.java', 'claim-server/src/test/java/acme/ChangedTest.java')
    })
    $runnerContract = Join-Path $replayRoot 'RUNNER_ENFORCEMENT_CONTRACT.md'
    Write-TextFile $runnerContract '# contract'

    Import-RunSliceLoopFunctions
    $script:RunSliceLoopScriptRootOverride = $PSScriptRoot
    $result = Invoke-TodoDetectorGate -ReplayRoot $replayRoot -Worktree $worktree -SliceIndex 1 -RunnerContractPath $runnerContract
    Assert-True 'TODO gate ignores legacy TODO outside current slice files' ([bool]$result.CanProceed) ($result | ConvertTo-Json -Depth 12)
    $gate = Read-JsonFile (Join-Path $replayRoot 'TODO_DETECTION_01.json')
    Assert-True 'TODO gate records scoped production path' (@($gate.paths_checked) -contains 'claim-core/src/main/java/acme/Changed.java' -and @($gate.paths_checked).Count -eq 1) ($gate | ConvertTo-Json -Depth 12)
    Assert-True 'TODO gate writes checker result under replay root' ((Test-Path -LiteralPath (Join-Path $replayRoot 'TODO_CHECK_RESULT_01.json')) -and -not (Test-Path -LiteralPath (Join-Path $worktree 'TODO_CHECK_RESULT.json'))) ($gate | ConvertTo-Json -Depth 12)

    Write-Host 'v539 TODO gate slice scope regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
