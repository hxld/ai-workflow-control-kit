[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$memoryPath = Join-Path $env:USERPROFILE ".memory\MEMORY.md"
$errorLessonsPath = Join-Path $env:USERPROFILE ".memory\error-lessons.md"
$rule1 = "RULE: batch op (2+ files) => re-read MEMORY.md first. Fail 2x => switch strategy."
$rule2 = "RULE: 4-platform sync MUST also update guide doc."

if ($env:CLAUDE_HOOK_EVENT -eq "SessionStart") {
    $output = @()
    $output += "[memory-inject] === Error Memory ==="
    if (Test-Path $memoryPath) {
        $output += Get-Content $memoryPath -Encoding UTF8 -Raw
    }
    if (Test-Path $errorLessonsPath) {
        $output += Get-Content $errorLessonsPath -Encoding UTF8 -Raw
    }
    $output += "=== END ==="
    $output += $rule1
    $output += $rule2
    $text = $output -join "`n"
    [Console]::Write($text)
} else {
    [Console]::Write("[memory-inject] $rule1 | $rule2")
}
exit 0
