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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v543-stale-resume-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $runnerContract = Join-Path $tempRoot 'RUNNER_ENFORCEMENT_CONTRACT.md'
    '# contract' | Set-Content -LiteralPath $runnerContract -Encoding UTF8
    $sourceChainPath = Join-Path $tempRoot 'SOURCE_CHAIN_CONTRACT.json'
    Write-JsonFile $sourceChainPath ([ordered]@{
        required_source_chain = $true
        next_required_slice = [ordered]@{
            slice_type = 'exact_contract_slice'
            carrier = 'TaskProcessor rebuildTaskData -> InputData.policy_num/InputData.insure_num'
        }
    })

    Import-RunSliceLoopFunctions

    $ledger = [pscustomobject]@{
        families = @(
            [pscustomobject]@{
                id = 'core_entry'
                required = $true
                status = 'EXECUTABLE_CLOSED'
                touched_count = 1
                weight = 100
                recommended_slice_type = 'exact_contract_slice'
                open_sibling_surfaces = @()
                first_executable_carrier = 'AiApplyClaimApiTaskProcessor.rebuildTaskData'
                proof_required = @('behavior_test')
                forbidden_proof = @('helper_only')
                last_gap_flags = @()
            },
            [pscustomobject]@{
                id = 'wire_payload_api_contract'
                required = $true
                status = 'OPEN'
                touched_count = 0
                weight = 88
                recommended_slice_type = 'exact_contract_slice'
                open_sibling_surfaces = @('AiApplyClaimApiTaskProcessor.doIt')
                first_executable_carrier = 'AiApplyClaimApiTaskProcessor.doIt'
                proof_required = @('payload_assertion')
                forbidden_proof = @('helper_only')
                last_gap_flags = @()
            }
        )
    }

    $rank = New-CarrierRankMap -Ledger $ledger -SliceIndex 2
    $forced = Resolve-ForcedFamilyDecisionForSlice -Ledger $ledger -SliceIndex 2 -CarrierRank $rank -SourceChainContractPath $sourceChainPath -RunnerContractPath $runnerContract
    Assert-True 'source-chain override is skipped once core_entry is closed' ([string]$forced.family_id -eq 'wire_payload_api_contract') ($forced | ConvertTo-Json -Depth 10)
    $contractText = Get-Content -LiteralPath $runnerContract -Raw -Encoding UTF8
    Assert-True 'source-chain skip is recorded in runner contract' ($contractText.Contains('source-chain override skipped')) $contractText

    $staleResult = [pscustomobject]@{
        slice_status = 'BLOCKED'
        slice_title = 'pre-slice authorization stopped before implementation: forced_family_not_highest_weight_open:core_entry!=rank1:wire_payload_api_contract'
        blocker = 'Phase1 slice blocked'
        implemented_files = @()
        remaining_gaps = @('pre-slice authorization stopped before implementation')
        gap_flags = @('tooling_executor_failed', 'no_progress_slice', 'gate_present_but_not_enforced')
    }
    $staleVerify = [pscustomobject]@{
        authorization_blockers = @('verification_failed_or_blocked', 'behavior_evidence_missing')
        gap_flags = @('tooling_executor_failed', 'no_progress_slice', 'gate_present_but_not_enforced')
        closed_requirement_families = @()
        next_required_slice = [pscustomobject]@{ family = 'source_chain' }
    }
    Assert-True 'no-progress blocked slice is stale for resume' (Test-StaleBlockedSliceForResume -SliceResultObject $staleResult -SliceVerifyObject $staleVerify -ForcedDecision $forced)

    $sliceResult = Join-Path $tempRoot 'SLICE_RESULT_02.json'
    $sliceVerify = Join-Path $tempRoot 'SLICE_VERIFY_02.json'
    Write-JsonFile $sliceResult $staleResult
    Write-JsonFile $sliceVerify $staleVerify
    Archive-StaleSliceArtifacts -ReplayRoot $tempRoot -SliceIndex 2 -Paths @($sliceResult, $sliceVerify) -Reason 'unit-test stale blocker' -RunnerContractPath $runnerContract
    Assert-True 'stale slice result moved out of active replay root' (-not (Test-Path -LiteralPath $sliceResult))
    Assert-True 'stale slice verify moved out of active replay root' (-not (Test-Path -LiteralPath $sliceVerify))
    $archived = @(Get-ChildItem -LiteralPath (Join-Path $tempRoot 'logs\stale-slice-results\slice02') -File)
    Assert-True 'stale artifacts archived for audit' ($archived.Count -ge 2) ($archived | Select-Object Name | ConvertTo-Json)

    Write-Host 'v543 stale blocked slice resume and source-chain override regression passed.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
