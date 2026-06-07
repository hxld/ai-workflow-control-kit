param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

$scriptRoot = Resolve-AbsolutePath (Split-Path -Parent $MyInvocation.MyCommand.Path)
$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$worktree = Join-Path $replayRootFull 'worktree'

# Find Python executable
$pythonExe = 'python3'
$pythonCheck = Get-Command $pythonExe -ErrorAction SilentlyContinue
if ($null -eq $pythonCheck) {
    $pythonExe = 'python'
    $pythonCheck = Get-Command $pythonExe -ErrorAction SilentlyContinue
    if ($null -eq $pythonCheck) {
        throw "Python not found. Please install Python 3 to run experiment scripts."
    }
}

Write-Host "=== v419 Stop-And-Evolve Experiments ===" -ForegroundColor Cyan
Write-Host "Replay Root: $replayRootFull" -ForegroundColor Gray
Write-Host ""

$experimentResults = [ordered]@{}

# === EXPERIMENT 1: Requirement Traceability Binding ===
Write-Host "Experiment 1: Requirement Traceability Binding..." -ForegroundColor Cyan

$requirementSource = Join-Path $replayRootFull 'REQUIREMENT_SOURCE_SNAPSHOT.md'
$bindingsOutput = Join-Path $replayRootFull 'REQUIREMENT_CARRIER_BINDINGS.json'
$traceabilityScript = Join-Path $scriptRoot 'phase0_requirement_traceability_bind.py'

if (Test-Path -LiteralPath $requirementSource) {
    try {
        Write-Host "  Running: $traceabilityScript" -ForegroundColor Gray
        if ($WhatIf) {
            Write-Host "  [WHAT IF] Would run traceability binding" -ForegroundColor Yellow
            $experimentResults['requirement_traceability'] = 'SKIPPED_WHATIF'
        } else {
            $result = & $pythonExe $traceabilityScript $worktree $requirementSource $bindingsOutput 2>&1
            $json = $result | ConvertFrom-Json

            if ($json.status -in @('PASS', 'PARTIAL')) {
                Write-Host "  ✓ Traceability binding: $($json.bound_count)/$($json.total_phrases) phrases bound" -ForegroundColor Green
                $experimentResults['requirement_traceability'] = 'PASS'
            } else {
                Write-Host "  ✗ Traceability binding failed: $($json.error)" -ForegroundColor Red
                $experimentResults['requirement_traceability'] = 'FAIL'
            }
        }
    } catch {
        Write-Host "  ✗ Traceability binding error: $($_.Exception.Message)" -ForegroundColor Red
        $experimentResults['requirement_traceability'] = 'ERROR'
    }
} else {
    Write-Host "  ⊘ Requirement snapshot not found, skipping" -ForegroundColor DarkGray
    $experimentResults['requirement_traceability'] = 'SKIP_NO_FILE'
}

# === EXPERIMENT 2: Implementation Density Gate ===
Write-Host "Experiment 2: Implementation Density Gate..." -ForegroundColor Cyan

$densityScript = Join-Path $scriptRoot 'verify_implementation_density.py'
$slicePlanJson = Join-Path $replayRootFull 'SLICE_PLAN_01.json'

if (Test-Path -LiteralPath $slicePlanJson) {
    try {
        $slicePlan = Get-Content -LiteralPath $slicePlanJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $plannedFiles = @($slicePlan.planned_files | ForEach-Object { [string]$_ })

        if ($plannedFiles.Count -gt 0) {
            Write-Host "  Running: $densityScript with $($plannedFiles.Count) files" -ForegroundColor Gray
            if ($WhatIf) {
                Write-Host "  [WHAT IF] Would run density check" -ForegroundColor Yellow
                $experimentResults['implementation_density'] = 'SKIPPED_WHATIF'
            } else {
                $filesArg = $plannedFiles -join ','
                $result = & $pythonExe $densityScript --files $filesArg --min_density 0.7 --max_todo 0.0 2>&1
                $json = $result | ConvertFrom-Json

                if ($json.valid) {
                    Write-Host "  ✓ Density valid: $($json.metrics.overall_density.ToString('P')) executable, $($json.metrics.overall_todo_ratio.ToString('P')) TODOs" -ForegroundColor Green
                    $experimentResults['implementation_density'] = 'PASS'
                } else {
                    Write-Host "  ✗ Density gate failed:" -ForegroundColor Red
                    foreach ($failure in $json.failures) {
                        Write-Host "    - $($failure.type): $($failure.message)" -ForegroundColor Red
                    }
                    $experimentResults['implementation_density'] = 'FAIL'
                }
            }
        } else {
            Write-Host "  ⊘ No planned files in slice plan" -ForegroundColor DarkGray
            $experimentResults['implementation_density'] = 'SKIP_NO_FILES'
        }
    } catch {
        Write-Host "  ✗ Density gate error: $($_.Exception.Message)" -ForegroundColor Red
        $experimentResults['implementation_density'] = 'ERROR'
    }
} else {
    Write-Host "  ⊘ Slice plan not found, skipping" -ForegroundColor DarkGray
    $experimentResults['implementation_density'] = 'SKIP_NO_FILE'
}

# === EXPERIMENT 3: Horizontal Slice Pre-Authorization ===
Write-Host "Experiment 3: Horizontal Slice Pre-Authorization..." -ForegroundColor Cyan

$horizontalScript = Join-Path $scriptRoot 'authorize_horizontal_slice.py'

if (Test-Path -LiteralPath $slicePlanJson) {
    try {
        Write-Host "  Running: $horizontalScript" -ForegroundColor Gray
        if ($WhatIf) {
            Write-Host "  [WHAT IF] Would run horizontal authorization" -ForegroundColor Yellow
            $experimentResults['horizontal_authorization'] = 'SKIPPED_WHATIF'
        } else {
            $result = & $pythonExe $horizontalScript --slice_plan $slicePlanJson --min_categories 3 --required "Backend,Database" 2>&1
            $json = $result | ConvertFrom-Json

            if ($json.authorized) {
                Write-Host "  ✓ Horizontal authorized: $($json.touched_count)/3 categories - $($json.touched_categories -join ', ')" -ForegroundColor Green
                $experimentResults['horizontal_authorization'] = 'PASS'
            } else {
                Write-Host "  ✗ Horizontal authorization blocked: $($json.reason)" -ForegroundColor Red
                Write-Host "    Missing: $($json.missing_required_categories -join ', ')" -ForegroundColor Red
                $experimentResults['horizontal_authorization'] = 'FAIL'
            }
        }
    } catch {
        Write-Host "  ✗ Horizontal authorization error: $($_.Exception.Message)" -ForegroundColor Red
        $experimentResults['horizontal_authorization'] = 'ERROR'
    }
} else {
    Write-Host "  ⊘ Slice plan not found, skipping" -ForegroundColor DarkGray
    $experimentResults['horizontal_authorization'] = 'SKIP_NO_FILE'
}

# === SUMMARY ===
Write-Host ""
Write-Host "=== Experiment Summary ===" -ForegroundColor White

$passCount = ($experimentResults.Values | Where-Object { $_ -eq 'PASS' }).Count
$failCount = ($experimentResults.Values | Where-Object { $_ -eq 'FAIL' }).Count
$errorCount = ($experimentResults.Values | Where-Object { $_ -eq 'ERROR' }).Count
$skipCount = ($experimentResults.Values | Where-Object { $_ -like 'SKIP*' }).Count

Write-Host "  Pass: $passCount | Fail: $failCount | Error: $errorCount | Skip: $skipCount" -ForegroundColor $(if ($failCount -eq 0 -and $errorCount -eq 0) { "Green" } elseif ($failCount -gt 0) { "Red" } else { "Yellow" })

# Create result output
$result = [ordered]@{
    schema_version = 'v419'
    replay_root = $replayRootFull
    experiments = $experimentResults
    summary = [ordered]@{
        pass = $passCount
        fail = $failCount
        error = $errorCount
        skip = $skipCount
        total = $experimentResults.Count
    }
    overall_status = if ($failCount -eq 0 -and $errorCount -eq 0) { 'ALL_PASS' } elseif ($failCount -gt 0) { 'HAS_FAILURES' } else { 'INCOMPLETE' }
    timestamp = (Get-Date -Format "o")
}

$outputPath = Join-Path $replayRootFull 'V419_EXPERIMENTS_RESULT.json'
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding UTF8

Write-Host ""
Write-Host "Result written to: $outputPath" -ForegroundColor Cyan
$result | ConvertTo-Json -Depth 10

exit $(if ($failCount -gt 0 -or $errorCount -gt 0) { 1 } else { 0 })
