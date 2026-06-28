param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$PlanResultPath = '',
    [string]$FirstSliceProofPath = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Get-ObjectPropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-ObjectPropertyString {
    param($Object, [string]$Name)
    $value = Get-ObjectPropertyValue -Object $Object -Name $Name
    if ($null -eq $value) { return '' }
    return ([string]$value).Trim()
}

function Set-ObjectPropertyValue {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.PSObject.Properties[$Name].Value = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-ArrayItems {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @($Value)
    }
    return @($Value)
}

function Test-NonEmptyArrayValue {
    param($Value)
    $items = @(Get-ArrayItems -Value $Value)
    if ($items.Count -eq 0) { return $false }
    foreach ($item in $items) {
        if ($null -eq $item) { continue }
        if ($item -is [string] -and [string]::IsNullOrWhiteSpace($item)) { continue }
        return $true
    }
    return $false
}

function ConvertTo-JsonArrayText {
    param($Value)
    $items = [object[]]@(Get-ArrayItems -Value $Value)
    return (ConvertTo-Json -InputObject $items -Compress -Depth 16)
}

function Test-SideEffectItemSchemaShape {
    param($Item)
    if ($null -eq $Item) { return $false }
    if ($Item -is [string]) {
        return -not [string]::IsNullOrWhiteSpace($Item)
    }

    $effect = Get-ObjectPropertyString -Object $Item -Name 'side_effect'
    $state = Get-ObjectPropertyString -Object $Item -Name 'state'
    $proof = Get-ObjectPropertyString -Object $Item -Name 'proof'
    if (-not [string]::IsNullOrWhiteSpace($effect) -and
        -not [string]::IsNullOrWhiteSpace($state) -and
        -not [string]::IsNullOrWhiteSpace($proof)) {
        return $true
    }

    $description = Get-ObjectPropertyString -Object $Item -Name 'description'
    $type = Get-ObjectPropertyString -Object $Item -Name 'type'
    if (-not [string]::IsNullOrWhiteSpace($description) -and -not [string]::IsNullOrWhiteSpace($type)) {
        return $true
    }

    $operation = Get-ObjectPropertyString -Object $Item -Name 'operation'
    $memory = Get-ObjectPropertyString -Object $Item -Name 'memory'
    $target = Get-ObjectPropertyString -Object $Item -Name 'target'
    $value = Get-ObjectPropertyString -Object $Item -Name 'value'
    $source = Get-ObjectPropertyString -Object $Item -Name 'source'
    return (
        -not [string]::IsNullOrWhiteSpace($operation) -and
        (-not [string]::IsNullOrWhiteSpace($memory) -or -not [string]::IsNullOrWhiteSpace($target)) -and
        (-not [string]::IsNullOrWhiteSpace($value) -or -not [string]::IsNullOrWhiteSpace($source))
    )
}

function Test-SideEffectsSchemaShape {
    param($Value)
    $items = @(Get-ArrayItems -Value $Value)
    if ($items.Count -eq 0) { return $false }
    foreach ($item in $items) {
        if (-not (Test-SideEffectItemSchemaShape -Item $item)) {
            return $false
        }
    }
    return $true
}

function ConvertTo-SchemaSideEffectItems {
    param($Value)
    $normalized = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-ArrayItems -Value $Value)) {
        if ($null -eq $item) { continue }
        if ($item -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $normalized.Add([string]$item) | Out-Null
            }
            continue
        }

        $effect = Get-ObjectPropertyString -Object $item -Name 'side_effect'
        $state = Get-ObjectPropertyString -Object $item -Name 'state'
        $proof = Get-ObjectPropertyString -Object $item -Name 'proof'
        $description = Get-ObjectPropertyString -Object $item -Name 'description'
        $type = Get-ObjectPropertyString -Object $item -Name 'type'
        $table = Get-ObjectPropertyString -Object $item -Name 'table'
        $field = Get-ObjectPropertyString -Object $item -Name 'field'
        $operation = Get-ObjectPropertyString -Object $item -Name 'operation'
        $value = Get-ObjectPropertyString -Object $item -Name 'value'
        $memory = Get-ObjectPropertyString -Object $item -Name 'memory'
        $target = Get-ObjectPropertyString -Object $item -Name 'target'
        $source = Get-ObjectPropertyString -Object $item -Name 'source'

        if ([string]::IsNullOrWhiteSpace($state)) {
            if (-not [string]::IsNullOrWhiteSpace($table) -and -not [string]::IsNullOrWhiteSpace($field)) {
                $state = "$table.$field"
            } elseif (-not [string]::IsNullOrWhiteSpace($table)) {
                $state = $table
            } elseif (-not [string]::IsNullOrWhiteSpace($memory)) {
                $state = $memory
            } elseif (-not [string]::IsNullOrWhiteSpace($target)) {
                $state = $target
            } elseif (-not [string]::IsNullOrWhiteSpace($description)) {
                $state = $description
            } else {
                $state = 'planned_state_change'
            }
        }

        if ([string]::IsNullOrWhiteSpace($effect)) {
            if (-not [string]::IsNullOrWhiteSpace($description)) {
                $effect = $description
            } elseif (-not [string]::IsNullOrWhiteSpace($operation)) {
                $effect = "$operation $state".Trim()
            } elseif (-not [string]::IsNullOrWhiteSpace($type)) {
                $effect = "$type $state".Trim()
            } else {
                $effect = "verify $state"
            }
        }

        if ([string]::IsNullOrWhiteSpace($proof)) {
            if (-not [string]::IsNullOrWhiteSpace($source)) {
                $proof = "source: $source"
            } elseif (-not [string]::IsNullOrWhiteSpace($value)) {
                $proof = "assert value $value"
            } else {
                $proof = 'planned executable assertion'
            }
        }

        $shape = [ordered]@{
            side_effect = $effect
            state = $state
            proof = $proof
        }
        foreach ($name in @('table', 'field', 'operation', 'value', 'memory', 'target', 'source', 'type', 'description')) {
            $propertyValue = Get-ObjectPropertyValue -Object $item -Name $name
            if ($null -ne $propertyValue -and -not [string]::IsNullOrWhiteSpace([string]$propertyValue)) {
                $shape[$name] = $propertyValue
            }
        }
        $normalized.Add([pscustomobject]$shape) | Out-Null
    }
    return @($normalized.ToArray())
}

function Set-MachineFieldLine {
    param([string]$Text, [string]$Field, [string]$Value)

    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        $lines = @($Text -split "\r?\n", -1)
    }

    $output = New-Object System.Collections.Generic.List[string]
    $fieldPattern = '^\s*(?:[-*]\s*)?(?:\*{0,2})' + [regex]::Escape($Field) + '(?:\*{0,2})\s*[:=]'
    $found = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if ($line -match $fieldPattern) {
            $output.Add("${Field}: $Value") | Out-Null
            $found = $true

            $j = $i + 1
            while ($j -lt $lines.Count) {
                $next = [string]$lines[$j]
                if ([string]::IsNullOrWhiteSpace($next)) { break }
                if ($next -match '^\s{2,}\S' -or $next -match '^\s*[-*]\s+') {
                    $j++
                    continue
                }
                break
            }
            $i = $j - 1
            continue
        }
        $output.Add($line) | Out-Null
    }

    if (-not $found) {
        if ($output.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
            $output.Add('') | Out-Null
        }
        $output.Add("${Field}: $Value") | Out-Null
    }

    return ($output.ToArray() -join "`r`n").TrimEnd() + "`r`n"
}

$replayRootFull = Resolve-FullPath $ReplayRoot
if ([string]::IsNullOrWhiteSpace($PlanResultPath)) {
    $PlanResultPath = Join-Path $replayRootFull 'PLAN_RESULT.json'
}
if ([string]::IsNullOrWhiteSpace($FirstSliceProofPath)) {
    $FirstSliceProofPath = Join-Path $replayRootFull 'FIRST_SLICE_PROOF_PLAN.md'
}
$planResultFull = Resolve-FullPath $PlanResultPath
$firstSliceProofFull = Resolve-FullPath $FirstSliceProofPath
$resultPath = Join-Path $replayRootFull 'PLAN_MACHINE_CONTRACT_NORMALIZATION.json'

$changes = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $planResultFull -PathType Leaf)) {
    [ordered]@{
        schema = 'plan_machine_contract_normalization.v1'
        status = 'SKIPPED'
        reason = 'PLAN_RESULT.json_missing'
        replay_root = $replayRootFull
        generated_at = (Get-Date -Format 'o')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 0
}

try {
    $plan = Get-Content -LiteralPath $planResultFull -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    [ordered]@{
        schema = 'plan_machine_contract_normalization.v1'
        status = 'FAILED'
        reason = 'PLAN_RESULT.json_parse_failed'
        error = [string]$_.Exception.Message
        replay_root = $replayRootFull
        generated_at = (Get-Date -Format 'o')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 2
}

$planStatus = (Get-ObjectPropertyString -Object $plan -Name 'plan_status').ToUpperInvariant()
if ($planStatus -eq 'PROCEED') {
    $sideEffects = Get-ObjectPropertyValue -Object $plan -Name 'side_effects'
    $expectedSideEffects = Get-ObjectPropertyValue -Object $plan -Name 'expected_side_effects'
    if (-not (Test-NonEmptyArrayValue -Value $expectedSideEffects) -and (Test-NonEmptyArrayValue -Value $sideEffects)) {
        Set-ObjectPropertyValue -Object $plan -Name 'expected_side_effects' -Value ([object[]]@(Get-ArrayItems -Value $sideEffects))
        $changes.Add('PLAN_RESULT.json.expected_side_effects_from_side_effects') | Out-Null
        $expectedSideEffects = Get-ObjectPropertyValue -Object $plan -Name 'expected_side_effects'
    }

    if ((-not (Test-NonEmptyArrayValue -Value $sideEffects) -or -not (Test-SideEffectsSchemaShape -Value $sideEffects)) -and
        (Test-NonEmptyArrayValue -Value $expectedSideEffects)) {
        $normalizedSideEffects = [object[]]@(ConvertTo-SchemaSideEffectItems -Value $expectedSideEffects)
        if ($normalizedSideEffects.Count -gt 0) {
            Set-ObjectPropertyValue -Object $plan -Name 'side_effects' -Value $normalizedSideEffects
            $changes.Add('PLAN_RESULT.json.side_effects_from_expected_side_effects') | Out-Null
            $sideEffects = Get-ObjectPropertyValue -Object $plan -Name 'side_effects'
        }
    }

    $expectedAssertions = Get-ObjectPropertyValue -Object $plan -Name 'expected_assertions'
    if ((Test-Path -LiteralPath $firstSliceProofFull -PathType Leaf) -and (Test-NonEmptyArrayValue -Value $expectedAssertions)) {
        $proofText = Read-TextIfExists $firstSliceProofFull
        $newProofText = Set-MachineFieldLine -Text $proofText -Field 'expected_assertions' -Value (ConvertTo-JsonArrayText -Value $expectedAssertions)

        $proofSideEffects = Get-ObjectPropertyValue -Object $plan -Name 'expected_side_effects'
        if (-not (Test-NonEmptyArrayValue -Value $proofSideEffects)) {
            $proofSideEffects = Get-ObjectPropertyValue -Object $plan -Name 'side_effects'
        }
        if (Test-NonEmptyArrayValue -Value $proofSideEffects) {
            $newProofText = Set-MachineFieldLine -Text $newProofText -Field 'expected_side_effects' -Value (ConvertTo-JsonArrayText -Value $proofSideEffects)
        } else {
            $warnings.Add('FIRST_SLICE_PROOF_PLAN.expected_side_effects_not_synced:no_source_array') | Out-Null
        }

        if ($newProofText -ne $proofText) {
            Set-Content -LiteralPath $firstSliceProofFull -Value $newProofText -Encoding UTF8
            $changes.Add('FIRST_SLICE_PROOF_PLAN.md.v457_json_fields_synced') | Out-Null
        }
    }
}

if ($changes.Count -gt 0) {
    $plan | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $planResultFull -Encoding UTF8
}

[ordered]@{
    schema = 'plan_machine_contract_normalization.v1'
    status = if ($changes.Count -gt 0) { 'NORMALIZED' } else { 'UNCHANGED' }
    replay_root = $replayRootFull
    plan_result = $planResultFull
    first_slice_proof_plan = $firstSliceProofFull
    changes = @($changes.ToArray())
    warnings = @($warnings.ToArray())
    generated_at = (Get-Date -Format 'o')
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

exit 0
