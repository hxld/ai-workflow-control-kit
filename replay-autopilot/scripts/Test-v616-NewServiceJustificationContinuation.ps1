param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$verifier = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v616-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $validRoot = Join-Path $tmp 'valid-folded-justification'
    $validWorktree = Join-Path $validRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $validWorktree | Out-Null
    Write-Utf8 (Join-Path $validRoot 'PLAN_RESULT.md') @'
# Plan Result

- plan_status: PROCEED
- carrier_search: performed
- carrier_search_queries: rg "AutoClaimFlow" example-core; rg "FlowService" example-core; rg "TaskProcessor" example-server
- existing_production_carriers: ExampleApplyClaimApiTaskProcessor; ApplyClaimService; ClaimTaskService
- selected_carrier_from_search: NEW_SERVICE_ExampleFlowService
- new_service_created: true
- new_service_justification: >
  Exhaustive search found no existing carrier handles the complete workflow.
  The oracle adds 1502 lines that require separate orchestration.
- first_slice: S1 auto claim flow orchestration
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $validRoot -Stage Plan -Worktree $validWorktree -ErrorAction SilentlyContinue | Out-Null
    $validVerify = Get-Content -LiteralPath (Join-Path $validRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($validVerify.issues) -notcontains 'carrier_search_new_service_unjustified') "Folded multi-line justification should be accepted, issues=$(@($validVerify.issues) -join ';')"

    $weakRoot = Join-Path $tmp 'weak-folded-justification'
    $weakWorktree = Join-Path $weakRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $weakWorktree | Out-Null
    Write-Utf8 (Join-Path $weakRoot 'PLAN_RESULT.md') @'
# Plan Result

- plan_status: PROCEED
- carrier_search: performed
- carrier_search_queries: rg "AutoClaimFlow" example-core; rg "FlowService" example-core; rg "TaskProcessor" example-server
- existing_production_carriers: ExampleApplyClaimApiTaskProcessor; ApplyClaimService; ClaimTaskService
- selected_carrier_from_search: NEW_SERVICE_ExampleFlowService
- new_service_created: true
- new_service_justification: >
  Prefer a cleaner service name.
  Keep responsibilities organized.
- first_slice: S1 auto claim flow orchestration
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $weakRoot -Stage Plan -Worktree $weakWorktree -ErrorAction SilentlyContinue | Out-Null
    $weakVerify = Get-Content -LiteralPath (Join-Path $weakRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($weakVerify.issues) -contains 'carrier_search_new_service_unjustified') "Weak folded justification should still be rejected"
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

[ordered]@{
    status = 'PASS'
    assertions = 2
    cases = @(
        'folded_new_service_justification_accepts_real_no_existing_carrier_evidence',
        'folded_new_service_justification_rejects_weak_reason'
    )
} | ConvertTo-Json -Depth 5
