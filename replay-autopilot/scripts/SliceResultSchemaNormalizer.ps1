function Get-SliceResultStringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-SliceResultPropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-SliceResultStringValue {
    param($Object, [string]$Name)
    $value = Get-SliceResultPropertyValue -Object $Object -Name $Name
    if ($null -eq $value) { return '' }
    return [string]$value
}

function Set-SliceResultProperty {
    param($Object, [string]$Name, $Value)
    if ($null -eq $Object) { return }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function ConvertTo-CanonicalSliceStatus {
    param([string]$Value)
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $upper = $text.ToUpperInvariant()
    switch -Regex ($upper) {
        '^(DONE|COMPLETE|COMPLETED|SUCCESS|SUCCEEDED|PASS|PASSED)$' { return 'DONE' }
        '^(PARTIAL|PARTIALLY_DONE|PARTIALLY_COMPLETED)$' { return 'PARTIAL' }
        '^(BLOCKED|FAILED_BLOCKED)$' { return 'BLOCKED' }
        '^(INVALID|INVALID_REPLAY)$' { return 'INVALID_REPLAY' }
        default { return $upper }
    }
}

function Add-SliceResultGapFlag {
    param($Slice, [string]$Flag)
    if ($null -eq $Slice -or [string]::IsNullOrWhiteSpace($Flag)) { return }
    $flags = @(Get-SliceResultStringArray (Get-SliceResultPropertyValue -Object $Slice -Name 'gap_flags'))
    if ($flags -notcontains $Flag) {
        $flags = @($flags + $Flag)
        Set-SliceResultProperty -Object $Slice -Name 'gap_flags' -Value @($flags | Select-Object -Unique)
    }
}

function Get-SliceResultIntValueOrNull {
    param($Object, [string]$Name)
    $value = Get-SliceResultPropertyValue -Object $Object -Name $Name
    if ($null -eq $value) { return $null }
    $text = ([string]$value).Trim()
    if ($text -match '^-?\d+$') { return [int]$text }
    return $null
}

function ConvertTo-SyntheticTestResult {
    param($TestResultObject, [string]$FlatResult)
    $result = ([string]$FlatResult).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($result)) { $result = 'pass' }
    if ($result -match '^(passed|success|succeeded|completed|done)$') { $result = 'pass' }
    if ($result -match '^(failed|failure|error|errored)$') { $result = 'fail' }

    if ($null -ne $TestResultObject) {
        $failures = Get-SliceResultIntValueOrNull -Object $TestResultObject -Name 'failures'
        $errors = Get-SliceResultIntValueOrNull -Object $TestResultObject -Name 'errors'
        if (($null -ne $failures -and $failures -gt 0) -or ($null -ne $errors -and $errors -gt 0)) {
            return 'fail'
        }
        $testsRun = Get-SliceResultIntValueOrNull -Object $TestResultObject -Name 'tests_run'
        if ($null -ne $testsRun -and $testsRun -gt 0) {
            return 'pass'
        }
    }

    return $result
}

function Invoke-SliceResultSchemaNormalization {
    param($Slice)

    $normalizedFields = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $originalStatus = Get-SliceResultStringValue -Object $Slice -Name 'slice_status'
    $rawStatus = $originalStatus
    $statusSource = 'slice_status'

    if ([string]::IsNullOrWhiteSpace($rawStatus)) {
        foreach ($candidate in @('status', 'execution_status', 'completion_status')) {
            $candidateValue = Get-SliceResultStringValue -Object $Slice -Name $candidate
            if (-not [string]::IsNullOrWhiteSpace($candidateValue)) {
                $rawStatus = $candidateValue
                $statusSource = $candidate
                break
            }
        }
    }

    $canonicalStatus = ConvertTo-CanonicalSliceStatus -Value $rawStatus
    if (-not [string]::IsNullOrWhiteSpace($canonicalStatus) -and $canonicalStatus -ne $originalStatus) {
        if (-not [string]::IsNullOrWhiteSpace($rawStatus)) {
            Set-SliceResultProperty -Object $Slice -Name 'agent_original_slice_status' -Value $rawStatus
            Set-SliceResultProperty -Object $Slice -Name 'agent_original_slice_status_source' -Value $statusSource
        }
        Set-SliceResultProperty -Object $Slice -Name 'slice_status' -Value $canonicalStatus
        $normalizedFields.Add("slice_status:$statusSource") | Out-Null
    }

    $tests = @()
    $existingTests = Get-SliceResultPropertyValue -Object $Slice -Name 'tests'
    if ($null -ne $existingTests) {
        if ($existingTests -is [System.Array]) { $tests = @($existingTests) } else { $tests = @($existingTests) }
    }

    if ($tests.Count -eq 0) {
        $flatResult = Get-SliceResultStringValue -Object $Slice -Name 'test_result'
        $flatResults = Get-SliceResultPropertyValue -Object $Slice -Name 'test_results'
        $command = Get-SliceResultStringValue -Object $Slice -Name 'test_execution_command'
        if ([string]::IsNullOrWhiteSpace($command)) { $command = Get-SliceResultStringValue -Object $Slice -Name 'maven_command' }
        if ([string]::IsNullOrWhiteSpace($command)) { $command = Get-SliceResultStringValue -Object $Slice -Name 'test_command' }

        if (-not [string]::IsNullOrWhiteSpace($flatResult) -or $null -ne $flatResults) {
            $synthetic = [ordered]@{
                phase = 'GREEN'
                result = ConvertTo-SyntheticTestResult -TestResultObject $flatResults -FlatResult $flatResult
            }
            if (-not [string]::IsNullOrWhiteSpace($command)) {
                $synthetic.command = $command
            }
            if ($null -ne $flatResults) {
                foreach ($name in @('tests_run', 'failures', 'errors', 'skipped')) {
                    $value = Get-SliceResultPropertyValue -Object $flatResults -Name $name
                    if ($null -ne $value) { $synthetic[$name] = $value }
                }
            }
            Set-SliceResultProperty -Object $Slice -Name 'tests' -Value @([pscustomobject]$synthetic)
            $normalizedFields.Add('tests:test_result') | Out-Null
        }
    }

    if ($normalizedFields.Count -gt 0) {
        Add-SliceResultGapFlag -Slice $Slice -Flag 'agent_result_schema_normalized'
        Set-SliceResultProperty -Object $Slice -Name 'schema_normalization' -Value ([ordered]@{
            schema = 'slice_result_schema_normalization.v1'
            normalized = $true
            normalized_fields = @($normalizedFields)
            original_status = $rawStatus
            canonical_status = $canonicalStatus
        })
    }

    return [pscustomobject]@{
        normalized = ($normalizedFields.Count -gt 0)
        normalized_fields = @($normalizedFields)
        warnings = @($warnings)
        original_status = $rawStatus
        canonical_status = $canonicalStatus
    }
}
