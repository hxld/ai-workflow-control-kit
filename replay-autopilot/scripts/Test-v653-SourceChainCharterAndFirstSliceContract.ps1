#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$scriptsRoot = Split-Path -Parent $PSCommandPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v653-source-chain-contract-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $validRoot = Join-Path $tempRoot 'valid-charter'
    New-Item -ItemType Directory -Force -Path $validRoot | Out-Null
    Write-Utf8 (Join-Path $validRoot 'TEST_CHARTER.md') @'
# TEST_CHARTER

Entry Point: DemoTaskProcessor.rebuildTaskData(Long caseId)
Test Class: GenericIdRebuildPathTest
DB Verification: AtomicReference captures the RequestBuildFunction request and assertEquals verifies primaryId and secondaryId.
Side Effects:
- assert AtomicReference contains the rebuilt request payload from the real rebuildTaskData invocation.

Use no-Spring JUnit and Mockito. Reflect DemoTaskProcessor.getDeclaredMethod("rebuildTaskData", Long.class) and call rebuildMethod.invoke(realProcessor, caseId). Mock collaborators are allowed. CommonRequestAssemblyHelper.buildRequestCommon is mocked only to provide deterministic RequestBuildContext input, and the real RequestBuildFunction is invoked to build the request.
'@
    $validJson = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-TestCharterPrevalidator.ps1') -WorkDir $validRoot -PassThru
    Assert-True ($LASTEXITCODE -eq 0) 'valid source-chain charter with mocked collaborators should pass'
    $valid = ($validJson | Out-String) | ConvertFrom-Json
    Assert-True (-not [bool]$valid.repairable_charter_failure) 'valid charter should not be marked repairable failure'
    $validClassifications = @($valid.source_chain_classifications | ForEach-Object { [string]$_.classification })
    Assert-True ($validClassifications -contains 'mocked_collaborator') 'valid charter should classify mocked collaborator as allowed'

    $invalidRoot = Join-Path $tempRoot 'invalid-charter'
    New-Item -ItemType Directory -Force -Path $invalidRoot | Out-Null
    Write-Utf8 (Join-Path $invalidRoot 'TEST_CHARTER.md') @'
# TEST_CHARTER

Entry Point: DemoTaskProcessor.rebuildTaskData(Long caseId)
Test Class: GenericIdRebuildPathTest
DB Verification: AtomicReference capture.
Side Effects:
- assert the copied terminal payload field.

Method rebuildMethod = DemoTaskProcessor.class.getDeclaredMethod("rebuildTaskData", Long.class);
The plan uses new DemoTaskData() with hand-built fields and returns new DemoRequest() from the test.
assertTrue("documents expected behavior", true);
'@
    $invalidJson = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-TestCharterPrevalidator.ps1') -WorkDir $invalidRoot -PassThru
    Assert-True ($LASTEXITCODE -ne 0) 'synthetic source-chain charter should fail'
    $invalid = ($invalidJson | Out-String) | ConvertFrom-Json
    $invalidCodes = @($invalid.failures | ForEach-Object { [string]$_.code })
    Assert-True ($invalidCodes -contains 'SYNTHETIC_SOURCE_CHAIN_CHARTER') 'synthetic charter should expose synthetic failure code'
    Assert-True ([bool]$invalid.repairable_charter_failure) 'synthetic data/no-invocation charter should be repairable once'
    $invalidClassifications = @($invalid.failures | ForEach-Object { @($_.classifications) } | ForEach-Object { [string]$_ })
    Assert-True ($invalidClassifications -contains 'synthetic_data_setup') 'synthetic data setup classification should be present'

    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>demo-root</artifactId><version>1</version></project>'

    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    $worktreePom = Join-Path $worktree 'pom.xml'
    $mvnCommand = "mvn --% -f $worktreePom -pl demo-harness -am -Dtest=GenericIdRebuildPathTest#rebuildCopiesPrimaryAndSecondaryIds -Dsurefire.failIfNoSpecifiedTests=false test"
    @{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = 'demo.TaskProcessor.rebuildTaskData(Long): TaskData'
        selected_carrier = 'demo.TaskProcessor.rebuildTaskData(Long): TaskData'
        production_boundary = 'demo.TaskProcessor.rebuildTaskData(Long): TaskData'
        downstream_side_effect_or_output = 'rebuilt taskData primaryId and secondaryId'
        red_expectation = 'assertEquals on primaryId and secondaryId fails before rebuild source chain is fixed'
        issues = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    @{
        gate = 'callable_carrier_authorization'
        slice_index = 1
        authorization = 'ALLOW'
        can_proceed = $true
        selected_carrier = 'demo.TaskProcessor.rebuildTaskData(Long): TaskData'
        selected_real_entry = 'demo.TaskProcessor.rebuildTaskData(Long): TaskData'
        resolved_signature = @{ selected_carrier = @{ class_name = 'demo.TaskProcessor'; visibility = 'private'; formatted = 'TaskData demo.TaskProcessor.rebuildTaskData(Long)' } }
        blockers = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_01.json') -Encoding UTF8
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
- selected_carrier: demo.TaskProcessor.rebuildTaskData(Long): TaskData
- selected_real_entry: demo.TaskProcessor.rebuildTaskData(Long): TaskData
- entry_invocation_method: reflection invoke rebuildTaskData on real TaskProcessor with mocked collaborators
- first_red_test: GenericIdRebuildPathTest#rebuildCopiesPrimaryAndSecondaryIds
- red_command: $mvnCommand
- green_command: $mvnCommand
- expected_red_failure: assertEquals on primaryId and secondaryId fails before rebuild source chain is fixed
- expected_green_assertion: assertEquals on primaryId and secondaryId passes through real rebuildTaskData
- red_assertion: assertEquals on primaryId and secondaryId
- downstream_output_or_side_effect: rebuilt taskData primaryId and secondaryId
- production_boundary: demo.TaskProcessor.rebuildTaskData(Long): TaskData
- must_not_behavior: must not hand-build final request or return terminal DTO without invoking the production builder
- green_change_boundary: rebuildTaskData source-chain assignment
- validation_command: $mvnCommand
"@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 1 `
        -ForcedRequirementFamily core_entry `
        -ForcedSliceType real_entry_behavior
    Assert-True ($LASTEXITCODE -eq 0) 'pre-slice contracts should authorize complete first-slice source-chain contract'
    $contract = Get-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_EXECUTABLE_CONTRACT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($field in @('production_entry_qn', 'entry_invocation_method', 'required_side_effects', 'business_red_assertion', 'negative_guard_assertion', 'forbidden_test_surfaces', 'allowed_mock_boundaries', 'maven_test_command_template')) {
        $value = $contract.$field
        $present = if ($value -is [System.Array]) { @($value).Count -gt 0 } else { -not [string]::IsNullOrWhiteSpace([string]$value) }
        Assert-True $present "FIRST_SLICE_EXECUTABLE_CONTRACT must include $field"
    }
    Assert-True ([string]$contract.contract_status -eq 'AUTHORIZED') 'first-slice execution contract should be authorized'

    $promptText = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $scriptsRoot) 'prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
    Assert-True ($promptText -match 'directly returning a hand-built final request') 'executor prompt should forbid hand-built final request source-chain proof'
    Assert-True ($promptText -match 'FIRST_SLICE_EXECUTABLE_CONTRACT\.json') 'executor prompt should require first-slice execution contract'

    Write-Host 'v653 Source-Chain Charter and First-Slice Contract: PASS'
    exit 0
} catch {
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
