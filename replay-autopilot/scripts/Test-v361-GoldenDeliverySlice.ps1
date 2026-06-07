param(
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
    Write-Host "PASS: $Name"
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("golden-delivery-v361-" + [guid]::NewGuid().ToString('N'))
$evidenceRoot = Join-Path $tempRoot 'evidence'
$controlRoot = Join-Path $evidenceRoot '_control'
$goldenRoot = Join-Path $evidenceRoot '_golden-samples'
$replayRoot = Join-Path $evidenceRoot 'sample-feature\claim-codex-replay-v361-r01'

try {
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-JsonFile -Path (Join-Path $controlRoot 'RUN_CONTROL_LATEST.json') -Value ([ordered]@{
        schema = 'replay_control_summary.v1'
        latest = [ordered]@{
            replay_root = $replayRoot
            feature = 'sample-feature'
            verification_capped_coverage = 0
            oracle_adjusted_coverage = 0
            fingerprints = @('wrong_test_surface', 'side_effect_ledger_gap', 'low_verification_cap')
        }
        control_decision = [ordered]@{
            decision_kind = 'EVOLVE'
            recommended_next_step = 'Run deep review / external practice / golden sample evolution before more blind replay.'
            repeated_blockers = @('wrong_test_surface', 'side_effect_ledger_gap')
        }
    })

    Write-JsonFile -Path (Join-Path $goldenRoot 'GOLDEN_SAMPLE_LEDGER.json') -Value ([ordered]@{
        schema = 'golden_sample_mining.v1'
        candidates = @(
            [ordered]@{
                feature = 'good-feature'
                oracle_adjusted_coverage = 86
                verification_capped_coverage = 82
                replay_root = 'D:\example\good'
            }
        )
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Write-GoldenDeliverySlice.ps1') -EvidenceRoot $evidenceRoot -Quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Write-GoldenDeliverySlice failed: $LASTEXITCODE"
    }

    $jsonPath = Join-Path $goldenRoot 'GOLDEN_DELIVERY_SLICE.json'
    $mdPath = Join-Path $goldenRoot 'GOLDEN_DELIVERY_SLICE.md'
    $promptPath = Join-Path $goldenRoot 'GOLDEN_DELIVERY_SLICE_PROMPT.md'
    $nextPath = Join-Path $replayRoot 'NEXT_GOLDEN_DELIVERY_SLICE.md'

    Assert-True -Name 'writes_delivery_json' -Condition (Test-Path -LiteralPath $jsonPath)
    Assert-True -Name 'writes_delivery_md' -Condition (Test-Path -LiteralPath $mdPath)
    Assert-True -Name 'writes_delivery_prompt' -Condition (Test-Path -LiteralPath $promptPath)
    Assert-True -Name 'copies_next_slice_to_latest_replay' -Condition (Test-Path -LiteralPath $nextPath)

    $delivery = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Name 'uses_repeated_blockers' -Condition (@($delivery.repeated_blockers) -contains 'wrong_test_surface' -and @($delivery.repeated_blockers) -contains 'side_effect_ledger_gap')
    Assert-True -Name 'emits_wrong_test_surface_rule' -Condition (@($delivery.rules | Where-Object { $_.fingerprint -eq 'wrong_test_surface' -and $_.focus -eq 'real_entry_behavior_test' }).Count -eq 1)
    Assert-True -Name 'emits_side_effect_rule' -Condition (@($delivery.rules | Where-Object { $_.fingerprint -eq 'side_effect_ledger_gap' -and $_.focus -eq 'stateful_side_effect_slice' }).Count -eq 1)

    $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
    Assert-True -Name 'prompt_contains_positive_first_slice' -Condition ($promptText -match 'positive first-slice contract')
    Assert-True -Name 'prompt_forbids_prose_gap_fill' -Condition ($promptText -match 'Do not fill with prose')

    Write-Host 'PASS: v361 golden delivery slice'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
