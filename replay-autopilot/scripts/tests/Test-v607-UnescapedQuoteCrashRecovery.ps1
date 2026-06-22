param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw $Name }
        throw "$Name :: $Detail"
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Invoke-SchemaScript {
    param([string]$ReplayRoot, [string]$PlanPath, [string]$Worktree)
    $schemaScript = Join-Path $script:ScriptRoot 'Invoke-PlanSchemaFailFast.ps1'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$schemaScript`" -ReplayRoot `"$ReplayRoot`" -PlanResultPath `"$PlanPath`" -Worktree `"$Worktree`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Stderr = $stderr; Stdout = $stdout }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("v607-unescaped-quote-" + [guid]::NewGuid().ToString('N'))
$script:ScriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

try {
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'sample-module\src\test\java\com\example') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project></project>'
    Write-Utf8 (Join-Path $worktree 'sample-module\pom.xml') '<project></project>'
    Write-Utf8 (Join-Path $worktree 'sample-module\src\test\java\com\example\SomeTest.java') 'class SomeTest {}'

    Write-Utf8 (Join-Path $tempRoot 'PLAN_RESULT.json') @'
{
  "plan_status": "PROCEED",
  "target_carrier_file_path": "sample-module/src/main/java/com/example/Service.java",
  "target_carrier_line_number": 42,
  "expected_test_class": "com.example.SomeTest",
  "expected_test_method": "testMethod",
  "expected_assertions": [
    "contains("expected status")",
    "verify(mock).method(eq("value"))"
  ],
  "side_effects": ["state mutation"],
  "test_infrastructure_check": {
    "test_module_for_target": "sample-module",
    "test_module_has_dependencies": true,
    "test_harness_available": true,
    "can_import_production_classes": true,
    "compilation_dry_run_exit_code": 0,
    "compilation_dry_run_command": "mvn -f D:\\temp\\pom.xml -pl sample-module -am test-compile",
    "compilation_dry_run_evidence_file": "TEST_INFRASTRUCTURE_DRY_RUN.json",
    "blocker_reason": "none"
  }
}
'@

    $r = Invoke-SchemaScript -ReplayRoot $tempRoot -PlanPath (Join-Path $tempRoot 'PLAN_RESULT.json') -Worktree $worktree
    $schemaPath = Join-Path $tempRoot 'PLAN_SCHEMA_FAILFAST.json'

    Assert-True 'schema_not_null_output_exists' (Test-Path -LiteralPath $schemaPath) "PLAN_SCHEMA_FAILFAST.json NOT found. exit=$($r.ExitCode) stderr=$($r.Stderr)"

    $schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_status_is_fail' ($schema.status -eq 'FAIL') "status=$($schema.status)"
    Assert-True 'schema_exit_nonzero' ($r.ExitCode -ne 0) "exitCode=$($r.ExitCode)"
    $errText = [string]($schema.error)
    Assert-True 'schema_error_about_invalid_json' ($errText -match '(?i)(invalid json|null|parse)') "error=$errText"

    Remove-Item $schemaPath -Force
    Remove-Item (Join-Path $tempRoot 'PLAN_RESULT.json') -Force

    $infra = [ordered]@{
        test_module_for_target = 'sample-module'
        test_module_has_dependencies = $true
        test_harness_available = $true
        can_import_production_classes = $true
        compilation_dry_run_exit_code = 0
        compilation_dry_run_command = ('mvn -f ' + $worktree + '\pom.xml -pl sample-module -am test-compile')
        compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
        blocker_reason = 'none'
    }
    $validPlan = [ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'sample-module/src/main/java/com/example/Service.java'
        target_carrier_line_number = 42
        expected_test_class = 'com.example.SomeTest'
        expected_test_method = 'testMethod'
        expected_assertions = @(
            'contains("expected status")',
            'verify(mock).method(eq("value"))'
        )
        side_effects = @(@{
            side_effect = 'state mutation'
            state = 'state updated'
            proof = 'verify(repository).save()'
        })
        test_infrastructure_check = $infra
    }
    $evidence = [ordered]@{
        exit_code = 0
        command = $infra.compilation_dry_run_command
        stdout = 'BUILD SUCCESS'
    }
    $evidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tempRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') -Encoding UTF8
    $validPlan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempRoot 'PLAN_RESULT.json') -Encoding UTF8

    $r2 = Invoke-SchemaScript -ReplayRoot $tempRoot -PlanPath (Join-Path $tempRoot 'PLAN_RESULT.json') -Worktree $worktree
    $schema2 = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'valid_exit_zero' ($r2.ExitCode -eq 0) "exit=$($r2.ExitCode) stderr=[$($r2.Stderr)] schema_issues=$($schema2.issues)"
    Assert-True 'valid_status_pass' ($schema2.status -eq 'PASS') "status=$($schema2.status)"
    Assert-True 'valid_can_proceed' ($schema2.can_proceed -eq $true) "can_proceed=$($schema2.can_proceed)"

    $r3 = Invoke-SchemaScript -ReplayRoot $tempRoot -PlanPath (Join-Path $tempRoot 'NONEXISTENT.json') -Worktree $worktree
    $schema3 = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'nofile_status_fail' ($schema3.status -eq 'FAIL') "status=$($schema3.status)"
    $nofileErr = [string]($schema3.error)
    Assert-True 'nofile_error_not_crash' ($nofileErr -match '(?i)(not found|missing)') "error=$nofileErr"

    [ordered]@{
        status = 'PASS'
        version = 'v607'
        assertions = @(
            'schema_not_null_output_exists',
            'schema_status_is_fail',
            'schema_exit_nonzero',
            'schema_error_about_invalid_json',
            'valid_exit_zero',
            'valid_status_pass',
            'valid_can_proceed',
            'nofile_status_fail',
            'nofile_error_not_crash'
        )
    } | ConvertTo-Json -Depth 5

} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
