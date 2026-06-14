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

$script = Join-Path $PSScriptRoot 'Invoke-TodoPlaceholderCheck.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v538-" + [guid]::NewGuid().ToString('N'))

try {
    $cleanRoot = Join-Path $tempRoot 'clean'
    Write-TextFile (Join-Path $cleanRoot 'claim-core\src\main\java\acme\Service.java') @'
package acme;
public class Service {
    public String value() { return "ok"; }
}
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Worktree $cleanRoot | Out-Null
    Assert-True 'TODO placeholder check passes clean worktree without -replace binding error' ($LASTEXITCODE -eq 0)
    $cleanResult = Read-JsonFile (Join-Path $cleanRoot 'TODO_CHECK_RESULT.json')
    Assert-True 'TODO clean result is PASS' ([string]$cleanResult.validation_status -eq 'PASS' -and [bool]$cleanResult.can_proceed) ($cleanResult | ConvertTo-Json -Depth 12)

    $dirtyRoot = Join-Path $tempRoot 'dirty'
    Write-TextFile (Join-Path $dirtyRoot 'claim-core\src\main\java\acme\Service.java') @'
package acme;
public class Service {
    // TODO implement after test
    public String value() { return "ok"; }
}
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Worktree $dirtyRoot | Out-Null
    Assert-True 'TODO placeholder check fails when production TODO exists' ($LASTEXITCODE -eq 1)
    $dirtyResult = Read-JsonFile (Join-Path $dirtyRoot 'TODO_CHECK_RESULT.json')
    Assert-True 'TODO dirty result is FAIL' ([string]$dirtyResult.validation_status -eq 'FAIL' -and (-not [bool]$dirtyResult.can_proceed)) ($dirtyResult | ConvertTo-Json -Depth 12)

    $scopedRoot = Join-Path $tempRoot 'scoped'
    Write-TextFile (Join-Path $scopedRoot 'claim-core\src\main\java\acme\Legacy.java') @'
package acme;
public class Legacy {
    // TODO legacy unrelated item
}
'@
    Write-TextFile (Join-Path $scopedRoot 'claim-core\src\main\java\acme\Changed.java') @'
package acme;
public class Changed {
    public String value() { return "ok"; }
}
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Worktree $scopedRoot -Paths 'claim-core/src/main/java/acme/Changed.java' | Out-Null
    Assert-True 'TODO placeholder check ignores legacy TODO outside provided paths' ($LASTEXITCODE -eq 0)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Worktree $scopedRoot -PathList ('claim-core/src/main/java/acme/Changed.java' + [System.IO.Path]::PathSeparator + 'claim-core/src/main/java/acme/Legacy.java') | Out-Null
    Assert-True 'TODO placeholder check accepts PathList without array binding errors' ($LASTEXITCODE -eq 1)

    $defaultScopedResult = Join-Path $scopedRoot 'TODO_CHECK_RESULT.json'
    if (Test-Path -LiteralPath $defaultScopedResult) {
        Remove-Item -LiteralPath $defaultScopedResult -Force
    }
    $externalResult = Join-Path $tempRoot 'external\TODO_CHECK_RESULT.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Worktree $scopedRoot -PathList 'claim-core/src/main/java/acme/Changed.java' -ResultPath $externalResult | Out-Null
    Assert-True 'TODO placeholder check can write result outside worktree' ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $externalResult) -and -not (Test-Path -LiteralPath (Join-Path $scopedRoot 'TODO_CHECK_RESULT.json')))

    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Worktree $scopedRoot -Paths 'claim-core/src/main/java/acme/Legacy.java' | Out-Null
    Assert-True 'TODO placeholder check fails when provided path has TODO' ($LASTEXITCODE -eq 1)

    Write-Host 'v538 TODO placeholder path expression regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
