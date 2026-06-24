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

    # v630: Normalize red_phase/green_phase format → tests[] array.
    # Some agents emit red_phase and green_phase objects at the top level
    # instead of a structured tests[] array. Without this normalization,
    # Invoke-EvidenceCaptureRepair cannot extract test commands and the
    # executable evidence gate blocks even when test evidence exists.
    if ($tests.Count -eq 0) {
        $redPhase = Get-SliceResultPropertyValue -Object $Slice -Name 'red_phase'
        $greenPhase = Get-SliceResultPropertyValue -Object $Slice -Name 'green_phase'
        $command = Get-SliceResultStringValue -Object $Slice -Name 'test_execution_command'
        if ([string]::IsNullOrWhiteSpace($command)) { $command = Get-SliceResultStringValue -Object $Slice -Name 'test_command' }

        if ($null -ne $redPhase -or $null -ne $greenPhase) {
            $testEntries = New-Object System.Collections.Generic.List[object]
            if ($null -ne $redPhase) {
                $redResult = ConvertTo-SyntheticTestResult -TestResultObject $redPhase -FlatResult ([string]$redPhase.result)
                # RED phase must report fail — if ConvertTo-SyntheticTestResult
                # returned the raw text (e.g. "Tests run: 1, Failures: 1"),
                # normalize it rather than letting a success-shaped string pass.
                if ($redResult -ne 'fail') {
                    $redText = ([string]$redPhase.result).ToLowerInvariant()
                    if ($redText -match '\b(fail(?:ure|ed)?|error)\b' -or $redText -match 'failures:\s*[1-9]' -or $redText -match 'errors:\s*[1-9]') {
                        $redResult = 'fail'
                    } else {
                        $redResult = 'fail'  # RED must always be fail
                    }
                }
                $entry = [ordered]@{
                    phase = 'RED'
                    result = $redResult
                    evidence = (Get-SliceResultStringValue -Object $redPhase -Name 'assertion')
                }
                $testName = (Get-SliceResultStringValue -Object $redPhase -Name 'test')
                if (-not [string]::IsNullOrWhiteSpace($testName)) {
                    $entry.test = $testName
                }
                if (-not [string]::IsNullOrWhiteSpace($command)) {
                    $entry.command = $command
                }
                $testEntries.Add([pscustomobject]$entry) | Out-Null
            }
            if ($null -ne $greenPhase) {
                $greenResult = ConvertTo-SyntheticTestResult -TestResultObject $greenPhase -FlatResult ([string]$greenPhase.result)
                if ($greenResult -ne 'pass' -and $greenResult -ne 'fail') {
                    $greenText = ([string]$greenPhase.result).ToLowerInvariant()
                    if ($greenText -match '\bfail(?:ure|ed)?\b' -or $greenText -match 'failures:\s*[1-9]' -or $greenText -match 'errors:\s*[1-9]') {
                        $greenResult = 'fail'
                    } else {
                        $greenResult = 'pass'
                    }
                }
                $entry = [ordered]@{
                    phase = 'GREEN'
                    result = $greenResult
                }
                $testName = (Get-SliceResultStringValue -Object $greenPhase -Name 'test')
                if (-not [string]::IsNullOrWhiteSpace($testName)) {
                    $entry.test = $testName
                }
                if (-not [string]::IsNullOrWhiteSpace($command)) {
                    $entry.command = $command
                }
                $testEntries.Add([pscustomobject]$entry) | Out-Null
            }
            if ($testEntries.Count -gt 0) {
                $testsArray = @()
                foreach ($entry in $testEntries) { $testsArray += [pscustomobject]$entry }
                Set-SliceResultProperty -Object $Slice -Name 'tests' -Value $testsArray
                $normalizedFields.Add('tests:red_phase_green_phase') | Out-Null
                $tests = $testsArray
            }
        }
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

    # v632: Normalize proofs format -> tests[] array.
    # Some agents emit free-text proofs (nested object) at the top level
    # instead of a structured tests[] array. This is common for tracer-bullet
    # slices where the executor provides natural-language proof summaries.
    if ($tests.Count -eq 0) {
        $proofs = Get-SliceResultPropertyValue -Object $Slice -Name 'proofs'
        $isProofsObject = ($null -ne $proofs -and $proofs -is [System.Management.Automation.PSCustomObject])
        if ($null -ne $proofs -and ($isProofsObject -or $proofs -is [System.Collections.IDictionary] -or $proofs -is [System.Collections.Hashtable])) {
            $testEntries = New-Object System.Collections.Generic.List[object]
            $proofKeys = @($proofs.PSObject.Properties.Name)

            foreach ($key in $proofKeys) {
                $rawValue = [string]$proofs.$key
                if ([string]::IsNullOrWhiteSpace($rawValue)) { continue }
                $upperKey = $key.ToUpperInvariant()

                $phase = ''
                $result = 'pass'
                if ($upperKey -match '^RED_') {
                    $phase = 'RED'
                    $result = 'fail'
                } elseif ($upperKey -match '^GREEN_') {
                    $phase = 'GREEN'
                    $result = 'pass'
                } else {
                    continue
                }

                $evidence = $rawValue
                if ($rawValue -match '(?i)PASS\s*(?:\u2014|-|:)\s*(.+)') {
                    $evidence = $matches[1].Trim()
                }
                if ($rawValue -match '(?i)FAIL\s*(?:\u2014|-|:)\s*(.+)') {
                    $evidence = $matches[1].Trim()
                }

                $entry = [ordered]@{
                    phase = $phase
                    result = $result
                    evidence = $evidence
                }

                # Extract maven command from evidence text if present
                if ($rawValue -match '(?i)(mvn(?:\.cmd)?\s+--?[^\n]*?(?:test|install|package|compile|verify)\b[^\n]*)') {
                    $entry.command = $matches[1].Trim()
                }

                $testEntries.Add([pscustomobject]$entry) | Out-Null
            }

            if ($testEntries.Count -gt 0) {
                $testsArray = @()
                foreach ($entry in $testEntries) { $testsArray += [pscustomobject]$entry }
                Set-SliceResultProperty -Object $Slice -Name 'tests' -Value $testsArray
                $normalizedFields.Add('tests:proofs') | Out-Null
            }
        }
    }

    # === Post-processing: red_result/green_result flat strings ===
    # Some agents emit red_result and green_result as flat free-text strings
    # rather than structured red_phase/green_phase objects. These must be
    # injected into the tests[] array as RED/GREEN entries regardless of
    # whether an earlier pass (test_result->GREEN) already populated tests[].
    # Use $Slice.tests direct access to avoid PSObject.Properties indexer
    # edge case with single-element arrays.
    $existingTests = @()
    if ($null -ne $Slice -and $null -ne $Slice.tests) {
        $rawValue = $Slice.tests
        if ($rawValue -is [System.Collections.IList]) {
            $existingTests = @($rawValue)
        } elseif ($rawValue -is [System.Management.Automation.PSCustomObject]) {
            $existingTests = @($rawValue)
        }
    }
    $hasRedPhaseInTests = $false
    $hasGreenPhaseInTests = $false
    foreach ($entry in $existingTests) {
        $phase = if ($null -ne $entry.phase) { [string]$entry.phase } else { '' }
        if ($phase.ToUpperInvariant() -eq 'RED') { $hasRedPhaseInTests = $true }
        if ($phase.ToUpperInvariant() -eq 'GREEN') { $hasGreenPhaseInTests = $true }
    }
    $currentTests = @($existingTests)

    $redResultValue = Get-SliceResultStringValue -Object $Slice -Name 'red_result'
    $greenResultValue = Get-SliceResultStringValue -Object $Slice -Name 'green_result'
    $command = Get-SliceResultStringValue -Object $Slice -Name 'test_execution_command'
    if ([string]::IsNullOrWhiteSpace($command)) { $command = Get-SliceResultStringValue -Object $Slice -Name 'test_command' }

    $testsAppended = $false
    if (-not $hasRedPhaseInTests -and -not [string]::IsNullOrWhiteSpace($redResultValue)) {
        $entry = [ordered]@{
            phase = 'RED'
            result = 'fail'
            evidence = $redResultValue
        }
        if (-not [string]::IsNullOrWhiteSpace($command)) {
            $entry.command = $command
        }
        $currentTests += [pscustomobject]$entry
        $normalizedFields.Add('tests:red_result_flat_string') | Out-Null
        $testsAppended = $true
    }

    if (-not $hasGreenPhaseInTests -and -not [string]::IsNullOrWhiteSpace($greenResultValue)) {
        $entry = [ordered]@{
            phase = 'GREEN'
            result = 'pass'
            evidence = $greenResultValue
        }
        if (-not [string]::IsNullOrWhiteSpace($command)) {
            $entry.command = $command
        }
        $currentTests += [pscustomobject]$entry
        $normalizedFields.Add('tests:green_result_flat_string') | Out-Null
        $testsAppended = $true
    }

    if ($testsAppended) {
        Set-SliceResultProperty -Object $Slice -Name 'tests' -Value @($currentTests)
    }

    # === Map build_status to test_compilation_exit_code ===
    # Some agents emit build_status ("SUCCESS"/"FAILURE") instead of
    # test_compilation_exit_code. Normalize this so the executable
    # evidence gate can evaluate compilation evidence.
    $buildStatus = Get-SliceResultStringValue -Object $Slice -Name 'build_status'
    $existingCompileExit = Get-SliceResultIntValueOrNull -Object $Slice -Name 'test_compilation_exit_code'
    $hasCompileExitCode = ($null -ne $existingCompileExit)
    if (-not $hasCompileExitCode -and -not [string]::IsNullOrWhiteSpace($buildStatus)) {
        $upperBuild = $buildStatus.ToUpperInvariant()
        $mappedExitCode = $null
        if ($upperBuild -match '^(SUCCESS|SUCCEEDED|PASSED|PASS|COMPLETED|DONE)$') {
            $mappedExitCode = 0
        } elseif ($upperBuild -match '^(FAIL(?:URE|ED)?|ERROR|BUILD_FAILURE)$') {
            $mappedExitCode = 1
        }
        if ($null -ne $mappedExitCode) {
            Set-SliceResultProperty -Object $Slice -Name 'test_compilation_exit_code' -Value $mappedExitCode
            Set-SliceResultProperty -Object $Slice -Name 'test_compilation_evidence' -Value ($mappedExitCode -eq 0)
            Set-SliceResultProperty -Object $Slice -Name 'test_compilation_evidence_source' -Value 'build_status'
            $normalizedFields.Add('test_compilation_exit_code:build_status') | Out-Null
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
