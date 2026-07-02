#!/usr/bin/env pwsh
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw "FAIL: $Name" }
        throw "FAIL: $Name :: $Detail"
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

Import-RunSliceLoopFunctions

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v695-reused-gate-stale-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $runnerContract = Join-Path $tempRoot 'RUNNER_ENFORCEMENT_CONTRACT.md'
    '# contract' | Set-Content -LiteralPath $runnerContract -Encoding UTF8

    $forced = [pscustomobject]@{
        family_id = 'wire_payload_api_contract'
        slice_type = 'exact_contract_slice'
        target_sibling_surface = 'ClaimAgentFacadeImpl.batchQueryCaseDetail'
    }
    $sliceResult = Join-Path $tempRoot 'SLICE_RESULT_05.json'
    $sliceVerify = Join-Path $tempRoot 'SLICE_VERIFY_05.json'
    $v348Gate = Join-Path $tempRoot 'V348_SLICE_QUALITY_GATE_05.json'
    $progress = Join-Path $tempRoot 'SLICE_PROGRESS.json'

    Write-JsonFile $sliceResult ([ordered]@{
        slice_index = 5
        slice_status = 'PARTIAL'
        slice_type = 'exact_contract_slice'
        touched_requirement_families = @('wire_payload_api_contract')
        closed_requirement_families = @()
        implemented_files = @('example-core/src/main/java/acme/ClaimAgentFacadeImpl.java')
    })
    Write-JsonFile $sliceVerify ([ordered]@{
        slice_index = 5
        verification_status = 'FAIL'
        slice_status = 'PARTIAL'
        adjusted_coverage_delta = 0
        authorized_for_next_slice = $false
        authorized_for_synthesis = $false
        should_continue = $false
        touched_requirement_families = @('wire_payload_api_contract')
        closed_requirement_families = @()
        authorization_blockers = @('exact_contract_post_green_not_closed')
        gap_flags = @('exact_contract_boundary_proof_stop')
    })
    Write-JsonFile $v348Gate ([ordered]@{
        gate = 'v348_slice_quality'
        slice_index = 5
        can_proceed = $false
        issues = @('exact_contract_post_green_not_closed')
    })
    Write-JsonFile $progress ([ordered]@{
        replay_root = $tempRoot
        max_slices = 12
        completed = @(1, 2, 3, 4, 5)
        stopped = $true
        stop_reason = 'v348_slice_quality_gate: exact_contract_post_green_not_closed'
    })

    Assert-True 'v348-refreshed zero-coverage reused partial slice is stale' `
        (Test-StaleReusedSliceAfterGateRefresh -SliceResultPath $sliceResult -SliceVerifyPath $sliceVerify -ForcedDecision $forced)

    Archive-StaleSliceArtifacts `
        -ReplayRoot $tempRoot `
        -SliceIndex 5 `
        -Paths @($sliceResult, $sliceVerify, $v348Gate) `
        -Reason 'unit-test stale reused gate refresh' `
        -RunnerContractPath $runnerContract
    Normalize-SliceProgress -Path $progress -ReplayRoot $tempRoot -MaxSlices 12

    Assert-True 'stale reused slice result moved out of active root' (-not (Test-Path -LiteralPath $sliceResult))
    Assert-True 'stale reused slice verify moved out of active root' (-not (Test-Path -LiteralPath $sliceVerify))
    Assert-True 'stale reused v348 gate moved out of active root' (-not (Test-Path -LiteralPath $v348Gate))
    $archived = @(Get-ChildItem -LiteralPath (Join-Path $tempRoot 'logs\stale-slice-results\slice05') -File)
    Assert-True 'stale reused artifacts remain auditable' ($archived.Count -ge 3) ($archived | Select-Object Name | ConvertTo-Json)
    $progressJson = Get-Content -LiteralPath $progress -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'resume progress stop reason is cleared before fresh slice generation' (-not [bool]$progressJson.stopped -and [string]::IsNullOrWhiteSpace([string]$progressJson.stop_reason)) ($progressJson | ConvertTo-Json -Depth 8)

    $positiveVerify = Join-Path $tempRoot 'SLICE_VERIFY_POSITIVE_05.json'
    Write-JsonFile $positiveVerify ([ordered]@{
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 4
        authorized_for_next_slice = $false
        authorized_for_synthesis = $false
        should_continue = $false
        closed_requirement_families = @()
    })
    Write-JsonFile $sliceResult ([ordered]@{ slice_status = 'PARTIAL' })
    Assert-True 'positive verifier-adjusted progress is not treated as stale gate replay' `
        (-not (Test-StaleReusedSliceAfterGateRefresh -SliceResultPath $sliceResult -SliceVerifyPath $positiveVerify -ForcedDecision $forced))

    $authorizedVerify = Join-Path $tempRoot 'SLICE_VERIFY_AUTHORIZED_05.json'
    Write-JsonFile $authorizedVerify ([ordered]@{
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 0
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        should_continue = $true
        closed_requirement_families = @('wire_payload_api_contract')
    })
    Assert-True 'authorizing reused slice is not stale gate replay' `
        (-not (Test-StaleReusedSliceAfterGateRefresh -SliceResultPath $sliceResult -SliceVerifyPath $authorizedVerify -ForcedDecision $forced))

    Write-Host 'PASS: v695 reused gate failure archives stale partial slice'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
