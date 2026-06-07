# v449 Expected Diff Closure Test

$testResults = @()

# Test 1: Prompt includes v449 closure format
$test1 = @{ name = 'test1'; pass = $false }
$promptPath = Join-Path $PSScriptRoot "..\prompts\phase-plan-tournament.prompt.md"
if (Test-Path $promptPath) {
    $promptContent = Get-Content $promptPath -Raw
    if ($promptContent -match 'v449' -and $promptContent -match 'closure') {
        $test1.pass = $true
    }
}
$testResults += $test1

# Test 2: Verifier includes v449 closure check
$test2 = @{ name = 'test2'; pass = $false }
$verifierPath = Join-Path $PSScriptRoot "Verify-PlanContract.ps1"
if (Test-Path $verifierPath) {
    $verifierContent = Get-Content $verifierPath -Raw
    if ($verifierContent -match 'v449' -and $verifierContent -match 'closure') {
        $test2.pass = $true
    }
}
$testResults += $test2

# Test 3: Verifier has closure check logic
$test3 = @{ name = 'test3'; pass = $false }
if (Test-Path $verifierPath) {
    $verifierContent = Get-Content $verifierPath -Raw
    if ($verifierContent -match 'hasClosureKeyword') {
        $test3.pass = $true
    }
}
$testResults += $test3

# Output results
$passedCount = ($testResults | Where-Object { $_.pass }).Count
$totalCount = $testResults.Count

Write-Host "v449 Test: $passedCount/$totalCount passed"

foreach ($test in $testResults) {
    if ($test.pass) {
        Write-Host "  [PASS] $($test.name)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($test.name)" -ForegroundColor Red
    }
}

exit $(if ($passedCount -eq $totalCount) { 0 } else { 1 })
