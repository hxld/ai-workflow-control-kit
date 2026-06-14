param(
    [Parameter(Mandatory=$true)][string]$ReplayRoot,
    [string]$RequirementSource = '',
    [string]$Mode = 'DryRun'
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Read-JsonIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Read-TextIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

$root = Resolve-AbsolutePath $ReplayRoot
if ([string]::IsNullOrWhiteSpace($RequirementSource)) {
    $run = Read-JsonIfExists (Join-Path $root 'AUTOPILOT_RUN.json')
    if ($null -ne $run) { $RequirementSource = [string]$run.requirement_source }
}
$requirementText = if (-not [string]::IsNullOrWhiteSpace($RequirementSource)) { Read-TextIfExists $RequirementSource } else { '' }

$issues = New-Object System.Collections.ArrayList

$behaviorKeywordPatterns = @(
    '(?i)\bMQ\b',
    '(?i)\bpush\b',
    '(?i)\bnotify\b',
    '(?i)\bsend\b',
    '(?i)\bcallback\b',
    '消息推送',
    '通知',
    '发送',
    '推送',
    '回调',
    '(?i)\bmessage\b',
    '(?i)\bevent\b',
    '(?i)\bqueue\b'
)

$facadeDirectionPatterns = @(
    @('Receive', '(?i)\bReceive[A-Za-z]*\b'),
    @('Push',    '(?i)\bPush[A-Za-z]*\b'),
    @('Send',    '(?i)\bSend[A-Za-z]*\b'),
    @('Callback','(?i)\bCallback[A-Za-z]*\b'),
    @('Notify',  '(?i)\bNotify[A-Za-z]*\b')
)

# Facade-class-level patterns: only match actual Facade class names, not Service/Handler/etc.
# Allows prefixed names like ExamplePushFacade, ExampleReceiveFacadeImpl
$facadeClassDirectionPatterns = @(
    @('Receive', '(?i)\b[A-Za-z]*Receive[A-Za-z]*Facade(?:Impl)?\b'),
    @('Push',    '(?i)\b[A-Za-z]*Push[A-Za-z]*Facade(?:Impl)?\b'),
    @('Send',    '(?i)\b[A-Za-z]*Send[A-Za-z]*Facade(?:Impl)?\b'),
    @('Callback','(?i)\b[A-Za-z]*Callback[A-Za-z]*Facade(?:Impl)?\b'),
    @('Notify',  '(?i)\b[A-Za-z]*Notify[A-Za-z]*Facade(?:Impl)?\b')
)

# Non-Facade class patterns that must NOT satisfy Facade evidence
$nonFacadeClassPatterns = @(
    '(?i)\bPushService\b',
    '(?i)\bPushHandler\b',
    '(?i)\bPushProcessor\b',
    '(?i)\bSendService\b',
    '(?i)\bSendHandler\b',
    '(?i)\bReceiveService\b',
    '(?i)\bReceiveHandler\b'
)

$dataOnlyCarrierPatterns = @(
    '(?i)\benum\b',
    '(?i)\bDTO\b',
    '(?i)\bconstant\b',
    '(?i)\benumeration\b',
    '(?i)\bClaimNofityType\b',
    '(?i)\b\(production enum\b',
    '(?i)\b\(existing enum\b'
)

$realBehaviorCarrierPatterns = @(
    '(?i)\bFacade\b',
    '(?i)\bService\b',
    '(?i)\bController\b',
    '(?i)\bProcessor\b',
    '(?i)\bHandler\b',
    '(?i)\bListener\b',
    '(?i)\bConsumer\b',
    '(?i)\bProducer\b',
    '(?i)\bPublisher\b',
    '(?i)\bEvent[A-Za-z]*\b',
    '(?i)\bPushService\b',
    '(?i)\bPushFacade\b'
)

$hasBehaviorRequirement = $false
foreach ($pattern in $behaviorKeywordPatterns) {
    if ($requirementText -match $pattern) {
        $hasBehaviorRequirement = $true
        break
    }
}

function Test-IsDataOnlyCarrier {
    param([string]$CarrierText)
    if ([string]::IsNullOrWhiteSpace($CarrierText)) { return $false }
    $isDataOnly = $false
    $hasRealBehavior = $false
    foreach ($pattern in $dataOnlyCarrierPatterns) {
        if ($CarrierText -match $pattern) { $isDataOnly = $true; break }
    }
    foreach ($pattern in $realBehaviorCarrierPatterns) {
        if ($CarrierText -match $pattern) { $hasRealBehavior = $true; break }
    }
    return ($isDataOnly -and -not $hasRealBehavior)
}

function Test-HasFacadeDirectionEvidence {
    param(
        [string]$ExplorationText,
        [string]$ContractText
    )
    $combined = @($ExplorationText, $ContractText) -join "`n"
    $directionsFound = @()
    foreach ($dir in $facadeDirectionPatterns) {
        $name = [string]$dir[0]
        $pattern = [string]$dir[1]
        if ($combined -match $pattern) {
            $directionsFound += $name
        }
    }
    return @($directionsFound | Select-Object -Unique)
}

function Test-HasFacadeClassDirectionEvidence {
    param(
        [string]$ExplorationText,
        [string]$ContractText
    )
    $combined = @($ExplorationText, $ContractText) -join "`n"
    $directionsFound = @()
    $matchedClasses = @()
    foreach ($dir in $facadeClassDirectionPatterns) {
        $name = [string]$dir[0]
        $pattern = [string]$dir[1]
        $matches2 = [regex]::Matches($combined, $pattern)
        if ($matches2.Count -gt 0) {
            $directionsFound += $name
            foreach ($m in $matches2) {
                $matchedClasses += $m.Value
            }
        }
    }
    return @(@($directionsFound | Select-Object -Unique), @($matchedClasses | Select-Object -Unique))
}

$explorationReport = Read-TextIfExists (Join-Path $root 'EXPLORATION_REPORT.md')
$roundContract = Read-TextIfExists (Join-Path $root 'ROUND_CONTRACT.md')
$familyContract = Read-JsonIfExists (Join-Path $root 'FAMILY_CONTRACT.json')
$implementationContract = Read-TextIfExists (Join-Path $root 'IMPLEMENTATION_CONTRACT.md')
$firstSliceProofPlan = Read-TextIfExists (Join-Path $root 'FIRST_SLICE_PROOF_PLAN.md')

$allPlanText = @($explorationReport, $roundContract, $implementationContract, $firstSliceProofPlan) -join "`n"

foreach ($sliceAuth in @(Get-ChildItem -LiteralPath $root -Filter 'CARRIER_AUTHORIZATION_*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $auth = Read-JsonIfExists $sliceAuth.FullName
    if ($null -eq $auth) { continue }
    $slice = if ($auth.slice_index) { [int]$auth.slice_index } else { 1 }
    $selectedCarrier = [string]$auth.selected_carrier
    $realEntry = [string]$auth.real_entry
    $productionBoundary = [string]$auth.production_boundary
    $downstream = [string]$auth.downstream_side_effect_or_output
    $proofRequired = (Get-StringArray $auth.proof_required) -join ' '
    $carrierText = @($selectedCarrier, $realEntry, $productionBoundary, $downstream, $proofRequired) -join "`n"

    if ($hasBehaviorRequirement -and (Test-IsDataOnlyCarrier -CarrierText $carrierText)) {
        [void]$issues.Add([pscustomobject][ordered]@{
            slice = $slice
            file = $sliceAuth.Name
            selected_carrier = $selectedCarrier
            issue = 'data_only_carrier_for_behavior_requirement'
            evidence = "Requirement contains behavior keywords (MQ/push/notify/send/callback) but carrier is data-only: $selectedCarrier"
            required = 'Real behavior entry point (Facade/Service/Controller/Processor/Handler/Listener) that performs the MQ push/send/notify/callback'
        })
    }

    if ($hasBehaviorRequirement) {
        $carrierIsFacade = $selectedCarrier -match '(?i)Facade'
        $carrierIsReceiveOnly = $selectedCarrier -match '(?i)Receive' -and $selectedCarrier -notmatch '(?i)Push|Send|Callback|Notify'
        $carrierIsPushOnly = $selectedCarrier -match '(?i)Push|Send|Callback|Notify' -and $selectedCarrier -notmatch '(?i)Receive'

        if ($carrierIsFacade -and ($carrierIsReceiveOnly -or $carrierIsPushOnly)) {
            $facadeClassResult = Test-HasFacadeClassDirectionEvidence -ExplorationText $explorationReport -ContractText $allPlanText
            $facadeClassDirections = @($facadeClassResult[0])
            $facadeClassNames = @($facadeClassResult[1])

            $broadResult = Test-HasFacadeDirectionEvidence -ExplorationText $explorationReport -ContractText $allPlanText
            $broadDirections = @($broadResult)

            $oppositeFacadeClassFound = $false
            $oppositeDirectionNames = @()
            if ($carrierIsReceiveOnly) {
                $oppositeDirectionNames = @('Push', 'Send')
            }
            if ($carrierIsPushOnly) {
                $oppositeDirectionNames = @('Receive')
            }

            foreach ($oppDir in $oppositeDirectionNames) {
                if ($facadeClassDirections -contains $oppDir) {
                    $oppositeFacadeClassFound = $true
                    break
                }
            }

            if (-not $oppositeFacadeClassFound) {
                $hasBroadButNotFacade = $false
                foreach ($oppDir in $oppositeDirectionNames) {
                    if ($broadDirections -contains $oppDir) {
                        $hasBroadButNotFacade = $true
                        break
                    }
                }

                [void]$issues.Add([pscustomobject][ordered]@{
                    slice = $slice
                    file = $sliceAuth.Name
                    selected_carrier = $selectedCarrier
                    issue = 'facade_direction_facade_class_missing'
                    evidence = "Carrier '$selectedCarrier' is a directional Facade but no opposite-direction Facade CLASS found in evidence. Broad keywords ($($broadDirections -join ', ')) present but no Facade class names ($($facadeClassNames -join ', ')) for direction(s): $($oppositeDirectionNames -join ', '). Non-Facade matches (PushService etc.) do not satisfy Facade evidence."
                    required = "Search the opposite-direction Facade CLASS in codebase (e.g. ExamplePushFacade for ExampleReceiveFacade); record class name and method/signature comparison in EXPLORATION_REPORT.md; justify selection with Facade-level comparison"
                })
            } else {
                $oppositeFacadeClassNames = @()
                foreach ($dir in $facadeClassDirectionPatterns) {
                    $dirName = [string]$dir[0]
                    $dirPattern = [string]$dir[1]
                    if ($oppositeDirectionNames -contains $dirName) {
                        $oppMatches = [regex]::Matches($allPlanText, $dirPattern)
                        foreach ($m in $oppMatches) {
                            $oppositeFacadeClassNames += $m.Value
                        }
                    }
                }
                $oppositeFacadeClassNames = @($oppositeFacadeClassNames | Select-Object -Unique)

                $hasMethodSignature = $false
                if ($oppositeFacadeClassNames.Count -gt 0) {
                    # Method-signature evidence must be explicitly bound to the opposite Facade class.
                    # Priority 1: class-qualified signature (OppositeFacade.methodName) - strongest.
                    # Priority 2: Markdown table row binding - the row structure creates explicit
                    #             association between the Facade column and the Method/Signature column.
                    #             Loose same-line co-occurrence in prose is NOT accepted because
                    #             the method is not guaranteed to belong to the opposite Facade.
                    $allLines = $allPlanText -split "`n"
                    $sigPattern = '(?i)(void|ResultModel|String|int|boolean)\s+(\w+)\s*\('
                    $oppFacadeEscaped = @($oppositeFacadeClassNames | ForEach-Object { [regex]::Escape($_) })

                    # Selected carrier's direction keywords - methods starting with these are the carrier's own
                    $selectedCarrierDirPatterns = @()
                    if ($carrierIsReceiveOnly) { $selectedCarrierDirPatterns = @('(?i)^receive') }
                    elseif ($carrierIsPushOnly) { $selectedCarrierDirPatterns = @('(?i)^push', '(?i)^send', '(?i)^callback', '(?i)^notify') }

                    foreach ($line in $allLines) {
                        if (-not ($line -match $sigPattern)) { continue }
                        $methodName = $Matches[2]

                        $lineHasOppFacade = $false
                        foreach ($facadeName in $oppFacadeEscaped) {
                            if ($line -match $facadeName) {
                                $lineHasOppFacade = $true
                                break
                            }
                        }
                        if (-not $lineHasOppFacade) { continue }

                        # Priority 1: class-qualified (OppositeFacade.methodName)
                        $hasClassQualified = $false
                        foreach ($facadeName in $oppFacadeEscaped) {
                            if ($line -match "${facadeName}\.${methodName}") {
                                $hasClassQualified = $true
                                break
                            }
                        }
                        if ($hasClassQualified) {
                            $hasMethodSignature = $true
                            break
                        }

                        # Priority 2: Markdown table row binding only.
                        # A table row (| Facade | Method | Signature |) provides structured binding
                        # between the Facade name and its method. The opposite Facade name and the
                        # method signature must appear in **distinct non-empty cells** to establish
                        # a real binding. A single-cell note row co-mentioning both is NOT accepted.
                        $isTableRow = ($line -match '^\s*\|') -and ($line -match '\|\s*$')
                        $isSeparatorRow = ($line -match '^\s*\|[-:\s|]+\|\s*$')
                        if ($isTableRow -and -not $isSeparatorRow) {
                            # Parse cells: split by |, trim, drop empty leading/trailing from edge pipes
                            $rawCells = $line -split '\|'
                            $cells = @($rawCells | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

                            # Find which cell(s) contain the opposite Facade name and which contain the sig
                            $facadeCellIndex = -1
                            $sigCellIndex = -1
                            for ($ci = 0; $ci -lt $cells.Count; $ci++) {
                                $cellText = $cells[$ci]
                                foreach ($facadeName in $oppFacadeEscaped) {
                                    if ($cellText -match $facadeName) {
                                        $facadeCellIndex = $ci
                                        break
                                    }
                                }
                                if ($cellText -match $sigPattern -and $Matches[2] -eq $methodName) {
                                    $sigCellIndex = $ci
                                }
                            }

                            # Binding requires distinct non-empty cells for Facade and signature
                            if ($facadeCellIndex -ge 0 -and $sigCellIndex -ge 0 -and $facadeCellIndex -ne $sigCellIndex) {
                                # Still reject if method name matches selected carrier's own direction
                                $isCarrierOwnMethod = $false
                                foreach ($dirPat in $selectedCarrierDirPatterns) {
                                    if ($methodName -match $dirPat) {
                                        $isCarrierOwnMethod = $true
                                        break
                                    }
                                }
                                if (-not $isCarrierOwnMethod) {
                                    $hasMethodSignature = $true
                                    break
                                }
                            }
                        }

                        # Non-table, non-class-qualified co-occurrence: NOT accepted
                    }
                }

                if (-not $hasMethodSignature) {
                    [void]$issues.Add([pscustomobject][ordered]@{
                        slice = $slice
                        file = $sliceAuth.Name
                        selected_carrier = $selectedCarrier
                        issue = 'facade_direction_method_signature_missing'
                        evidence = "Opposite-direction Facade class(es) found ($($oppositeFacadeClassNames -join ', ')) but no method/signature comparison evidence in planning docs"
                        required = 'Record method signatures from the opposite-direction Facade in EXPLORATION_REPORT.md and compare with selected carrier'
                    })
                }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($downstream) -and $downstream -match '(?i)push.*MQ|MQ.*push|send.*message|notify|callback') {
        if (Test-IsDataOnlyCarrier -CarrierText $selectedCarrier) {
            [void]$issues.Add([pscustomobject][ordered]@{
                slice = $slice
                file = $sliceAuth.Name
                selected_carrier = $selectedCarrier
                issue = 'downstream_behavior_without_behavior_carrier'
                evidence = "downstream_side_effect_or_output references behavior (MQ/push/notify) but selected_carrier is not a behavior entry point: $selectedCarrier"
                required = 'Carrier must be a real behavior entry point (Service/Handler/Listener/Publisher) that orchestrates the MQ push/send/notify'
            })
        }
    }
}

$sideEffectFiles = @(Get-ChildItem -LiteralPath $root -Filter 'SIDE_EFFECT_EVIDENCE_*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($seFile in $sideEffectFiles) {
    $se = Read-JsonIfExists $seFile.FullName
    if ($null -eq $se) { continue }
    $expectedWrites = (Get-StringArray $se.expected_writes_or_outputs) -join ' '
    if ($hasBehaviorRequirement -and $expectedWrites -match '(?i)push.*MQ|MQ.*push|send.*message|notify.*event|callback') {
        $entryCall = [string]$se.entry_call
        if ((Test-IsDataOnlyCarrier -CarrierText $entryCall)) {
            [void]$issues.Add([pscustomobject][ordered]@{
                slice = if ($se.slice_index) { [int]$se.slice_index } else { 0 }
                file = $seFile.Name
                selected_carrier = $entryCall
                issue = 'side_effect_entry_is_data_only_for_behavior'
                evidence = "Side effect references behavior writes but entry_call is data-only: $entryCall"
                required = 'entry_call must reference a real behavior orchestrator, not an enum/DTO/constant'
            })
        }
    }
}

$sliceResults = @(Get-ChildItem -LiteralPath $root -Filter 'SLICE_RESULT_*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($srFile in $sliceResults) {
    $sr = Read-JsonIfExists $srFile.FullName
    if ($null -eq $sr) { continue }
    $slice = [int]$sr.slice_index
    $carrier = [string]$sr.target_subsurface_or_carrier
    $boundary = [string]$sr.production_boundary
    $srText = @($carrier, $boundary) -join "`n"

    if ($hasBehaviorRequirement -and (Test-IsDataOnlyCarrier -CarrierText $srText)) {
        [void]$issues.Add([pscustomobject][ordered]@{
            slice = $slice
            file = $srFile.Name
            selected_carrier = $carrier
            issue = 'slice_result_carrier_is_data_only_for_behavior'
            evidence = "Slice result carrier is data-only for a behavior requirement: $carrier"
            required = 'Must provide real behavior entry point evidence'
        })
    }
}

$status = if ($issues.Count -eq 0) { 'ALLOW' } else { 'BLOCKED' }
$result = [ordered]@{
    status = $status
    mode = $Mode
    replay_root = $root
    has_behavior_requirement = $hasBehaviorRequirement
    checked_carriers = (@(Get-ChildItem -LiteralPath $root -Filter 'CARRIER_AUTHORIZATION_*.json' -File -ErrorAction SilentlyContinue).Count)
    checked_side_effects = $sideEffectFiles.Count
    checked_slice_results = $sliceResults.Count
    issues = @($issues)
    gate = 'behavior_carrier_facade_validation_v267'
}
$outPath = Join-Path $root 'BEHAVIOR_CARRIER_FACADE_VALIDATION.json'
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12
