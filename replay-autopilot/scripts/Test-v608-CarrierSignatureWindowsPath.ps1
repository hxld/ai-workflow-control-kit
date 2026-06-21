param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw $Name }
        throw "$Name :: $Detail"
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$signatureScript = Join-Path $scriptRoot 'verify_carrier_signature.py'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v608-' + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $tempRoot 'worktree'
    $sourceDir = Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task'
    New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

    @'
package com.huize.claim.core.ai.task;

public class AiApplyClaimApiTaskProcessor {
    @Override
    public void handleTaskResponse(AiApplyClaimApiTask aiClaimApiTask, AiApplyClaimApiTaskResponse taskResponse) {
    }
}
'@ | Set-Content -LiteralPath (Join-Path $sourceDir 'AiApplyClaimApiTaskProcessor.java') -Encoding UTF8

    $input = @{
        plan_carrier = 'AiApplyClaimApiTaskProcessor.handleTaskResponse(AiApplyClaimApiTask, AiApplyClaimApiTaskResponse)'
        worktree_path = $worktree
    } | ConvertTo-Json -Compress

    $output = $input | python $signatureScript
    $exitCode = $LASTEXITCODE
    Assert-True 'carrier_signature_passes_windows_absolute_rg_path' ($exitCode -eq 0) "exit=$exitCode output=$output"
    $json = $output | ConvertFrom-Json
    Assert-True 'carrier_signature_status_pass' ([string]$json.status -eq 'PASS') $output
    Assert-True 'carrier_signature_file_path_preserved' ([string]$json.file_path -match 'AiApplyClaimApiTaskProcessor\.java$') ([string]$json.file_path)

    [ordered]@{
        status = 'PASS'
        version = 'v608'
        assertions = @(
            'verify_carrier_signature_handles_windows_absolute_rg_paths',
            'verify_carrier_signature_parses_indented_java_methods'
        )
    } | ConvertTo-Json -Depth 5
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
