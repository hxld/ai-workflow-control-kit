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
$repoRoot = Split-Path -Parent $scriptRoot
$runSliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$requirementWrapper = Join-Path $scriptRoot 'Invoke-RequirementContractValidation.ps1'
$phase1Prompt = Join-Path $repoRoot 'prompts\phase1-slice-executor.prompt.md'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("v504-cross-module-harness-" + [guid]::NewGuid().ToString('N'))

try {
    $runSliceLoopText = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8
    $promptText = Get-Content -LiteralPath $phase1Prompt -Raw -Encoding UTF8
    $wrapperText = Get-Content -LiteralPath $requirementWrapper -Raw -Encoding UTF8

    Assert-True 'runner_has_cross_module_harness_dependency_check' (
        $runSliceLoopText.Contains('Test-TestModuleDependsOnProductionModule') -and
        $runSliceLoopText.Contains('cross_module_test_harness_depends_on_production_module') -and
        $runSliceLoopText.Contains('-Worktree $Worktree')
    )
    Assert-True 'phase1_prompt_uses_generic_cross_module_rule' (
        $promptText.Contains('默认把测试放在生产文件同一 Maven 模块') -and
        $promptText.Contains('cross_module_test_harness_depends_on_production_module') -and
        $promptText.Contains('scripts\Invoke-TestCharterPrevalidator.ps1')
    )
    Assert-True 'requirement_wrapper_handles_non_json_plan' (
        $wrapperText.Contains('PLAN_RESULT_NOT_JSON') -and
        $wrapperText.Contains('Resolve-PythonLauncher') -and
        $wrapperText.Contains('PYTHON_OUTPUT_NOT_JSON')
    )

    $start = $runSliceLoopText.IndexOf('function Get-SourcePathModule')
    $end = $runSliceLoopText.IndexOf('function Invoke-V348SliceQualityGates')
    Assert-True 'can_extract_v348_module_helpers' ($start -ge 0 -and $end -gt $start)
    Invoke-Expression $runSliceLoopText.Substring($start, $end - $start)

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Write-Text (Join-Path $tempRoot 'sample-core\pom.xml') @'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>example</groupId>
  <artifactId>sample-core</artifactId>
  <version>1.0.0</version>
</project>
'@
    Write-Text (Join-Path $tempRoot 'sample-server\pom.xml') @'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>example</groupId>
  <artifactId>sample-server</artifactId>
  <version>1.0.0</version>
  <dependencies>
    <dependency>
      <groupId>example</groupId>
      <artifactId>sample-core</artifactId>
      <version>1.0.0</version>
    </dependency>
  </dependencies>
</project>
'@
    Write-Text (Join-Path $tempRoot 'sample-other\pom.xml') @'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>example</groupId>
  <artifactId>sample-other</artifactId>
  <version>1.0.0</version>
</project>
'@

    $validSurface = Test-TestFileMatchesProductionModule `
        -TestFile 'sample-server/src/test/java/com/example/SampleCarrierTest.java' `
        -ImplementedFiles @('sample-core/src/main/java/com/example/SampleCarrier.java') `
        -Worktree $tempRoot
    Assert-True 'cross_module_harness_with_dependency_is_valid' ([bool]$validSurface.valid -and [string]$validSurface.reason -eq 'cross_module_test_harness_depends_on_production_module')

    $invalidSurface = Test-TestFileMatchesProductionModule `
        -TestFile 'sample-other/src/test/java/com/example/SampleCarrierTest.java' `
        -ImplementedFiles @('sample-core/src/main/java/com/example/SampleCarrier.java') `
        -Worktree $tempRoot
    Assert-True 'cross_module_without_dependency_still_fails' (-not [bool]$invalidSurface.valid -and [string]$invalidSurface.reason -eq 'test_module_differs_from_production_module')

    $planMarkdown = Join-Path $tempRoot 'PLAN_RESULT.md'
    $ledgerJson = Join-Path $tempRoot 'REQUIREMENT_FAMILY_LEDGER.json'
    Write-Text $planMarkdown '# Plan Result'
    Write-Text $ledgerJson '{"families":[]}'
    $wrapperOut = Join-Path $tempRoot 'requirement-wrapper.out'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $requirementWrapper -PlanResultPath $planMarkdown -RequirementLedgerPath $ledgerJson > $wrapperOut
    $wrapperExit = $LASTEXITCODE
    $wrapperOutput = Get-Content -LiteralPath $wrapperOut -Raw -Encoding UTF8
    Assert-True 'requirement_wrapper_skips_markdown_without_traceback' ($wrapperExit -eq 0 -and $wrapperOutput.Contains('PLAN_RESULT_NOT_JSON') -and -not $wrapperOutput.Contains('Traceback'))

    Write-Host 'PASS: v504 cross-module harness and requirement wrapper'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
