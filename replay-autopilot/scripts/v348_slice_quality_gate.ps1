# v348 Slice Quality Gate
#
# Integrates side effect verification and placeholder detection
# into slice authorization workflow.
#
# Usage:
#   .\v348_slice_quality_gate.ps1 -SliceDir <path> -Worktree <path>
#
# Exit codes:
#   0 - PASS
#   1 - FAIL (blocked)
#   2 - WARN (warning only)

param(
    [Parameter(Mandatory = $true)]
    [string]$SliceDir,

    [Parameter(Mandatory = $true)]
    [string]$Worktree,

    [switch]$WarnOnly
)

$ErrorActionPreference = 'Stop'

$canProceed = $true
$issues = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

# Write header
Write-Host "=== v348 Slice Quality Gate ===" -ForegroundColor Cyan
Write-Host "SliceDir: $SliceDir"
Write-Host "Worktree: $Worktree"
Write-Host ""

# === Check 1: Side Effect Ledger ===

Write-Host "[Check 1] Side Effect Ledger..." -ForegroundColor Yellow

$sideEffectLedger = Join-Path $SliceDir "side-effect-ledger.md"
if (-not (Test-Path -LiteralPath $sideEffectLedger)) {
    Write-Host "  ❌ FAIL: side-effect-ledger.md not found" -ForegroundColor Red
    $issues.Add("side_effect_ledger_missing")
    $canProceed = $false
} else {
    $ledgerContent = Get-Content $sideEffectLedger -Raw -Encoding UTF8

    # Check for VERIFIED markers
    $verifiedEffects = [regex]::Matches($ledgerContent, "VERIFIED:\s*(\w+)").Count

    if ($verifiedEffects -eq 0) {
        Write-Host "  ❌ FAIL: No VERIFIED side effects found" -ForegroundColor Red
        $issues.Add("no_verified_side_effects")
        $canProceed = $false
    } else {
        Write-Host "  ✓ PASS: $verifiedEffects verified side effects" -ForegroundColor Green
    }

    # Check for TODO placeholders
    $todoCount = [regex]::Matches($ledgerContent, "TODO").Count
    if ($todoCount -gt 0) {
        Write-Host "  ⚠ WARN: $todoCount TODO markers found in ledger" -ForegroundColor Yellow
        $warnings.Add("todo_in_ledger")
    }
}

# === Check 2: DB State Verification ===

Write-Host "[Check 2] DB State Verification..." -ForegroundColor Yellow

$dbStateVerification = Join-Path $SliceDir "db-state-verification.json"
if (-not (Test-Path -LiteralPath $dbStateVerification)) {
    Write-Host "  ❌ FAIL: db-state-verification.json not found" -ForegroundColor Red
    $issues.Add("db_state_verification_missing")
    $canProceed = $false
} else {
    try {
        $dbVerif = Get-Content $dbStateVerification -Raw -Encoding UTF8 | ConvertFrom-Json

        if ($null -eq $dbVerif.assertions -or $dbVerif.assertions.Count -eq 0) {
            Write-Host "  ❌ FAIL: No DB state assertions found" -ForegroundColor Red
            $issues.Add("no_db_assertions")
            $canProceed = $false
        } else {
            Write-Host "  ✓ PASS: $($dbVerif.assertions.Count) DB state assertions" -ForegroundColor Green
        }

        # Check for expected tables
        $expectedTables = @("t_compensate_info", "t_compensate_detail", "t_case_progress", "task", "t_examine_log")
        $foundTables = 0

        foreach ($table in $expectedTables) {
            if ($dbVerif.assertions -match $table) {
                $foundTables++
            }
        }

        if ($foundTables -lt 2) {
            Write-Host "  ⚠ WARN: Only $foundTables/5 expected tables verified" -ForegroundColor Yellow
            $warnings.Add("limited_table_coverage")
        } else {
            Write-Host "  ✓ INFO: $foundTables/5 expected tables verified" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "  ❌ FAIL: Invalid db-state-verification.json" -ForegroundColor Red
        $issues.Add("db_verification_invalid")
        $canProceed = $false
    }
}

# === Check 3: Test File Existence ===

Write-Host "[Check 3] Test File Existence..." -ForegroundColor Yellow

$testEvidence = Join-Path $SliceDir "SLICE_TEST_EVIDENCE.json"
if (Test-Path -LiteralPath $testEvidence) {
    try {
        $testData = Get-Content $testEvidence -Raw -Encoding UTF8 | ConvertFrom-Json
        $testFile = $testData.test_file

        if ($testFile) {
            $testPath = if ([System.IO.Path]::IsPathRooted($testFile)) {
                $testFile
            } else {
                Join-Path $Worktree $testFile
            }

            if (Test-Path -LiteralPath $testPath) {
                Write-Host "  ✓ PASS: Test file exists at $testFile" -ForegroundColor Green
            } else {
                Write-Host "  ❌ FAIL: Test file not found: $testFile" -ForegroundColor Red
                $issues.Add("test_file_not_found")
                $canProceed = $false
            }
        } else {
            Write-Host "  ⚠ WARN: No test_file specified in evidence" -ForegroundColor Yellow
            $warnings.Add("test_file_unspecified")
        }
    } catch {
        Write-Host "  ⚠ WARN: Invalid test evidence JSON" -ForegroundColor Yellow
        $warnings.Add("test_evidence_invalid")
    }
} else {
    Write-Host "  ⚠ WARN: No test evidence file found" -ForegroundColor Yellow
    $warnings.Add("test_evidence_missing")
}

# === Check 4: Placeholder Detection ===

Write-Host "[Check 4] Placeholder Detection..." -ForegroundColor Yellow

$placeholderPatterns = @(
    "TODO.*实际.*实现",
    "TODO.*数据库",
    "TODO.*插入",
    "placeholder",
    "占位",
    "待实现",
    "fail\(""            # fail("...")
    "return false;?\s*//.*TODO",
    "return true;?\s*//.*TODO"
)

$foundPlaceholders = 0

# Search in worktree Java files
$javaFiles = Get-ChildItem -Path $Worktree -Filter "*.java" -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*\src\main\java\*" }

foreach ($file in $javaFiles) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue

    if ($content) {
        foreach ($pattern in $placeholderPatterns) {
            $matches = [regex]::Matches($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($matches.Count -gt 0) {
                $foundPlaceholders += $matches.Count
                $relPath = $file.FullName.Substring($Worktree.Length + 1)
                Write-Host "  ⚠ Found placeholder in: $relPath" -ForegroundColor DarkYellow
            }
        }
    }
}

if ($foundPlaceholders -gt 0) {
    Write-Host "  ❌ FAIL: $foundPlaceholders placeholders found" -ForegroundColor Red
    $issues.Add("placeholders_found")
    $canProceed = $false
} else {
    Write-Host "  ✓ PASS: No placeholders detected" -ForegroundColor Green
}

# === Check 5: Behavioral Assertion Check ===

Write-Host "[Check 5] Behavioral Assertion Check..." -ForegroundColor Yellow

$behavioralPatterns = @(
    "assertEquals",
    "assertThat.*\.isEqualTo",
    "assertThat.*\.contains",
    "assertThat.*\.matches",
    "verify\s*\(",
    "assertTrue",
    "assertFalse"
)

$foundBehavioral = $false

if (Test-Path -LiteralPath $testEvidence) {
    try {
        $testData = Get-Content $testEvidence -Raw -Encoding UTF8 | ConvertFrom-Json
        $testFile = $testData.test_file

        if ($testFile) {
            $testPath = if ([System.IO.Path]::IsPathRooted($testFile)) { $testFile } else { Join-Path $Worktree $testFile }

            if (Test-Path -LiteralPath $testPath) {
                $testContent = Get-Content $testPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue

                if ($testContent) {
                    foreach ($pattern in $behavioralPatterns) {
                        if ([regex]::IsMatch($testContent, $pattern)) {
                            $foundBehavioral = $true
                            break
                        }
                    }
                }
            }
        }
    } catch {
        # Ignore errors
    }
}

if (-not $foundBehavioral) {
    Write-Host "  ⚠ WARN: No behavioral assertions found" -ForegroundColor Yellow
    $warnings.Add("no_behavioral_assertions")
} else {
    Write-Host "  ✓ PASS: Behavioral assertions found" -ForegroundColor Green
}

# === Check 6: Coverage Penalty Calculation (Experiment 2) ===

Write-Host "[Check 6] Coverage Penalty Calculation..." -ForegroundColor Yellow

$penaltyScript = Join-Path $PSScriptRoot "calculate-coverage-penalty.py"
$penaltyResult = $null

if (Test-Path -LiteralPath $penaltyScript) {
    $sliceResultJson = Join-Path $SliceDir "SLICE_RESULT_*.json"
    $sliceResultFile = Get-ChildItem -Path $sliceResultJson -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($sliceResultFile) {
        $inputJson = @{
            worktree_path = $Worktree
            slice_result_path = $sliceResultFile.FullName
        } | ConvertTo-Json -Compress

        try {
            $penaltyOutput = python $penaltyScript --input $inputJson 2>&1
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1) {
                $penaltyResult = $penaltyOutput | ConvertFrom-Json

                $totalPenalty = $penaltyResult.total_penalty_percent
                $credit = $penaltyResult.implementation_credit_percent

                if ($totalPenalty -gt 0) {
                    Write-Host "  ⚠ INFO: Coverage penalty: $totalPenalty% (Credit: $credit%)" -ForegroundColor Yellow
                    $warnings.Add("coverage_penalty_applied:$totalPenalty%")

                    if ($totalPenalty -gt 50) {
                        Write-Host "  ❌ FAIL: Penalty exceeds 50%" -ForegroundColor Red
                        $issues.Add("coverage_penalty_exceeds_threshold")
                        $canProceed = $false
                    } else {
                        Write-Host "  ✓ INFO: Penalty within threshold" -ForegroundColor Green
                    }
                } else {
                    Write-Host "  ✓ PASS: No penalty applied" -ForegroundColor Green
                }
            }
        } catch {
            Write-Host "  ⚠ WARN: Penalty calculation failed" -ForegroundColor Yellow
            $warnings.Add("penalty_calculation_failed")
        }
    } else {
        Write-Host "  ⚠ WARN: No slice result file found" -ForegroundColor Yellow
        $warnings.Add("no_slice_result_for_penalty")
    }
} else {
    Write-Host "  ⚠ WARN: Penalty script not found" -ForegroundColor Yellow
    $warnings.Add("penalty_script_missing")
}

# === Summary ===

Write-Host ""
Write-Host "=== v348 Slice Quality Gate Summary ===" -ForegroundColor Cyan

if ($canProceed) {
    Write-Host "Status: PASS" -ForegroundColor Green
    Write-Host "Warnings: $($warnings.Count)" -ForegroundColor Yellow

    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Warnings:" -ForegroundColor Yellow
        foreach ($warn in $warnings) {
            Write-Host "  - $warn"
        }
    }

    exit 0
} else {
    Write-Host "Status: FAIL" -ForegroundColor Red
    Write-Host "Issues: $($issues.Count)" -ForegroundColor Red

    Write-Host ""
    Write-Host "Blocking Issues:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  - $issue"
    }

    if ($WarnOnly) {
        Write-Host ""
        Write-Host "Running in WARN mode - allowing continuation" -ForegroundColor Yellow
        exit 0
    } else {
        Write-Host ""
        Write-Host "Slice is NOT authorized. Fix issues before proceeding." -ForegroundColor Red
        exit 1
    }
}
