param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw $Name }
        throw "$Name :: $Detail"
    }
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$preExecutionScript = Join-Path $scriptRoot 'Invoke-PreExecutionConstraintCheck.ps1'
$controllerScript = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'
$runnerScript = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$configPath = Join-Path (Split-Path -Parent $scriptRoot) 'config.yaml'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v606-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null

    $facadeDir = Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\facade'
    $serviceDir = Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\service'
    $testDir = Join-Path $worktree 'claim-server\src\test\java\com\huize\claim\core\ai'
    New-Item -ItemType Directory -Force -Path $facadeDir, $serviceDir, $testDir | Out-Null
    'class AiClaimModuleConfigFacadeImpl { void save(Object dto) {} }' | Set-Content -LiteralPath (Join-Path $facadeDir 'AiClaimModuleConfigFacadeImpl.java') -Encoding UTF8
    'class AiClaimModuleConfigService { void save(Object dto) {} }' | Set-Content -LiteralPath (Join-Path $serviceDir 'AiClaimModuleConfigService.java') -Encoding UTF8
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'claim-server\pom.xml') -Encoding UTF8
    'class ExistingHarnessTest {}' | Set-Content -LiteralPath (Join-Path $testDir 'ExistingHarnessTest.java') -Encoding UTF8

    Write-JsonFile (Join-Path $replayRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/com/huize/claim/core/ai/service/AiClaimModuleConfigService.java'
        target_carrier_line_number = 216
        expected_test_class = 'AiClaimModuleConfigServiceTest'
        expected_test_method = 'testConvertPreservesFreeReviewAmount'
        side_effects = @('DB insert t_ai_claim_module_config.free_review_amount')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = "mvn -f $worktree\pom.xml -pl claim-server -am test-compile"
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })
    Write-JsonFile (Join-Path $replayRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        exit_code = 0
        command = "mvn -f $worktree\pom.xml -pl claim-server -am test-compile"
    })
    @'
# FIRST_SLICE_PROOF_PLAN

highest_weight_open_gate: core_entry
selected_real_entry: com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl.save(AiClaimModuleConfigDto)
selected_carrier: AiClaimModuleConfigFacadeImpl
target_subsurface_or_carrier: AiClaimModuleConfigService
target_carrier_file_path: claim-core/src/main/java/com/huize/claim/core/ai/service/AiClaimModuleConfigService.java
target_carrier_line_number: 216
expected_test_class: AiClaimModuleConfigServiceTest
expected_test_method: testConvertPreservesFreeReviewAmount
expected_assertions: ["entity gets freeReviewAmount","mapper captures freeReviewAmount","null input clears field"]
expected_side_effects: [{"table":"t_ai_claim_module_config","operation":"INSERT","field":"free_review_amount"}]
minimum_side_effect_or_blocker: mapper insert/update captures free_review_amount
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8
    @'
Entry Point: AiClaimModuleConfigFacadeImpl.save
Test Class: AiClaimModuleConfigServiceTest
DB Verification: mapper capture verifies free_review_amount
Side Effects: verify insert/update field propagation
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER.md') -Encoding UTF8

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $preExecutionScript `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -PlanResultPath (Join-Path $replayRoot 'PLAN_RESULT.json') | Out-Null
    Assert-True 'pre_execution_exit_zero_for_facade_entry_service_target' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

    $preExecution = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'pre_execution_passes' ([string]$preExecution.status -eq 'PASS') ($preExecution | ConvertTo-Json -Depth 10)
    Assert-True 'selected_target_remains_service_file' ([string]$preExecution.selected_carrier -match 'AiClaimModuleConfigService\.java$') ([string]$preExecution.selected_carrier)
    Assert-True 'selected_entry_uses_facade' ([string]$preExecution.selected_entry_carrier -match 'AiClaimModuleConfigFacadeImpl') ([string]$preExecution.selected_entry_carrier)
    $layerCheck = @($preExecution.checks | Where-Object { [string]$_.name -eq 'carrier_in_valid_layer' }) | Select-Object -First 1
    Assert-True 'layer_check_uses_facade_carrier' ([string]$layerCheck.carrier -match 'AiClaimModuleConfigFacadeImpl') ($layerCheck | ConvertTo-Json -Depth 5)
    Assert-True 'layer_check_preserves_target_file' ([string]$layerCheck.target_carrier_file_path -match 'AiClaimModuleConfigService\.java$') ($layerCheck | ConvertTo-Json -Depth 5)

    $controllerText = Get-Content -LiteralPath $controllerScript -Raw -Encoding UTF8
    $runnerText = Get-Content -LiteralPath $runnerScript -Raw -Encoding UTF8
    $configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    foreach ($text in @($controllerText, $runnerText)) {
        Assert-True 'push_timeout_config_used' ($text -match 'knowledge_backup_push_timeout_seconds')
        Assert-True 'push_wait_has_timeout' ($text -match 'WaitForExit\(\$pushTimeoutSeconds \* 1000\)')
        Assert-True 'hung_push_is_killed' ($text -match 'Stop-Process -Id \$pushProcess\.Id')
        Assert-True 'pending_records_timeout' ($text -match 'timed_out\s*=\s*\$pushTimedOut' -and $text -match 'timeout_seconds\s*=\s*\$pushTimeoutSeconds')
    }
    Assert-True 'config_exposes_push_timeout_default' ($configText -match '(?m)^knowledge_backup_push_timeout_seconds:\s*\d+\s*$')

    foreach ($script in @($preExecutionScript, $controllerScript, $runnerScript)) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErrors) | Out-Null
        Assert-True "parse_$([System.IO.Path]::GetFileName($script))" (-not $parseErrors -or $parseErrors.Count -eq 0) (($parseErrors | ForEach-Object { $_.Message }) -join '; ')
    }

    [ordered]@{
        status = 'PASS'
        version = 'v606'
        assertions = @(
            'pre_execution_uses_real_entry_for_core_layer_gate',
            'target_carrier_file_path_can_be_supporting_service_file',
            'knowledge_push_has_timeout_and_pending_degrade'
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
