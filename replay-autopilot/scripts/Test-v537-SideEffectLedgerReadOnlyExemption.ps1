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

$script = Join-Path $PSScriptRoot 'verify-slice.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v537-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Write-JsonFile (Join-Path $tempRoot 'FEATURE_CLASSIFICATION.json') ([ordered]@{
        classification = 'narrow_backend_read_only_fix'
        read_only = $true
        verifier_adjustments = [ordered]@{
            stateful_side_effect_required = $false
            non_applicable_families = @('stateful_side_effect')
        }
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        side_effect_evidence = [ordered]@{
            status = 'CLOSED'
            expected_writes_or_outputs = @('memory write: taskData.policyNum')
        }
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        warnings = @('side_effect_evidence_not_applicable_by_feature_classification')
        verifier_adjustments_applied = [ordered]@{ side_effect_evidence_required = $false }
    })
    Write-TextFile (Join-Path $tempRoot 'SIDE_EFFECT_LEDGER.md') '# Side Effect Ledger without DB SELECT patterns'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReplayRoot $tempRoot -SliceResultPath (Join-Path $tempRoot 'SLICE_RESULT_01.json') | Out-Null
    Assert-True 'read-only side-effect ledger exemption passes' ($LASTEXITCODE -eq 0)
    $result = Read-JsonFile (Join-Path $tempRoot 'SIDE_EFFECT_VERIFICATION_RESULT.json')
    Assert-True 'side-effect result records skip reason' ([bool]$result.skipped -and [string]$result.skip_reason -eq 'side_effect_not_applicable_by_feature_classification') ($result | ConvertTo-Json -Depth 12)
    Assert-True 'side-effect exemption does not report stateful side effects' (-not [bool]$result.has_side_effects) ($result | ConvertTo-Json -Depth 12)

    Write-Host 'v537 side-effect read-only exemption regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
