param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$Ledger = '',
    [int]$SliceIndex = 0,
    [string]$AssertExpectedFamily = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonObject {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Normalize-SiblingSurface {
    param([string]$Surface)
    if ([string]::IsNullOrWhiteSpace($Surface)) { return '' }
    $text = $Surface.Trim()
    if ($text -match '^[A-Za-z]\s*:\s*(?![\\/])(.+)$') {
        return $matches[1].Trim()
    }
    return $text
}

function Get-CarrierSurfacePriority {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    $score = 0
    if ($Text -match '(?i)\b(callback|webhook|fallback|external|integration|client|adapter|partner|provider)\b') { $score += 45 }
    if ($Text -match '(?i)\b(payload|request|response|wire|json|message|mq|queue|exchange|producer|consumer|publish|notify|push|event)\b') { $score += 35 }
    if ($Text -match '(?i)\b(controller|endpoint|route|handler|export|download|workbook|excel|page|view|display|template|render|upload|artifact)\b') { $score += 30 }
    if ($Text -match '(?i)\b(mapper|dao|repository|insert|update|delete|save|persist|db|database|column|transaction|rollback)\b') { $score += 20 }
    if ($Text -match '(?i)\b(helper|util|constant|enum[-_ ]?only|dto[-_ ]?only|static[-_ ]?only)\b') { $score -= 25 }
    return $score
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Read-JsonIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Write-JsonObject {
    param([string]$Path, $Value)
    $tmp = "$Path.tmp.$PID"
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Set-ObjectProperty {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Test-NarrowBackendReadOnlyFeature {
    param($FeatureClassification)
    if ($null -eq $FeatureClassification) { return $false }
    $classification = [string]$FeatureClassification.classification
    $baseClassification = [string]$FeatureClassification.base_classification
    $readOnly = $false
    if ($FeatureClassification.PSObject.Properties.Name -contains 'read_only') {
        $readOnly = [bool]$FeatureClassification.read_only
    }
    return $readOnly -and (
        $classification -eq 'narrow_backend_read_only_fix' -or
        $baseClassification -eq 'narrow_backend_fix'
    )
}

function Get-FeatureNonApplicableFamilies {
    param($FeatureClassification)
    $families = New-Object System.Collections.Generic.List[string]
    if ($null -eq $FeatureClassification) { return @() }
    if ($null -ne $FeatureClassification.verifier_adjustments -and
        $FeatureClassification.verifier_adjustments.PSObject.Properties.Name -contains 'non_applicable_families') {
        foreach ($family in @(Get-StringArray $FeatureClassification.verifier_adjustments.non_applicable_families)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$family) -and -not $families.Contains([string]$family)) {
                $families.Add([string]$family) | Out-Null
            }
        }
    }
    if (Test-NarrowBackendReadOnlyFeature -FeatureClassification $FeatureClassification) {
        foreach ($family in @('stateful_side_effect', 'deploy_export_page', 'config_policy_threshold', 'generated_artifact_template_upload', 'external_integration', 'lifecycle_cleanup_retention')) {
            if (-not $families.Contains($family)) { $families.Add($family) | Out-Null }
        }
    }
    return @($families)
}

function Apply-FeatureClassificationToLedger {
    param($LedgerObject, [string]$ReplayRoot)
    if ($null -eq $LedgerObject -or $null -eq $LedgerObject.families) { return @() }
    $featureClassification = Read-JsonIfExists (Join-Path $ReplayRoot 'FEATURE_CLASSIFICATION.json')
    if ($null -eq $featureClassification) { return @() }
    $nonApplicableFamilies = @(Get-FeatureNonApplicableFamilies -FeatureClassification $featureClassification)
    if ($nonApplicableFamilies.Count -eq 0) { return @() }
    Set-ObjectProperty -Object $LedgerObject -Name 'feature_classification' -Value ([ordered]@{
        classification = [string]$featureClassification.classification
        base_classification = [string]$featureClassification.base_classification
        read_only = [bool]$featureClassification.read_only
        non_applicable_families = @($nonApplicableFamilies)
    })
    $filtered = New-Object System.Collections.Generic.List[string]
    foreach ($family in @($LedgerObject.families)) {
        $id = [string]$family.id
        if ($nonApplicableFamilies -notcontains $id) { continue }
        if ([bool]$family.required -or [string]$family.status -ne 'NOT_APPLICABLE_BY_FEATURE_CLASSIFIER') {
            Set-ObjectProperty -Object $family -Name 'required' -Value $false
            Set-ObjectProperty -Object $family -Name 'status' -Value 'NOT_APPLICABLE_BY_FEATURE_CLASSIFIER'
            Set-ObjectProperty -Object $family -Name 'coverage_cap_if_open' -Value 100
            Set-ObjectProperty -Object $family -Name 'open_sibling_surfaces' -Value @()
            Set-ObjectProperty -Object $family -Name 'open_sibling_count' -Value 0
            Set-ObjectProperty -Object $family -Name 'last_reason' -Value 'Excluded by feature classifier; this feature class is narrow backend read-only and does not require this family unless requirement_source explicitly says otherwise.'
            $filtered.Add($id) | Out-Null
        }
    }
    return @($filtered)
}

function Test-ExplicitRequirementFamilyScope {
    param(
        [string]$FamilyId,
        [string]$RequirementText,
        $ContractFamily,
        [string]$EvidenceText = ''
    )

    $contractRequired = $null -ne $ContractFamily -and $null -ne $ContractFamily.required -and [bool]$ContractFamily.required
    $carrier = if ($null -ne $ContractFamily) { [string]$ContractFamily.first_executable_carrier } else { '' }
    $plannedSlice = if ($null -ne $ContractFamily) { [string]$ContractFamily.planned_slice } else { '' }
    $proof = if ($null -ne $ContractFamily -and $null -ne $ContractFamily.proof_required) { ((Get-StringArray $ContractFamily.proof_required) -join ' ') } else { '' }
    $hasConcreteContract = $contractRequired -and (
        -not [string]::IsNullOrWhiteSpace($carrier) -or
        -not [string]::IsNullOrWhiteSpace($proof) -or
        (-not [string]::IsNullOrWhiteSpace($plannedSlice) -and $plannedSlice -ne 'not_required')
    )
    if ($hasConcreteContract) { return $true }
    $combined = @($RequirementText, $EvidenceText, $carrier, $proof) -join "`n"

    switch ($FamilyId) {
        'deploy_export_page' {
            if ($combined -match '(?i)(导出|报表|报表接口|excel|页面|前端|jsp|javascript|js\b|展示字段|列表接口|查询接口|接口返回|下载|header|column|view|screen|display)') { return $true }
            if ($carrier -match '(?i)(controller|endpoint|export|report|excel|download|\.jsp|\.js|\.ts|\.vue|\.html|\.ftl|\.vm)') { return $true }
            return $false
        }
        'automation_test_interface' {
            return $combined -match '(?i)(自动化测试接口|测试接口|projectList|project_list|raw|original|原始责任项|automation\s+test)'
        }
        'wire_payload_api_contract' {
            return $combined -match '(?i)(payload|request|response|api|接口|请求|响应|报文|字段|json|wire|body)'
        }
        'generated_artifact_template_upload' {
            return $combined -match '(?i)(模板|图片|png|pdf|附件|上传|生成文件|影像|template|image|upload|artifact|attachment)'
        }
        'external_integration' {
            return $combined -match '(?i)(外部|对接|外部接口|第三方|回调|推送|http|client|adapter|external|integration|partner)'
        }
        'lifecycle_cleanup_retention' {
            if ($combined -match '(?i)(清理|删除|移除|过期|保留|留存|expire|cleanup|delete|remove|retention|duplicate|idempotent|same-status|same status|re-entry)') { return $true }
            return $contractRequired -and $combined -match '(?i)(cleanup|retention|expire|expired|delete|remove|preserve|must_not|must-not|do_not|do-not)'
        }
        default {
            return $contractRequired -or -not [string]::IsNullOrWhiteSpace($RequirementText)
        }
    }
}

function Apply-FamilyScopeFilter {
    param(
        $LedgerObject,
        [string]$ReplayRoot
    )

    $featureFilteredFamilies = @(Apply-FeatureClassificationToLedger -LedgerObject $LedgerObject -ReplayRoot $ReplayRoot)
    $run = Read-JsonIfExists (Join-Path $ReplayRoot 'AUTOPILOT_RUN.json')
    $requirementSource = if ($null -ne $run -and $run.PSObject.Properties.Name -contains 'requirement_source') { [string]$run.requirement_source } else { '' }
    $requirementText = Read-TextIfExists -Path $requirementSource
    $familyContract = Read-JsonIfExists (Join-Path $ReplayRoot 'FAMILY_CONTRACT.json')
    $evidenceText = @(
        $requirementSource,
        (Join-Path $ReplayRoot 'FAMILY_CONTRACT.json'),
        (Join-Path $ReplayRoot 'EXPECTED_DIFF_MATRIX.md'),
        (Join-Path $ReplayRoot 'IMPLEMENTATION_CONTRACT.md'),
        (Join-Path $ReplayRoot 'REPLAY_PLAN.md')
    ) | ForEach-Object { Read-TextIfExists $_ }
    $evidenceText = $evidenceText -join "`n"
    if ([string]::IsNullOrWhiteSpace($requirementText) -and $null -eq $familyContract) { return @() }
    $contractFamiliesById = @{}
    if ($null -ne $familyContract -and $null -ne $familyContract.families) {
        foreach ($family in @($familyContract.families)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$family.id)) {
                $contractFamiliesById[[string]$family.id] = $family
            }
        }
    }

    $strictScopeFamilies = @(
        'deploy_export_page',
        'automation_test_interface',
        'wire_payload_api_contract',
        'generated_artifact_template_upload',
        'external_integration',
        'lifecycle_cleanup_retention'
    )
    $filtered = New-Object System.Collections.Generic.List[string]
    foreach ($family in @($LedgerObject.families)) {
        $id = [string]$family.id
        if (-not [bool]$family.required) { continue }
        if ($strictScopeFamilies -notcontains $id) { continue }
        $contractFamily = if ($contractFamiliesById.ContainsKey($id)) { $contractFamiliesById[$id] } else { $null }
        if (-not (Test-ExplicitRequirementFamilyScope -FamilyId $id -RequirementText $requirementText -ContractFamily $contractFamily -EvidenceText $evidenceText)) {
            Set-ObjectProperty -Object $family -Name 'required' -Value $false
            Set-ObjectProperty -Object $family -Name 'status' -Value 'NOT_REQUIRED_BY_SCOPE_FILTER'
            Set-ObjectProperty -Object $family -Name 'coverage_cap_if_open' -Value 100
            Set-ObjectProperty -Object $family -Name 'open_sibling_surfaces' -Value @()
            Set-ObjectProperty -Object $family -Name 'open_sibling_count' -Value 0
            Set-ObjectProperty -Object $family -Name 'last_reason' -Value 'Excluded by requirement-scope filter; no explicit requirement or concrete production carrier supports this family.'
            $filtered.Add($id) | Out-Null
        }
    }
    return @((@($featureFilteredFamilies) + @($filtered)) | Select-Object -Unique)
}

function Get-SliceTypeForFamily {
    param($Family, [int]$Index)
    $last = [string]$Family.last_next_recommended_slice_type
    if ([string]$Family.id -eq 'core_entry' -and $Index -gt 1) { return 'stateful_success_slice' }
    if ([string]$Family.id -eq 'stateful_side_effect') { return 'stateful_success_slice' }
    if (-not [string]::IsNullOrWhiteSpace($last)) { return $last }
    return [string]$Family.recommended_slice_type
}

function Get-SliceTypeForSurface {
    param([string]$Surface)
    if ([string]::IsNullOrWhiteSpace($Surface)) { return '' }
    if ($Surface -match '(?i)(controller|endpoint|route|export|download|workbook|excel|page|view|display|jsp|js|html|submit|query)\b') {
        return 'deploy_surface_first_slice'
    }
    if ($Surface -match '(?i)\b(payload|request|response|wire|json|dto|field|body)\b') {
        return 'exact_contract_slice'
    }
    if ($Surface -match '(?i)\b(callback|webhook|external|integration|client|adapter|provider|partner)\b') {
        return 'deploy_surface_first_slice'
    }
    return ''
}

function Get-FamilyCoverageCap {
    param($LedgerObject, [object[]]$OpenFamilies)

    $cap = 100
    if ($OpenFamilies.Count -gt 0) {
        $cap = [Math]::Min($cap, 89)
    }
    foreach ($family in $OpenFamilies) {
        if ($null -ne $family.coverage_cap_if_open -and "$($family.coverage_cap_if_open)" -match '^\d+$') {
            $cap = [Math]::Min($cap, [int]$family.coverage_cap_if_open)
        }
    }
    if ($null -ne $LedgerObject.coverage_cap -and "$($LedgerObject.coverage_cap)" -match '^\d+$') {
        $cap = [Math]::Min($cap, [int]$LedgerObject.coverage_cap)
    }
    if ($null -ne $LedgerObject.no_progress_slices -and @($LedgerObject.no_progress_slices).Count -gt 0) {
        $cap = [Math]::Min($cap, 10)
    }
    return $cap
}

function Test-LedgerConsistencyWithVerifiedSlices {
    param($LedgerObject, [string]$ReplayRoot)

    $issues = New-Object System.Collections.ArrayList
    $verifiedClosed = New-Object System.Collections.ArrayList
    $verifiedTouched = New-Object System.Collections.ArrayList
    $verifyFiles = @(Get-ChildItem -LiteralPath $ReplayRoot -File -Filter 'SLICE_VERIFY_*.json' -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($verifyFiles.Count -eq 0) {
        return [pscustomobject]@{ valid = $true; issues = @(); verified_closed_families = @(); verified_touched_families = @() }
    }

    $familiesById = @{}
    if ($null -ne $LedgerObject -and $null -ne $LedgerObject.families) {
        foreach ($family in @($LedgerObject.families)) {
            $id = [string]$family.id
            if (-not [string]::IsNullOrWhiteSpace($id)) { $familiesById[$id] = $family }
        }
    }

    foreach ($file in $verifyFiles) {
        $verify = Read-JsonIfExists $file.FullName
        if ($null -eq $verify) { continue }
        $authorized = $null -ne $verify.authorized_for_next_slice -and [bool]$verify.authorized_for_next_slice
        $status = [string]$verify.verification_status
        if (-not $authorized -or @('PASS', 'PARTIAL') -notcontains $status) { continue }

        foreach ($familyId in @(Get-StringArray $verify.touched_requirement_families)) {
            if (-not [string]::IsNullOrWhiteSpace($familyId)) { $verifiedTouched.Add($familyId) | Out-Null }
        }
        foreach ($familyId in @(Get-StringArray $verify.closed_requirement_families)) {
            if ([string]::IsNullOrWhiteSpace($familyId)) { continue }
            $verifiedClosed.Add($familyId) | Out-Null
            if (-not $familiesById.ContainsKey($familyId)) {
                $issues.Add([ordered]@{
                    family = $familyId
                    expected = 'CLOSED'
                    actual = 'MISSING_FROM_LEDGER'
                    source = $file.Name
                }) | Out-Null
                continue
            }
            $ledgerFamily = $familiesById[$familyId]
            $ledgerStatus = [string]$ledgerFamily.status
            if (@('EXECUTABLE_CLOSED', 'CLOSED') -notcontains $ledgerStatus) {
                $issues.Add([ordered]@{
                    family = $familyId
                    expected = 'EXECUTABLE_CLOSED'
                    actual = $ledgerStatus
                    touched_count = $(if ($null -ne $ledgerFamily.touched_count -and "$($ledgerFamily.touched_count)" -match '^\d+$') { [int]$ledgerFamily.touched_count } else { 0 })
                    source = $file.Name
                }) | Out-Null
            }
        }
    }

    return [pscustomobject]@{
        valid = $issues.Count -eq 0
        issues = @($issues.ToArray())
        verified_closed_families = @($verifiedClosed | Select-Object -Unique)
        verified_touched_families = @($verifiedTouched | Select-Object -Unique)
    }
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
if ([string]::IsNullOrWhiteSpace($Ledger)) {
    $Ledger = Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json'
}
$ledgerFull = Resolve-AbsolutePath $Ledger
if (-not (Test-Path -LiteralPath $ledgerFull)) {
    throw "Ledger not found: $ledgerFull"
}

$ledgerObject = Read-JsonObject -Path $ledgerFull
$scopeFilteredFamilies = @(Apply-FamilyScopeFilter -LedgerObject $ledgerObject -ReplayRoot $replayRootFull)
if ($scopeFilteredFamilies.Count -gt 0) {
    Write-JsonObject -Path $ledgerFull -Value $ledgerObject
}
if ($SliceIndex -le 0) {
    $progressPath = Join-Path $replayRootFull 'SLICE_PROGRESS.json'
    $completedCount = 0
    if (Test-Path -LiteralPath $progressPath) {
        try {
            $progress = Read-JsonObject -Path $progressPath
            $completedCount = @($progress.completed).Count
        } catch {
            $completedCount = 0
        }
    }
    $SliceIndex = $completedCount + 1
}

$consistency = Test-LedgerConsistencyWithVerifiedSlices -LedgerObject $ledgerObject -ReplayRoot $replayRootFull
if (-not [bool]$consistency.valid) {
    $errorPath = Join-Path $replayRootFull 'LEDGER_CONSISTENCY_ERROR.json'
    $errorResult = [ordered]@{
        status = 'METADATA_INCONSISTENCY'
        validation_status = 'FAIL'
        replay_root = $replayRootFull
        ledger = $ledgerFull
        slice_index = $SliceIndex
        verified_closed_families = @($consistency.verified_closed_families)
        verified_touched_families = @($consistency.verified_touched_families)
        inconsistencies = @($consistency.issues)
        diagnosis = 'SLICE_VERIFY marked families as closed but REQUIREMENT_FAMILY_LEDGER still shows them open or partial.'
        gate = 'family_ledger_consistency'
    }
    Write-JsonObject -Path $errorPath -Value $errorResult
    $routerError = [ordered]@{
        status = 'METADATA_INCONSISTENCY'
        validation_status = 'FAIL'
        replay_root = $replayRootFull
        ledger = $ledgerFull
        slice_index = $SliceIndex
        selected_family = ''
        selected_slice_type = ''
        target_sibling_surface = ''
        reason = 'family ledger is stale relative to authorized SLICE_VERIFY output'
        coverage_cap_from_ledger = 0
        final_pass_allowed = $false
        open_required_family_count = 0
        open_families = @()
        closed_families = @()
        scope_filtered_families = @($scopeFilteredFamilies)
        validation_issues = @('ledger_stale_after_slice_verify')
        consistency_error = $errorPath
        gate = 'highest_weight_family_router_and_ledger_cap'
    }
    Write-JsonObject -Path (Join-Path $replayRootFull 'FAMILY_ROUTER_AND_CAP.json') -Value $routerError
    $routerError | ConvertTo-Json -Depth 12
    exit 1
}

$openFamilies = @($ledgerObject.families | Where-Object {
    [bool]$_.required -and @('OPEN', 'PARTIAL') -contains ([string]$_.status)
} | Sort-Object @{Expression = 'weight'; Descending = $true}, @{Expression = 'touched_count'; Ascending = $true})

$closedFamilies = @($ledgerObject.families | Where-Object {
    [bool]$_.required -and @('EXECUTABLE_CLOSED', 'CLOSED') -contains ([string]$_.status)
})

$selected = if ($openFamilies.Count -gt 0) { $openFamilies | Select-Object -First 1 } else { $null }
$selectedFamily = if ($null -ne $selected) { [string]$selected.id } else { '' }
$selectedSliceType = if ($null -ne $selected) { Get-SliceTypeForFamily -Family $selected -Index $SliceIndex } else { '' }
$targetSibling = if ($null -ne $selected) {
    $sibling = @(@(Get-StringArray $selected.open_sibling_surfaces) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Sort-Object @{ Expression = { Get-CarrierSurfacePriority ([string]$_) }; Descending = $true }, @{ Expression = { [string]$_ }; Ascending = $true } |
        Select-Object -First 1)
    if ($sibling.Count -gt 0) { Normalize-SiblingSurface -Surface ([string]$sibling[0]) } elseif (-not [string]::IsNullOrWhiteSpace([string]$selected.first_executable_carrier)) { Normalize-SiblingSurface -Surface ([string]$selected.first_executable_carrier) } else { '' }
} else { '' }
$surfaceSliceType = Get-SliceTypeForSurface -Surface $targetSibling
if (-not [string]::IsNullOrWhiteSpace($surfaceSliceType)) {
    $selectedSliceType = $surfaceSliceType
}
$coverageCap = Get-FamilyCoverageCap -LedgerObject $ledgerObject -OpenFamilies $openFamilies

$issues = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($AssertExpectedFamily) -and $selectedFamily -ne $AssertExpectedFamily) {
    $issues.Add("selected_family_mismatch:$AssertExpectedFamily") | Out-Null
}
$closedIds = @($closedFamilies | ForEach-Object { [string]$_.id })
if ($selectedFamily -ne '' -and $closedIds -contains $selectedFamily) {
    $issues.Add('closed_family_selected') | Out-Null
}
if ($openFamilies.Count -gt 0 -and $coverageCap -ge 90) {
    $issues.Add('coverage_cap_allows_pass_with_open_required_family') | Out-Null
}

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$routerStatus = if ($issues.Count -eq 0) { 'ALLOW' } else { 'BLOCKED_PLAN_MISMATCH' }

$result = [ordered]@{
    status = $routerStatus
    validation_status = $status
    replay_root = $replayRootFull
    ledger = $ledgerFull
    slice_index = $SliceIndex
    selected_family = $selectedFamily
    selected_slice_type = $selectedSliceType
    target_sibling_surface = [string]$targetSibling
    reason = $(if ($selectedFamily -ne '') { 'highest-weight OPEN/PARTIAL required family selected; closed families are excluded.' } else { 'no OPEN/PARTIAL required family remains.' })
    coverage_cap_from_ledger = $coverageCap
    final_pass_allowed = $openFamilies.Count -eq 0 -and $coverageCap -ge 90
    open_required_family_count = $openFamilies.Count
    open_families = @($openFamilies | ForEach-Object {
        [ordered]@{
            id = [string]$_.id
            status = [string]$_.status
            weight = $(if ($null -ne $_.weight) { [int]$_.weight } else { 0 })
            touched_count = $(if ($null -ne $_.touched_count) { [int]$_.touched_count } else { 0 })
            coverage_cap_if_open = $(if ($null -ne $_.coverage_cap_if_open) { [int]$_.coverage_cap_if_open } else { $null })
        }
    })
    closed_families = @($closedIds)
    scope_filtered_families = @($scopeFilteredFamilies)
    validation_issues = @($issues)
    gate = 'highest_weight_family_router_and_ledger_cap'
}

Write-JsonObject -Path (Join-Path $replayRootFull 'FAMILY_ROUTER_AND_CAP.json') -Value $result
$result | ConvertTo-Json -Depth 12

if ($status -ne 'PASS') { exit 1 }
