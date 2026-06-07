param(
    [string]$RegistryPath = (Join-Path $PSScriptRoot '..\features\replay-feature-registry.json'),
    [string]$ProjectRoot = 'D:\opt\claim'
)

$ErrorActionPreference = 'Stop'
$passed = 0
$failed = 0

function Test-BaseCommitIsolation {
    param(
        [string]$Repo,
        [string]$FeatureName,
        [string]$BaseCommit,
        [object[]]$ForbiddenCommits
    )
    if ($null -eq $ForbiddenCommits -or $ForbiddenCommits.Count -eq 0) { return }
    foreach ($entry in @($ForbiddenCommits)) {
        $forbiddenCommit = if ($entry -is [hashtable]) { $entry['commit'] } else { [string]$entry.commit }
        $reason = if ($entry -is [hashtable]) { $entry['reason'] } else { [string]$entry.reason }
        if ([string]::IsNullOrWhiteSpace($forbiddenCommit)) { continue }
        & git -C $Repo merge-base --is-ancestor $forbiddenCommit $BaseCommit 2>$null
        if ($LASTEXITCODE -eq 0) {
            throw "BASE_ISOLATION_VIOLATION: feature='$FeatureName' base_commit='$BaseCommit' contains forbidden commit '$forbiddenCommit'. Reason: $reason"
        }
    }
}

function Assert-Throws {
    param([scriptblock]$Block, [string]$ExpectedSubstring, [string]$Label)
    try {
        & $Block
        Write-Host "  FAIL: $Label - expected exception but none thrown" -ForegroundColor Red
        $script:failed++
    } catch {
        if ($_.Exception.Message -like "*$ExpectedSubstring*") {
            Write-Host "  PASS: $Label" -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host "  FAIL: $Label - exception message does not contain '$ExpectedSubstring'. Got: $($_.Exception.Message)" -ForegroundColor Red
            $script:failed++
        }
    }
}

function Assert-NoThrow {
    param([scriptblock]$Block, [string]$Label)
    try {
        & $Block
        Write-Host "  PASS: $Label" -ForegroundColor Green
        $script:passed++
    } catch {
        Write-Host "  FAIL: $Label - unexpected exception: $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host "`n=== Test-BaseCommitIsolationGuard ===" -ForegroundColor Cyan

# --- Test 1: Contaminated base should be rejected ---
$contaminatedBase = 'a9e7ea3c74135245b7b135226cc541a72f17b687'
$forbiddenCommit = '932a4d10abbe4d2810e814f4b37dcfcb9d9ae7df'
Assert-Throws -Label "Test 1: contaminated base (a9e7ea3c) rejected" -ExpectedSubstring 'BASE_ISOLATION_VIOLATION' -Block {
    Test-BaseCommitIsolation -Repo $ProjectRoot -FeatureName 'renbao-tuipiao' -BaseCommit $contaminatedBase -ForbiddenCommits @(
        @{ commit = $forbiddenCommit; reason = 'Implementation commit contaminates base' }
    )
}

# --- Test 2: Clean base should pass ---
$cleanBase = '31c38b935bc8e4c8de3ddb927d68a10a4d4286f8'
Assert-NoThrow -Label "Test 2: clean base (31c38b93) passes" -Block {
    Test-BaseCommitIsolation -Repo $ProjectRoot -FeatureName 'renbao-tuipiao' -BaseCommit $cleanBase -ForbiddenCommits @(
        @{ commit = $forbiddenCommit; reason = 'Implementation commit contaminates base' }
    )
}

# --- Test 3: Empty forbidden list should pass (no guard configured) ---
Assert-NoThrow -Label "Test 3: empty forbidden list passes" -Block {
    Test-BaseCommitIsolation -Repo $ProjectRoot -FeatureName 'any-feature' -BaseCommit $cleanBase -ForbiddenCommits @()
}

# --- Test 4: Verify registry renbao entry has correct clean base ---
Write-Host "`n--- Registry Verification ---" -ForegroundColor Cyan
$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$renbao = $registry.features | Where-Object { $_.feature_name -eq 'renbao-tuipiao' }

if ([string]$renbao.base_commit -eq $cleanBase) {
    Write-Host "  PASS: renbao-tuipiao base_commit is clean ($cleanBase)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL: renbao-tuipiao base_commit is '$($renbao.base_commit)', expected '$cleanBase'" -ForegroundColor Red
    $failed++
}

if ($null -ne $renbao.base_must_not_contain_commits -and $renbao.base_must_not_contain_commits.Count -gt 0) {
    Write-Host "  PASS: renbao-tuipiao has base_must_not_contain_commits guard ($($renbao.base_must_not_contain_commits.Count) entries)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL: renbao-tuipiao missing base_must_not_contain_commits guard" -ForegroundColor Red
    $failed++
}

# --- Test 5: Verify forbidden commit is NOT ancestor of the clean base ---
Assert-NoThrow -Label "Test 5: forbidden 932a4d10 not ancestor of clean base 31c38b93" -Block {
    & git -C $ProjectRoot merge-base --is-ancestor $forbiddenCommit $cleanBase 2>$null
    # exit 1 means NOT ancestor (which is what we want), exit 0 would be bad
    if ($LASTEXITCODE -eq 0) {
        throw "FORBIDDEN: 932a4d10 is ancestor of clean base 31c38b93 - base is contaminated!"
    }
}

# --- Test 6: Verify clean base IS ancestor of oracle ---
$oracleCommit = 'd1e5c590e261673465604c5a50790ba0e02545d1'
Assert-NoThrow -Label "Test 6: clean base 31c38b93 is ancestor of oracle d1e5c590" -Block {
    & git -C $ProjectRoot merge-base --is-ancestor $cleanBase $oracleCommit 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "CLEAN_BASE_INVALID: 31c38b93 is NOT ancestor of oracle d1e5c590"
    }
}

# --- Summary ---
Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $passed"
Write-Host "  Failed: $failed"
if ($failed -gt 0) {
    Write-Host "`nOVERALL: FAIL" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nOVERALL: PASS" -ForegroundColor Green
    exit 0
}
