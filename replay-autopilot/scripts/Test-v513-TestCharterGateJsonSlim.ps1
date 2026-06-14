param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'

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

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($sliceLoop, [ref]$tokens, [ref]$errors)
Assert-True 'Run-SliceLoop parses after v513' (-not $errors -or $errors.Count -eq 0)

$text = Get-Content -LiteralPath $sliceLoop -Raw -Encoding UTF8
$gateStart = $text.IndexOf('function Invoke-TestCharterPrevalidatorGate')
$gateEnd = $text.IndexOf('function Invoke-TestCharterRepairGate')
Assert-True 'test charter gate function boundaries found' ($gateStart -ge 0 -and $gateEnd -gt $gateStart)
$gateText = $text.Substring($gateStart, $gateEnd - $gateStart)

Assert-True 'diagnostic sanitizer exists' ($text.Contains('function Convert-TestCharterDiagnosticList'))
Assert-True 'failure diagnostics are sanitized' ($gateText.Contains('Convert-TestCharterDiagnosticList $jsonOutput.failures'))
Assert-True 'warning diagnostics are sanitized' ($gateText.Contains('Convert-TestCharterDiagnosticList $jsonOutput.warnings'))
Assert-True 'stdout is referenced by log path only' ($gateText.Contains('$result.stdout_log = $stdoutPath') -and -not $gateText.Contains('stdout_excerpt'))
Assert-True 'test charter gate writes plain pscustomobject json' ($gateText.Contains('([pscustomobject]$result) | ConvertTo-Json -Depth 8'))
Assert-True 'test charter gate no longer embeds full stdout_output' (-not $gateText.Contains('$result.stdout_output = $stdoutText'))
Assert-True 'test charter repair gate still present' ($text.Contains('function Invoke-TestCharterRepairGate'))

Write-Host 'v513 test charter gate JSON slimming regression passed.'
