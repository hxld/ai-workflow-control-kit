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
    param([string]$Path, [object]$Value, [int]$Depth = 16)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v698-carrier-invocation-same-round-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    $entry = 'com.huize.claim.core.examine.service.CaseExamineLogService.saveExamineLog'
    $signature = 'void com.huize.claim.core.examine.service.CaseExamineLogService.saveExamineLog(Long, String, String, String)'
    $contractPath = Join-Path $replayRoot 'SLICE_EXECUTION_CONTRACT_05.json'
    $indexPath = Join-Path $replayRoot 'replay-context-index.json'
    $outputPath = Join-Path $replayRoot 'CARRIER_INVOCATION_CONTRACT_05.json'
    $dryRunPath = Join-Path $replayRoot 'CARRIER_AUTHORIZATION_DRY_RUN_05.json'
    $callablePath = Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_05.json'

    Write-JsonFile $contractPath ([ordered]@{
        schema = 'slice_execution_contract.v1'
        family_id = 'lifecycle_cleanup_retention'
        production_entry_qn = $entry
        entry_invocation_method = 'new CaseExamineLogService().saveExamineLog(caseNo, userId, operator, remark)'
        contract_status = 'AUTHORIZED'
        execution_authorized = $true
        issues = @()
    })
    Write-JsonFile $indexPath ([ordered]@{
        carrier_candidates = @(
            [ordered]@{ signature = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse' }
        )
    })

    Write-JsonFile $dryRunPath ([ordered]@{
        slice_index = 5
        selected_symbol = $entry
        signature = $signature
        pre_authorized = $true
        chosen_replacement_or_blocked = 'authorized_original'
        blockers = @()
    })
    Write-JsonFile $callablePath ([ordered]@{
        gate = 'callable_carrier_authorization'
        slice_index = 5
        selected_carrier = 'com.example.BlockedFallback.noop'
        selected_real_entry = 'com.example.BlockedFallback.noop'
        method_signature_found = $false
        authorization_status = 'BLOCKED'
        can_proceed = $false
        blockers = @('not_the_current_slice_entry')
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'verify_carrier_invocation_contract.ps1') `
        -Contract $contractPath `
        -CarrierIndex $indexPath `
        -OutputPath $outputPath | Out-Null
    Assert-True 'dry_run_authorization_resolves_index_miss' ($LASTEXITCODE -eq 0)
    $dryRunResult = Read-JsonFile $outputPath
    Assert-True 'dry_run_result_passes' ([string]$dryRunResult.status -eq 'PASS') ($dryRunResult | ConvertTo-Json -Depth 12)
    Assert-True 'dry_run_resolution_source_recorded' ([string]$dryRunResult.resolution_source -eq 'carrier_authorization_dry_run') ($dryRunResult | ConvertTo-Json -Depth 12)
    Assert-True 'dry_run_reports_existing_production' ([bool]$dryRunResult.resolved -and [bool]$dryRunResult.signature_match -and [string]$dryRunResult.carrier_origin -eq 'existing_production') ($dryRunResult | ConvertTo-Json -Depth 12)

    Write-JsonFile $dryRunPath ([ordered]@{
        slice_index = 5
        selected_symbol = $entry
        signature = $signature
        pre_authorized = $true
        chosen_replacement_or_blocked = 'authorized_original'
        blockers = @('signature_mismatch')
    })
    Write-JsonFile $callablePath ([ordered]@{
        gate = 'callable_carrier_authorization'
        slice_index = 5
        selected_carrier = $entry
        selected_real_entry = $entry
        selected_carrier_fqn = $entry
        existing_entry_fqn = $entry
        existing_entry_signature = $signature
        method_signature_found = $true
        authorization_status = 'AUTHORIZED'
        can_proceed = $true
        resolved_signature = [ordered]@{
            selected_carrier = [ordered]@{ formatted = $signature }
            selected_real_entry = [ordered]@{ formatted = $signature }
        }
        blockers = @()
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'verify_carrier_invocation_contract.ps1') `
        -Contract $contractPath `
        -CarrierIndex $indexPath `
        -OutputPath $outputPath | Out-Null
    Assert-True 'callable_authorization_resolves_index_miss' ($LASTEXITCODE -eq 0)
    $callableResult = Read-JsonFile $outputPath
    Assert-True 'callable_result_passes' ([string]$callableResult.status -eq 'PASS') ($callableResult | ConvertTo-Json -Depth 12)
    Assert-True 'callable_resolution_source_recorded' ([string]$callableResult.resolution_source -eq 'callable_carrier_authorization') ($callableResult | ConvertTo-Json -Depth 12)
    Assert-True 'callable_reports_existing_production' ([bool]$callableResult.resolved -and [bool]$callableResult.signature_match -and [string]$callableResult.carrier_origin -eq 'existing_production') ($callableResult | ConvertTo-Json -Depth 12)

    Write-JsonFile $dryRunPath ([ordered]@{
        slice_index = 5
        selected_symbol = $entry
        signature = $signature
        pre_authorized = $true
        chosen_replacement_or_blocked = 'authorized_original'
        blockers = @('signature_mismatch')
    })
    Write-JsonFile $callablePath ([ordered]@{
        gate = 'callable_carrier_authorization'
        slice_index = 5
        selected_carrier = $entry
        selected_real_entry = $entry
        method_signature_found = $false
        authorization_status = 'BLOCKED'
        can_proceed = $false
        blockers = @('method_signature_not_found')
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'verify_carrier_invocation_contract.ps1') `
        -Contract $contractPath `
        -CarrierIndex $indexPath `
        -OutputPath $outputPath 2>&1 | Out-Null
    Assert-True 'untrusted_same_round_evidence_still_fails' ($LASTEXITCODE -ne 0)
    $blockedResult = Read-JsonFile $outputPath
    Assert-True 'blocked_result_fails' ([string]$blockedResult.status -eq 'FAIL') ($blockedResult | ConvertTo-Json -Depth 12)
    Assert-True 'blocked_result_not_resolved' (-not [bool]$blockedResult.resolved -and -not [bool]$blockedResult.signature_match) ($blockedResult | ConvertTo-Json -Depth 12)
    Assert-True 'blocked_result_keeps_index_issue' (@($blockedResult.issues) -contains 'carrier_not_resolved_in_baseline_index') ($blockedResult | ConvertTo-Json -Depth 12)

    Write-Host ''
    Write-Host 'v698 Carrier Invocation Uses Same-Round Authorization: ALL PASSED'
    exit 0
} catch {
    Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
