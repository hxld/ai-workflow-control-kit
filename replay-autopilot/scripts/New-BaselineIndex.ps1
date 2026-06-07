param(
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [string]$RequirementSource,
    [Parameter(Mandatory = $true)]
    [string]$OutPath,
    [string]$ProjectRoot = '',
    [string]$BaseCommit = '',
    [string]$RunLabel = '',
    [string]$RoundId = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$Path
    )
    $base = (Resolve-AbsolutePath $BasePath).TrimEnd('\') + '\'
    $full = Resolve-AbsolutePath $Path
    if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($base.Length)
    }
    return $full
}

function Get-FileDigestLine {
    param(
        [string]$Root,
        [string]$Path,
        [string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return "| $Label | missing |  |  |"
    }
    $item = Get-Item -LiteralPath $Path
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $lineCount = (Get-Content -LiteralPath $Path -Encoding UTF8 | Measure-Object).Count
    return "| $Label | $(Get-RelativePath -BasePath $Root -Path $Path) | $lineCount | $($hash.Substring(0, 16)) |"
}

function Count-FilesByExtension {
    param(
        [string]$Root,
        [string]$ModulePath
    )
    $extensions = @('.java', '.xml', '.ftl', '.jsp', '.js', '.properties', '.yml', '.yaml')
    $counts = [ordered]@{}
    foreach ($ext in $extensions) {
        $counts[$ext] = 0
    }

    Get-ChildItem -LiteralPath $ModulePath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\target\\' -and
            $_.FullName -notmatch '\\.git\\' -and
            $extensions -contains $_.Extension.ToLowerInvariant()
        } |
        ForEach-Object {
            $ext = $_.Extension.ToLowerInvariant()
            $counts[$ext]++
        }

    $parts = foreach ($ext in $extensions) {
        if ($counts[$ext] -gt 0) { "$ext=$($counts[$ext])" }
    }
    if (-not $parts) { $parts = @('none') }
    return ($parts -join ', ')
}

$worktreeFull = Resolve-AbsolutePath $Worktree
$requirementFull = Resolve-AbsolutePath $RequirementSource
$outFull = Resolve-AbsolutePath $OutPath

if (-not (Test-Path -LiteralPath $worktreeFull)) {
    throw "Worktree not found: $worktreeFull"
}
if (-not (Test-Path -LiteralPath $requirementFull)) {
    throw "Requirement source not found: $requirementFull"
}

$repoRules = @(
    @{ Label = 'worktree AGENTS.md'; Path = (Join-Path $worktreeFull 'AGENTS.md'); Root = $worktreeFull },
    @{ Label = 'worktree CLAUDE.md'; Path = (Join-Path $worktreeFull 'CLAUDE.md'); Root = $worktreeFull },
    @{ Label = 'worktree .memory/build-test-profile.yaml'; Path = (Join-Path $worktreeFull '.memory\build-test-profile.yaml'); Root = $worktreeFull }
)
if (-not [string]::IsNullOrWhiteSpace($ProjectRoot) -and (Test-Path -LiteralPath $ProjectRoot)) {
    $projectRootFull = Resolve-AbsolutePath $ProjectRoot
    $repoRules += @(
        @{ Label = 'project AGENTS.md'; Path = (Join-Path $projectRootFull 'AGENTS.md'); Root = $projectRootFull },
        @{ Label = 'project CLAUDE.md'; Path = (Join-Path $projectRootFull 'CLAUDE.md'); Root = $projectRootFull },
        @{ Label = 'project .memory/build-test-profile.yaml'; Path = (Join-Path $projectRootFull '.memory\build-test-profile.yaml'); Root = $projectRootFull }
    )
}

$digestLines = New-Object System.Collections.Generic.List[string]
$digestLines.Add((Get-FileDigestLine -Root $worktreeFull -Path $requirementFull -Label 'requirement_source'))
foreach ($rule in $repoRules) {
    $digestLines.Add((Get-FileDigestLine -Root $rule.Root -Path $rule.Path -Label $rule.Label))
}

$headingLines = @()
Select-String -LiteralPath $requirementFull -Encoding UTF8 -Pattern '^\s{0,3}#{1,6}\s+(.+)$' |
    Select-Object -First 80 |
    ForEach-Object {
        $heading = $_.Line.Trim()
        $headingLines += "- L$($_.LineNumber): $heading"
    }
if ($headingLines.Count -eq 0) {
    $headingLines = @('- none detected')
}

$moduleRows = @()
Get-ChildItem -LiteralPath $worktreeFull -Directory -Filter 'claim-*' |
    Sort-Object Name |
    ForEach-Object {
        $moduleRows += "| $($_.Name) | $(Count-FilesByExtension -Root $worktreeFull -ModulePath $_.FullName) |"
    }
if ($moduleRows.Count -eq 0) {
    $moduleRows = @('| none | none |')
}

$testCharterTemplate = @"
## Test Charter Template (MANDATORY for all slices)

Location: `{replay_root}/worktree/TEST_CHARTER.md`

### Required Sections

1. **Test Scenarios**: Minimum 3 scenarios
   - Happy path: Normal flow, all data valid
   - Error path: Validation fails, business assertion fails
   - Edge case: Boundary conditions, null inputs

2. **Entry Point Specification**:
   - Facade/Controller method (not Service)
   - Parameter types and values
   - Expected return type

3. **DB State Verification** (for each scenario):
   - Query to verify state after transaction
   - Expected table rows (t_compensate_info, t_task, etc.)
   - Columns to verify

4. **Transaction Rollback Test**:
   - Scenario that triggers rollback
   - Verify no partial writes

5. **Side Effect Verification**:
   - File creation: Verify file exists
   - External call: Verify mock interaction
   - Log entries: Verify log output

### Example Template

~~~markdown
# Test Charter: {ServiceName}.{MethodName}()

## Test Scenarios

### Scenario 1: Happy Path - {Description}

**Entry Point**: `{FacadeName}.{MethodName}({Parameters})`

**Given**:
- {Precondition 1}
- {Precondition 2}

**When**: `{MethodName}` is called

**Then**:
- {Expected result 1}
- {Expected result 2}

**DB Verification**:
~~~sql
{SQL query to verify state}
-- Expect: {expected results}
~~~

**Transaction Test**:
~~~java
@Test(expected = {ExceptionType}.class)
public void test{MethodName}_{ErrorCondition}_ThrowsException() {
    // Given invalid input
    // When method called
    // Then throws exception and no DB writes
    // Verify: SELECT ... returns 0 rows
}
~~~
~~~

### Verification Rules

Before writing tests:
1. Copy TEST_CHARTER.md template to worktree root
2. Fill in all required sections
3. Verify: Test charter must pass validation
4. Tests will NOT be verified if charter is missing or incomplete
"@

$index = @"
# Baseline Index

- generated_at: $(Get-Date -Format s)
- mode: neutral_structure_cache
- run_label: $RunLabel
- round: $RoundId
- base_commit: $BaseCommit
- worktree: $worktreeFull
- requirement_source: $requirementFull

## Neutrality Contract

This file is allowed in strict blind replay only as a neutral index. It must not contain prior replay conclusions, oracle evidence, selected entries, rejected-entry decisions, expected implementation choices, or gap summaries.

Allowed content:

- source digests and line counts
- requirement headings
- top-level module/file-family counts
- copy-ready commands to regenerate the same neutral facts from allowed sources
- test charter template (neutral format guidance, not implementation-specific content)

Forbidden content:

- selected real entry or core path
- previous replay gaps or scores
- oracle-derived file families or target diff names
- implementation recommendations
- DONE/PARTIAL judgments

## Source Digests

| source | path | lines | sha256-16 |
| --- | --- | ---: | --- |
$($digestLines -join "`n")

## Requirement Headings

$($headingLines -join "`n")

## Module File-Family Counts

| module | file-family counts |
| --- | --- |
$($moduleRows -join "`n")

## Test Charter Template (MANDATORY for all slices)

$testCharterTemplate

## Regeneration Commands

~~~powershell
Get-FileHash -LiteralPath "$requirementFull" -Algorithm SHA256
Select-String -LiteralPath "$requirementFull" -Encoding UTF8 -Pattern '^\s{0,3}#{1,6}\s+(.+)$'
Get-ChildItem -LiteralPath "$worktreeFull" -Directory -Filter 'claim-*'
rg --files "$worktreeFull" --glob 'claim-*/src/main/**' --glob '!**/target/**'
~~~
"@

$dir = Split-Path -Parent $outFull
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Content -LiteralPath $outFull -Value $index -Encoding UTF8
Write-Host "Wrote baseline index: $outFull"
