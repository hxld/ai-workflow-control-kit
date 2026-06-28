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
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("red-phase-v692-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_04.json') ([ordered]@{
        slice_index = 4
        slice_status = 'DONE'
        implemented_files = @(
            'claim-web/src/main/java/com/huize/claim/web/claim/system/controller/PushConfigController.java'
        )
        current_slice_changed_files = @(
            'claim-web/src/main/java/com/huize/claim/web/claim/system/controller/PushConfigController.java',
            'claim-web/src/test/java/com/huize/claim/web/claim/system/controller/PushConfigControllerTest.java'
        )
        tests = @(
            [ordered]@{
                phase = 'RED'
                command = 'mvn -Dtest=PushConfigControllerTest#deploySurface_shouldExposeAutoClaimConfigPayload test'
                result = 'blocked'
                evidence = 'Initial focused RED attempt compiled production but testCompile failed on ambiguous JUnit assertEquals overloads in the newly created focused test; this was repaired test-only before production edit.'
            },
            [ordered]@{
                phase = 'RED'
                command = 'mvn -Dtest=PushConfigControllerTest#deploySurface_shouldExposeAutoClaimConfigPayload test'
                result = 'fail'
                evidence = 'Tests run: 1, Failures: 1, Errors: 0, Skipped: 0. Business assertion failed because result.get("autoClaimConfigPayload") was null before production change.'
            },
            [ordered]@{
                phase = 'GREEN'
                command = 'mvn -Dtest=PushConfigControllerTest#deploySurface_shouldExposeAutoClaimConfigPayload test'
                result = 'pass'
                evidence = 'Tests run: 1, Failures: 0, Errors: 0, Skipped: 0.'
            }
        )
    })

    $exitWithClearFailure = Invoke-RedGate -ReplayRoot $tempRoot -SliceIndex 4
    Assert-True 'RED gate passes when a later clear business failure supersedes a blocked attempt' ($exitWithClearFailure -eq 0)
    $gate = Read-JsonFile (Join-Path $tempRoot 'RED_PHASE_GATE_04.json')
    Assert-True 'RED gate selected clear failure result' ([string]$gate.selected_red_result -eq 'fail') ($gate | ConvertTo-Json -Depth 12)
    $selectedWarnings = @($gate.warnings | Where-Object { [string]$_ -match '^selected_authoritative_red_phase:' })
    Assert-True 'RED gate selected authoritative RED warning for multi-RED result' ($selectedWarnings.Count -gt 0) ($gate | ConvertTo-Json -Depth 12)

    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_05.json') ([ordered]@{
        slice_index = 5
        slice_status = 'DONE'
        implemented_files = @(
            'claim-web/src/main/java/com/huize/claim/web/claim/system/controller/PushConfigController.java'
        )
        current_slice_changed_files = @(
            'claim-web/src/main/java/com/huize/claim/web/claim/system/controller/PushConfigController.java',
            'claim-web/src/test/java/com/huize/claim/web/claim/system/controller/PushConfigControllerTest.java'
        )
        tests = @(
            [ordered]@{
                phase = 'RED'
                command = 'mvn -Dtest=PushConfigControllerTest#deploySurface_shouldExposeAutoClaimConfigPayload test'
                result = 'blocked'
                evidence = 'Initial focused RED attempt compiled production but testCompile failed on ambiguous JUnit assertEquals overloads in the newly created focused test.'
            },
            [ordered]@{
                phase = 'GREEN'
                command = 'mvn -Dtest=PushConfigControllerTest#deploySurface_shouldExposeAutoClaimConfigPayload test'
                result = 'pass'
                evidence = 'Tests run: 1, Failures: 0, Errors: 0, Skipped: 0.'
            }
        )
    })

    $exitBlockedOnly = Invoke-RedGate -ReplayRoot $tempRoot -SliceIndex 5
    Assert-True 'RED gate still blocks when all RED attempts are blocked' ($exitBlockedOnly -ne 0)
    $blockedGate = Read-JsonFile (Join-Path $tempRoot 'RED_PHASE_GATE_05.json')
    $codes = @($blockedGate.issues | ForEach-Object { [string]$_.code })
    Assert-True 'blocked-only case records red_phase_blocked' ($codes -contains 'red_phase_blocked') ($blockedGate | ConvertTo-Json -Depth 12)

    Write-Host 'v692 RED gate blocked-attempt selection regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
