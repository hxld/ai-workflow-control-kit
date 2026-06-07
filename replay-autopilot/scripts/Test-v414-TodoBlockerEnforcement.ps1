param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifySlicePath = Join-Path $scriptRoot 'Verify-SliceClosure.ps1'

$verifyContent = Get-Content -LiteralPath $verifySlicePath -Raw -Encoding UTF8

# Verify v414 TODO blocker is present
Assert-True -Name 'v414_todo_blocker_comment_present' -Condition ($verifyContent -match '# v414 TODO Blocker')
Assert-True -Name 'v414_todo_blocker_enforcement_present' -Condition ($verifyContent.Contains("if (`$gapFlags -contains 'todo_placeholder_exists')"))
Assert-True -Name 'v414_todo_blocker_adds_non_authorizing' -Condition ($verifyContent.Contains("`$nonAuthorizingReasons.Add('todo_placeholder_exists')"))

# Verify the blocker comes before the unique filter
$todoIndex = $verifyContent.IndexOf("if (`$gapFlags -contains 'todo_placeholder_exists')")
$uniqueIndex = $verifyContent.IndexOf("`$nonAuthorizingReasons = @(`$nonAuthorizingReasons | Select-Object -Unique)")
Assert-True -Name 'v414_todo_blocker_before_unique_filter' -Condition (($todoIndex -gt 0) -and ($uniqueIndex -gt $todoIndex))

# Verify TODO detector integration exists
$todoDetectorPath = Join-Path $scriptRoot 'Invoke-TodoDetector.ps1'
Assert-True -Name 'todo_detector_script_exists' -Condition (Test-Path -LiteralPath $todoDetectorPath)

# Verify gap flag is set when TODOs exist
Assert-True -Name 'todo_gap_flag_set' -Condition ($verifyContent.Contains("`$todoCount -gt 0") -and $verifyContent.Contains("'todo_placeholder_exists'"))

Write-Host 'PASS: v414 TODO blocker enforcement'
