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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v531-" + [guid]::NewGuid().ToString('N'))
$script = Join-Path $PSScriptRoot 'Invoke-EconomyCheckpoint.ps1'

try {
    $passRoot = Join-Path $tempRoot 'pass'
    New-Item -ItemType Directory -Force -Path $passRoot | Out-Null
    Write-TextFile (Join-Path $passRoot 'TEST_CHARTER.md') "# Test Charter`n`n## Test Class: PolicyNumRebuildPathTest`n`n## Entry Point: Processor.rebuildTaskData(Long caseId)`n"
    Write-JsonFile (Join-Path $passRoot 'TEST_CHARTER_VALIDATION_01.json') ([ordered]@{
        gate = 'test_charter_prevalidation'
        slice_index = 1
        verification_status = 'PASSED'
        can_proceed = $true
        failures = @()
        warnings = @()
        warning_count = 0
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReplayRoot $passRoot -CheckpointId CP4_TEST_CHARTER | Out-Null
    Assert-True 'CP4 accepts modern validation artifact without legacy TEST_CHARTER.json' ($LASTEXITCODE -eq 0)
    $checkpoint = Read-JsonFile (Join-Path $passRoot 'CHECKPOINT_CP4_TEST_CHARTER.json')
    Assert-True 'CP4 records accepted validation artifact' ([bool]$checkpoint.validation_passed -and [string]$checkpoint.validation_artifact -eq 'TEST_CHARTER_VALIDATION_01.json') ($checkpoint | ConvertTo-Json -Depth 12)

    $failRoot = Join-Path $tempRoot 'fail'
    New-Item -ItemType Directory -Force -Path $failRoot | Out-Null
    Write-TextFile (Join-Path $failRoot 'TEST_CHARTER.md') "# Test Charter`n`n## Test Class: PolicyNumRebuildPathTest`n`n## Entry Point: Processor.rebuildTaskData(Long caseId)`n"
    Write-JsonFile (Join-Path $failRoot 'TEST_CHARTER_VALIDATION_01.json') ([ordered]@{
        gate = 'test_charter_prevalidation'
        slice_index = 1
        verification_status = 'FAILED'
        can_proceed = $false
        failures = @([ordered]@{ code = 'NO_SIDE_EFFECT_PROOF'; message = 'fixture failure' })
        warnings = @()
        warning_count = 0
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReplayRoot $failRoot -CheckpointId CP4_TEST_CHARTER | Out-Null
    Assert-True 'CP4 rejects failed modern validation artifact even when markdown exists' ($LASTEXITCODE -ne 0)
    $failedCheckpoint = Read-JsonFile (Join-Path $failRoot 'CHECKPOINT_CP4_TEST_CHARTER.json')
    Assert-True 'CP4 failure names validator failure code' ((-not [bool]$failedCheckpoint.validation_passed) -and ([string]$failedCheckpoint.validation_reason).Contains('NO_SIDE_EFFECT_PROOF')) ($failedCheckpoint | ConvertTo-Json -Depth 12)

    Write-Host 'v531 modern test charter economy checkpoint regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
