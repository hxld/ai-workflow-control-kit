#!/usr/bin/env node
'use strict';

const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

function run(command, args, options = {}) {
  return childProcess.execFileSync(command, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    stdio: options.stdio || 'pipe',
    windowsHide: true,
  });
}

function assert(condition, message) {
  if (!condition) throw new Error(`FAIL: ${message}`);
  console.log(`PASS: ${message}`);
}

const repoRoot = path.resolve(__dirname, '..');
const script = path.join(repoRoot, 'scripts', 'start-requirement-workspace.js');
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'aiw-requirement-workspace-'));

try {
  const repoBase = path.join(tempRoot, 'repos');
  const baseDir = path.join(tempRoot, 'workspaces');
  const serviceRepo = path.join(repoBase, 'svc-a');
  fs.mkdirSync(serviceRepo, { recursive: true });

  run('git', ['init'], { cwd: serviceRepo });
  run('git', ['config', 'user.email', 'test@example.com'], { cwd: serviceRepo });
  run('git', ['config', 'user.name', 'Test User'], { cwd: serviceRepo });
  fs.writeFileSync(path.join(serviceRepo, 'README.md'), '# svc-a\n', 'utf8');
  run('git', ['add', 'README.md'], { cwd: serviceRepo });
  run('git', ['commit', '-m', 'init'], { cwd: serviceRepo });

  run('node', [
    script,
    'REQ-001',
    '--services',
    'svc-a',
    '--base-dir',
    baseDir,
    '--repo-base-dir',
    repoBase,
  ]);

  const workspace = path.join(baseDir, 'req-REQ-001');
  const worktree = path.join(workspace, 'services', 'svc-a');
  assert(fs.existsSync(path.join(workspace, 'req-manifest.yaml')), 'creates requirement manifest');
  assert(fs.existsSync(path.join(worktree, 'README.md')), 'creates service worktree');
  const branch = run('git', ['-C', worktree, 'branch', '--show-current']).trim();
  assert(branch === 'feature/req-REQ-001', 'creates branch inside worktree');
  const mainBranch = run('git', ['-C', serviceRepo, 'branch', '--show-current']).trim();
  assert(mainBranch !== 'feature/req-REQ-001', 'does not checkout requirement branch in source repo');
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}

