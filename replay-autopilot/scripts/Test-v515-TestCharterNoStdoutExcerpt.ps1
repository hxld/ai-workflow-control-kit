param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-autopilot-v515-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )
    if (-not $Condition) {
        throw "ASSERT FAILED: $Name"
    }
    Write-Host "PASS: $Name"
}

try {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($sliceLoop, [ref]$tokens, [ref]$errors)
    Assert-True 'Run-SliceLoop parses after v515' (-not $errors -or $errors.Count -eq 0)

    $text = Get-Content -LiteralPath $sliceLoop -Raw -Encoding UTF8
    $gateStart = $text.IndexOf('function Invoke-TestCharterPrevalidatorGate')
    $gateEnd = $text.IndexOf('function Invoke-TestCharterRepairGate')
    Assert-True 'test charter gate function boundaries found' ($gateStart -ge 0 -and $gateEnd -gt $gateStart)
    $gateText = $text.Substring($gateStart, $gateEnd - $gateStart)

    Assert-True 'gate keeps stdout log path' ($gateText.Contains('$result.stdout_log = $stdoutPath'))
    Assert-True 'gate does not serialize stdout excerpt' (-not $gateText.Contains('stdout_excerpt'))
    Assert-True 'gate does not serialize full stdout output' (-not $gateText.Contains('$result.stdout_output = $stdoutText'))

    $samplePath = Join-Path $tempRoot 'validator-stdout.json'
    @'
{
    "can_proceed": false,
    "verification_status": "FAILED",
    "failures": [
        {
            "code": "MISSING_ENTRY_POINT",
            "message": "Entry point not specified in test charter",
            "detail": "Required: Add \"Entry Point: YourFacade.yourMethod()\" or similar"
        }
    ],
    "warnings": [
        {
            "code": "MISSING_DB_VERIFICATION",
            "message": "No DB verification queries found",
            "detail": "Required: Add SELECT queries or AtomicReference capture patterns for side effects"
        },
        {
            "code": "MISSING_SIDE_EFFECTS_LIST",
            "message": "Side effects not explicitly listed"
        }
    ],
    "failure_count": 1,
    "warning_count": 2
}
'@ | Set-Content -LiteralPath $samplePath -Encoding UTF8

    $probePath = Join-Path $tempRoot 'ps5-json-probe.ps1'
    $resultPath = Join-Path $tempRoot 'gate-result.json'
    @"
`$ErrorActionPreference = 'Stop'
`$stdoutPath = '$($samplePath.Replace("'", "''"))'
`$resultPath = '$($resultPath.Replace("'", "''"))'
`$stdoutText = Get-Content -LiteralPath `$stdoutPath -Raw -Encoding UTF8
`$jsonOutput = `$stdoutText | ConvertFrom-Json
function Convert-TestCharterDiagnosticList {
    param(`$Items)
    `$diagnostics = @()
    foreach (`$item in @(`$Items)) {
        if (`$null -eq `$item) { continue }
        `$entry = [ordered]@{}
        foreach (`$name in @('code', 'message', 'detail')) {
            if (`$item.PSObject.Properties[`$name]) {
                `$entry[`$name] = [string]`$item.`$name
            }
        }
        if (`$entry.Count -eq 0) {
            `$entry['message'] = [string]`$item
        }
        `$diagnostics += [pscustomobject]`$entry
    }
    return @(`$diagnostics)
}
`$result = [ordered]@{
    gate = 'test_charter_prevalidation'
    slice_index = 1
    verification_status = 'FAILED'
    can_proceed = `$false
    failures = @(Convert-TestCharterDiagnosticList `$jsonOutput.failures)
    warnings = @(Convert-TestCharterDiagnosticList `$jsonOutput.warnings)
    exit_code = 1
    stdout_log = `$stdoutPath
    failure_count = [int]`$jsonOutput.failure_count
    warning_count = [int]`$jsonOutput.warning_count
}
([pscustomobject]`$result) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath `$resultPath -Encoding UTF8
"@ | Set-Content -LiteralPath $probePath -Encoding UTF8

    $stdoutLog = Join-Path $tempRoot 'ps5-json-probe.stdout.log'
    $stderrLog = Join-Path $tempRoot 'ps5-json-probe.stderr.log'
    $process = Start-Process -FilePath powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $probePath) -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit(10000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'Windows PowerShell 5 JSON probe timed out; stdout text may still be embedded in gate JSON.'
    }
    Assert-True 'Windows PowerShell 5 JSON probe exits successfully' ($process.ExitCode -eq 0)
    Assert-True 'Windows PowerShell 5 JSON probe wrote result' (Test-Path -LiteralPath $resultPath)
    $probeJson = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8
    Assert-True 'Windows PowerShell 5 JSON result keeps stdout_log' ($probeJson.Contains('"stdout_log"'))
    Assert-True 'Windows PowerShell 5 JSON result omits stdout_excerpt' (-not $probeJson.Contains('"stdout_excerpt"'))
    Assert-True 'Windows PowerShell 5 JSON result keeps diagnostic code' ($probeJson.Contains('"MISSING_ENTRY_POINT"'))

    Write-Host 'v515 test charter no-stdout-excerpt regression passed.'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
