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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v546-phase0-green-only-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_02.json'
    Write-JsonFile $sliceResultPath ([ordered]@{
        slice_index = 2
        slice_status = 'DONE'
        slice_type = 'exact_contract_slice'
        proof_kind = 'payload_shape_behavior'
        tests = @(
            [ordered]@{
                command = 'mvn -pl example-server -am -Dtest=PolicyNumRebuildPathTest test'
                phase = 'VERIFY'
                result = 'pass'
                evidence = 'Tests run: 5, Failures: 0, Errors: 0, Skipped: 0'
            }
        )
        implemented_files = @(
            'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java',
            'example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java'
        )
    })

    & (Join-Path $PSScriptRoot 'phase0-precheck.ps1') -ReplayRoot $replayRoot -SliceIndex 2 | Out-Null
    Assert-True 'phase0 still fails missing RED without verifier authorization' ($LASTEXITCODE -eq 1)
    $first = Get-Content -Raw -Encoding UTF8 (Join-Path $replayRoot 'PHASE0_PRECHECK_RESULT.json') | ConvertFrom-Json
    Assert-True 'unauthorized missing RED records blocker' (@($first.issues | Where-Object { $_.reason -eq 'red_phase_not_executed' }).Count -eq 1) ($first | ConvertTo-Json -Depth 12)

    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_02.json') ([ordered]@{
        verification_status = 'PASS'
        authorized_for_synthesis = $true
        authorized_for_next_slice = $true
        feature_classification = 'narrow_backend_read_only_fix'
        warnings = @('green_only_evidence_accepted_by_feature_classification')
        verifier_adjustments_applied = [ordered]@{
            narrow_backend_read_only = $true
            green_only_evidence_accepted = $true
            side_effect_evidence_required = $false
        }
    })

    & (Join-Path $PSScriptRoot 'phase0-precheck.ps1') -ReplayRoot $replayRoot -SliceIndex 2 | Out-Null
    Assert-True 'phase0 honors verifier-authorized green-only read-only slice' ($LASTEXITCODE -eq 0)
    $second = Get-Content -Raw -Encoding UTF8 (Join-Path $replayRoot 'PHASE0_PRECHECK_RESULT.json') | ConvertFrom-Json
    Assert-True 'green-only verifier authorization is recorded' ([bool]$second.checks.green_only_verifier_authorization.IsValid) ($second | ConvertTo-Json -Depth 12)
    Assert-True 'phase0 result has no blocking issues after verifier authorization' (@($second.issues).Count -eq 0 -and [bool]$second.can_proceed) ($second | ConvertTo-Json -Depth 12)

    Write-Host 'v546 phase0 verifier green-only authorization regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
