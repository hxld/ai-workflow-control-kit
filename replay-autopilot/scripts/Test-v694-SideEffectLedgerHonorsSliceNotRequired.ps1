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

function Invoke-VerifySlice {
    param([string]$ReplayRoot, [int]$SliceIndex)
    $sliceResult = Join-Path $ReplayRoot ('SLICE_RESULT_{0:D2}.json' -f $SliceIndex)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-slice.ps1') `
        -ReplayRoot $ReplayRoot `
        -SliceResultPath $sliceResult | Out-Null
    return $LASTEXITCODE
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v694-side-effect-not-required-" + [guid]::NewGuid().ToString('N'))

try {
    $deployRoot = Join-Path $tempRoot 'deploy'
    New-Item -ItemType Directory -Force -Path $deployRoot | Out-Null
    Write-TextFile (Join-Path $deployRoot 'SIDE_EFFECT_LEDGER.md') '# Side Effect Ledger without DB SELECT patterns'
    Write-JsonFile (Join-Path $deployRoot 'SLICE_RESULT_04.json') ([ordered]@{
        slice_index = 4
        slice_type = 'deploy_surface_first_slice'
        slice_status = 'DONE'
        touched_requirement_families = @('deploy_export_page')
        side_effect_evidence = [ordered]@{
            status = 'CLOSED'
            expected_writes_or_outputs = @('config_api_payload')
        }
    })
    Write-JsonFile (Join-Path $deployRoot 'SIDE_EFFECT_EVIDENCE_04.json') ([ordered]@{
        schema_version = 1
        slice_index = 4
        forced_requirement_family = 'deploy_export_page'
        required_for_this_slice = $false
        expected_writes_or_outputs = @('config_api_payload')
        status = 'NOT_REQUIRED'
        gate = 'stateful_side_effect_evidence_harness'
    })

    $deployExit = Invoke-VerifySlice -ReplayRoot $deployRoot -SliceIndex 4
    Assert-True 'deploy slice side-effect not-required evidence passes' ($deployExit -eq 0)
    $deployResult = Read-JsonFile (Join-Path $deployRoot 'SIDE_EFFECT_VERIFICATION_RESULT.json')
    Assert-True 'deploy skip reason recorded' ([bool]$deployResult.skipped -and [string]$deployResult.skip_reason -eq 'side_effect_not_required_for_slice') ($deployResult | ConvertTo-Json -Depth 12)
    Assert-True 'deploy skip reports no side effects' (-not [bool]$deployResult.has_side_effects) ($deployResult | ConvertTo-Json -Depth 12)

    $statefulRoot = Join-Path $tempRoot 'stateful'
    New-Item -ItemType Directory -Force -Path $statefulRoot | Out-Null
    Write-TextFile (Join-Path $statefulRoot 'SIDE_EFFECT_LEDGER.md') '# Side Effect Ledger without DB SELECT patterns'
    Write-JsonFile (Join-Path $statefulRoot 'SLICE_RESULT_02.json') ([ordered]@{
        slice_index = 2
        slice_type = 'stateful_side_effect_slice'
        slice_status = 'DONE'
        touched_requirement_families = @('stateful_side_effect')
        side_effect_evidence = [ordered]@{
            status = 'CLOSED'
            expected_writes_or_outputs = @('compensate_info_row')
        }
    })
    Write-JsonFile (Join-Path $statefulRoot 'SIDE_EFFECT_EVIDENCE_02.json') ([ordered]@{
        schema_version = 1
        slice_index = 2
        forced_requirement_family = 'stateful_side_effect'
        required_for_this_slice = $false
        expected_writes_or_outputs = @('compensate_info_row')
        status = 'NOT_REQUIRED'
        gate = 'stateful_side_effect_evidence_harness'
    })

    $statefulExit = Invoke-VerifySlice -ReplayRoot $statefulRoot -SliceIndex 2
    Assert-True 'stateful family cannot bypass side-effect ledger with not-required evidence' ($statefulExit -ne 0)
    $statefulResult = Read-JsonFile (Join-Path $statefulRoot 'SIDE_EFFECT_VERIFICATION_RESULT.json')
    $codes = @($statefulResult.issues | ForEach-Object { [string]$_.code })
    Assert-True 'stateful bypass attempt still records side-effect ledger gap' ($codes -contains 'side_effect_ledger_gap') ($statefulResult | ConvertTo-Json -Depth 12)

    Write-Host 'v694 side-effect ledger slice not-required regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
