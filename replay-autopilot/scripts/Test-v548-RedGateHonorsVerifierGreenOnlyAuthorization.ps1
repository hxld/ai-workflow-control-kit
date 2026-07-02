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

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Invoke-RedGate {
    param([string]$ReplayRoot, [int]$SliceIndex)
    $sliceResult = Join-Path $ReplayRoot ('SLICE_RESULT_{0:D2}.json' -f $SliceIndex)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-RedPhaseHardGate.ps1') `
        -VerifyOnly `
        -ReplayRoot $ReplayRoot `
        -SliceResultPath $sliceResult `
        -SliceIndex $SliceIndex | Out-Null
    return $LASTEXITCODE
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v548-red-green-only-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_02.json') ([ordered]@{
        slice_index = 2
        slice_status = 'DONE'
        tests = @(
            [ordered]@{
                phase = 'VERIFY'
                command = 'mvn -pl example-server -am -Dtest=PolicyNumRebuildPathTest test'
                result = 'pass'
                evidence = 'Tests run: 5, Failures: 0, Errors: 0, Skipped: 0'
            }
        )
        implemented_files = @(
            'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java',
            'example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java'
        )
        current_slice_changed_files = @(
            'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java',
            'example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java'
        )
    })

    $exitWithoutVerify = Invoke-RedGate -ReplayRoot $replayRoot -SliceIndex 2
    Assert-True 'RED gate still fails missing RED/GREEN without verifier authorization' ($exitWithoutVerify -ne 0)
    $blockedGate = Read-JsonFile (Join-Path $replayRoot 'RED_PHASE_GATE_02.json')
    $blockedCodes = @($blockedGate.issues | ForEach-Object { [string]$_.code })
    Assert-True 'ordinary missing RED/GREEN records blockers' ($blockedCodes -contains 'red_phase_missing' -and $blockedCodes -contains 'green_phase_missing') ($blockedGate | ConvertTo-Json -Depth 12)

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

    $exitWithVerify = Invoke-RedGate -ReplayRoot $replayRoot -SliceIndex 2
    Assert-True 'RED gate honors verifier-authorized green-only read-only slice' ($exitWithVerify -eq 0)
    $authorizedGate = Read-JsonFile (Join-Path $replayRoot 'RED_PHASE_GATE_02.json')
    Assert-True 'RED gate records green-only authorization warning' (@($authorizedGate.warnings) -contains 'green_only_verifier_authorized_missing_red_green_phase_entries') ($authorizedGate | ConvertTo-Json -Depth 12)
    Assert-True 'RED gate clears missing RED/GREEN blockers under verifier authorization' (@($authorizedGate.issues).Count -eq 0 -and [bool]$authorizedGate.can_proceed) ($authorizedGate | ConvertTo-Json -Depth 12)

    Write-Host 'v548 RED gate verifier green-only authorization regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
