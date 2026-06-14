param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$prevalidator = Join-Path $scriptRoot 'Invoke-TestCharterPrevalidator.ps1'
$prevalidatorPython = Join-Path $scriptRoot 'test_charter_prevalidator.py'
$prevalidatorPythonText = Get-Content -LiteralPath $prevalidatorPython -Raw -Encoding UTF8
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("test-charter-markdown-labels-v503-" + [guid]::NewGuid().ToString('N'))

try {
    Assert-True 'prevalidator_has_markdown_label_patterns' ($prevalidatorPythonText.Contains('MARKDOWN_LABEL_PREFIX') -and $prevalidatorPythonText.Contains('MARKDOWN_LABEL_SUFFIX'))

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Write-Text (Join-Path $tempRoot 'TEST_CHARTER.md') @'
# Test Charter

## **Test Class**: SampleFacadeTest

### RED Phase

#### Scenario: Preserves output state
**Entry Point**: `SampleFacade.execute(Long id)`

**DB Verification**: AtomicReference capture verifies output state.

**Side Effects**:
- verify: assertEquals expected state after execute

**Transaction Test**: transaction rollback not required for this in-memory behavior proof.
'@

    $outPath = Join-Path $tempRoot 'prevalidator-output.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $prevalidator -WorkDir $tempRoot -PassThru > $outPath
    $exitCode = $LASTEXITCODE
    $resultText = Get-Content -LiteralPath $outPath -Raw -Encoding UTF8
    $result = $resultText | ConvertFrom-Json

    Assert-True 'markdown_bold_entry_point_is_accepted' ($exitCode -eq 0 -and [bool]$result.can_proceed)
    Assert-True 'markdown_bold_labels_do_not_emit_entry_failure' (-not (($result.failures | ForEach-Object { $_.code }) -contains 'MISSING_ENTRY_POINT'))

    Write-Host 'PASS: v503 test charter markdown labels'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
