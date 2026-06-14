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
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sliceLoop, [ref]$tokens, [ref]$errors)
Assert-True 'Run-SliceLoop parses after v514' (-not $errors -or $errors.Count -eq 0)

$helperAst = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Convert-TestCharterDiagnosticList'
}, $true)

Assert-True 'diagnostic helper function found' ($null -ne $helperAst)

$helperText = $helperAst.Extent.Text
Assert-True 'helper uses plain object array accumulator' ($helperText.Contains('$diagnostics = @()'))
Assert-True 'helper returns PSCustomObject diagnostic entries' ($helperText.Contains('$diagnostics += [pscustomobject]$entry'))
Assert-True 'helper no longer returns Generic.List container' (-not $helperText.Contains('System.Collections.Generic.List'))

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

Invoke-Expression $helperText

$validatorOutput = @'
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
'@ | ConvertFrom-Json

$result = [ordered]@{
    failures = @()
    warnings = @()
}

$result.failures = @(Convert-TestCharterDiagnosticList $validatorOutput.failures)
$result.warnings = @(Convert-TestCharterDiagnosticList $validatorOutput.warnings)

Assert-True 'failures assignment does not throw and keeps one item' ($result.failures.Count -eq 1)
Assert-True 'warnings assignment does not throw and keeps two items' ($result.warnings.Count -eq 2)
Assert-True 'failure diagnostic code survives conversion' ([string]$result.failures[0].code -eq 'MISSING_ENTRY_POINT')
Assert-True 'warning diagnostic code survives conversion' ([string]$result.warnings[0].code -eq 'MISSING_DB_VERIFICATION')

$json = ([pscustomobject]$result) | ConvertTo-Json -Depth 8
Assert-True 'converted result serializes as JSON' ($json.Contains('"MISSING_ENTRY_POINT"') -and $json.Contains('"MISSING_SIDE_EFFECTS_LIST"'))

Write-Host 'v514 test charter diagnostic array regression passed.'
