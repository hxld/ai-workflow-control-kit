#!/usr/bin/env pwsh
param([switch]$KeepTemp)

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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v702-zero-coverage-progress-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Import-RunSliceLoopFunctions

    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'PARTIAL'
        touched_requirement_families = @('core_entry')
        implemented_files = @('example-core/src/main/java/acme/TaskProcessor.java')
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PARTIAL'
        slice_status = 'PARTIAL'
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        should_continue = $true
        adjusted_coverage_delta = 3
        closed_requirement_families = @('core_entry')
        authorization_blockers = @()
    })

    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_02.json') ([ordered]@{
        slice_index = 2
        slice_status = 'PARTIAL'
        touched_requirement_families = @('wire_payload_api_contract')
        closed_requirement_families = @()
        implemented_files = @('example-core/src/main/java/acme/PayloadProcessor.java')
        gap_flags = @('exact_contract_gap', 'exact_contract_minimum_coverage_gap')
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_VERIFY_02.json') ([ordered]@{
        slice_index = 2
        verification_status = 'PARTIAL'
        slice_status = 'PARTIAL'
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        should_continue = $true
        adjusted_coverage_delta = 0
        touched_requirement_families = @('wire_payload_api_contract')
        closed_requirement_families = @()
        authorization_blockers = @()
        gap_flags = @('exact_contract_gap', 'exact_contract_minimum_coverage_gap')
    })

    Assert-True 'closed positive verifier evidence is progress' `
        (Test-AuthorizingSliceEvidence -ReplayRoot $tempRoot -SliceIndex 1)
    Assert-True 'authorized next-slice zero-coverage evidence is not progress' `
        (-not (Test-AuthorizingSliceEvidence -ReplayRoot $tempRoot -SliceIndex 2))

    $forced = [pscustomobject]@{
        family_id = 'wire_payload_api_contract'
        slice_type = 'exact_contract_slice'
        target_sibling_surface = 'PayloadProcessor.handle'
    }
    $result2 = Get-Content -LiteralPath (Join-Path $tempRoot 'SLICE_RESULT_02.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $verify2 = Get-Content -LiteralPath (Join-Path $tempRoot 'SLICE_VERIFY_02.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'authorized reusable zero-coverage slice is stale for resume' `
        (Test-StaleBlockedSliceForResume -SliceResultObject $result2 -SliceVerifyObject $verify2 -ForcedDecision $forced)

    $progressPath = Join-Path $tempRoot 'SLICE_PROGRESS.json'
    Set-SliceProgressFromAuthorizingEvidence -Path $progressPath -ReplayRoot $tempRoot -MaxSlices 2
    $progress = Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'progress excludes authorized zero-coverage slice' `
        ((@($progress.completed) -join ',') -eq '1') ($progress | ConvertTo-Json -Depth 8)

    Write-JsonFile $progressPath ([ordered]@{
        replay_root = $tempRoot
        max_slices = 12
        completed = @(1, 2, 3)
        stopped = $true
        stop_reason = 'stale stop'
    })
    Normalize-SliceProgress -Path $progressPath -ReplayRoot $tempRoot -MaxSlices 12
    $progress = Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'normalize prunes active zero-coverage completed slice' `
        ((@($progress.completed) -join ',') -eq '1,3') ($progress | ConvertTo-Json -Depth 8)
    Assert-True 'normalize clears stale stop marker' `
        (-not [bool]$progress.stopped -and [string]::IsNullOrWhiteSpace([string]$progress.stop_reason)) ($progress | ConvertTo-Json -Depth 8)

    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_03.json') ([ordered]@{
        slice_index = 3
        slice_status = 'DONE'
        implemented_files = @('example-core/src/main/java/acme/Finalizer.java')
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_VERIFY_03.json') ([ordered]@{
        slice_index = 3
        verification_status = 'PASS'
        slice_status = 'DONE'
        authorized_for_next_slice = $false
        authorized_for_synthesis = $true
        should_continue = $false
        adjusted_coverage_delta = 0
        closed_requirement_families = @()
        authorization_blockers = @()
    })
    Assert-True 'synthesis-authorized terminal evidence remains resumable' `
        (Test-AuthorizingSliceEvidence -ReplayRoot $tempRoot -SliceIndex 3)

    Write-Host 'PASS: v702 zero-coverage reusable slice is not progress'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
