# Regression tests for v317 STOP_AND_EVOLVE tooling evolution
# Tests the three priority experiments: Exact Contract, RED Phase, Side Effect Ledger

Describe "v317-StopAndEvolve-Tooling" {
    BeforeAll {
        $ScriptRoot = $PSScriptRoot
        $ScriptsRoot = Join-Path $ScriptRoot ".." -Resolve
        $Python = "python"
        $TestRepo = "D:\opt\claim"
        $TestWorktree = "D:\opt\claim\.git\worktrees\test-worktree"
    }

    Context "Priority 1: Exact Contract Pre-Binding" {
        It "extract_oracle_contracts.py script exists" {
            $scriptPath = Join-Path $ScriptsRoot "extract_oracle_contracts.py"
            Test-Path $scriptPath | Should -Be $true
        }

        It "extract_oracle_contracts.py has valid Python syntax" {
            $scriptPath = Join-Path $ScriptsRoot "extract_oracle_contracts.py"
            $result = & $Python -m py_compile $scriptPath 2>&1
            $LASTEXITCODE | Should -Be 0
        }

        It "extract_oracle_contracts.py shows help when run without args" {
            $scriptPath = Join-Path $ScriptsRoot "extract_oracle_contracts.py"
            $output = & $Python $scriptPath 2>&1
            $output | Should -Match "Usage:"
        }
    }

    Context "Priority 2: RED Phase Hard Gate" {
        It "enforce_red_phase_gate.py script exists" {
            $scriptPath = Join-Path $ScriptsRoot "enforce_red_phase_gate.py"
            Test-Path $scriptPath | Should -Be $true
        }

        It "enforce_red_phase_gate.py has valid Python syntax" {
            $scriptPath = Join-Path $ScriptsRoot "enforce_red_phase_gate.py"
            $result = & $Python -m py_compile $scriptPath 2>&1
            $LASTEXITCODE | Should -Be 0
        }

        It "enforce_red_phase_gate.py shows help when run without args" {
            $scriptPath = Join-Path $ScriptsRoot "enforce_red_phase_gate.py"
            $output = & $Python $scriptPath 2>&1
            $output | Should -Match "Usage:"
        }

        It "Can create a test file with behavioral assertions" {
            $testDir = Join-Path $ScriptRoot ".tmp\behavioral-test"
            New-Item -ItemType Directory -Force -Path $testDir | Out-Null

            $testContent = @"
package com.example.project.test;

import org.junit.Test;
import org.junit.Assert;
import org.mockito.Mockito;

public class BehavioralTest {
    @Test
    public void testAutoFlow_Success() {
        // Arrange
        Long caseId = 12345L;

        // Act
        aiAutoClaimFlowService.handle(caseId, task);

        // Assert - Verify DB state change
        CompensateDetail detail = compensateDetailMapper.selectByCaseId(caseId);
        Assert.assertEquals("理算状态应该正确", "35", detail.getStatus());

        // Assert - Verify task created
        Assert.assertNotNull(taskMapper.selectByCaseId(caseId));
    }
}
"@

            $testFile = Join-Path $testDir "BehavioralTest.java"
            Set-Content -Path $testFile -Value $testContent

            $scriptPath = Join-Path $ScriptsRoot "enforce_red_phase_gate.py"
            $output = & $Python $scriptPath "analyze" $testFile 2>&1
            $json = $output | ConvertFrom-Json

            $json.behavioral_count | Should -BeGreaterThan 0
            $json.red_phase_compliant | Should -Be $true

            # Cleanup
            Remove-Item -Recurse -Force $testDir -ErrorAction SilentlyContinue
        }

        It "Rejects test file with only structural assertions" {
            $testDir = Join-Path $ScriptRoot ".tmp\structural-test"
            New-Item -ItemType Directory -Force -Path $testDir | Out-Null

            $testContent = @"
package com.example.project.test;

import org.junit.Test;

public class StructuralTest {
    @Test
    public void testClassExists() {
        // This only tests structure, not behavior
        ExampleFlowService service = new ExampleFlowService();
        Assert.assertNotNull(service);
    }

    @Test(expected = ClassNotFoundException.class)
    public void testMethodMissing() throws ClassNotFoundException {
        Class.forName("com.example.project.NonExistentClass");
    }
}
"@

            $testFile = Join-Path $testDir "StructuralTest.java"
            Set-Content -Path $testFile -Value $testContent

            $scriptPath = Join-Path $ScriptsRoot "enforce_red_phase_gate.py"
            $output = & $Python $scriptPath "analyze" $testFile 2>&1
            $json = $output | ConvertFrom-Json

            $json.red_phase_compliant | Should -Be $false
            $json.violations | Should -Contain "all_tests_structural"

            # Cleanup
            Remove-Item -Recurse -Force $testDir -ErrorAction SilentlyContinue
        }
    }

    Context "Priority 3: Side Effect Ledger Enforcement" {
        It "enforce_side_effect_ledger.py script exists" {
            $scriptPath = Join-Path $ScriptsRoot "enforce_side_effect_ledger.py"
            Test-Path $scriptPath | Should -Be $true
        }

        It "enforce_side_effect_ledger.py has valid Python syntax" {
            $scriptPath = Join-Path $ScriptsRoot "enforce_side_effect_ledger.py"
            $result = & $Python -m py_compile $scriptPath 2>&1
            $LASTEXITCODE | Should -Be 0
        }

        It "enforce_side_effect_ledger.py shows help when run without args" {
            $scriptPath = Join-Path $ScriptsRoot "enforce_side_effect_ledger.py"
            $output = & $Python $scriptPath 2>&1
            $output | Should -Match "Usage:"
        }

        It "Detects TODO placeholders in test file" {
            $testDir = Join-Path $ScriptRoot ".tmp\todo-test"
            New-Item -ItemType Directory -Force -Path $testDir | Out-Null

            $testContent = @"
package com.example.project.test;

import org.junit.Test;

public class TodoTest {
    @Test
    public void testWithTodo() {
        // TODO: 实际数据库插入
        // Placeholder for PNG upload
        aiAutoClaimFlowService.handle(caseId, task);
    }
}
"@

            $testFile = Join-Path $testDir "TodoTest.java"
            Set-Content -Path $testFile -Value $testContent

            $scriptPath = Join-Path $ScriptsRoot "enforce_side_effect_ledger.py"
            $output = & $Python $scriptPath "check-todos" $testFile 2>&1
            $json = $output | ConvertFrom-Json

            $json.has_todo_placeholders | Should -Be $true

            # Cleanup
            Remove-Item -Recurse -Force $testDir -ErrorAction SilentlyContinue
        }
    }

    Context "Integration: All three gates work together" {
        It "All Priority scripts exist and are valid Python" {
            $scripts = @(
                "extract_oracle_contracts.py",
                "enforce_red_phase_gate.py",
                "enforce_side_effect_ledger.py"
            )

            foreach ($script in $scripts) {
                $scriptPath = Join-Path $ScriptsRoot $script
                Test-Path $scriptPath | Should -Be $true
                & $Python -m py_compile $scriptPath 2>&1
                $LASTEXITCODE | Should -Be 0
            }
        }
    }
}
