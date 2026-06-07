param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'scripts\Build-NextSliceExactContract.ps1'
$tempRoot = Join-Path $root ('.tmp\exact-normalizer-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

function Write-JsonFile {
    param([string]$Path, $Value)
    ($Value | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

$cases = New-Object System.Collections.Generic.List[string]

try {
    Write-JsonFile -Path (Join-Path $tempRoot 'CARRIER_AUTHORIZATION_01.json') -Value ([ordered]@{
        selected_carrier = 'claim-core/src/main/java/Foo.java#handle'
        requires_exact_contract_assertions = $false
    })
    Write-JsonFile -Path (Join-Path $tempRoot 'SIDE_EFFECT_EVIDENCE_01.json') -Value ([ordered]@{
        test_name = 'claim-server/src/test/java/FooTest.java#red'
    })
    Write-JsonFile -Path (Join-Path $tempRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_01.json') -Value ([ordered]@{
        required_for_this_slice = $false
        rows = @(
            [ordered]@{
                literal = 'git diff'
                symbol_or_field = 'git diff'
                db_or_wire_or_display = 'meta'
                production_boundary = 'claim-core/src/main/java/Foo.java#handle'
                test_assertion = 'not a business assertion'
            },
            [ordered]@{
                literal = 'Foo.handle(...)'
                symbol_or_field = 'Foo.handle(...)'
                db_or_wire_or_display = 'behavior'
                production_boundary = 'claim-core/src/main/java/Foo.java#handle'
                test_assertion = 'method label only'
            },
            [ordered]@{
                literal = 'business payload field'
                symbol_or_field = 'payload.field'
                db_or_wire_or_display = 'wire'
                production_boundary = 'claim-core/src/main/java/Foo.java#handle'
                test_assertion = 'assert payload.field is present'
            }
        )
    })

    $result = (& powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReplayRoot $tempRoot -SliceIndex 1 -FailOnBroadRows | ConvertFrom-Json)
    $cases.Add((Assert-True 'non_required_broad_rows_do_not_stop' ([string]$result.decision -eq 'ALLOW'))) | Out-Null
    $cases.Add((Assert-True 'invalid_meta_row_classified' (@($result.row_classes | Where-Object { $_.class -eq 'invalid_meta_row' }).Count -ge 1))) | Out-Null
    $cases.Add((Assert-True 'warning_only_row_classified' (@($result.row_classes | Where-Object { $_.class -eq 'warning_only' }).Count -ge 1))) | Out-Null
    $cases.Add((Assert-True 'no_broad_row_issue_emitted' (-not ((@($result.issues) -join "`n") -match 'broad_exact_contract_row')))) | Out-Null

    $requiredRoot = Join-Path $root ('.tmp\exact-normalizer-required-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $requiredRoot | Out-Null
    Write-JsonFile -Path (Join-Path $requiredRoot 'CARRIER_AUTHORIZATION_01.json') -Value ([ordered]@{
        selected_carrier = 'claim-core/src/main/java/Foo.java#handle'
        requires_exact_contract_assertions = $true
    })
    Write-JsonFile -Path (Join-Path $requiredRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_01.json') -Value ([ordered]@{
        required_for_this_slice = $true
        rows = @(
            [ordered]@{
                literal = 'git log'
                symbol_or_field = 'git log'
                db_or_wire_or_display = 'meta'
                production_boundary = 'claim-core/src/main/java/Foo.java#handle'
                test_assertion = 'not a business assertion'
            }
        )
    })
    $requiredResult = (& powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReplayRoot $requiredRoot -SliceIndex 1 -FailOnBroadRows | ConvertFrom-Json)
    $cases.Add((Assert-True 'required_empty_subset_still_stops' ([string]$requiredResult.decision -eq 'STOP'))) | Out-Null
    $cases.Add((Assert-True 'required_empty_subset_issue' ((@($requiredResult.issues) -join "`n") -match 'next_slice_exact_contract_subset_empty'))) | Out-Null

    $source = Get-Content -LiteralPath $script -Raw -Encoding UTF8
    $cases.Add((Assert-True 'script_outputs_row_classes' ($source -match 'row_classes'))) | Out-Null
    $cases.Add((Assert-True 'script_has_invalid_meta_row' ($source -match 'invalid_meta_row'))) | Out-Null
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    if ($requiredRoot -and (Test-Path -LiteralPath $requiredRoot)) { Remove-Item -LiteralPath $requiredRoot -Recurse -Force }
}

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 6
