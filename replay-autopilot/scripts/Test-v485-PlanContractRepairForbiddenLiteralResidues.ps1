param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-contract-repair-forbidden-v485-" + [guid]::NewGuid().ToString('N'))

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
    "policy_rebuild_plan_invalid:fixed_db_caseid",
    "policy_rebuild_plan_invalid:null_taskdata_pass_path",
    "policy_rebuild_plan_invalid:dto_or_downstream_only"
  ],
  "residual_examples": [
    "No test uses fixed database caseIds",
    "Trigger Condition: taskData == null in doIt() method",
    "taskData.setPolicyNum(request.getPolicyNum())"
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

    Assert-True 'prompt_forbids_fixed_database_caseids_negative_checklist' (
        $promptText.Contains('These tokens are forbidden even in negative checklist text such as "No test uses fixed database caseIds"') -and
        $promptText.Contains('rewrite that as "No numeric fixture id literals are used."')
    )
    Assert-True 'prompt_forbids_null_taskdata_literals_even_red' (
        $promptText.Contains('remove the exact literal forms `taskData == null`, `result == null`, `null then pass`, `null then warn`, `null then print`, and `returns null pass`') -and
        $promptText.Contains('forbidden even when describing RED failure, fail-closed behavior, trigger conditions, or boundary conditions')
    )
    Assert-True 'prompt_rejects_doIt_null_branch_as_first_slice' (
        $promptText.Contains('Do not use the doIt null-taskData branch as the first-slice proof')
    )
    Assert-True 'prompt_forbids_downstream_taskdata_setter_literal' (
        $promptText.Contains('remove the exact literal forms `DTO getter`, `getter/setter`, `hasPolicyNumAndInsureNumFields`, `field existence`, and `taskData.setPolicyNum(request.getPolicyNum())`')
    )
    Assert-True 'prompt_requires_self_scan_for_all_r20_residues' (
        $promptText.Contains('`fixed database caseIds`') -and
        $promptText.Contains('`taskData == null`') -and
        $promptText.Contains('`taskData.setPolicyNum(request.getPolicyNum())`')
    )

    Write-Host 'PASS: v485 plan contract repair forbidden literal residues'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
