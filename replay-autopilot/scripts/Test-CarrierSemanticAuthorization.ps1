param(
    [string]$FixtureRoot = '',
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonObject {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-TextFile {
    param([string]$Path, [string]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Assert-ContainsAll {
    param([string[]]$Actual, [string[]]$Expected, [string]$Label)
    foreach ($item in $Expected) {
        if (@($Actual) -notcontains $item) {
            throw "$Label missing expected item: $item"
        }
    }
}

function Invoke-Verifier {
    param([string]$Root, [string]$Worktree)
    $slice = Join-Path $Root 'SLICE_RESULT_01.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script:Verifier -ReplayRoot $Root -Worktree $Worktree -SliceResult $slice -SliceIndex 1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Verify-SliceClosure failed for $Root" }
    return Read-JsonObject (Join-Path $Root 'SLICE_VERIFY_01.json')
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$script:Verifier = Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1'
$tempRoot = Join-Path $scriptRoot ('.tmp\carrier-semantic-{0}' -f $PID)

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        verifier = $script:Verifier
        fixture_root = $FixtureRoot
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($FixtureRoot)) {
    $fixture = Resolve-AbsolutePath $FixtureRoot
    $worktree = Join-Path $fixture 'worktree'
    $verifyPath = Join-Path $fixture 'SLICE_VERIFY_01.json'
    if (-not (Test-Path -LiteralPath $verifyPath)) {
        Invoke-Verifier -Root $fixture -Worktree $worktree | Out-Null
    }
    $negative = Read-JsonObject $verifyPath
    if ([bool]$negative.authorized_for_next_slice) {
        throw "Negative fixture should not authorize next slice: $fixture"
    }
    if ([int]$negative.adjusted_coverage_delta -ne 0) {
        throw "Negative fixture should force adjusted_coverage_delta=0"
    }
    Assert-ContainsAll -Actual @($negative.gap_flags | ForEach-Object { [string]$_ }) -Expected @('synthetic_carrier_gap', 'wrong_test_surface', 'shallow_module') -Label 'negative fixture gap_flags'
}

$positiveRoot = Join-Path $tempRoot 'positive-real-carrier'
$positiveWorktree = Join-Path $positiveRoot 'worktree'
New-Item -ItemType Directory -Force -Path $positiveWorktree | Out-Null
& git -C $positiveWorktree init | Out-Null
& git -C $positiveWorktree config user.email replay@example.invalid | Out-Null
& git -C $positiveWorktree config user.name replay-test | Out-Null
Write-TextFile (Join-Path $positiveWorktree 'src/main/java/demo/RealEntry.java') @'
package demo;

public class RealEntry {
    public String process(String input) {
        return "persisted:" + input;
    }
}
'@
Write-TextFile (Join-Path $positiveWorktree 'src/test/java/demo/RealEntryTest.java') @'
package demo;

public class RealEntryTest {
}
'@
& git -C $positiveWorktree add . | Out-Null
& git -C $positiveWorktree commit -m baseline | Out-Null
Write-TextFile (Join-Path $positiveWorktree 'src/main/java/demo/RealEntry.java') @'
package demo;

public class RealEntry {
    public String process(String input) {
        saveAuditRow(input);
        return "persisted:" + input;
    }

    private void saveAuditRow(String input) {
        if (input == null) {
            throw new IllegalArgumentException("input");
        }
    }
}
'@
Write-TextFile (Join-Path $positiveWorktree 'src/test/java/demo/RealEntryTest.java') @'
package demo;

public class RealEntryTest {
    // RED asserted RealEntry.process persisted output before GREEN.
}
'@

Write-JsonFile (Join-Path $positiveRoot 'FAMILY_CONTRACT.json') ([ordered]@{
    families = @(
        [ordered]@{
            id = 'core_entry'
            required = $true
            required_proof_type = @('real_entry_behavior')
        }
    )
})
Write-JsonFile (Join-Path $positiveRoot 'CARRIER_AUTHORIZATION_01.json') ([ordered]@{
    authorization = 'ALLOW'
    selected_carrier = 'demo.RealEntry.process'
    downstream_side_effect_or_output = 'saveAuditRow persistence side effect and persisted output'
    requires_side_effect_evidence = $true
    requires_exact_contract_assertions = $false
    forbidden_synthetic_carrier = $false
    forbidden_helper_only_carrier = $false
    issues = @()
})
Write-JsonFile (Join-Path $positiveRoot 'SIDE_EFFECT_EVIDENCE_01.json') ([ordered]@{
    status = 'CLOSED'
    entry_call = 'demo.RealEntry.process'
    expected_writes_or_outputs = @('audit row persistence', 'persisted output')
    must_not_writes = @('no failure status on valid input')
    test_name = 'RealEntryTest#processWritesAuditAndReturnsOutput'
    red_result = 'BUSINESS_ASSERTION_FAILED'
    green_result = 'PASS'
})
Write-JsonFile (Join-Path $positiveRoot 'SLICE_RESULT_01.json') ([ordered]@{
    slice_index = 1
    slice_id = 'S1'
    slice_title = 'real carrier positive fixture'
    slice_type = 'stateful_success_slice'
    slice_status = 'DONE'
    coverage_delta = 18
    target_subsurface_or_carrier = 'demo.RealEntry.process'
    required_sibling_surfaces = @()
    production_boundary = 'existing production entry calls saveAuditRow persistence side effect and returns output'
    proof_kind = 'real_entry_behavior'
    red_expectation = 'RealEntryTest#processWritesAuditAndReturnsOutput fails before saveAuditRow call'
    implemented_files = @('src/main/java/demo/RealEntry.java', 'src/test/java/demo/RealEntryTest.java')
    tests = @(
        [ordered]@{ command = 'fixture-test'; phase = 'RED'; result = 'fail'; evidence = 'business assertion failed' },
        [ordered]@{ command = 'fixture-test'; phase = 'GREEN'; result = 'pass'; evidence = 'business assertion passed' }
    )
    exact_contract_assertions = @()
    side_effect_evidence = [ordered]@{
        status = 'CLOSED'
        entry_call = 'demo.RealEntry.process'
        expected_writes_or_outputs = @('audit row persistence', 'persisted output')
        must_not_writes = @('no failure status on valid input')
        test_name = 'RealEntryTest#processWritesAuditAndReturnsOutput'
        red_result = 'BUSINESS_ASSERTION_FAILED'
        green_result = 'PASS'
    }
    closed_assertions = @('real entry calls production side effect and returns output')
    must_not_assertions = @()
    remaining_gaps = @()
    gap_flags = @()
    touched_requirement_families = @('core_entry')
    closed_requirement_families = @('core_entry')
    blocker = ''
    next_recommended_slice_type = ''
})

$positive = Invoke-Verifier -Root $positiveRoot -Worktree $positiveWorktree
if (-not [bool]$positive.authorized_for_next_slice) {
    throw "Positive real-carrier fixture should authorize next slice. Blockers: $($positive.authorization_blockers -join ',')"
}
if ([int]$positive.adjusted_coverage_delta -le 0) {
    throw "Positive real-carrier fixture should keep positive adjusted coverage."
}

[ordered]@{
    status = 'PASS'
    negative_fixture = $FixtureRoot
    positive_fixture = $positiveRoot
    assertions = @('negative_synthetic_rejected', 'positive_real_carrier_allowed')
} | ConvertTo-Json -Depth 8

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
