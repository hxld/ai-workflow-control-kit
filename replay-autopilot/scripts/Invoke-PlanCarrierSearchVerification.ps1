# Plan Carrier Search Verification
# Implements Experiment 3: Carrier Search Requirement Before New Service Creation
#
# This script verifies plan includes carrier search documentation

param(
    [Parameter(Mandatory = $true)]
    [string]$PlanResultPath,

    [Parameter(Mandatory = $true)]
    [string]$Worktree,

    [Parameter(Mandatory = $true)]
    [string]$OracleCommit,

    [string]$OracleDiffPath = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

$planResultPathFull = Resolve-AbsolutePath $PlanResultPath
$worktreeFull = Resolve-AbsolutePath $Worktree

# Read plan result
$planRaw = Get-Content -LiteralPath $planResultPathFull -Raw -Encoding UTF8
if ([System.IO.Path]::GetExtension($planResultPathFull) -ieq '.json') {
    $planResult = $planRaw | ConvertFrom-Json
} else {
    # Parse markdown key-value pairs with better handling for:
    # - Keys with underscores, colons, hyphens
    # - Values with quotes, pipes, asterisks, glob patterns
    # - Multi-line values (continued lines)
    $kv = [ordered]@{}
    $lines = $planRaw -split "`r?`n"
    $currentKey = $null
    $currentValue = $null

    foreach ($line in $lines) {
        # Skip empty lines and section headers
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^#{1,6}\s') {
            if ($currentKey) {
                $kv[$currentKey] = $currentValue
                $currentKey = $null
                $currentValue = $null
            }
            continue
        }

        # Check if this is a key-value line (key: value format)
        # Updated regex to handle:
        # - Optional markdown bold markers (**key**)
        # - Keys with underscores, colons, hyphens, spaces
        # - Values that start at the first colon and go to end of line
        if ($line -match '^\s*(?:[-*]\s*)?(?:\*\*)?([A-Za-z0-9_ :,/-]+?)(?:\*\*)?\s*:\s*(.+)$') {
            # Save previous key-value if exists
            if ($currentKey) {
                $kv[$currentKey] = $currentValue
            }

            $currentKey = ($Matches[1].Trim() -replace '\s+', '_').ToLowerInvariant()
            $currentValue = $Matches[2].Trim()
        }
        # Continuation of previous value (indented line)
        elseif ($currentKey -and $line -match '^\s+\S') {
            $currentValue += ' ' + $line.Trim()
        }
        # Save key-value at section boundaries
        elseif ($line -match '^---+$|^#{1,6}\s') {
            if ($currentKey) {
                $kv[$currentKey] = $currentValue
                $currentKey = $null
                $currentValue = $null
            }
        }
    }

    # Save last key-value
    if ($currentKey) {
        $kv[$currentKey] = $currentValue
    }
    $queries = @()
    if ($kv.Contains('carrier_search_queries')) {
        $queries = @(([string]$kv['carrier_search_queries']) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $newServiceValue = if ($kv.Contains('new_service_created')) { [string]$kv['new_service_created'] } elseif ($kv.Contains('new_service_proposed')) { [string]$kv['new_service_proposed'] } else { 'false' }
    $planResult = [pscustomobject]@{
        new_service_created = ($newServiceValue -match '(?i)^(true|yes|y|1|proposed|required)$')
        carrier_search_queries = @($queries)
        new_service_justification = if ($kv.Contains('new_service_justification')) { [string]$kv['new_service_justification'] } else { '' }
    }
}

# Read oracle diff if provided
$oracleDiff = if ($OracleDiffPath -and (Test-Path -LiteralPath $OracleDiffPath)) {
    Get-Content -LiteralPath $OracleDiffPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    @{}
}

# Build input for Python script
$inputData = @{
    plan_result = $planResult
    oracle_diff = $oracleDiff
    worktree = $worktreeFull
    oracle_commit = $OracleCommit
} | ConvertTo-Json -Depth 10

# Locate the Python script
$scriptDir = Split-Path -Parent $PSCommandPath
$pythonScript = Join-Path $scriptDir 'verify_plan_carrier_search.py'

if (-not (Test-Path -LiteralPath $pythonScript)) {
    throw "Python script not found: $pythonScript"
}

# Run the Python verification
$env:PYTHONIOENCODING = 'utf-8'
$tempInput = [System.IO.Path]::GetTempFileName()
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tempInput, $inputData, $utf8NoBom)
$resultJson = & python $pythonScript --input $tempInput 2>&1
$exitCode = $LASTEXITCODE
Remove-Item -LiteralPath $tempInput -Force -ErrorAction SilentlyContinue

# Parse result
try {
    $result = ($resultJson -join "`n") | ConvertFrom-Json
} catch {
    throw "Unable to parse carrier-search JSON: $($_.Exception.Message). Raw output: $($resultJson -join ' ')"
}

# Write verification result to file
$verifyPath = if ($planResultPathFull -match '\.(json|md)$') {
    $planResultPathFull -replace '\.(json|md)$', '_CARRIER_SEARCH_VERIFY.json'
} else {
    "$planResultPathFull`_CARRIER_SEARCH_VERIFY.json"
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $verifyPath -Encoding UTF8

# Log output
switch ($result.status) {
    'PASS' {
        Write-Host "Carrier Search: PASS - Carrier search documented and validated"
        exit 0
    }
    'WARN' {
        Write-Host "Carrier Search: WARN - Issues detected but not blocking"
        Write-Host "  Warnings: $(($result.warnings | ForEach-Object { $_.message }) -join '; ')"
        exit 0  # Warnings don't block
    }
    'FAIL' {
        Write-Host "Carrier Search: FAIL - Carrier search requirements not met"

        foreach ($issue in $result.issues) {
            Write-Host "  [$($issue.code)] $($issue.message)"
        }

        if ($result.warnings) {
            Write-Host "  Warnings:"
            foreach ($warning in $result.warnings) {
                Write-Host "    - $($warning.message)"
            }
        }

        exit 1  # Block on failures
    }
    default {
        Write-Host "Carrier Search: UNKNOWN status '$($result.status)'"
        exit 1
    }
}
