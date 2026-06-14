param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-contract-repair-policy-v483-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8

    $match = [regex]::Match(
        $runLoopText,
        "(?s)\`$planContractRepairPrompt\s*=\s*@'\r?\n(?<body>.*?)\r?\n'@\r?\n\s*\`$planContractRepairPrompt\s*=\s*\`$planContractRepairPrompt\.Replace"
    )
    Assert-True 'plan_contract_repair_prompt_template_extractable' $match.Success

    $initialVerifyText = @'
{
  "issues": [
    "policy_rebuild_plan_missing:AiClaimDataAssemblyHelper.RequestBuildFunction",
    "policy_rebuild_plan_missing:AiClaimDataAssemblyHelper.buildRequestCommon",
    "policy_rebuild_plan_invalid:fixed_db_caseid"
  ],
  "residual_examples": [
    "Function<RequestBuildContext, T>",
    "RequestBuildFunction",
    "Long caseId = 12345L",
    "ctx.setCaseId(12345L)",
    "mockContext.setCaseId(12345L)",
    "rebuildTaskData(12345L)"
  ]
}
'@
    $contractRepairResultPath = Join-Path $tempRoot 'PLAN_CONTRACT_REPAIR_RESULT.md'
    $prompt = $match.Groups['body'].Value
    $prompt = $prompt.Replace('$initialVerifyText', $initialVerifyText)
    $prompt = $prompt.Replace('$contractRepairResultPath', $contractRepairResultPath)

    $promptPath = Join-Path $tempRoot 'PLAN_CONTRACT_REPAIR_PROMPT.md'
    Set-Content -LiteralPath $promptPath -Encoding UTF8 -Value $prompt
    $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8

    $forbiddenControlChars = [regex]::Matches($promptText, '[\x00-\x09\x0B\x0C\x0E-\x1F]')
    Assert-True 'plan_contract_repair_prompt_has_no_control_chars' ($forbiddenControlChars.Count -eq 0)

    Assert-True 'prompt_handles_exact_request_build_function_missing_issue' (
        $promptText.Contains('policy_rebuild_plan_missing:AiClaimDataAssemblyHelper.RequestBuildFunction')
    )
    Assert-True 'prompt_handles_exact_build_request_common_missing_issue' (
        $promptText.Contains('policy_rebuild_plan_missing:AiClaimDataAssemblyHelper.buildRequestCommon')
    )
    Assert-True 'prompt_requires_both_fully_qualified_source_chain_tokens' (
        $promptText.Contains('add both exact literal tokens `AiClaimDataAssemblyHelper.buildRequestCommon` and `AiClaimDataAssemblyHelper.RequestBuildFunction`')
    )
    Assert-True 'prompt_rejects_near_miss_request_build_function_substitutes' (
        $promptText.Contains('Do not substitute `buildRequestCommon`, `RequestBuildFunction`, `Function<RequestBuildContext, T>`, or `requestBuilder` alone')
    )
    Assert-True 'prompt_lists_fixed_caseid_code_shapes_from_r19' (
        $promptText.Contains('`Long caseId = 12345L`') -and
        $promptText.Contains('`ctx.setCaseId(12345L)`') -and
        $promptText.Contains('`mockContext.setCaseId(12345L)`') -and
        $promptText.Contains('`rebuildTaskData(12345L)`')
    )
    Assert-True 'prompt_requires_symbolic_fixture_caseid_rewrite' (
        $promptText.Contains('`Long fixtureCaseId = generatedFixtureCaseId`') -and
        $promptText.Contains('`ctx.setCaseId(fixtureCaseId)`') -and
        $promptText.Contains('`rebuildTaskData(fixtureCaseId)`')
    )
    Assert-True 'prompt_requires_policy_rebuild_self_scan_presence_and_absence' (
        $promptText.Contains('The scan must prove both `AiClaimDataAssemblyHelper.buildRequestCommon` and `AiClaimDataAssemblyHelper.RequestBuildFunction` exist') -and
        $promptText.Contains('the following forbidden residues do not exist anywhere') -and
        $promptText.Contains('`12345L`, `67890L`, `fixed caseId`, `fixed database caseId`, `fixed database caseIds`, `fixed DB caseId`, `real database caseId`, `external test data`')
    )

    Write-Host 'PASS: v483 plan contract repair policy rebuild residuals'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
