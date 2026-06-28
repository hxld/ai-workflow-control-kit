#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function New-FocusedMavenCommand {
    param([string]$Worktree, [string]$TestFilter)
    return "mvn --% -s D:\maven\settings\settings.xml -Dproject.build.sourceEncoding=UTF-8 -Dfile.encoding=UTF-8 -f `"$Worktree\pom.xml`" -pl demo-harness -am -Dtest=$TestFilter -Dsurefire.failIfNoSpecifiedTests=false test"
}

function Write-CarrierLockFixture {
    param(
        [string]$ReplayRoot,
        [string]$QualifiedEntry,
        [string]$ExpectedFile,
        [string]$ProductionBoundary
    )
    @{
        schema = 'carrier_lock.v1'
        experiment = 'pre_budget_carrier_lock'
        family_id = 'core_entry'
        selected_family = 'core_entry'
        qualified_entry = $QualifiedEntry
        selected_carrier = $QualifiedEntry
        selected_carrier_fqn = $QualifiedEntry
        existing_source_file = $ExpectedFile
        source_file = $ExpectedFile
        expected_production_files = @($ExpectedFile)
        production_boundary = $ProductionBoundary
        downstream_side_effect_or_output = 'business route side effect'
        carrier_lock_status = 'PASS'
        status = 'LOCKED'
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'CARRIER_LOCK.json') -Encoding UTF8
}

function Write-AuthorizationFixture {
    param([string]$ReplayRoot, [string]$QualifiedEntry, [bool]$RequiresSideEffect = $true)
    @{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = $QualifiedEntry
        selected_carrier = $QualifiedEntry
        production_boundary = $QualifiedEntry
        downstream_side_effect_or_output = 'business route side effect'
        requires_side_effect_evidence = $RequiresSideEffect
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
}

function Write-SideEffectFixture {
    param([string]$ReplayRoot, [string]$QualifiedEntry, [string]$TestName)
    @{
        schema_version = 1
        slice_index = 1
        required_for_this_slice = $true
        entry_call = $QualifiedEntry
        expected_writes_or_outputs = @('business route side effect')
        must_not_writes = @('must not use adjacent constant as carrier closure')
        test_name = $TestName
        red_result = 'BUSINESS_ASSERTION_FAILED'
        green_result = 'PASS'
        status = 'CLOSED'
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'SIDE_EFFECT_EVIDENCE_01.json') -Encoding UTF8
}

function Write-SliceResultFixture {
    param(
        [string]$ReplayRoot,
        [string]$Worktree,
        [string]$QualifiedEntry,
        [string]$ProductionBoundary,
        [string[]]$ImplementedFiles,
        [string[]]$ChangedFiles,
        [string]$TestFilter = 'demo.RealEntryBehaviorTest#shouldRouteThroughLockedCarrier',
        [string]$EvidenceFile = 'demo-harness/src/test/java/demo/RealEntryBehaviorTest.java'
    )
    $command = New-FocusedMavenCommand -Worktree $Worktree -TestFilter $TestFilter
    $compileCommand = "mvn --% -s D:\maven\settings\settings.xml -Dproject.build.sourceEncoding=UTF-8 -Dfile.encoding=UTF-8 -f `"$Worktree\pom.xml`" -pl demo-harness -am test-compile"
    @{
        slice_index = 1
        slice_id = 'S1'
        slice_status = 'DONE'
        slice_type = 'tracer_bullet'
        coverage_delta = 10
        target_subsurface_or_carrier = $QualifiedEntry
        production_boundary = $ProductionBoundary
        proof_kind = 'real_entry_behavior'
        red_expectation = 'focused behavior test fails before route marker changes'
        implemented_files = @($ImplementedFiles)
        current_slice_changed_files = @($ChangedFiles)
        round_changed_files_snapshot = @($ChangedFiles)
        test_compilation_exit_code = 0
        test_execution_exit_code = 0
        tests = @(
            @{ command = $command; phase = 'RED'; result = 'fail'; evidence = 'business assertion failed before GREEN' },
            @{ command = $compileCommand; phase = 'VERIFY'; result = 'pass'; evidence = 'BUILD SUCCESS test-compile' },
            @{ command = $command; phase = 'GREEN'; result = 'pass'; evidence = 'BUILD SUCCESS; Tests run: 1, Failures: 0, Errors: 0' }
        )
        behavior_test_charter = @{
            proof_kind = 'real_entry_behavior'
            production_entry = $QualifiedEntry
            state_or_output = 'business route side effect'
            must_not = 'must not use adjacent constant as carrier closure'
            RED_command = $command
            expected_RED_failure = 'business assertion failed before GREEN'
            GREEN_command = $command
            evidence_file = $EvidenceFile
        }
        side_effect_evidence = @{
            status = 'CLOSED'
            entry_call = $QualifiedEntry
            expected_writes_or_outputs = @('business route side effect')
            must_not_writes = @('must not use adjacent constant as carrier closure')
            test_name = $TestFilter
            red_result = 'BUSINESS_ASSERTION_FAILED'
            green_result = 'PASS'
        }
        closed_assertions = @('focused behavior test passed')
        must_not_assertions = @('must not use adjacent constant as carrier closure')
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        gap_flags = @()
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'SLICE_RESULT_01.json') -Encoding UTF8
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v668-carrier-lock-diff-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    & git -C $worktree init | Out-Null
    & git -C $worktree config user.email test@example.invalid | Out-Null
    & git -C $worktree config user.name test | Out-Null

    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'
    Write-Utf8 (Join-Path $worktree 'demo-core\src\main\java\demo\RealEntry.java') @'
package demo;

public class RealEntry {
    public String handle(String value) {
        return value;
    }
}
'@
    Write-Utf8 (Join-Path $worktree 'demo-common\src\main\java\demo\AdjacentConstant.java') @'
package demo;

public final class AdjacentConstant {
    public static final String MESSAGE = "old";
}
'@
    Write-Utf8 (Join-Path $worktree 'demo-harness\src\test\java\demo\RealEntryBehaviorTest.java') @'
package demo;

public class RealEntryBehaviorTest {
    public void shouldRouteThroughLockedCarrier() {
        new RealEntry().handle("input");
    }
}
'@
    & git -C $worktree add . | Out-Null
    & git -C $worktree commit -m baseline | Out-Null

    Write-Utf8 (Join-Path $worktree 'demo-common\src\main\java\demo\AdjacentConstant.java') @'
package demo;

public final class AdjacentConstant {
    public static final String MESSAGE = "new";
}
'@
    Write-Utf8 (Join-Path $worktree 'demo-harness\src\test\java\demo\RealEntryBehaviorTest.java') @'
package demo;

public class RealEntryBehaviorTest {
    public void shouldRouteThroughLockedCarrier() {
        if (!"new".equals(AdjacentConstant.MESSAGE)) {
            throw new AssertionError("route marker should change");
        }
    }
}
'@

    Write-CarrierLockFixture `
        -ReplayRoot $replayRoot `
        -QualifiedEntry 'demo.RealEntry.handle(String): String' `
        -ExpectedFile 'demo-core/src/main/java/demo/RealEntry.java' `
        -ProductionBoundary 'demo-core/src/main/java/demo/RealEntry.java -> demo-common/src/main/java/demo/AdjacentConstant.java'
    Write-AuthorizationFixture -ReplayRoot $replayRoot -QualifiedEntry 'demo.RealEntry.handle(String): String'
    Write-SideEffectFixture -ReplayRoot $replayRoot -QualifiedEntry 'demo.RealEntry.handle(String): String' -TestName 'demo.RealEntryBehaviorTest#shouldRouteThroughLockedCarrier'

    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
selected_carrier: demo.RealEntry.handle(String): String
selected_real_entry: demo.RealEntry.handle(String): String
first_red_test: demo.RealEntryBehaviorTest#shouldRouteThroughLockedCarrier
expected_test_class: demo.RealEntryBehaviorTest
expected_test_method: shouldRouteThroughLockedCarrier
production_boundary: demo-core/src/main/java/demo/RealEntry.java
entry_file: demo-core/src/main/java/demo/RealEntry.java
"@

    Write-SliceResultFixture `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -QualifiedEntry 'demo.RealEntry.handle(String): String' `
        -ProductionBoundary 'demo-core/src/main/java/demo/RealEntry.java -> demo-common/src/main/java/demo/AdjacentConstant.java' `
        -ImplementedFiles @('demo-common/src/main/java/demo/AdjacentConstant.java', 'demo-harness/src/test/java/demo/RealEntryBehaviorTest.java') `
        -ChangedFiles @('demo-common/src/main/java/demo/AdjacentConstant.java', 'demo-harness/src/test/java/demo/RealEntryBehaviorTest.java')

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Verify-SliceClosure.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceResult (Join-Path $replayRoot 'SLICE_RESULT_01.json') `
        -SliceIndex 1 | Out-Null

    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($verify.issues) -notcontains 'test_command_missing_test_filter') 'focused mvn --% -Dtest=Class#method command must not be reported as missing test filter'
    Assert-True (@($verify.gap_flags) -contains 'carrier_lock_implementation_gap') 'locked carrier implementation gap must be emitted when production diff misses expected carrier file'
    Assert-True (@($verify.authorization_blockers) -contains 'carrier_lock_implementation_gap') 'locked carrier implementation gap must block authorization'
    Assert-True (@($verify.blocking_gap_flags) -contains 'carrier_lock_implementation_gap') 'locked carrier implementation gap must be a blocking gap flag'
    Assert-True ([int]$verify.coverage_cap -eq 0) 'locked carrier implementation gap must cap coverage at zero'
    Assert-True ([int]$verify.adjusted_coverage_delta -eq 0) 'locked carrier implementation gap must force adjusted coverage to zero'
    Assert-True (-not [bool]$verify.authorized_for_next_slice) 'locked carrier implementation gap must block next slice authorization'
    Assert-True (@($verify.carrier_lock_expected_production_files) -contains 'demo-core/src/main/java/demo/RealEntry.java') 'verify output must expose locked expected production file'
    Assert-True (@($verify.carrier_lock_touched_production_files).Count -eq 0) 'verify output must show no locked production file was touched'

    $positiveReplayRoot = Join-Path $tempRoot 'replay-new-production'
    $positiveWorktree = Join-Path $positiveReplayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $positiveWorktree | Out-Null
    & git -C $positiveWorktree init | Out-Null
    & git -C $positiveWorktree config user.email test@example.invalid | Out-Null
    & git -C $positiveWorktree config user.name test | Out-Null
    Write-Utf8 (Join-Path $positiveWorktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'
    Write-Utf8 (Join-Path $positiveWorktree 'demo-harness\src\test\java\demo\NewCarrierBehaviorTest.java') 'package demo; public class NewCarrierBehaviorTest {}'
    & git -C $positiveWorktree add . | Out-Null
    & git -C $positiveWorktree commit -m baseline | Out-Null
    Write-Utf8 (Join-Path $positiveWorktree 'demo-core\src\main\java\demo\NewCarrier.java') @'
package demo;

public class NewCarrier {
    public String handle(String input) {
        return "handled:" + input;
    }
}
'@
    Write-Utf8 (Join-Path $positiveWorktree 'demo-harness\src\test\java\demo\NewCarrierBehaviorTest.java') @'
package demo;

public class NewCarrierBehaviorTest {
    public void shouldCallNewCarrier() {
        if (!"handled:x".equals(new NewCarrier().handle("x"))) {
            throw new AssertionError("new production carrier should be called");
        }
    }
}
'@
    Write-CarrierLockFixture `
        -ReplayRoot $positiveReplayRoot `
        -QualifiedEntry 'demo.NewCarrier.handle(String): String' `
        -ExpectedFile 'demo-core/src/main/java/demo/NewCarrier.java' `
        -ProductionBoundary 'demo-core/src/main/java/demo/NewCarrier.java'
    Write-AuthorizationFixture -ReplayRoot $positiveReplayRoot -QualifiedEntry 'demo.NewCarrier.handle(String): String'
    Write-SideEffectFixture -ReplayRoot $positiveReplayRoot -QualifiedEntry 'demo.NewCarrier.handle(String): String' -TestName 'demo.NewCarrierBehaviorTest#shouldCallNewCarrier'
    Write-SliceResultFixture `
        -ReplayRoot $positiveReplayRoot `
        -Worktree $positiveWorktree `
        -QualifiedEntry 'demo.NewCarrier.handle(String): String' `
        -ProductionBoundary 'demo-core/src/main/java/demo/NewCarrier.java' `
        -ImplementedFiles @('demo-core/src/main/java/demo/NewCarrier.java', 'demo-harness/src/test/java/demo/NewCarrierBehaviorTest.java') `
        -ChangedFiles @('demo-core/src/main/java/demo/NewCarrier.java', 'demo-harness/src/test/java/demo/NewCarrierBehaviorTest.java') `
        -TestFilter 'demo.NewCarrierBehaviorTest#shouldCallNewCarrier' `
        -EvidenceFile 'demo-harness/src/test/java/demo/NewCarrierBehaviorTest.java'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Verify-SliceClosure.ps1') `
        -ReplayRoot $positiveReplayRoot `
        -Worktree $positiveWorktree `
        -SliceResult (Join-Path $positiveReplayRoot 'SLICE_RESULT_01.json') `
        -SliceIndex 1 | Out-Null
    $positiveVerify = Get-Content -LiteralPath (Join-Path $positiveReplayRoot 'SLICE_VERIFY_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($positiveVerify.gap_flags) -notcontains 'carrier_lock_implementation_gap') 'new production file diff must satisfy locked expected production file'
    Assert-True (@($positiveVerify.carrier_lock_touched_production_files) -contains 'demo-core/src/main/java/demo/NewCarrier.java') 'verify output must expose touched new locked production file'

    Write-Host 'v668 Carrier Lock Implementation And Command Filter: PASS'
    exit 0
} catch {
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
