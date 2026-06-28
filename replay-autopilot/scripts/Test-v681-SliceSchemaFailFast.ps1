#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$gatePath = Join-Path $scriptRoot 'Invoke-SliceSchemaFailFast.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v681-slice-schema-failfast-' + [guid]::NewGuid().ToString('N'))

try {
    # 1. ValidateOnly
    & pwsh -NoProfile -File $gatePath -ReplayRoot 'nonexistent' -SliceIndex 1 -ValidateOnly
    Assert-True 'validate_only_exits_zero' ($LASTEXITCODE -eq 0)

    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    # 2. Valid pure JSON slice result -> PASS
    $valid = @{ slice_index = 1; slice_status = 'DONE'; slice_type = 'real_entry_behavior'; proof_kind = 'real_entry_behavior'; coverage_delta = 15; touched_requirement_families = @('core_entry'); closed_requirement_families = @('core_entry') } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Value $valid -Encoding UTF8
    & pwsh -NoProfile -File $gatePath -ReplayRoot $replayRoot -SliceIndex 1
    Assert-True 'valid_pure_json_passes' ($LASTEXITCODE -eq 0)
    $result = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_SCHEMA_FAILFAST_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'valid_writes_pass_status' ([string]$result.status -eq 'PASS')

    # 3. Markdown-fenced JSON -> FAIL
    $fenced = '```json' + "`n" + $valid + "`n" + '```'
    Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Value $fenced -Encoding UTF8
    & pwsh -NoProfile -File $gatePath -ReplayRoot $replayRoot -SliceIndex 1
    Assert-True 'fenced_json_fails' ($LASTEXITCODE -ne 0)

    # 4. Missing slice_status -> FAIL
    $noStatus = @{ slice_index = 1 } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Value $noStatus -Encoding UTF8
    & pwsh -NoProfile -File $gatePath -ReplayRoot $replayRoot -SliceIndex 1
    Assert-True 'no_status_fails' ($LASTEXITCODE -ne 0)

    # 5. Mismatched slice_index -> FAIL
    $wrongIdx = @{ slice_index = 2; slice_status = 'DONE'; slice_type = 'tracer_bullet' } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Value $wrongIdx -Encoding UTF8
    & pwsh -NoProfile -File $gatePath -ReplayRoot $replayRoot -SliceIndex 1
    Assert-True 'wrong_index_fails' ($LASTEXITCODE -ne 0)

    # 6. Execution result (DONE) without proof_kind -> FAIL
    $noProof = @{ slice_index = 1; slice_status = 'DONE'; slice_type = 'real_entry_behavior' } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -Value $noProof -Encoding UTF8
    & pwsh -NoProfile -File $gatePath -ReplayRoot $replayRoot -SliceIndex 1
    Assert-True 'done_no_proof_kind_fails' ($LASTEXITCODE -ne 0)

    Write-Host ''
    Write-Host 'v681 Slice Schema FailFast: ALL PASSED'
    exit 0
} catch {
    Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
