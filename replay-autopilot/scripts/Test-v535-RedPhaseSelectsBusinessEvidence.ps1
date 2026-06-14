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

$script = Join-Path $PSScriptRoot 'Invoke-RedPhaseHardGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("red-phase-v535-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $slice = Join-Path $tempRoot 'SLICE_RESULT_01.json'
    Write-JsonFile $slice ([ordered]@{
        slice_index = 1
        implemented_files = @(
            'claim-core/src/main/java/acme/ApplyProcessor.java',
            'claim-core/src/main/java/acme/CalcProcessor.java'
        )
        current_slice_changed_files = @(
            'claim-core/src/main/java/acme/ApplyProcessor.java',
            'claim-core/src/main/java/acme/CalcProcessor.java',
            'claim-server/src/test/java/acme/PolicyNumRebuildPathTest.java'
        )
        tests = @(
            [ordered]@{ phase = 'RED'; command = 'test-compile'; result = 'pass'; evidence = 'Test class compiled successfully' },
            [ordered]@{ phase = 'RED'; command = 'test execution with fixed argument index'; result = 'pass'; evidence = 'Tests ran but with failures indicating missing source-chain assignments' },
            [ordered]@{ phase = 'GREEN'; command = 'test execution'; result = 'pass'; evidence = 'Tests run: 5, Failures: 0, Errors: 0, Skipped: 0' }
        )
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -VerifyOnly -SliceResultPath $slice -SliceIndex 1 -ReplayRoot $tempRoot | Out-Null
    Assert-True 'RED gate authorizes business failure evidence after compile pass' ($LASTEXITCODE -eq 0)
    $gate = Read-JsonFile (Join-Path $tempRoot 'RED_PHASE_GATE_01.json')
    Assert-True 'RED gate selected business RED command' ([string]$gate.selected_red_command -eq 'test execution with fixed argument index') ($gate | ConvertTo-Json -Depth 12)
    Assert-True 'RED gate records pass-with-business-evidence warning' (@($gate.warnings) -contains 'red_phase_result_pass_with_business_failure_evidence') ($gate | ConvertTo-Json -Depth 12)

    Write-Host 'v535 RED phase business evidence selection regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
