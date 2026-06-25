#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression coverage for callable carrier authorization of path-shaped method evidence.

.DESCRIPTION
Plan repair may preserve concrete evidence as
`module/src/main/java/.../Carrier.java#method`. The callable-carrier gate must
resolve that to the Java class and method, while preserving strict signature
checks when params or return type are explicitly supplied.
#>

param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$signatureScript = Join-Path $scriptsRoot 'verify_carrier_signature.py'
$callableGateScript = Join-Path $scriptsRoot 'Invoke-CallableCarrierAuthorization.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v650-callable-carrier-path-method-' + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $tempRoot 'worktree'
    $sourceDir = Join-Path $worktree 'app-core\src\main\java\com\example'
    New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

    Write-Utf8 (Join-Path $sourceDir 'ExampleFacadeImpl.java') @'
package com.example;

import java.util.List;

public class ExampleFacadeImpl {
    public ResultModel<List<ResponseDto>> batchQueryCaseDetail(List<Long> ids) {
        return null;
    }
}
'@

    Write-Utf8 (Join-Path $sourceDir 'ResultModel.java') @'
package com.example;

public class ResultModel<T> {
}
'@

    Write-Utf8 (Join-Path $sourceDir 'ResponseDto.java') @'
package com.example;

public class ResponseDto {
}
'@

    Write-Host '[Scenario 1] Path-shaped Class.java#method authorizes as callable method reference...'
    $pathInput = @{
        worktree_path = $worktree
        selected_real_entry = 'com.example.ExampleFacadeImpl.batchQueryCaseDetail'
        selected_carrier = 'app-core/src/main/java/com/example/ExampleFacadeImpl.java#batchQueryCaseDetail'
        test_invocation_path = 'invoke_facade_entry'
        proof_observation_point = 'assert_result_model_success'
    } | ConvertTo-Json -Compress
    $pathOutput = $pathInput | python $signatureScript
    Assert-True ($LASTEXITCODE -eq 0) "path-shaped carrier should pass, output=$pathOutput"
    $pathJson = $pathOutput | ConvertFrom-Json
    Assert-True ([bool]$pathJson.authorized) 'path-shaped carrier should expose authorized=true'
    Assert-True ($pathJson.resolved_signature.selected_carrier.method_name -eq 'batchQueryCaseDetail') 'path-shaped carrier should resolve method name'
    Assert-True (-not [bool]$pathJson.exact_signature_required.selected_carrier) 'path-shaped method reference should not require exact param/return signature'
    Assert-True ($pathJson.normalized_carriers.selected_carrier -eq 'ExampleFacadeImpl.batchQueryCaseDetail') "path-shaped carrier should normalize to class.method, got $($pathJson.normalized_carriers.selected_carrier)"

    Write-Host '[Scenario 2] Callable gate accepts repaired plan carrier path while preserving output evidence...'
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
selected_real_entry: com.example.ExampleFacadeImpl.batchQueryCaseDetail
selected_carrier: app-core/src/main/java/com/example/ExampleFacadeImpl.java#batchQueryCaseDetail
'@
    Write-Utf8 (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') @'
selected_real_entry: com.example.ExampleFacadeImpl.batchQueryCaseDetail
selected_carrier: app-core/src/main/java/com/example/ExampleFacadeImpl.java#batchQueryCaseDetail
'@
    @{
        real_entry = 'com.example.ExampleFacadeImpl.batchQueryCaseDetail'
        selected_carrier = 'app-core/src/main/java/com/example/ExampleFacadeImpl.java#batchQueryCaseDetail'
        downstream_side_effect_or_output = 'assert_result_model_success'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $callableGateScript -ReplayRoot $replayRoot -Worktree $worktree -SliceIndex 1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'callable carrier gate should pass path-shaped selected_carrier'
    $gateJson = Get-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($gateJson.authorization -eq 'ALLOW') "callable gate should ALLOW, got $($gateJson.authorization)"
    Assert-True ($gateJson.resolved_signature.selected_carrier.method_name -eq 'batchQueryCaseDetail') 'callable gate should expose resolved selected carrier signature'

    Write-Host '[Scenario 3] Explicit wrong params still fail strict signature comparison...'
    $strictInput = @{
        plan_carrier = 'com.example.ExampleFacadeImpl.batchQueryCaseDetail(String): ResultModel'
        worktree_path = $worktree
    } | ConvertTo-Json -Compress
    $strictOutput = $strictInput | python $signatureScript 2>&1
    Assert-True ($LASTEXITCODE -ne 0) 'explicit wrong signature must still fail'
    $strictJson = $strictOutput | ConvertFrom-Json
    Assert-True ($strictJson.error -eq 'carrier_signature_mismatch') "expected carrier_signature_mismatch, got $($strictJson.error)"
    Assert-True ([bool]$strictJson.exact_signature_required) 'explicit params should set exact_signature_required=true'

    Write-Host ''
    Write-Host '=== v650 CALLABLE CARRIER PATH METHOD AUTHORIZATION: PASS ===' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ''
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
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
