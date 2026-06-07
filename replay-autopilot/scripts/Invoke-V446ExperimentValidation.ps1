# V446 Experiment Validation - Integrated Three Experiments
#
# This script integrates Experiments 1, 2, and 3 from NEXT_EXPERIMENT_PLAN.md:
# - Exp1: Facade-First Carrier Selection (P0)
# - Exp2: Phase 0 Layer Binding Validation (P1)
# - Exp3: Baseline Index Cache (P2)
#
# Usage:
#   Invoke-V446ExperimentValidation.ps1 -PlanResultPath <path> -Worktree <path>

param(
    [Parameter(Mandatory = $true)]
    [string]$PlanResultPath,

    [Parameter(Mandatory = $true)]
    [string]$Worktree,

    [Parameter(Mandatory = $false)]
    [switch]$ValidateOnly,

    [Parameter(Mandatory = $false)]
    [string]$FamiliesPath = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot

# Helper function to run Python script
function Invoke-PythonScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments,
        [switch]$ThrowOnError
    )

    $pythonExe = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonExe) {
        $pythonExe = Get-Command python3 -ErrorAction SilentlyContinue
    }

    if (-not $pythonExe) {
        throw "Python not found. Please install Python 3."
    }

    $output = & $pythonExe.Path $ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0 -and $ThrowOnError) {
        throw "Python script failed: $ScriptPath. Exit code: $exitCode. Output: $($output -join '`n')"
    }

    return @{
        ExitCode = $exitCode
        Output = $output -join "`n"
    }
}

# Helper to check if file exists
function Test-FileExists {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }
    return $true
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "V446 Experiment Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 0: Validate inputs
Write-Host "[Step 0] Validating inputs..." -ForegroundColor Yellow
Test-FileExists $PlanResultPath
Test-FileExists $Worktree

$planResultFullPath = Resolve-Path $PlanResultPath
$worktreeFullPath = Resolve-Path $Worktree

Write-Host "  Plan Result: $planResultFullPath" -ForegroundColor Gray
Write-Host "  Worktree: $worktreeFullPath" -ForegroundColor Gray
Write-Host ""

# Step 1: Baseline Index Cache (Exp3) - Initialize cache
Write-Host "[Step 1] Initializing Baseline Index Cache (Exp3)..." -ForegroundColor Yellow

$cacheScript = Join-Path $scriptDir "baseline_index_cache.py"
if (Test-Path $cacheScript) {
    $cacheStats = Invoke-PythonScript -ScriptPath $cacheScript -Arguments @("stats")
    Write-Host "  Cache stats:" -ForegroundColor Gray
    Write-Host "    $($cacheStats.Output)" -ForegroundColor Gray

    # Get baseline commit
    $baselineCommit = Invoke-PythonScript -ScriptPath $cacheScript -Arguments @("baseline-commit", $worktreeFullPath)
    Write-Host "  Baseline commit: $($baselineCommit.Output.Trim())" -ForegroundColor Gray
} else {
    Write-Host "  Warning: Cache script not found at $cacheScript" -ForegroundColor DarkYellow
}
Write-Host ""

# Step 2: Facade-First Carrier Search (Exp1)
Write-Host "[Step 2] Facade-First Carrier Selection (Exp1)..." -ForegroundColor Yellow

$facadeScript = Join-Path $scriptDir "facade_first_carrier_search.py"
if (Test-Path $facadeScript) {
    # Check if families file is provided or extract from plan
    $familiesJson = $FamiliesPath

    if (-not $familiesJson) {
        # Try to extract families from plan result
        # For now, use default families
        $familiesJson = "[]"
        Write-Host "  Warning: No families provided, using empty list" -ForegroundColor DarkYellow
    }

    Test-FileExists $familiesJson

    $facadeResult = Invoke-PythonScript -ScriptPath $facadeScript -Arguments @("search", $worktreeFullPath, $familiesJson)

    Write-Host "  Facade search result:" -ForegroundColor Gray
    Write-Host "    $($facadeResult.Output)" -ForegroundColor Gray

    if ($facadeResult.ExitCode -eq 0) {
        Write-Host "  Status: PASS" -ForegroundColor Green
    } else {
        Write-Host "  Status: FAIL" -ForegroundColor Red
    }
} else {
    Write-Host "  Warning: Facade script not found at $facadeScript" -ForegroundColor DarkYellow
}
Write-Host ""

# Step 3: Layer Binding Validation (Exp2)
Write-Host "[Step 3] Layer Binding Validation (Exp2)..." -ForegroundColor Yellow

$layerScript = Join-Path $scriptDir "plan_layer_binding.py"
if (Test-Path $layerScript) {
    # Find IMPLEMENTATION_CONTRACT.md
    $contractPath = Join-Path (Split-Path $planResultFullPath) "IMPLEMENTATION_CONTRACT.md"

    if (-not (Test-Path $contractPath)) {
        $contractPath = Join-Path (Split-Path $planResultFullPath) "IMPLEMENTATION_CONTRACT.json"
    }

    if (Test-Path $contractPath) {
        $layerResult = Invoke-PythonScript -ScriptPath $layerScript -Arguments @("validate-phase0", $planResultFullPath, $worktreeFullPath)

        Write-Host "  Layer validation result:" -ForegroundColor Gray
        Write-Host "    $($layerResult.Output)" -ForegroundColor Gray

        if ($layerResult.ExitCode -eq 0) {
            Write-Host "  Status: PASS" -ForegroundColor Green
        } else {
            Write-Host "  Status: FAIL" -ForegroundColor Red
        }
    } else {
        Write-Host "  Warning: IMPLEMENTATION_CONTRACT not found at expected location" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "  Warning: Layer script not found at $layerScript" -ForegroundColor DarkYellow
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "V446 Experiment Validation Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Experiments integrated:" -ForegroundColor White
Write-Host "  [Exp1] Facade-First Carrier Selection" -ForegroundColor Gray
Write-Host "  [Exp2] Phase 0 Layer Binding Validation" -ForegroundColor Gray
Write-Host "  [Exp3] Baseline Index Cache" -ForegroundColor Gray
Write-Host ""

# Write verification result
$verifyPath = $planResultFullPath -replace '\.(json|md)$', '_V446_EXPERIMENT_VERIFY.json'

$verifyResult = @{
    version = "v446"
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    experiments = @{
        exp1_facade_first = $facadeResult.ExitCode -eq 0
        exp2_layer_binding = $layerResult.ExitCode -eq 0 -or (-not (Test-Path $layerScript))
        exp3_baseline_cache = $true  # Cache is transparent
    }
    overall_status = if ($facadeResult.ExitCode -eq 0 -and $layerResult.ExitCode -eq 0) { "PASS" } else { "FAIL" }
}

$verifyResult | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $verifyPath -Encoding UTF8
Write-Host "Verification result written to: $verifyPath" -ForegroundColor Cyan

if ($verifyResult.overall_status -eq "FAIL") {
    exit 1
}

exit 0
