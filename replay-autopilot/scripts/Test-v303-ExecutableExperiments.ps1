param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Text {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v303-exec-" + [guid]::NewGuid().ToString('N'))
$root = Join-Path $tmp 'root'
$worktree = Join-Path $tmp 'worktree'
New-Item -ItemType Directory -Force -Path $root, $worktree | Out-Null

try {
    $ledgerPath = Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json'
    [ordered]@{
        coverage_cap = 100
        families = @(
            [ordered]@{
                id = 'core_entry'
                status = 'OPEN'
                required = $true
                weight = 100
                coverage_cap_if_open = 0
                first_executable_carrier = 'RealEntry.handle()'
                open_sibling_count = 1
                proof_required = @('real behavior assertion')
                forbidden_proof = @('structural_only')
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ledgerPath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Write-PreSliceCapDisplay.ps1') `
        -ReplayRoot $root `
        -RequirementFamilyLedger $ledgerPath `
        -SliceIndex 1 `
        -ForcedRequirementFamily 'core_entry' `
        -ForcedSliceType 'core_entry' `
        -ForcedSiblingSurface 'RealEntry.handle()' | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Pre-slice cap display should generate successfully'
    $cap = Get-Content -LiteralPath (Join-Path $root 'PRE_SLICE_CAP_DISPLAY_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([int]$cap.coverage_cap_if_forced_family_remains_open -eq 0) 'Pre-slice cap display must expose forced-family cap'

    Write-Text (Join-Path $root 'SIDE_EFFECT_LEDGER.md') 'state status progress task log insert update transaction'
    Write-Text (Join-Path $root 'TEST_CHARTER.md') 'business assertion required'
    $slicePath = Join-Path $root 'SLICE_RESULT_01.json'
    [ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        coverage_delta = 25
        target_subsurface_or_carrier = 'RealEntry.handle()'
        production_boundary = 'core/src/main/RealEntry.java'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        implemented_files = @('core/src/main/RealEntry.java', 'server/src/test/RealEntryTest.java')
        gap_flags = @()
        closed_assertions = @(
            'RealEntry class exists',
            'handle method exists',
            'Method can be called successfully'
        )
        side_effect_evidence = [ordered]@{
            status = 'READY'
            entry_call = 'RealEntry.handle()'
            expected_writes_or_outputs = @('status UPDATE', 'task INSERT')
            red_result = 'BUSINESS_ASSERTION_FAILED'
            green_result = 'PASS'
        }
        tests = @(
            [ordered]@{
                phase = 'RED'
                result = 'fail'
                evidence = 'ClassNotFoundException: RealEntry'
            },
            [ordered]@{
                phase = 'GREEN'
                result = 'pass'
                evidence = 'method exists and executes successfully'
            }
        )
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $slicePath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $root `
        -Worktree $worktree `
        -SliceResultPath $slicePath `
        -SliceIndex 1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'Executable assertion gate must reject structural-only core entry closure'
    $gateText = Get-Content -LiteralPath (Join-Path $root 'EXECUTABLE_EVIDENCE_GATE_01.json') -Raw -Encoding UTF8
    Assert-True ($gateText.Contains('shallow_module:core_entry_structural_only')) 'Gate should report shallow structural-only core entry'
    Assert-True ($gateText.Contains('side_effect_ledger_gap:expected_writes_not_closed')) 'Gate should report expected writes not closed'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

[ordered]@{
    status = 'PASS'
    assertions = 5
    cases = @(
        'pre_slice_cap_display_generated',
        'forced_family_cap_exposed',
        'structural_only_core_entry_rejected',
        'expected_writes_not_closed_rejected'
    )
} | ConvertTo-Json -Depth 5
