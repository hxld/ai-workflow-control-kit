param(
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [string]$BaseCommit,
    [Parameter(Mandatory = $true)]
    [string]$OracleCommit,
    [Parameter(Mandatory = $true)]
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'

$diffStat = & git -C $Worktree diff "$BaseCommit" "$OracleCommit" --stat --no-color 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "git diff --stat failed: $diffStat"
}

$diffNumstat = & git -C $Worktree diff "$BaseCommit" "$OracleCommit" --numstat --no-color 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "git diff --numstat failed: $diffNumstat"
}

function Get-LayerClassification {
    param([string]$Path)

    if ($Path -match '(?i)(test|spec)/') { return 'Test' }
    if ($Path -match '(?i)(controller|facade|api|endpoint|route)\b') { return 'Controller' }
    if ($Path -match '(?i)(service|processor|handler|listener|consumer|producer|worker|job|task|scheduler)\b.*\.java$') { return 'Service' }
    if ($Path -match '(?i)(mapper|dao|repository|persistence)\b') { return 'Mapper' }
    if ($Path -match '(?i)(dto|param|request|response|vo|model|entity|domain)\b.*\.java$') { return 'DTO' }
    if ($Path -match '(?i)(enum|constant|config|properties|yaml|yml)\b') { return 'Enum' }
    if ($Path -match '(?i)\.(xml|ftl|vm|jsp|js|html|css|properties)$') { return 'Resource' }
    if ($Path -match '(?i)\.(java)$') { return 'Other' }
    return 'Other'
}

function Get-BusinessWeight {
    param(
        [string]$Layer,
        [string]$Path
    )

    switch ($Layer) {
        'Service' { return 'HIGH' }
        'Controller' { return 'HIGH' }
        'Mapper' { return 'MEDIUM' }
        'Enum' { return 'MEDIUM' }
        'Resource' { return 'MEDIUM' }
        'Test' { return 'LOW' }
        'DTO' { return 'LOW' }
        default { return 'LOW' }
    }
}

$files = New-Object System.Collections.Generic.List[object]
$totalAdd = 0
$totalDel = 0

foreach ($line in ($diffNumstat -split "`n")) {
    $line = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $parts = $line -split "`t"
    if ($parts.Count -lt 3) { continue }

    $additions = if ($parts[0] -match '^\d+$') { [int]$parts[0] } else { 0 }
    $deletions = if ($parts[1] -match '^\d+$') { [int]$parts[1] } else { 0 }
    $filePath = $parts[2]

    if ($filePath -match '(^|/)target/' -or $filePath -match '\.class$') { continue }

    $layer = Get-LayerClassification -Path $filePath
    $weight = Get-BusinessWeight -Layer $layer -Path $filePath
    $isTest = $layer -eq 'Test'
    $isProduction = -not $isTest

    $totalAdd += $additions
    $totalDel += $deletions

    $files.Add([ordered]@{
        path = $filePath
        layer = $layer
        weight = $weight
        is_test = $isTest
        is_production = $isProduction
        additions = $additions
        deletions = $deletions
    })
}

$productionFiles = @($files | Where-Object { $_.is_production })
$highWeightFiles = @($files | Where-Object { $_.weight -eq 'HIGH' })
$layerSummary = @{}
foreach ($f in $files) {
    if (-not $layerSummary.ContainsKey($f.layer)) {
        $layerSummary[$f.layer] = 0
    }
    $layerSummary[$f.layer]++
}

$analysis = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToString('s')
    base_commit = $BaseCommit
    oracle_commit = $OracleCommit
    total_files = $files.Count
    production_files = $productionFiles.Count
    test_files = ($files.Count - $productionFiles.Count)
    high_weight_files = $highWeightFiles.Count
    total_additions = $totalAdd
    total_deletions = $totalDel
    layer_summary = $layerSummary
    files = $files.ToArray()
}

$analysis | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutPath -Encoding UTF8
Write-Host "Oracle diff analysis: $($files.Count) files, $($productionFiles.Count) production, $($highWeightFiles.Count) high-weight"
Write-Host "Output: $OutPath"

