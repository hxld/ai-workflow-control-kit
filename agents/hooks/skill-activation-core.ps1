param(
    [Parameter(Mandatory=$true)]
    [string]$PromptText,
    [string]$ProjectDir = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-HookLog {
    param([string]$Message)

    try {
        $logDir = Join-Path $env:USERPROFILE ".agents\logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
        }
        $logPath = Join-Path $logDir "skill-hooks.log"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $logPath -Value "[$timestamp][core] $Message" -Encoding UTF8 -ErrorAction Stop
    } catch {
    }
}

function Decode-Utf8Base64 {
    param([string]$Value)

    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Value))
}

$TEXT_HOOK_SUMMARY = Decode-Utf8Base64 "SE9PSyDmioDog73mkZjopoE="
$TEXT_LAST_EFFECT = Decode-Utf8Base64 "5LiK5LiA6L2u5bey56Gu6K6k5pWI5p6c77ya"
$TEXT_MATCHED_SKILLS = Decode-Utf8Base64 "5pys5qyh5o+Q56S65ZG95Lit5LqG5Lul5LiL5oqA6IO977ya"
$TEXT_AUTO_APPLY_CANDIDATE = Decode-Utf8Base64 "5Y+v6Ieq5Yqo5bqU55So5YCZ6YCJ"
$TEXT_SUGGEST_ONLY = Decode-Utf8Base64 "5LuF5bu66K6u"
$TEXT_TRIGGER = Decode-Utf8Base64 "6Kem5Y+R6K+NOiA="
$TEXT_PLANNED_EFFECT = Decode-Utf8Base64 "6K6h5YiS5Lit55qE55So5oi35Y+v6KeB5pWI5p6c77ya"
$TEXT_AUTO_APPLY_SECTION = Decode-Utf8Base64 "6Ieq5Yqo5bqU55So77yI5L2O6aOO6Zmp77yJ77ya"
$TEXT_CRITICAL_SECTION = Decode-Utf8Base64 "5YWz6ZSu5bu66K6u77ya"
$TEXT_HIGH_SECTION = Decode-Utf8Base64 "6auY5LyY5YWI57qn77ya"
$TEXT_MEDIUM_SECTION = Decode-Utf8Base64 "5Lit5LyY5YWI57qn77ya"
$TEXT_ACTION_AUTO = Decode-Utf8Base64 "5bu66K6u5Yqo5L2c77ya56uL5Y2z5Yqg6L295bm25bqU55So6Ieq5Yqo5bqU55So5oqA6IO977yM6Zmk6Z2e55So5oi35piO56Gu6YCJ5oup6Lez6L+H"
$TEXT_ACTION_MANUAL = Decode-Utf8Base64 "5bu66K6u5Yqo5L2c77ya5aaC5pyJ6ZyA6KaB77yM5L2/55SoIFNraWxsIOW3peWFt+aYvuW8j+WKoOi9vQ=="
$TEXT_NOTE_AUTO = Decode-Utf8Base64 "6K+05piO77ya6Ieq5Yqo5bqU55So5Y+q6Z2i5ZCR5L2O6aOO6Zmp5oqA6IO977yb5pu06auY6aOO6Zmp55qE5oqA6IO95LuN54S26ZyA6KaB5piO56Gu56Gu6K6k44CC"
$TEXT_NOTE_MANUAL = Decode-Utf8Base64 "6K+05piO77ya6L+Z6YeM5Y+q5piv5bu66K6u77yM5LiN5Lya6Ieq5Yqo5Yqg6L2977yb5aaC6ZyA5Yqg6L296K+35piO56Gu56Gu6K6k44CC"
$TEXT_TIP = Decode-Utf8Base64 "5o+Q56S677ya5aaC5p6c5L2g5biM5pyb5oqA6IO95Zyo6IGK5aSp6YeM55WZ5LiL5pu05piO5pi+55qE6L2o6L+577yM5Y+v5Lul5Zyo5o+Q56S65Lit5Yqg5YWlICforrDlvZXov5nkuKrmqKHlvI8n44CBJ+efpeivhuayiea3gCcg6L+Z57G75pi+5byP55+t6K+t44CC"
$TEXT_PRIORITY_CRITICAL = Decode-Utf8Base64 "5YWz6ZSu"
$TEXT_PRIORITY_HIGH = Decode-Utf8Base64 "6auY"
$TEXT_PRIORITY_MEDIUM = Decode-Utf8Base64 "5Lit"

function Get-PriorityLabel {
    param([string]$Priority)

    switch ($Priority) {
        "critical" { return $TEXT_PRIORITY_CRITICAL }
        "high" { return $TEXT_PRIORITY_HIGH }
        "medium" { return $TEXT_PRIORITY_MEDIUM }
        default { return $Priority }
    }
}

function Get-ProjectHash {
    param([string]$InputText)

    if ([string]::IsNullOrWhiteSpace($InputText)) {
        return $null
    }

    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputText.ToLowerInvariant())
        $hashBytes = $md5.ComputeHash($bytes)
        return -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
    } finally {
        $md5.Dispose()
    }
}

function Get-PendingExecutionReceipt {
    param([string]$ProjectDir)

    $receiptDir = Join-Path $env:USERPROFILE ".agents\state\skill-feedback"
    if (-not (Test-Path $receiptDir)) {
        return $null
    }

    $candidatePaths = @()
    $resolvedProjectDir = $null
    if (-not [string]::IsNullOrWhiteSpace($ProjectDir)) {
        try {
            $resolvedProjectDir = (Resolve-Path $ProjectDir).Path
        } catch {
            $resolvedProjectDir = $ProjectDir
        }
        $projectHash = Get-ProjectHash -InputText $resolvedProjectDir
        if (-not [string]::IsNullOrWhiteSpace($projectHash)) {
            $candidatePaths += (Join-Path $receiptDir ($projectHash + ".json"))
        }
    }

    $candidatePaths += (Join-Path $receiptDir "latest.json")

    foreach ($candidatePath in $candidatePaths | Select-Object -Unique) {
        if (-not (Test-Path $candidatePath)) {
            continue
        }

        try {
            $receipt = Get-Content $candidatePath -Encoding UTF8 -Raw | ConvertFrom-Json
            if ($null -eq $receipt) {
                Remove-Item $candidatePath -Force -ErrorAction SilentlyContinue
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($resolvedProjectDir) -and
                -not [string]::IsNullOrWhiteSpace($receipt.projectRoot) -and
                $receipt.projectRoot -ne $resolvedProjectDir) {
                continue
            }

            Remove-Item $candidatePath -Force -ErrorAction SilentlyContinue
            return $receipt
        } catch {
            Remove-Item $candidatePath -Force -ErrorAction SilentlyContinue
        }
    }

    return $null
}

$rulesPath = Join-Path $env:USERPROFILE ".agents\skills\skill-rules.json"

if (-not (Test-Path $rulesPath)) {
    Write-HookLog -Message "missing rules file: $rulesPath"
    exit 0
}

$rules = Get-Content $rulesPath -Encoding UTF8 -Raw | ConvertFrom-Json
$promptLower = $PromptText.ToLower()
$matchedSkills = @()
$receipt = Get-PendingExecutionReceipt -ProjectDir $ProjectDir
$hasReceipt = $null -ne $receipt -and $null -ne $receipt.summaries -and $receipt.summaries.Count -gt 0

function New-TextFromCodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$readOnlyIntentMarkers = @(
    (New-TextFromCodePoints @(0x4E0D, 0x8981, 0x4FEE, 0x6539)),
    (New-TextFromCodePoints @(0x4E0D, 0x4FEE, 0x6539)),
    (New-TextFromCodePoints @(0x522B, 0x4FEE, 0x6539)),
    (New-TextFromCodePoints @(0x4E0D, 0x7528, 0x4FEE, 0x6539)),
    (New-TextFromCodePoints @(0x4E0D, 0x8981, 0x52A8)),
    (New-TextFromCodePoints @(0x53EA, 0x8BFB)),
    (New-TextFromCodePoints @(0x53EA, 0x89E3, 0x91CA)),
    (New-TextFromCodePoints @(0x89E3, 0x91CA, 0x4E00, 0x4E0B)),
    (New-TextFromCodePoints @(0x8BF4, 0x660E, 0x4E00, 0x4E0B))
)

foreach ($marker in $readOnlyIntentMarkers) {
    if ($PromptText.Contains($marker)) {
        Write-HookLog -Message "skip read-only intent marker: $marker"
        exit 0
    }
}

foreach ($skillName in $rules.skills.PSObject.Properties.Name) {
    $skill = $rules.skills.$skillName
    $keywords = $skill.triggers.keywords
    
    foreach ($kw in $keywords) {
        if ($promptLower -match [regex]::Escape($kw.ToLower())) {
            $matchedSkills += @{
                name = $skillName
                priority = $skill.priority
                description = $skill.description
                auto_apply = [bool]$skill.auto_apply
                trigger_keyword = $kw
                feedback_summary = $skill.feedback_summary
            }
            break
        }
    }
}

if ($matchedSkills.Count -gt 0 -or $hasReceipt) {
    $matchedNames = $matchedSkills | ForEach-Object { $_.name } | Sort-Object -Unique
    if ($matchedSkills.Count -gt 0) {
        $matchReasonSummary = $matchedSkills |
            Sort-Object name -Unique |
            ForEach-Object { $_.name + " via [" + $_.trigger_keyword + "]" }
        Write-HookLog -Message ("matched skills: " + ($matchReasonSummary -join ", "))
    } elseif ($hasReceipt) {
        Write-HookLog -Message "show pending execution receipt"
    }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("-----------------------------------------")
    [void]$sb.AppendLine($TEXT_HOOK_SUMMARY)
    [void]$sb.AppendLine("-----------------------------------------")
    [void]$sb.AppendLine("")

    if ($hasReceipt) {
        [void]$sb.AppendLine($TEXT_LAST_EFFECT)
        foreach ($item in $receipt.summaries) {
            [void]$sb.AppendLine("  -> " + $item.skillName + ": " + $item.message)
        }
        [void]$sb.AppendLine("")
    }

    if ($matchedSkills.Count -gt 0) {
        [void]$sb.AppendLine($TEXT_MATCHED_SKILLS)
        foreach ($s in ($matchedSkills | Sort-Object name -Unique)) {
            $modeLabel = if ($s.auto_apply) { $TEXT_AUTO_APPLY_CANDIDATE } else { $TEXT_SUGGEST_ONLY }
            $priorityLabel = Get-PriorityLabel -Priority $s.priority
            [void]$sb.AppendLine("  -> " + $s.name + " [" + $priorityLabel + ", " + $modeLabel + "]")
            [void]$sb.AppendLine("     " + $TEXT_TRIGGER + $s.trigger_keyword)
        }
        [void]$sb.AppendLine("")
    }

    if ($matchedSkills.Count -gt 0) {
        $skillsWithFeedback = $matchedSkills | Where-Object { -not [string]::IsNullOrWhiteSpace($_.feedback_summary) } | Sort-Object name -Unique
        if ($skillsWithFeedback.Count -gt 0) {
            [void]$sb.AppendLine($TEXT_PLANNED_EFFECT)
            foreach ($s in $skillsWithFeedback) {
                [void]$sb.AppendLine("  -> " + $s.name + ": " + $s.feedback_summary)
            }
            [void]$sb.AppendLine("")
        }

        $autoApply = $matchedSkills | Where-Object { $_.auto_apply -eq $true } | Sort-Object name -Unique
        $nonAutoMatched = $matchedSkills | Where-Object { $_.auto_apply -ne $true }
        $critical = $nonAutoMatched | Where-Object { $_.priority -eq "critical" }
        $high = $nonAutoMatched | Where-Object { $_.priority -eq "high" }
        $medium = $nonAutoMatched | Where-Object { $_.priority -eq "medium" }

        $canAutoApplyNow = ($autoApply.Count -gt 0 -and $critical.Count -eq 0 -and $high.Count -eq 0)

        if ($canAutoApplyNow) {
            [void]$sb.AppendLine($TEXT_AUTO_APPLY_SECTION)
            foreach ($s in $autoApply) {
                [void]$sb.AppendLine("  -> " + $s.name + ": " + $s.description)
            }
            [void]$sb.AppendLine("")
        }

        if ($critical.Count -gt 0) {
            [void]$sb.AppendLine($TEXT_CRITICAL_SECTION)
            foreach ($s in $critical) {
                [void]$sb.AppendLine("  -> " + $s.name + ": " + $s.description)
            }
            [void]$sb.AppendLine("")
        }

        if ($high.Count -gt 0) {
            [void]$sb.AppendLine($TEXT_HIGH_SECTION)
            foreach ($s in $high) {
                [void]$sb.AppendLine("  -> " + $s.name + ": " + $s.description)
            }
            [void]$sb.AppendLine("")
        }

        if ($medium.Count -gt 0) {
            [void]$sb.AppendLine($TEXT_MEDIUM_SECTION)
            foreach ($s in $medium) {
                [void]$sb.AppendLine("  -> " + $s.name + ": " + $s.description)
            }
            [void]$sb.AppendLine("")
        }

        [void]$sb.AppendLine("-----------------------------------------")
        if ($canAutoApplyNow) {
            [void]$sb.AppendLine($TEXT_ACTION_AUTO)
        } else {
            [void]$sb.AppendLine($TEXT_ACTION_MANUAL)
        }
        [void]$sb.AppendLine("-----------------------------------------")
        [void]$sb.AppendLine("")
        if ($canAutoApplyNow) {
            [void]$sb.AppendLine($TEXT_NOTE_AUTO)
        } else {
            [void]$sb.AppendLine($TEXT_NOTE_MANUAL)
        }
        [void]$sb.AppendLine($TEXT_TIP)
    }
    
    [Console]::Write($sb.ToString())
} else {
    Write-HookLog -Message "no matched skills"
}

exit 0
