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
    param([string]$Path, $Value, [int]$Depth = 10)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v547-economy-layer-" + [guid]::NewGuid().ToString('N'))
$script = Join-Path $PSScriptRoot 'Invoke-EconomyCheckpoint.ps1'

try {
    $modernRoot = Join-Path $tempRoot 'modern'
    New-Item -ItemType Directory -Force -Path $modernRoot | Out-Null
    Write-JsonFile (Join-Path $modernRoot 'LAYER_VALIDATION_RESULT.json') ([ordered]@{
        gate = 'layer_validation'
        slice_index = 2
        verification_status = 'PASSED'
        can_proceed = $true
        failures = @()
        warnings = @()
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReplayRoot $modernRoot -CheckpointId CP2_LAYER_VALIDATION | Out-Null
    Assert-True 'CP2 accepts modern layer verification_status PASSED artifact' ($LASTEXITCODE -eq 0)
    $modernCheckpoint = Read-JsonFile (Join-Path $modernRoot 'CHECKPOINT_CP2_LAYER_VALIDATION.json')
    Assert-True 'CP2 records modern layer pass' ([bool]$modernCheckpoint.validation_passed -and [string]$modernCheckpoint.status -eq 'PASSED') ($modernCheckpoint | ConvertTo-Json -Depth 10)

    $legacyRoot = Join-Path $tempRoot 'legacy'
    New-Item -ItemType Directory -Force -Path $legacyRoot | Out-Null
    Write-JsonFile (Join-Path $legacyRoot 'LAYER_VALIDATION_RESULT.json') ([ordered]@{
        validation_status = 'PASS'
        can_proceed = $true
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReplayRoot $legacyRoot -CheckpointId CP2_LAYER_VALIDATION | Out-Null
    Assert-True 'CP2 still accepts legacy validation_status PASS artifact' ($LASTEXITCODE -eq 0)

    $failRoot = Join-Path $tempRoot 'fail'
    New-Item -ItemType Directory -Force -Path $failRoot | Out-Null
    Write-JsonFile (Join-Path $failRoot 'LAYER_VALIDATION_RESULT.json') ([ordered]@{
        verification_status = 'FAILED'
        can_proceed = $false
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReplayRoot $failRoot -CheckpointId CP2_LAYER_VALIDATION | Out-Null
    $failedCheckpoint = Read-JsonFile (Join-Path $failRoot 'CHECKPOINT_CP2_LAYER_VALIDATION.json')
    Assert-True 'CP2 rejects explicit failed layer validation artifact' (-not [bool]$failedCheckpoint.validation_passed -and [string]$failedCheckpoint.status -eq 'FAILED') ($failedCheckpoint | ConvertTo-Json -Depth 10)

    Write-Host 'v547 economy checkpoint modern layer validation regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
