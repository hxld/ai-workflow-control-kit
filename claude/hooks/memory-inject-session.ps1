[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$memoryPath = Join-Path $env:USERPROFILE ".memory\MEMORY.md"
$errorLessonsPath = Join-Path $env:USERPROFILE ".memory\error-lessons.md"

$output = @()
$output += "=== Error Memory (SessionStart) ==="
if (Test-Path $memoryPath) {
    $output += Get-Content $memoryPath -Encoding UTF8 -Raw
}
if (Test-Path $errorLessonsPath) {
    $output += Get-Content $errorLessonsPath -Encoding UTF8 -Raw
}
$output += "=== END ==="
$output += "RULE: batch op (2+ files) => re-read MEMORY.md first. Fail 2x => switch strategy."
$output += "RULE: 4-platform sync must also update: <SYNC_GUIDE_PATH>"

[Console]::Write(($output -join "`n"))
exit 0
