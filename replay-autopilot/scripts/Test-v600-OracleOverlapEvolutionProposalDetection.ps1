param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
    Write-Host "PASS: $Name"
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = Join-Path $scriptRoot 'New-EvolutionProposal.ps1'

$tempRoot = Join-Path $env:TEMP ("replay-v600-oracle-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    Write-Host "`n[Test 1] oracle_overlap_below_threshold detected from PLAN_CONTRACT_VERIFY.json" -ForegroundColor Yellow
    Write-Utf8 -Path (Join-Path $tempRoot 'PLAN_CONTRACT_VERIFY.json') -Value @'
{
    "stage": "Plan",
    "verification_status": "FAIL",
    "oracle_overlap_percent": 47,
    "oracle_overlap_matched": 26,
    "oracle_overlap_total_production": 60,
    "oracle_high_weight_matched": 25,
    "oracle_high_weight_total": 25,
    "issues": [
        "oracle_overlap_below_threshold:47%<50%",
        "plan_status_not_proceed:BLOCKED"
    ]
}
'@

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut -ReplayRoot $tempRoot
    $proposalText = Get-Content -LiteralPath (Join-Path $tempRoot 'EVOLUTION_PROPOSAL.md') -Raw -Encoding UTF8

    Assert-True -Name 'proposal_contains_oracle_overlap_gap' -Condition ($proposalText -match 'plan_oracle_overlap_gap')
    Assert-True -Name 'proposal_has_should_evolve_true' -Condition ($proposalText -match 'should_evolve:\s*True')
    Assert-True -Name 'proposal_has_gap_in_detected_table' -Condition ($proposalText -match 'Surface Coverage Gate.*plan_oracle_overlap_gap')
    $rules1 = Get-Content -LiteralPath (Join-Path $tempRoot 'VERIFIABLE_RULES.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Name 'oracle_overlap_rule_pack_written' -Condition (@($rules1.rules | Where-Object { $_.machine_gate -eq 'plan_oracle_overlap_enforced' }).Count -eq 1)

    Write-Host "`n[Test 2] No PLAN_CONTRACT_VERIFY.json produces normal output without oracle overlap gap" -ForegroundColor Yellow
    $tempRoot2 = Join-Path $env:TEMP ("replay-v600-noverify-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tempRoot2 | Out-Null

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut -ReplayRoot $tempRoot2
    $proposalText2 = Get-Content -LiteralPath (Join-Path $tempRoot2 'EVOLUTION_PROPOSAL.md') -Raw -Encoding UTF8

    Assert-True -Name 'no_verify_no_oracle_gap' -Condition ($proposalText2 -notmatch 'plan_oracle_overlap_gap')

    Remove-Item -LiteralPath $tempRoot2 -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "`n[Test 3] oracle_high_weight_overlap_below_threshold detected" -ForegroundColor Yellow
    $tempRoot3 = Join-Path $env:TEMP ("replay-v600-highweight-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tempRoot3 | Out-Null

    Write-Utf8 -Path (Join-Path $tempRoot3 'PLAN_CONTRACT_VERIFY.json') -Value @'
{
    "stage": "Plan",
    "verification_status": "FAIL",
    "oracle_overlap_percent": 60,
    "oracle_high_weight_matched": 5,
    "oracle_high_weight_total": 10,
    "issues": [
        "oracle_high_weight_overlap_below_threshold:50%<70%",
        "plan_status_not_proceed:BLOCKED"
    ]
}
'@

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut -ReplayRoot $tempRoot3
    $proposalText3 = Get-Content -LiteralPath (Join-Path $tempRoot3 'EVOLUTION_PROPOSAL.md') -Raw -Encoding UTF8

    Assert-True -Name 'high_weight_gap_detected' -Condition ($proposalText3 -match 'plan_high_weight_oracle_overlap_gap')
    Assert-True -Name 'high_weight_gap_in_table' -Condition ($proposalText3 -match 'Surface Coverage Gate.*plan_high_weight_oracle_overlap_gap')
    $rules3 = Get-Content -LiteralPath (Join-Path $tempRoot3 'VERIFIABLE_RULES.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Name 'high_weight_rule_pack_written' -Condition (@($rules3.rules | Where-Object { $_.machine_gate -eq 'plan_high_weight_oracle_overlap_enforced' }).Count -eq 1)

    Remove-Item -LiteralPath $tempRoot3 -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "`n[Test 4] valid blocked test infrastructure does not request tooling evolution" -ForegroundColor Yellow
    $tempRoot4 = Join-Path $env:TEMP ("replay-v600-valid-infra-blocker-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tempRoot4 | Out-Null

    Write-Utf8 -Path (Join-Path $tempRoot4 'PLAN_RESULT.md') -Value @'
# Plan Result

- plan_status: BLOCKED
- blocker: PLAN_BLOCKED_TEST_INFRASTRUCTURE
- next_action: provide an allowed Mockito-capable test harness or authorize isolated-worktree test dependency change
'@
    Write-Utf8 -Path (Join-Path $tempRoot4 'PLAN_RESULT.json') -Value @'
{
  "plan_status": "BLOCKED",
  "blocker": "PLAN_BLOCKED_TEST_INFRASTRUCTURE",
  "test_infrastructure_check": {
    "test_module_for_target": "claim-server",
    "test_module_has_dependencies": false,
    "test_harness_available": false,
    "can_import_production_classes": true,
    "compilation_dry_run_exit_code": 1,
    "compilation_dry_run_command": "mvn --% -f D:\\replay\\worktree\\pom.xml -pl claim-server -am test-compile",
    "compilation_dry_run_evidence_file": "D:\\replay\\TEST_INFRASTRUCTURE_DRY_RUN.json",
    "blocker_reason": "Mockito dependency not found in any allowed worktree POM; prompt forbids pom.xml edits"
  }
}
'@
    Write-Utf8 -Path (Join-Path $tempRoot4 'PLAN_SCHEMA_FAILFAST.json') -Value @'
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

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut -ReplayRoot $tempRoot4
    $proposalText4 = Get-Content -LiteralPath (Join-Path $tempRoot4 'EVOLUTION_PROPOSAL.md') -Raw -Encoding UTF8

    Assert-True -Name 'valid_infrastructure_blocker_should_not_evolve' -Condition ($proposalText4 -match 'should_evolve:\s*False')
    Assert-True -Name 'valid_infrastructure_blocker_reason' -Condition ($proposalText4 -match 'valid terminal test-infrastructure blocker')
    Assert-True -Name 'valid_infrastructure_blocker_no_rules' -Condition (-not (Test-Path -LiteralPath (Join-Path $tempRoot4 'VERIFIABLE_RULES.json')))

    Remove-Item -LiteralPath $tempRoot4 -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "`n=== All tests PASS ===" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
