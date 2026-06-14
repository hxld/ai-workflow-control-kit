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

function Write-TextFile {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v545-wire-payload-source-chain-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null

    $ledgerPath = Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json'
    Write-JsonFile $ledgerPath ([ordered]@{
        schema_version = 1
        families = @(
            [ordered]@{
                id = 'core_entry'
                required = $true
                status = 'EXECUTABLE_CLOSED'
                weight = 100
                first_executable_carrier = 'AiApplyClaimApiTaskProcessor.rebuildTaskData'
                proof_required = @('behavior_test')
                forbidden_proof = @('helper_only')
            },
            [ordered]@{
                id = 'wire_payload_api_contract'
                required = $true
                status = 'OPEN'
                weight = 88
                first_executable_carrier = 'AiApplyClaimApiTaskProcessor.doIt'
                proof_required = @('code_inspection', 'payload_assertion')
                forbidden_proof = @('helper_only')
            }
        )
    })

    Write-JsonFile (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{
        required_source_chain = $true
        next_required_slice = [ordered]@{
            family = 'source_chain'
            entry = 'AiApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and AiCalculateLossApiTaskProcessor.rebuildTaskData(Long caseId)'
            carrier = 'TaskProcessor rebuildTaskData -> AiClaimBaseTaskData.policyNum/insureNum -> InputData.policy_num/InputData.insure_num'
            slice_type = 'exact_contract_slice'
            test_name = 'AiApplyClaimApiTaskProcessorTest.testRebuildTaskData_PreservesPolicyNumAndInsureNum'
            required_assertions = @('source-chain preserves policyNum')
            forbidden_proof = @('helper_only')
        }
    })

    Write-JsonFile (Join-Path $replayRoot 'FAMILY_CONTRACT.json') ([ordered]@{
        families = @(
            [ordered]@{ id = 'core_entry'; required = $true },
            [ordered]@{ id = 'wire_payload_api_contract'; required = $true }
        )
    })
    Write-JsonFile (Join-Path $replayRoot 'CARRIER_RANK_02.json') ([ordered]@{
        schema_version = 1
        slice_index = 2
        families = @(
            [ordered]@{
                family = 'wire_payload_api_contract'
                required = $true
                status = 'OPEN'
                production_carrier = 'AiApplyClaimApiTaskProcessor.doIt'
                rank = 1
            }
        )
        missing_required_rank1 = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        verification_status = 'PASS'
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        closed_requirement_families = @('core_entry')
    })

    Write-TextFile (Join-Path $replayRoot 'TEST_CHARTER.md') @'
# Test Charter

## Test Execution Command
mvn -pl claim-server -am test -Dtest=PolicyNumRebuildPathTest

## Exact Wire Assertions
- Assert `input_data.policy_num` is emitted by `AiApplyClaimApiTaskProcessor.doIt`.
- Assert `input_data.insure_num` is emitted by `AiApplyClaimApiTaskProcessor.doIt`.
'@
    Write-TextFile (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') @'
selected_real_entry: AiApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId), AiCalculateLossApiTaskProcessor.rebuildTaskData(Long caseId)
first_red_test: PolicyNumRebuildPathTest.testRebuildTaskData_SourceChainAssignment
'@

    & (Join-Path $PSScriptRoot 'Prepare-SliceEvidenceContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -RequirementFamilyLedger $ledgerPath `
        -SliceIndex 2 `
        -ForcedRequirementFamily 'wire_payload_api_contract' `
        -ForcedSliceType 'exact_contract_slice' `
        -ForcedSiblingSurface 'AiApplyClaimApiTaskProcessor.doIt' | Out-Null

    $carrier = Get-Content -Raw -Encoding UTF8 (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_02.json') | ConvertFrom-Json
    $sideEffect = Get-Content -Raw -Encoding UTF8 (Join-Path $replayRoot 'SIDE_EFFECT_EVIDENCE_02.json') | ConvertFrom-Json
    Assert-True 'wire payload carrier has executable red expectation' (-not [string]::IsNullOrWhiteSpace([string]$carrier.red_expectation)) ($carrier | ConvertTo-Json -Depth 10)
    Assert-True 'exact-contract harness infers planned test name' ([string]$sideEffect.test_name -match 'PolicyNumRebuildPathTest') ($sideEffect | ConvertTo-Json -Depth 10)
    Assert-True 'wire payload does not require side-effect evidence' ([string]$sideEffect.status -eq 'NOT_REQUIRED' -and [string]$sideEffect.red_result -eq 'PENDING_BUSINESS_ASSERTION') ($sideEffect | ConvertTo-Json -Depth 10)

    & (Join-Path $PSScriptRoot 'Build-NextSliceExactContract.ps1') -ReplayRoot $replayRoot -SliceIndex 2 | Out-Null
    $nextExact = Get-Content -Raw -Encoding UTF8 (Join-Path $replayRoot 'NEXT_SLICE_EXACT_CONTRACT_02.json') | ConvertFrom-Json
    Assert-True 'next exact contract is actionable for wire payload' ([string]$nextExact.decision -eq 'ALLOW') ($nextExact | ConvertTo-Json -Depth 10)
    $missingRed = @($nextExact.rows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.red_command) })
    Assert-True 'next exact contract rows include red commands' ($missingRed.Count -eq 0) ($nextExact | ConvertTo-Json -Depth 10)

    & (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 2 `
        -ForcedRequirementFamily 'wire_payload_api_contract' `
        -ForcedSliceType 'exact_contract_slice' `
        -ForcedSiblingSurface 'AiApplyClaimApiTaskProcessor.doIt' | Out-Null

    $preAuth = Get-Content -Raw -Encoding UTF8 (Join-Path $replayRoot 'PRE_SLICE_AUTHORIZATION_02.json') | ConvertFrom-Json
    $issueText = (@($preAuth.issues) -join ',')
    Assert-True 'pre-slice authorization allows wire payload exact-contract slice' ([string]$preAuth.decision -eq 'ALLOW') ($preAuth | ConvertTo-Json -Depth 12)
    Assert-True 'closed source-chain contract is not applied to wire payload slice' (-not [bool]$preAuth.source_chain_required) ($preAuth | ConvertTo-Json -Depth 12)
    Assert-True 'pre-slice authorization has no stale source-chain mismatch' ($issueText -notmatch 'next_required_slice_mismatch:source_chain') $issueText
    Assert-True 'pre-slice authorization does not require side-effect evidence for exact-contract-only harness' ($issueText -notmatch 'side_effect_evidence_not_ready|test_name_missing|carrier_authorization_field_not_ready:red_expectation') $issueText

    Write-Host 'v545 wire payload exact-contract source-chain regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
