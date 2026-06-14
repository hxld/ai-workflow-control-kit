param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-contract-repair-prompt-v482-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8

    Assert-True 'plan_contract_repair_prompt_uses_single_quoted_template' ($runLoopText -match "(?s)\`$planContractRepairPrompt\s*=\s*@'")
    Assert-True 'plan_contract_repair_prompt_replaces_initial_verify_placeholder' ($runLoopText -match [regex]::Escape('$planContractRepairPrompt = $planContractRepairPrompt.Replace(''$initialVerifyText'', $initialVerifyText)'))
    Assert-True 'plan_contract_repair_prompt_replaces_result_path_placeholder' ($runLoopText -match [regex]::Escape('$planContractRepairPrompt = $planContractRepairPrompt.Replace(''$contractRepairResultPath'', $contractRepairResultPath)'))

    $match = [regex]::Match(
        $runLoopText,
        "(?s)\`$planContractRepairPrompt\s*=\s*@'\r?\n(?<body>.*?)\r?\n'@\r?\n\s*\`$planContractRepairPrompt\s*=\s*\`$planContractRepairPrompt\.Replace"
    )
    Assert-True 'plan_contract_repair_prompt_template_extractable' $match.Success

    $initialVerifyText = @'
{
  "issues": [
    "policy_rebuild_plan_invalid:test_harness_claim_core",
    "policy_rebuild_plan_invalid:fixed_db_caseid",
    "policy_rebuild_plan_invalid:null_taskdata_pass_path",
    "policy_rebuild_plan_invalid:dto_or_downstream_only"
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
    Assert-True 'plan_contract_repair_prompt_has_no_backtick_escape_control_chars' ($forbiddenControlChars.Count -eq 0)
    Assert-True 'prompt_preserves_first_slice_contract_literal' ($promptText.Contains('`first_slice_contract`'))
    Assert-True 'prompt_preserves_real_entry_literal' ($promptText.Contains('`real_entry`'))
    Assert-True 'prompt_preserves_new_service_proposed_literal' ($promptText.Contains('`new_service_proposed: true | false`'))
    Assert-True 'prompt_preserves_target_carrier_file_path_literal' ($promptText.Contains('`target_carrier_file_path: <exact file path>'))
    Assert-True 'prompt_preserves_first_red_test_literal' ($promptText.Contains('`first_red_test:`'))
    Assert-True 'prompt_preserves_taskdata_null_literal' ($promptText.Contains('`taskData == null`'))
    Assert-True 'prompt_preserves_req_policy_assignment_literal' ($promptText.Contains('`req.setPolicyNum(buildContext.getPolicyNum())`'))
    Assert-True 'prompt_preserves_contract_repair_result_path' ($promptText.Contains($contractRepairResultPath))

    Write-Host 'PASS: v482 plan contract repair prompt literal backticks'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
