#!/usr/bin/env node
'use strict';

const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

function run(args, options = {}) {
  return childProcess.execFileSync(process.execPath, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    stdio: 'pipe',
    windowsHide: true,
  });
}

function runExpectFailure(args, options = {}) {
  try {
    run(args, options);
    throw new Error('command unexpectedly passed');
  } catch (error) {
    if (error.message === 'command unexpectedly passed') throw error;
    return String(error.stdout || '') + String(error.stderr || '');
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(`FAIL: ${message}`);
  console.log(`PASS: ${message}`);
}

const repoRoot = path.resolve(__dirname, '..');
const script = path.join(repoRoot, 'scripts', 'verify-control-contracts.js');
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'aiw-control-contracts-'));

try {
  const output = run([script], { cwd: repoRoot });
  assert(/Control contract verification passed/.test(output), 'default control contracts verify');

  const badGoalSpec = path.join(tempRoot, 'bad-goalspec.yaml');
  fs.writeFileSync(badGoalSpec, [
    'target: "REQ-1"',
    'desired_outcome: "mr_draft"',
    'success_criteria:',
    '  - "done"',
    'stop_policy:',
    '  ask_on_high_risk: true',
    '  ask_before_schema_change: true',
    '  ask_on_credentials_or_secrets: true',
    '  no_merge: false',
    'budget:',
    '  max_minutes: 0',
    '  max_steps: 1',
    'audit:',
    '  record_decisions: true',
    '  record_verification: true',
    '  record_stop_reason: true',
    '',
  ].join('\n'), 'utf8');
  const badGoalOutput = runExpectFailure([script, '--goal-spec', badGoalSpec], { cwd: repoRoot });
  assert(/goalspec:stop-policy-true/.test(badGoalOutput), 'bad GoalSpec fails on unsafe stop policy');
  assert(/goalspec:budget/.test(badGoalOutput), 'bad GoalSpec fails on budget');

  const weakLock = path.join(tempRoot, '.skill-lock.json');
  fs.writeFileSync(weakLock, JSON.stringify({
    version: 3,
    skills: {
      demo: {
        source: 'owner/repo',
        sourceType: 'github',
        sourceUrl: 'https://github.com/owner/repo.git',
        skillPath: 'skills/demo/SKILL.md',
        skillFolderHash: '',
      },
    },
  }, null, 2), 'utf8');

  const weakDefault = run([script, '--skill-lock', weakLock], { cwd: repoRoot });
  assert(/WARN: skill-lock:hash-integrity/.test(weakDefault), 'weak lock warns by default');

  const weakStrict = runExpectFailure([script, '--skill-lock', weakLock, '--strict-skill-lock'], { cwd: repoRoot });
  assert(/FAIL: skill-lock:hash-integrity/.test(weakStrict), 'weak lock fails in strict mode');
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
