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

function Import-RunSliceLoopFunctions {
    $runSliceLoop = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-SliceLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }
    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($functionAst in @($functionAsts)) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v549-closed-ledger-stop-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $runnerContract = Join-Path $tempRoot 'RUNNER_ENFORCEMENT_CONTRACT.md'
    '# contract' | Set-Content -LiteralPath $runnerContract -Encoding UTF8

    Import-RunSliceLoopFunctions

    $ledger = [pscustomobject]@{
        families = @(
            [pscustomobject]@{
                id = 'core_entry'
                required = $true
                status = 'EXECUTABLE_CLOSED'
                touched_count = 1
                weight = 100
                proof_required = @('behavior_test')
                forbidden_proof = @('helper_only')
            },
            [pscustomobject]@{
                id = 'wire_payload_api_contract'
                required = $true
                status = 'EXECUTABLE_CLOSED'
                touched_count = 1
                weight = 88
                proof_required = @('payload_assertion')
                forbidden_proof = @('helper_only')
            }
        )
    }
    $rank = New-CarrierRankMap -Ledger $ledger -SliceIndex 3
    $forced = Resolve-ForcedFamilyDecisionForSlice `
        -Ledger $ledger `
        -SliceIndex 3 `
        -CarrierRank $rank `
        -SourceChainContractPath (Join-Path $tempRoot 'SOURCE_CHAIN_CONTRACT.json') `
        -RunnerContractPath $runnerContract

    Assert-True 'closed ledger has no next forced family' (Test-NoOpenRequiredFamilyForSlice -Ledger $ledger -CarrierRank $rank -ForcedDecision $forced) ($forced | ConvertTo-Json -Depth 10)

    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_03.json') ([ordered]@{
        slice_index = 3
        slice_status = 'BLOCKED'
        gap_flags = @('no_progress_slice')
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_VERIFY_03.json') ([ordered]@{
        slice_index = 3
        verification_status = 'BLOCKED'
        authorized_for_next_slice = $false
        authorized_for_synthesis = $false
        authorization_blockers = @('selected_carrier_missing')
    })
    Write-JsonFile (Join-Path $tempRoot 'CARRIER_RANK_03.json') ([ordered]@{
        schema_version = 1
        slice_index = 3
        families = @()
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_AUTHORIZATION_03.json') ([ordered]@{
        slice_index = 3
        status = 'BLOCKED'
        issues = @('selected_carrier_missing')
    })

    $archivedCount = Clear-SliceArtifactsAfterRequirementClosure `
        -ReplayRoot $tempRoot `
        -SliceIndex 3 `
        -MaxSlices 4 `
        -RunnerContractPath $runnerContract

    Assert-True 'future blocked slice result is removed from active replay root' (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'SLICE_RESULT_03.json')))
    Assert-True 'future blocked slice verify is removed from active replay root' (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'SLICE_VERIFY_03.json')))
    Assert-True 'future slice authorization is removed from active replay root' (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'SLICE_AUTHORIZATION_03.json')))
    Assert-True 'future slice artifacts are archived' ([int]$archivedCount -ge 4) "archived_count=$archivedCount"
    $archived = @(Get-ChildItem -LiteralPath (Join-Path $tempRoot 'logs\stale-slice-results\slice03') -File)
    Assert-True 'archived S3 artifacts remain auditable' ($archived.Count -ge 4) ($archived | Select-Object Name | ConvertTo-Json)
    $contractText = Get-Content -LiteralPath $runnerContract -Raw -Encoding UTF8
    Assert-True 'runner contract records closure stop' ($contractText.Contains('all_required_families_closed')) $contractText

    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        implemented_files = @('src/main/java/acme/ApplyProcessor.java')
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PASS'
        slice_status = 'DONE'
        authorized_for_next_slice = $true
        authorized_for_synthesis = $true
        authorization_blockers = @()
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_02.json') ([ordered]@{
        slice_index = 2
        slice_status = 'DONE'
        implemented_files = @('src/main/java/acme/CalcProcessor.java')
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_VERIFY_02.json') ([ordered]@{
        slice_index = 2
        verification_status = 'PASS'
        slice_status = 'DONE'
        authorized_for_next_slice = $true
        authorized_for_synthesis = $true
        authorization_blockers = @()
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_RESULT_03.json') ([ordered]@{
        slice_index = 3
        slice_status = 'BLOCKED'
        gap_flags = @('no_progress_slice')
    })
    Write-JsonFile (Join-Path $tempRoot 'SLICE_VERIFY_03.json') ([ordered]@{
        slice_index = 3
        verification_status = 'BLOCKED'
        authorized_for_next_slice = $false
        authorized_for_synthesis = $false
        authorization_blockers = @('selected_carrier_missing')
    })
    Clear-SliceArtifactsAfterRequirementClosure `
        -ReplayRoot $tempRoot `
        -SliceIndex 1 `
        -MaxSlices 3 `
        -RunnerContractPath $runnerContract | Out-Null
    Assert-True 'closed replay cleanup preserves authorized S1 result' (Test-Path -LiteralPath (Join-Path $tempRoot 'SLICE_RESULT_01.json'))
    Assert-True 'closed replay cleanup preserves authorized S2 verify' (Test-Path -LiteralPath (Join-Path $tempRoot 'SLICE_VERIFY_02.json'))
    Assert-True 'closed replay cleanup removes only non-authorizing future S3 result' (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'SLICE_RESULT_03.json')))

    $progressPath = Join-Path $tempRoot 'SLICE_PROGRESS.json'
    Set-SliceProgressFromAuthorizingEvidence -Path $progressPath -ReplayRoot $tempRoot -MaxSlices 3
    $progress = Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'progress is rebuilt from authorized slices only' ((@($progress.completed) -join ',') -eq '1,2') ($progress | ConvertTo-Json -Depth 6)

    $openLedger = [pscustomobject]@{
        families = @(
            [pscustomobject]@{
                id = 'wire_payload_api_contract'
                required = $true
                status = 'OPEN'
                touched_count = 0
                weight = 88
                first_executable_carrier = 'AiApplyClaimApiTaskProcessor.doIt'
                proof_required = @('payload_assertion')
                forbidden_proof = @('helper_only')
            }
        )
    }
    $openRank = New-CarrierRankMap -Ledger $openLedger -SliceIndex 2
    $openForced = Resolve-ForcedFamilyDecisionForSlice `
        -Ledger $openLedger `
        -SliceIndex 2 `
        -CarrierRank $openRank `
        -SourceChainContractPath (Join-Path $tempRoot 'SOURCE_CHAIN_CONTRACT.json') `
        -RunnerContractPath $runnerContract
    Assert-True 'open required family still continues slicing' (-not (Test-NoOpenRequiredFamilyForSlice -Ledger $openLedger -CarrierRank $openRank -ForcedDecision $openForced)) ($openForced | ConvertTo-Json -Depth 10)

    Write-Host 'v549 closed ledger stops future slices regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
