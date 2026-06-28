#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Invoke-CarrierIndex {
    param(
        [string]$ProjectRoot,
        [string]$OutputPath,
        [string]$TempRoot
    )

    $scriptRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $stdout = Join-Path $TempRoot ('carrier-index-{0}.out' -f ([guid]::NewGuid().ToString('N')))
    $stderr = Join-Path $TempRoot ('carrier-index-{0}.err' -f ([guid]::NewGuid().ToString('N')))
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Generate-CarrierIndex.ps1') `
        -ProjectRoot $ProjectRoot `
        -OutputPath $OutputPath > $stdout 2> $stderr
    return [ordered]@{
        exit_code = $LASTEXITCODE
        stdout = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw -Encoding UTF8 } else { '' }
        stderr = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -Encoding UTF8 } else { '' }
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v707-carrier-index-' + [guid]::NewGuid().ToString('N'))

try {
    $emptyRepo = Join-Path $tempRoot 'empty-repo'
    New-Item -ItemType Directory -Force -Path $emptyRepo | Out-Null
    Write-Utf8 (Join-Path $emptyRepo 'README.md') '# non-java fixture'
    $emptyOut = Join-Path $tempRoot 'empty-SURFACE_CARRIER_INDEX.md'
    $emptyResult = Invoke-CarrierIndex -ProjectRoot $emptyRepo -OutputPath $emptyOut -TempRoot $tempRoot
    $emptyText = Get-Content -LiteralPath $emptyOut -Raw -Encoding UTF8

    Assert-True ($emptyResult.exit_code -eq 0) 'empty/non-Java project should not fail carrier index generation'
    Assert-True ([string]::IsNullOrWhiteSpace($emptyResult.stderr)) 'empty/non-Java project should not emit ripgrep-style stderr diagnostics'
    Assert-True ($emptyText -match 'Total Executable Carriers: 0') 'empty/non-Java project should produce a zero-carrier index'

    $javaRepo = Join-Path $tempRoot 'java-repo'
    Write-Utf8 (Join-Path $javaRepo 'claim-api\src\main\java\com\acme\PolicyFacade.java') 'public interface PolicyFacade {}'
    Write-Utf8 (Join-Path $javaRepo 'claim-web\src\main\java\com\acme\PolicyController.java') 'public class PolicyController {}'
    Write-Utf8 (Join-Path $javaRepo 'claim-core\src\main\java\com\acme\facade\PolicyFacadeImpl.java') 'public class PolicyFacadeImpl {}'
    $javaOut = Join-Path $tempRoot 'java-SURFACE_CARRIER_INDEX.md'
    $javaResult = Invoke-CarrierIndex -ProjectRoot $javaRepo -OutputPath $javaOut -TempRoot $tempRoot
    $javaText = Get-Content -LiteralPath $javaOut -Raw -Encoding UTF8

    Assert-True ($javaResult.exit_code -eq 0) 'Java project should still generate carrier index successfully'
    Assert-True ($javaText -match 'PolicyFacade - claim-api/src/main/java/com/acme/PolicyFacade.java') 'Facade interface should be detected'
    Assert-True ($javaText -match 'PolicyController - claim-web/src/main/java/com/acme/PolicyController.java') 'Controller class should be detected'
    Assert-True ($javaText -match 'PolicyFacadeImpl - claim-core/src/main/java/com/acme/facade/PolicyFacadeImpl.java') 'FacadeImpl class should be detected'
    Assert-True ($javaText -match 'Total Executable Carriers: 3') 'Java project should report three executable carriers'

    Write-Host ''
    Write-Host 'v707 Generate Carrier Index No Java: PASS'
    exit 0
} catch {
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
