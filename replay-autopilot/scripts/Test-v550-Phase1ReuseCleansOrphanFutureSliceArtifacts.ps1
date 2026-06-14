param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "ASSERT FAILED: $Name" }
        throw "ASSERT FAILED: $Name - $Details"
    }
    Write-Host "PASS: $Name"
}

function Write-JsonFile {
    param([string]$Path, $Value, [int]$Depth = 12)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Import-RunReplayLoopFunctions {
    $runLoop = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-ReplayLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }
    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($functionAst in @($functionAsts)) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v550-phase1-reuse-cleanup-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    '# contract' | Set-Content -LiteralPath (Join-Path $tempRoot 'RUNNER_ENFORCEMENT_CONTRACT.md') -Encoding UTF8
    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PASS'
        slice_status = 'DONE'
        authorized_for_next_slice = $true
        authorized_for_synthesis = $true
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_02.json') ([ordered]@{
        slice_index = 2
        slice_status = 'DONE'
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_VERIFY_02.json') ([ordered]@{
        slice_index = 2
        verification_status = 'PASS'
        slice_status = 'DONE'
        authorized_for_next_slice = $true
        authorized_for_synthesis = $true
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_AUTHORIZATION_03.json') ([ordered]@{
        slice_index = 3
        status = 'BLOCKED'
        issues = @('selected_carrier_missing')
    })
    'stale display' | Set-Content -LiteralPath (Join-Path $tempRoot 'PRE_SLICE_CAP_DISPLAY_03.md') -Encoding UTF8

    Import-RunReplayLoopFunctions

    $cleanup = Clear-OrphanFutureSliceArtifactsAfterPhase1Reuse `
        -ReplayRoot $tempRoot `
        -MaxSlices 3 `
        -ReuseDecision ([pscustomobject]@{
            runner_final_pass_allowed = $true
            open_required_family_count = 0
        })

    Assert-True 'orphan future slice artifacts are archived on phase1 reuse' ([int]$cleanup.archived_count -eq 2) ($cleanup | ConvertTo-Json -Depth 8)
    Assert-True 'future slice authorization removed from active root' (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'SLICE_AUTHORIZATION_03.json')))
    Assert-True 'future cap display removed from active root' (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'PRE_SLICE_CAP_DISPLAY_03.md')))
    Assert-True 'authorized S1 result remains active' (Test-Path -LiteralPath (Join-Path $tempRoot 'SLICE_RESULT_01.json'))
    Assert-True 'authorized S2 verify remains active' (Test-Path -LiteralPath (Join-Path $tempRoot 'SLICE_VERIFY_02.json'))
    $progress = Get-Content -LiteralPath (Join-Path $tempRoot 'SLICE_PROGRESS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'progress excludes orphan future slice after cleanup' ((@($progress.completed) -join ',') -eq '1,2') ($progress | ConvertTo-Json -Depth 6)

    Write-Host 'v550 phase1 reuse orphan future slice cleanup regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
