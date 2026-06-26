param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [int]$Slice = 1,
    [string]$TestCharter = '',
    [string]$FamilyLedger = '',
    [string]$Contract = '',
    [string]$OutputPath = ''
)

$replayRootFull = [System.IO.Path]::GetFullPath($ReplayRoot)
if ([string]::IsNullOrWhiteSpace($TestCharter)) {
    $candidate = Join-Path $replayRootFull ('TEST_CHARTER_{0:D2}.json' -f $Slice)
    $TestCharter = if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidate } else { Join-Path $replayRootFull 'TEST_CHARTER.json' }
}
if ([string]::IsNullOrWhiteSpace($FamilyLedger)) {
    $FamilyLedger = Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json'
}
if ([string]::IsNullOrWhiteSpace($Contract)) {
    $candidate = Join-Path $replayRootFull 'FIRST_SLICE_EXECUTABLE_CONTRACT.json'
    $Contract = if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidate } else { Join-Path $replayRootFull ('SLICE_EXECUTION_CONTRACT_{0:D2}.json' -f $Slice) }
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $replayRootFull 'PROOF_TYPE_POLICY_GATE.json'
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'proof_type_policy_gate.ps1') `
    -ReplayRoot $replayRootFull `
    -TestCharter $TestCharter `
    -FamilyLedger $FamilyLedger `
    -Contract $Contract `
    -OutputPath $OutputPath
exit $LASTEXITCODE
