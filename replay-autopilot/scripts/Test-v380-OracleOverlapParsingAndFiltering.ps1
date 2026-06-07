param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptRoot
$cases = New-Object System.Collections.Generic.List[string]

# Test 1: Semicolon format parsing
$semicolonText = '- oracle_out_of_scope_files: InsureCompanyPushFacade (dock domain); ExamineFlowFacade (examine domain); AiOcrService (OCR processing)'
$parts = @()
if ($semicolonText -match '(?im)^\s*-?\s*oracle_out_of_scope_files\s*[:=]\s*(.+)') {
    $content = $Matches[1]
    $parts = $content -split '\s*;\s*'
    $fileNames = @()
    foreach ($part in $parts) {
        if ($part -match '^\s*([A-Za-z0-9_$.]+)') {
            $fileNames += $Matches[1].Trim()
        }
    }
}
$cases.Add((Assert-True -Name 'semicolon_format_parse_count' -Condition ($fileNames.Count -eq 3))) | Out-Null
$cases.Add((Assert-True -Name 'semicolon_format_first_file' -Condition ($fileNames[0] -eq 'InsureCompanyPushFacade'))) | Out-Null

# Test 2: Bracket format parsing
$bracketText = '- oracle_out_of_scope_files: [File1, File2, File3]'
if ($bracketText -match '(?im)^\s*-?\s*oracle_out_of_scope_files\s*[:=]\s*\[(.+?)\]') {
    $content = $Matches[1]
    $parts = $content -split '\s*,\s*'
    $fileNames = @()
    foreach ($part in $parts) {
        $fileName = $part.Trim().Trim('''').Trim('"').Trim('`')
        if (-not [string]::IsNullOrWhiteSpace($fileName)) {
            $fileNames += $fileName
        }
    }
}
$cases.Add((Assert-True -Name 'bracket_format_parse_count' -Condition ($fileNames.Count -eq 3))) | Out-Null

# Test 3: Exact filename match (no substring false positive)
$outOfScope = @('Facade', 'Service')
$testFiles = @('AiAutoClaimFlowFacade.java', 'InsureCompanyPushFacade.java', 'MyService.java', 'AiOcrService.java')
$filtered = @($testFiles | Where-Object {
    $f = $_
    $fn = [System.IO.Path]::GetFileNameWithoutExtension($f)
    -not ($outOfScope | Where-Object {
        $exclName = [System.IO.Path]::GetFileNameWithoutExtension($_)
        $f -eq $_ -or $fn -eq $exclName
    })
})
# After filtering, only files NOT exactly matching 'Facade' or 'Service' should remain
# 'AiAutoClaimFlowFacade' != 'Facade', so it should NOT be filtered out (previous bug)
# 'InsureCompanyPushFacade' != 'Facade', so it should NOT be filtered out
# But wait - the out-of-scope list contains just 'Facade', not 'InsureCompanyPushFacade'
# So the expected behavior is:
# - 'AiAutoClaimFlowFacade' - NOT filtered (filename != 'Facade')
# - 'InsureCompanyPushFacade' - NOT filtered (filename != 'Facade')
# - 'MyService' - NOT filtered (filename != 'Service')
# - 'AiOcrService' - NOT filtered (filename != 'Service')
# All should remain because 'Facade' != 'AiAutoClaimFlowFacade'
$cases.Add((Assert-True -Name 'exact_match_no_false_positive' -Condition ($filtered.Count -eq 4))) | Out-Null

# Test 4: Exact filename match (correct exclusion)
$outOfScope2 = @('AiOcrService', 'ExamineFlowFacade')
$testFiles2 = @('AiOcrService.java', 'ExamineFlowFacade.java', 'AiAutoClaimFlowService.java')
$filtered2 = @($testFiles2 | Where-Object {
    $f = $_
    $fn = [System.IO.Path]::GetFileNameWithoutExtension($f)
    -not ($outOfScope2 | Where-Object {
        $exclName = [System.IO.Path]::GetFileNameWithoutExtension($_)
        $f -eq $_ -or $fn -eq $exclName
    })
})
# 'AiOcrService' == 'AiOcrService' - filtered out
# 'ExamineFlowFacade' == 'ExamineFlowFacade' - filtered out
# 'AiAutoClaimFlowService' != any - NOT filtered
$cases.Add((Assert-True -Name 'exact_match_correct_exclusion' -Condition ($filtered2.Count -eq 1 -and $filtered2[0] -eq 'AiAutoClaimFlowService.java'))) | Out-Null

# Test 5: Case sensitivity (PowerShell -eq is case-insensitive by default)
$outOfScope3 = @('aiocrservice')  # lowercase
$testFiles3 = @('AiOcrService.java')  # mixed case
$filtered3 = @($testFiles3 | Where-Object {
    $f = $_
    $fn = [System.IO.Path]::GetFileNameWithoutExtension($f)
    -not ($outOfScope3 | Where-Object {
        $exclName = [System.IO.Path]::GetFileNameWithoutExtension($_)
        $f -eq $_ -or $fn -eq $exclName
    })
})
# PowerShell -eq is case-insensitive, so 'AiOcrService' == 'aiocrservice'
# Therefore the file is filtered out
$cases.Add((Assert-True -Name 'case_insensitive_exact_match' -Condition ($filtered3.Count -eq 0))) | Out-Null

# Test 6: Domain filtering for cross-feature oracles
$allOracleFiles = @(
    'claim-core/src/main/java/com/huize/claim/core/ai/service/AiAutoClaimFlowService.java',
    'claim-core/src/main/java/com/huize/claim/core/ai/service/AiOcrService.java',
    'claim-core/src/main/java/com/huize/claim/core/dock/service/InsureCompanyPushService.java',
    'claim-core/src/main/java/com/huize/claim/core/examine/service/ExamineService.java'
)
$primaryDomain = 'ai'
$domainFiltered = @($allOracleFiles | Where-Object {
    $f = $_ -replace '\\', '/'
    $f -match "/$primaryDomain/"
})
# Should only match files containing "/ai/" in path
$cases.Add((Assert-True -Name 'domain_filter_ai_only' -Condition (
    $domainFiltered.Count -eq 2 -and
    $domainFiltered[0] -eq 'claim-core/src/main/java/com/huize/claim/core/ai/service/AiAutoClaimFlowService.java'
))) | Out-Null

# Test 7: Domain filter with no matching domain
$primaryDomain2 = 'nonexistent'
$domainFiltered2 = @($allOracleFiles | Where-Object {
    $f = $_ -replace '\\', '/'
    $f -match "/$primaryDomain2/"
})
# Should match no files
$cases.Add((Assert-True -Name 'domain_filter_no_match' -Condition ($domainFiltered2.Count -eq 0))) | Out-Null

# Test 8: Domain filter exact match (not substring)
$trickyFiles = @(
    'claim-core/src/main/java/com/huize/claim/core/ai/service/AiService.java',
    'claim-core/src/main/java/com/huize/claim/core/daily/DailyAiTaskService.java'
)
$primaryDomain3 = 'ai'
$domainFiltered3 = @($trickyFiles | Where-Object {
    $f = $_ -replace '\\', '/'
    $f -match "/$primaryDomain3/"
})
# Should only match first file (contains "/ai/"), not second (contains "/daily/" not "/ai/")
$cases.Add((Assert-True -Name 'domain_filter_exact_path_match' -Condition (
    $domainFiltered3.Count -eq 1 -and
    $domainFiltered3[0] -eq 'claim-core/src/main/java/com/huize/claim/core/ai/service/AiService.java'
))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
