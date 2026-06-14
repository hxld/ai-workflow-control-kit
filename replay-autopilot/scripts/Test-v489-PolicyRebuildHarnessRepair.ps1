param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Json {
    param([string]$Path, [object]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-PolicyHarnessFixture {
    param(
        [string]$Root,
        [string]$Module = 'claim-core',
        [string]$ExpectedTestClass = 'Manual code inspection',
        [string]$FirstRedTest = 'Code inspection of rebuildTaskData lambda'
    )

    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-server\src\test\java\com\huize\claim\core\ai\task') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task') | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'pom.xml') -Encoding UTF8
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'claim-server\pom.xml') -Encoding UTF8
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'claim-core\pom.xml') -Encoding UTF8
    'class ExistingHarnessTest {}' | Set-Content -LiteralPath (Join-Path $worktree 'claim-server\src\test\java\com\huize\claim\core\ai\task\ExistingHarnessTest.java') -Encoding UTF8
    'class AiApplyClaimApiTaskProcessor {}' | Set-Content -LiteralPath (Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task\AiApplyClaimApiTaskProcessor.java') -Encoding UTF8

    Write-Json (Join-Path $Root 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 384
        expected_test_class = $ExpectedTestClass
        expected_test_method = 'testRebuildTaskData_PreservesPolicyNumAndInsureNum'
        first_red_test = $FirstRedTest
        side_effects = @(
            'request object receives policyNum from RequestBuildContext',
            'request object receives insureNum from RequestBuildContext'
        )
        expected_assertions = @(
            'assert policyNum preserved',
            'assert insureNum preserved'
        )
        test_infrastructure_check = [ordered]@{
            test_module_for_target = $Module
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = "mvn -s D:\maven\settings\settings.xml -f `"$worktree\pom.xml`" -pl $Module -am test-compile"
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })

    return $worktree
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$schemaGate = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("policy-rebuild-harness-repair-v489-" + [guid]::NewGuid().ToString('N'))

try {
    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    $functionBlock = [regex]::Match(
        $runLoopText,
        '(?s)function Resolve-ReplayEvidencePath.+?(?=function Repair-Phase0ManualOracleWaitText)'
    ).Value
    Assert-True 'runner_policy_repair_functions_extractable' (-not [string]::IsNullOrWhiteSpace($functionBlock))
    Invoke-Expression $functionBlock

    $planMachineBlock = [regex]::Match(
        $runLoopText,
        '(?s)\$planMachineContractPath = Join-Path \$replayRoot ''PLAN_RESULT\.json''.+?Invoke-PlanSchemaFailFast\.ps1'
    ).Value
    Assert-True 'runner_invokes_policy_harness_repair_before_schema' (
        $planMachineBlock.Contains('Repair-PolicyRebuildPlanHarness -ReplayRoot $replayRoot -Worktree $worktree -PlanResultJsonPath $planMachineContractPath') -and
        $planMachineBlock.IndexOf('Repair-PolicyRebuildPlanHarness -ReplayRoot $replayRoot') -lt $planMachineBlock.IndexOf('Invoke-PlanSchemaFailFast.ps1')
    )
    Assert-True 'schema_rejects_code_inspection_literal' (
        (Get-Content -LiteralPath $schemaGate -Raw -Encoding UTF8).Contains('code\s+inspection')
    )

    $badRoot = Join-Path $tempRoot 'bad-manual'
    $badWorktree = New-PolicyHarnessFixture -Root $badRoot -Module 'claim-server' -ExpectedTestClass 'Manual code inspection' -FirstRedTest 'Code inspection of rebuildTaskData lambda'
    Write-Json (Join-Path $badRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = "mvn -s D:\maven\settings\settings.xml -f `"$badWorktree\pom.xml`" -pl claim-server -am test-compile"
        module = 'claim-server'
        exit_code = 0
        stdout_tail = 'BUILD SUCCESS'
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $badRoot -PlanResultPath (Join-Path $badRoot 'PLAN_RESULT.json') -Worktree $badWorktree | Out-Null
    Assert-True 'schema_fails_unrepaired_code_inspection' ($LASTEXITCODE -ne 0)
    $badSchema = Get-Content -LiteralPath (Join-Path $badRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_reports_manual_verification_issue_for_code_inspection' ((@($badSchema.checks.test_infrastructure_issues) -join ' ') -match 'manual_verification_not_allowed_for_proceed')

    $repairRoot = Join-Path $tempRoot 'repair'
    $repairWorktree = New-PolicyHarnessFixture -Root $repairRoot
    $repaired = Repair-PolicyRebuildPlanHarness -ReplayRoot $repairRoot -Worktree $repairWorktree -PlanResultJsonPath (Join-Path $repairRoot 'PLAN_RESULT.json')
    Assert-True 'policy_harness_repair_returns_true' ([bool]$repaired)
    $repairArtifact = Get-Content -LiteralPath (Join-Path $repairRoot 'PLAN_POLICY_REBUILD_HARNESS_REPAIR.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'policy_harness_repair_artifact_written' ($repairArtifact.status -eq 'REPAIRED' -and $repairArtifact.required_module -eq 'claim-server')
    $plan = Get-Content -LiteralPath (Join-Path $repairRoot 'PLAN_RESULT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'policy_harness_repair_sets_claim_server_module' ($plan.test_infrastructure_check.test_module_for_target -eq 'claim-server')
    Assert-True 'policy_harness_repair_sets_claim_server_test_class' ([string]$plan.expected_test_class -match 'claim-server[/\\]src[/\\]test[/\\]java')
    Assert-True 'policy_harness_repair_removes_code_inspection_red_test' ([string]$plan.first_red_test -notmatch '(?i)code\s+inspection|manual')
    Assert-True 'policy_harness_repair_sets_claim_server_compile_command' ([string]$plan.test_infrastructure_check.compilation_dry_run_command -match '-pl claim-server' -and [string]$plan.test_infrastructure_check.compilation_dry_run_command -match '\s-am\b' -and [string]$plan.test_infrastructure_check.compilation_dry_run_command -match 'test-compile')

    Write-Json (Join-Path $repairRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = [string]$plan.test_infrastructure_check.compilation_dry_run_command
        module = 'claim-server'
        exit_code = 0
        stdout_tail = 'BUILD SUCCESS'
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $repairRoot -PlanResultPath (Join-Path $repairRoot 'PLAN_RESULT.json') -Worktree $repairWorktree | Out-Null
    Assert-True 'schema_passes_after_policy_harness_repair_and_evidence' ($LASTEXITCODE -eq 0)

    Write-Host 'PASS: v489 policy rebuild harness repair'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
