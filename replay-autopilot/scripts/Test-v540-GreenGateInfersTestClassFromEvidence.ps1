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

function Import-RunSliceLoopFunctions {
    $runSliceLoop = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-SliceLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }

    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($functionAst in @($functionAsts)) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v540-" + [guid]::NewGuid().ToString('N'))

try {
    $slice = [pscustomobject]@{
        tests = @([pscustomobject]@{ phase = 'GREEN'; command = 'test execution'; result = 'pass' })
        behavior_test_charter = [pscustomobject]@{
            evidence_file = 'example-server/src/test/java/com/example/project/core/ai/task/PolicyNumRebuildPathTest.java'
        }
        current_slice_changed_files = @(
            'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java',
            'example-server/src/test/java/com/example/project/core/ai/task/PolicyNumRebuildPathTest.java'
        )
    }

    Import-RunSliceLoopFunctions
    $class = Get-TestClassFromSliceEvidence -SliceResultObject $slice
    $module = Get-TestModuleFromSliceEvidence -SliceResultObject $slice -ImplementedFiles @('example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java')
    Assert-True 'GREEN gate infers test class from behavior evidence file' ([string]$class -eq 'PolicyNumRebuildPathTest') $class
    Assert-True 'GREEN gate still infers test module from evidence path' ([string]$module -eq 'example-server') $module

    Write-Host 'v540 GREEN gate test class inference regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
