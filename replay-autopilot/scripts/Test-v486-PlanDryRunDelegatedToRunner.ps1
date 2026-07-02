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
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-TestHarnessFixture {
    param([string]$Worktree)
    New-Item -ItemType Directory -Force -Path (Join-Path $Worktree 'example-server\src\test\java\sample') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Worktree 'example-core\src\main\java\example') | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $Worktree 'pom.xml') -Encoding UTF8
    '<project />' | Set-Content -LiteralPath (Join-Path $Worktree 'example-server\pom.xml') -Encoding UTF8
    'class DemoServiceTest {}' | Set-Content -LiteralPath (Join-Path $Worktree 'example-server\src\test\java\sample\DemoServiceTest.java') -Encoding UTF8
    'class DemoService {}' | Set-Content -LiteralPath (Join-Path $Worktree 'example-core\src\main\java\example\DemoService.java') -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$promptPath = Join-Path $repoRoot 'prompts\phase-plan-tournament.prompt.md'
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$schemaGate = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'
$constraintCheck = Join-Path $scriptRoot 'Invoke-PreExecutionConstraintCheck.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-dry-run-delegated-v486-" + [guid]::NewGuid().ToString('N'))

try {
    $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    $schemaText = Get-Content -LiteralPath $schemaGate -Raw -Encoding UTF8
    $constraintText = Get-Content -LiteralPath $constraintCheck -Raw -Encoding UTF8

    Assert-True 'plan_prompt_forbids_maven_execution_in_plan' ($promptText.Contains('Do not execute Maven in Plan'))
    Assert-True 'plan_prompt_delegates_evidence_to_runner' ($promptText.Contains('schema gate') -and $promptText.Contains('materialize `TEST_INFRASTRUCTURE_DRY_RUN.json`') -and $promptText.Contains('worktree root POM'))
    Assert-True 'plan_prompt_no_longer_says_run_isolated_dry_run' (-not $promptText.Contains('运行 isolated worktree dry-run'))
    Assert-True 'plan_prompt_requires_worktree_pom_not_protected_root' ($promptText.Contains('protected project root') -and $promptText.Contains('{{WORKTREE}}\pom.xml'))
    Assert-True 'plan_prompt_blocks_null_target_carrier_line_number' ($promptText.Contains('target_carrier_line_number') -and $promptText.Contains('`null`') -and $promptText.Contains('PLAN_BLOCKED_LINE_NUMBER'))

    Assert-True 'repair_prompt_forbids_maven_execution' ($runLoopText.Contains('MUST NOT run Maven in this repair prompt'))
    Assert-True 'repair_prompt_delegates_to_runner_before_schema' ($runLoopText.Contains('The runner materializes that evidence file after this repair returns and before ``Invoke-PlanSchemaFailFast.ps1``'))
    Assert-True 'repair_prompt_blocks_null_line_number' ($runLoopText.Contains('target_carrier_line_number`` MUST be an exact integer line number') -and $runLoopText.Contains('PLAN_BLOCKED_LINE_NUMBER'))

    Assert-True 'schema_rejects_non_worktree_compile_command' ($schemaText.Contains('compilation_dry_run_command must target isolated worktree pom'))
    Assert-True 'schema_rejects_non_worktree_compile_command_existing' ($schemaText.Contains('compilation_dry_run_command must target isolated worktree root pom'))
    Assert-True 'pre_execution_rejects_same_compile_command' ($constraintText.Contains('compilation_dry_run_command must target isolated worktree pom') -and $constraintText.Contains('compilation_dry_run_command must target isolated worktree root pom'))

    $badRoot = Join-Path $tempRoot 'bad-protected-root-command'
    $badWorktree = Join-Path $badRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $badRoot | Out-Null
    New-TestHarnessFixture -Worktree $badWorktree
    Write-Json (Join-Path $badRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') ([ordered]@{
        command = 'mvn -s D:\maven\settings\settings.xml -f D:\opt\lipei\claim\pom.xml -pl example-server -am test-compile'
        exit_code = 0
        stdout_tail = 'BUILD SUCCESS'
    })
    Write-Json (Join-Path $badRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'example-core/src/main/java/example/DemoService.java'
        target_carrier_line_number = 42
        expected_test_class = 'DemoServiceTest'
        expected_test_method = 'testDemo'
        side_effects = @('DB state update')
        expected_assertions = @('assert DB state')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'example-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f D:\opt\lipei\claim\pom.xml -pl example-server -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $badRoot -PlanResultPath (Join-Path $badRoot 'PLAN_RESULT.json') -Worktree $badWorktree | Out-Null
    Assert-True 'schema_fails_protected_root_compile_command' ($LASTEXITCODE -ne 0)
    $badSchema = Get-Content -LiteralPath (Join-Path $badRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $badIssues = @($badSchema.checks.test_infrastructure_issues) -join ' '
    Assert-True 'schema_reports_protected_root_compile_command' ($badIssues -match 'must target isolated worktree pom')

    & powershell -NoProfile -ExecutionPolicy Bypass -File $constraintCheck -ReplayRoot $badRoot -Worktree $badWorktree -PlanResultPath (Join-Path $badRoot 'PLAN_RESULT.json') -BaselineRoot $badWorktree | Out-Null
    $constraintResult = Get-Content -LiteralPath (Join-Path $badRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $infraCheck = $constraintResult.checks | Where-Object { $_.name -eq 'test_infrastructure_check' } | Select-Object -First 1
    Assert-True 'pre_execution_fails_protected_root_compile_command' ([string]$infraCheck.status -eq 'FAIL')
    Assert-True 'pre_execution_reports_protected_root_compile_command' ((@($infraCheck.issues) -join ' ') -match 'must target isolated worktree pom')

    Write-Host 'PASS: v486 plan dry-run delegated to runner'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
