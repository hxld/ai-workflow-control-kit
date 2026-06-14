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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v532-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        implemented_files = @(
            'claim-core/src/main/java/acme/ApplyProcessor.java',
            'claim-core/src/main/java/acme/CalcProcessor.java',
            'claim-server/src/test/java/acme/PolicyNumRebuildPathTest.java'
        )
        current_slice_changed_files = @(
            'claim-core/src/main/java/acme/ApplyProcessor.java',
            'claim-core/src/main/java/acme/CalcProcessor.java',
            'claim-server/src/test/java/acme/PolicyNumRebuildPathTest.java'
        )
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PASS'
        slice_status = 'DONE'
        authorized_for_next_slice = $true
        changed_files = @(
            'claim-core/src/main/java/acme/ApplyProcessor.java',
            'claim-core/src/main/java/acme/CalcProcessor.java',
            'claim-server/src/test/java/acme/PolicyNumRebuildPathTest.java'
        )
    })

    Import-RunReplayLoopFunctions

    $allowed = Get-ReuseExistingPrePhase1DirtyDecision -ReplayRoot $replayRoot -DirtyEntries @(
        ' M claim-core/src/main/java/acme/ApplyProcessor.java',
        ' M claim-core/src/main/java/acme/CalcProcessor.java',
        '?? claim-server/src/test/java/acme/PolicyNumRebuildPathTest.java'
    )
    Assert-True 'authorized slice dirty files are allowed for reuse' ([bool]$allowed.allow -and [string]$allowed.reason -eq 'reuse_existing_dirty_matches_authorized_slice_files') ($allowed | ConvertTo-Json -Depth 12)
    Assert-True 'dirty paths are normalized from git status entries' (@($allowed.dirty_paths) -contains 'claim-server/src/test/java/acme/PolicyNumRebuildPathTest.java') ($allowed | ConvertTo-Json -Depth 12)

    $blocked = Get-ReuseExistingPrePhase1DirtyDecision -ReplayRoot $replayRoot -DirtyEntries @(
        ' M claim-core/src/main/java/acme/ApplyProcessor.java',
        ' M pom.xml'
    )
    Assert-True 'extra dirty file outside authorized slice remains blocked' (-not [bool]$blocked.allow) ($blocked | ConvertTo-Json -Depth 12)
    Assert-True 'blocked decision preserves diagnostic reason' ([string]$blocked.reason -eq 'dirty_entries_not_covered_by_authorized_slice_set') ($blocked | ConvertTo-Json -Depth 12)

    $multiReplayRoot = Join-Path $tempRoot 'multi-slice-replay'
    New-Item -ItemType Directory -Force -Path $multiReplayRoot | Out-Null
    Write-JsonFile (Join-Path $multiReplayRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        implemented_files = @(
            'claim-core/src/main/java/acme/ApplyProcessor.java'
        )
    })
    Write-JsonFile (Join-Path $multiReplayRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PASS'
        slice_status = 'DONE'
        authorized_for_next_slice = $true
        changed_files = @(
            'claim-core/src/main/java/acme/ApplyProcessor.java'
        )
    })
    Write-JsonFile (Join-Path $multiReplayRoot 'SLICE_RESULT_02.json') ([ordered]@{
        slice_index = 2
        slice_status = 'DONE'
        implemented_files = @(
            'claim-core/src/main/java/acme/CalcProcessor.java',
            'claim-server/src/test/java/acme/PolicyNumRebuildPathTest.java'
        )
    })
    Write-JsonFile (Join-Path $multiReplayRoot 'SLICE_VERIFY_02.json') ([ordered]@{
        slice_index = 2
        verification_status = 'PASS'
        slice_status = 'DONE'
        authorized_for_next_slice = $true
        changed_files = @(
            'claim-core/src/main/java/acme/CalcProcessor.java',
            'claim-server/src/test/java/acme/PolicyNumRebuildPathTest.java'
        )
    })
    $multiAllowed = Get-ReuseExistingPrePhase1DirtyDecision -ReplayRoot $multiReplayRoot -DirtyEntries @(
        ' M claim-core/src/main/java/acme/ApplyProcessor.java',
        ' M claim-core/src/main/java/acme/CalcProcessor.java',
        '?? claim-server/src/test/java/acme/PolicyNumRebuildPathTest.java'
    )
    Assert-True 'dirty files split across authorized slices are allowed for reuse' `
        ([bool]$multiAllowed.allow -and [string]$multiAllowed.reason -eq 'reuse_existing_dirty_matches_authorized_slice_set') `
        ($multiAllowed | ConvertTo-Json -Depth 12)

    Write-Host 'v532 reuse-existing dirty authorized slice regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
