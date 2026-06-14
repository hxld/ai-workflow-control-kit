Set-Location (Split-Path $PSScriptRoot -Parent)
$result = & '.\scripts\Verify-PlanContract.ps1' -ReplayRoot "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\aiClaimV2\claim-codex-replay-v438-autopilot-20260517-r02" 2>&1 | ConvertFrom-Json
Write-Host "Warnings:"
$result.warnings | ForEach-Object { Write-Host "  - $_" }
Write-Host "Issues:"
$result.issues | ForEach-Object { Write-Host "  - $_" }
Write-Host "Verification Status:" $result.verification_status
