#!/usr/bin/env pwsh
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Message - $Detail"
    }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$repoRoot = Split-Path -Parent $scriptsRoot
$proposalPath = Join-Path $scriptsRoot 'New-EvolutionProposal.ps1'
$runLoopPath = Join-Path $scriptsRoot 'Run-ReplayLoop.ps1'
$planPromptPath = Join-Path $repoRoot 'prompts\phase-plan-tournament.prompt.md'

$runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8
$proposalText = Get-Content -LiteralPath $proposalPath -Raw -Encoding UTF8
$promptText = Get-Content -LiteralPath $planPromptPath -Raw -Encoding UTF8

Assert-True ($runLoopText -match 'function\s+Test-ReplayRootHasStaticTestHarnessEvidence') 'Run-ReplayLoop checks static harness evidence before accepting terminal infrastructure blocker'
Assert-True ($proposalText -match 'function\s+Test-RootHasStaticTestHarnessEvidence') 'New-EvolutionProposal checks static harness evidence before suppressing evolution'
Assert-True ($promptText -match 'spring-boot-starter-test' -and $promptText -match 'mockito' -and $promptText -match 'PLAN_BLOCKED_TEST_INFRASTRUCTURE') 'Plan prompt forbids blocking on missing direct Mockito when starter test dependency exists'

$tempRoot = Join-Path $env:TEMP ("replay-v677-transitive-mockito-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Write-Utf8 -Path (Join-Path $tempRoot 'PLAN_RESULT.json') -Value @'
{
  "plan_status": "BLOCKED",
  "blocker": "PLAN_BLOCKED_TEST_INFRASTRUCTURE",
  "test_infrastructure_check": {
    "test_module_for_target": "sample-test-module",
    "test_module_has_dependencies": false,
    "test_harness_available": false,
    "can_import_production_classes": true,
    "compilation_dry_run_exit_code": 1,
    "compilation_dry_run_command": "mvn -f worktree\\pom.xml -pl sample-test-module -am test-compile",
    "compilation_dry_run_evidence_file": "TEST_INFRASTRUCTURE_DRY_RUN.json",
    "blocker_reason": "Mockito dependency not found in any allowed worktree POM; prompt forbids pom.xml edits"
  }
}
'@
    Write-Utf8 -Path (Join-Path $tempRoot 'PLAN_SCHEMA_FAILFAST.json') -Value @'
{
  "stage": "PlanSchemaFailFast",
  "status": "PASS",
  "required": true,
  "can_proceed": true,
  "checks": {
    "plan_status": "BLOCKED",
    "valid_plan_status": true,
    "all_required_fields_present": true,
    "missing_fields": [],
    "test_infrastructure_check_present": true,
    "test_infrastructure_check_valid": true,
    "test_infrastructure_issues": []
  },
  "issues": []
}
'@
    Write-Utf8 -Path (Join-Path $tempRoot 'worktree\sample-test-module\pom.xml') -Value @'
<project>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
'@
    Write-Utf8 -Path (Join-Path $tempRoot 'worktree\sample-test-module\src\test\java\ExampleHarnessTest.java') -Value @'
import org.junit.Test;

public class ExampleHarnessTest {
    @Test
    public void existingHarness() {
    }
}
'@
    Write-Utf8 -Path (Join-Path $tempRoot 'AUTOPILOT_SUMMARY.md') -Value @'
- verification_capped_coverage: 0
- blind_self_assessed_coverage: 0
'@

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $proposalPath -ReplayRoot $tempRoot
    $generatedProposal = Get-Content -LiteralPath (Join-Path $tempRoot 'EVOLUTION_PROPOSAL.md') -Raw -Encoding UTF8

    Assert-True ($generatedProposal -match 'should_evolve:\s*True') 'Transitive Mockito/static harness evidence keeps blocker evolvable instead of terminal'
    Assert-True ($generatedProposal -notmatch 'valid terminal test-infrastructure blocker') 'Transitive Mockito/static harness evidence is not reported as valid terminal blocker'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'v677 Transitive Mockito Plan Blocker Guard: PASS'
