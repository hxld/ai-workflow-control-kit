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

function New-SkillSet {
    param([string]$Root)
    foreach ($skill in @('pre-flight-check', 'replay-tdd-enforcer', 'replay-test-charter-validator')) {
        Write-Utf8 (Join-Path $Root (Join-Path $skill 'SKILL.md')) "---`nname: $skill`n---`n# $skill`n"
    }
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v708-workflow-hash-fallback-' + [guid]::NewGuid().ToString('N'))

try {
    $sourceRoot = Join-Path $tempRoot 'source-skills'
    $runtimeRoot = Join-Path $tempRoot 'runtime-skills'
    $logDir = Join-Path $tempRoot 'logs'
    New-Item -ItemType Directory -Force -Path $sourceRoot, $runtimeRoot, $logDir | Out-Null
    New-SkillSet -Root $sourceRoot
    New-SkillSet -Root $runtimeRoot

    $proofPath = Join-Path $tempRoot 'workflow-proof.json'
    $driverPath = Join-Path $tempRoot 'driver.ps1'
    @"
`$ErrorActionPreference = 'Stop'
function Get-FileHash {
    throw 'simulated Get-FileHash unavailable in unattended shell'
}
& '$scriptsRoot\Write-WorkflowFidelityProof.ps1' ``
    -OutputPath '$proofPath' ``
    -Executor codex ``
    -CommandSource 'codex.cmd' ``
    -LogDir '$logDir' ``
    -Stage 'test' ``
    -SkillSourceRoot '$sourceRoot' ``
    -RuntimeSkillRoot '$runtimeRoot'
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $driverPath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $driverPath *> (Join-Path $tempRoot 'driver.out')
    Assert-True ($LASTEXITCODE -eq 0) 'workflow fidelity writer should succeed when Get-FileHash invocation fails'
    $proof = Get-Content -LiteralPath $proofPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$proof.status -eq 'PASS') 'fallback hashing should preserve PASS workflow fidelity status'
    Assert-True (@($proof.skill_checks).Count -eq 3) 'fallback hashing should preserve required skill checks'
    Assert-True ([string]$proof.skill_checks[0].source_sha256 -match '^[0-9a-f]{64}$') 'fallback hashing should produce source sha256'
    Assert-True ([string]$proof.skill_checks[0].runtime_sha256 -match '^[0-9a-f]{64}$') 'fallback hashing should produce runtime sha256'

    Write-Host ''
    Write-Host 'v708 Workflow Fidelity Hash Fallback: PASS'
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
