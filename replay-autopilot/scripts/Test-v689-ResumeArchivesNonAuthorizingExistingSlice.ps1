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

$forced = [pscustomobject]@{
    family_id = 'stateful_side_effect'
    slice_type = 'stateful_success_slice'
    target_sibling_surface = 'TaskProcessor.handleTaskResponse'
}
$result = [pscustomobject]@{
    slice_status = 'DONE'
    touched_requirement_families = @('stateful_side_effect')
    closed_requirement_families = @('stateful_side_effect')
    implemented_files = @('claim-core/src/main/java/acme/TaskProcessor.java')
    gap_flags = @()
    slice_title = 'stale stateful slice'
    blocker = ''
    remaining_gaps = @()
}
$verify = [pscustomobject]@{
    verification_status = 'FAIL'
    authorized_for_next_slice = $false
    should_continue = $false
    touched_requirement_families = @('stateful_side_effect')
    closed_requirement_families = @()
    authorization_blockers = @('verification_failed_or_blocked')
    gap_flags = @('side_effect_db_evidence_missing')
}

Assert-True 'non_authorizing_done_slice_for_current_family_is_stale' (Test-StaleBlockedSliceForResume -SliceResultObject $result -SliceVerifyObject $verify -ForcedDecision $forced)

$verify.closed_requirement_families = @('stateful_side_effect')
$verify.verification_status = 'PARTIAL'
$verify.authorized_for_next_slice = $true
$verify.should_continue = $true
Assert-True 'authorizing_closed_slice_for_current_family_is_reusable' (-not (Test-StaleBlockedSliceForResume -SliceResultObject $result -SliceVerifyObject $verify -ForcedDecision $forced))

Write-Host 'PASS: v689 resume archives non-authorizing existing slice'
