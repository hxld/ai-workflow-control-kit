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

$scriptRoot = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptRoot
$runLoopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$promptPath = Join-Path $autopilotRoot 'prompts\phase-plan-tournament.prompt.md'
$schemaGate = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-machine-contract-test-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
    Assert-True 'prompt_requires_plan_result_json' ($promptText -match 'PLAN_RESULT\.json')
    Assert-True 'prompt_declares_machine_readable_authority' ($promptText -match 'machine-readable plan contract')
    Assert-True 'prompt_lists_proceed_required_json_fields' ($promptText -match 'target_carrier_file_path' -and $promptText -match 'expected_test_method' -and $promptText -match 'side_effects')

    $runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8
    Assert-True 'runner_requires_plan_result_json_artifact' ($runLoopText -match "'PLAN_RESULT\.json'")
    Assert-True 'runner_invokes_plan_schema_failfast_before_phase1' ($runLoopText -match 'Invoke-PlanSchemaFailFast\.ps1')
    Assert-True 'runner_stops_on_machine_contract_failure' ($runLoopText -match 'Plan machine contract failed')

    $goodProceedRoot = Join-Path $tempRoot 'good-proceed'
    New-Item -ItemType Directory -Force -Path $goodProceedRoot | Out-Null
    Write-Json (Join-Path $goodProceedRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'example-core/src/main/java/example/DemoService.java'
        target_carrier_line_number = 42
        expected_test_class = 'DemoServiceTest'
        expected_test_method = 'testDemo'
        side_effects = @('DB state update')
        expected_assertions = @('assert DB state')
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $goodProceedRoot -PlanResultPath (Join-Path $goodProceedRoot 'PLAN_RESULT.json') | Out-Null
    Assert-True 'schema_accepts_executable_proceed_contract' ($LASTEXITCODE -eq 0)

    $blockedRoot = Join-Path $tempRoot 'blocked'
    New-Item -ItemType Directory -Force -Path $blockedRoot | Out-Null
    Write-Json (Join-Path $blockedRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'BLOCKED'
        blocker = 'selected_real_entry_missing'
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $blockedRoot -PlanResultPath (Join-Path $blockedRoot 'PLAN_RESULT.json') | Out-Null
    Assert-True 'schema_accepts_blocked_with_blocker' ($LASTEXITCODE -eq 0)

    $badRoot = Join-Path $tempRoot 'bad'
    New-Item -ItemType Directory -Force -Path $badRoot | Out-Null
    Write-Json (Join-Path $badRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        expected_test_class = 'DemoServiceTest'
    })
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $badRoot -PlanResultPath (Join-Path $badRoot 'PLAN_RESULT.json') | Out-Null
    Assert-True 'schema_rejects_incomplete_proceed_contract' ($LASTEXITCODE -ne 0)
    $badSchema = Get-Content -LiteralPath (Join-Path $badRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_reports_missing_target_carrier' ((@($badSchema.checks.missing_fields) -join ' ') -match 'target_carrier_file_path')

    Write-Host 'PASS: v469 plan machine contract required'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
