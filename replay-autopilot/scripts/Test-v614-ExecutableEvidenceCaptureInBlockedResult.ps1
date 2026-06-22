param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-JsonFile {
    param([string]$Path, $Value, [int]$Depth = 16)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
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

function Initialize-GitWorktree {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    & git -C $Path init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git init failed for $Path" }
    '# replay test fixture' | Set-Content -LiteralPath (Join-Path $Path 'README.md') -Encoding UTF8
    & git -C $Path add README.md | Out-Null
    & git -C $Path commit -m 'initial' --allow-empty | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git commit failed for $Path" }
}

function New-BlockedSliceViaRunner {
    param(
        [string]$ReplayRoot,
        [string]$Reason,
        [int]$ExitCode = 88
    )

    $sliceResult = Join-Path $ReplayRoot 'SLICE_RESULT_01.json'
    $logDir = Join-Path $ReplayRoot 'logs\phase1-slices\slice01'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $forced = [pscustomobject]@{
        family_id = 'core_entry'
        slice_type = 'stateful_success_slice'
    }

    Write-ExecutorBlockedSliceResult `
        -Path $sliceResult `
        -SliceIndex 1 `
        -ForcedDecision $forced `
        -SliceLogDir $logDir `
        -ExitCode $ExitCode `
        -Reason $Reason `
        -FailureCategory 'executor_silent_no_output'

    return $sliceResult
}

function Invoke-SliceVerifier {
    param([string]$ReplayRoot, [string]$Worktree, [string]$SliceResult)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1') `
        -ReplayRoot $ReplayRoot `
        -Worktree $Worktree `
        -SliceResult $SliceResult `
        -SliceIndex 1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Verify-SliceClosure failed with exit code $LASTEXITCODE" }
    return Read-JsonFile (Join-Path $ReplayRoot 'SLICE_VERIFY_01.json')
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v614-blocked-compilation-evidence-" + [guid]::NewGuid().ToString('N'))

try {
    Import-RunSliceLoopFunctions

    $replayRoot1 = Join-Path $tempRoot 'scenario1'
    $worktree1 = Join-Path $replayRoot1 'worktree'
    Initialize-GitWorktree -Path $worktree1
    Write-JsonFile (Join-Path $replayRoot1 'PREFLIGHT_TEST_COMPILATION.json') ([ordered]@{
        stage = 'preflight_test_compilation'
        status = 'PASS'
        decision = 'ALLOW'
        exit_code = 0
        maven_command_args = '-f pom.xml -am test-compile -q -DskipTests'
        duration_seconds = 12.3
        issues = @()
    })
    $sliceResult1 = New-BlockedSliceViaRunner -ReplayRoot $replayRoot1 -Reason 'executor completed without writing required SLICE_RESULT after retry'
    $slice1 = Read-JsonFile $sliceResult1
    Assert-True ([int]$slice1.test_compilation_exit_code -eq 0) 'runner must inject preflight PASS exit code into BLOCKED slice result'
    Assert-True ([bool]$slice1.test_compilation_evidence) 'runner must mark preflight PASS as compilation evidence'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$slice1.test_compilation_command)) 'runner must inject preflight command'
    Assert-True (([string]$slice1.test_compilation_evidence_source).EndsWith('PREFLIGHT_TEST_COMPILATION.json')) 'runner must point to preflight evidence source'
    $verify1 = Invoke-SliceVerifier -ReplayRoot $replayRoot1 -Worktree $worktree1 -SliceResult $sliceResult1
    Assert-True ([int]$verify1.test_compilation_exit_code -eq 0) 'verifier must preserve injected preflight PASS exit code'
    Assert-True ([bool]$verify1.test_compilation_evidence) 'verifier must preserve injected preflight PASS evidence'
    Assert-True (@($verify1.gap_flags) -notcontains 'test_compilation_evidence_missing') 'preflight PASS must not emit missing compilation evidence'

    $replayRoot2 = Join-Path $tempRoot 'scenario2'
    $worktree2 = Join-Path $replayRoot2 'worktree'
    Initialize-GitWorktree -Path $worktree2
    $sliceResult2 = New-BlockedSliceViaRunner -ReplayRoot $replayRoot2 -Reason 'executor failed before completing slice' -ExitCode 1
    $slice2 = Read-JsonFile $sliceResult2
    Assert-True ($null -eq $slice2.test_compilation_exit_code) 'runner must leave exit code null when preflight is absent'
    Assert-True (-not [bool]$slice2.test_compilation_evidence) 'runner must not invent evidence when preflight is absent'
    $verify2 = Invoke-SliceVerifier -ReplayRoot $replayRoot2 -Worktree $worktree2 -SliceResult $sliceResult2
    Assert-True ($null -eq $verify2.test_compilation_exit_code) 'verifier must preserve null exit code when preflight is absent'
    Assert-True (-not [bool]$verify2.test_compilation_evidence) 'verifier must preserve false evidence when preflight is absent'
    Assert-True (@($verify2.blocking_gap_flags) -notcontains 'test_compilation_evidence_missing') 'blocked no-progress slices must not get a false missing-evidence blocker'

    $replayRoot3 = Join-Path $tempRoot 'scenario3'
    $worktree3 = Join-Path $replayRoot3 'worktree'
    Initialize-GitWorktree -Path $worktree3
    Write-JsonFile (Join-Path $replayRoot3 'PREFLIGHT_TEST_COMPILATION.json') ([ordered]@{
        stage = 'preflight_test_compilation'
        status = 'FAIL'
        decision = 'BLOCKED'
        exit_code = 1
        maven_command_args = '-f pom.xml -am test-compile -q -DskipTests'
        duration_seconds = 9.1
        issues = @('compilation_failure')
    })
    $sliceResult3 = New-BlockedSliceViaRunner -ReplayRoot $replayRoot3 -Reason 'pre-slice gate stopped after compile failure' -ExitCode 1
    $slice3 = Read-JsonFile $sliceResult3
    Assert-True ([int]$slice3.test_compilation_exit_code -eq 1) 'runner must inject preflight FAIL exit code into BLOCKED slice result'
    Assert-True (-not [bool]$slice3.test_compilation_evidence) 'runner must not mark failed preflight as passing evidence'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$slice3.test_compilation_command)) 'runner must preserve failed preflight command'
    $verify3 = Invoke-SliceVerifier -ReplayRoot $replayRoot3 -Worktree $worktree3 -SliceResult $sliceResult3
    Assert-True ([int]$verify3.test_compilation_exit_code -eq 1) 'verifier must preserve injected preflight FAIL exit code'
    Assert-True (-not [bool]$verify3.test_compilation_evidence) 'verifier must preserve failed preflight evidence=false'

    Write-Host 'Test-v614-ExecutableEvidenceCaptureInBlockedResult PASS'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
