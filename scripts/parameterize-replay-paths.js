#!/usr/bin/env node
/**
 * parameterize-replay-paths.js
 *
 * Stage 2 portability pass for replay-autopilot: replace hardcoded
 * D:\opt\* paths with env-var-driven defaults ($PSScriptRoot for
 * repo-relative resources in .ps1; relative/placeholder in .md; shell
 * env vars in .sh).
 *
 * Env contract:
 *   AI_WORKFLOW_PROJECT_ROOT          -> was D:\opt\claim
 *   AI_WORKFLOW_REPLAY_EVIDENCE_ROOT  -> was D:\opt\replay-evidence
 *   AI_WORKFLOW_REPLAY_ROOT           -> was D:\opt (parent; rare)
 *
 * Repo-relative resources resolve via $PSScriptRoot (.ps1) or .\ (.md
 * command examples, assuming cwd = replay-autopilot root).
 *
 * Usage:
 *   node scripts/parameterize-replay-paths.js --dry-run
 *   node scripts/parameterize-replay-paths.js --write
 */
'use strict';

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const replayRoot = path.join(repoRoot, 'replay-autopilot');

const args = process.argv.slice(2);
const write = args.includes('--write');

function norm(p) { return p.split(path.sep).join('/'); }

function listFiles(dir, exts, out) {
  out = out || [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) listFiles(full, exts, out);
    else if (exts.includes(path.extname(entry.name))) out.push(full);
  }
  return out;
}

// Skip lines that are author-local fixture DATA or semantic assertions.
const skipLineRe = /changed_files:|Assert-True|\[regex\]::Escape|-match\s+\[regex\]|Do not depend on D:\\opt/i;

const subMap = [
  ['D:\\opt\\replay-evidence', '$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT', true],
  ['D:\\opt\\claim', '$env:AI_WORKFLOW_PROJECT_ROOT', true],
  ['D:\\opt', '$env:AI_WORKFLOW_REPLAY_ROOT', true], // standalone parent (HistoryRoot)
];

// --- .ps1 processing (control-plane scripts + tests) ---
function processPs1(original) {
  const lines = original.split(/\r?\n/);
  const edits = [];
  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    if (!line.includes('D:\\opt')) continue;
    if (skipLineRe.test(line)) continue;
    const before = line;

    if (line.includes('D:\\opt\\replay-autopilot')) {
      line = line.replace(/(['"])D:\\opt\\replay-autopilot\\?([^'"]*)\1/g, (m, q, rest) => {
        if (!rest) return '(Split-Path $PSScriptRoot -Parent)';
        return `Join-Path (Split-Path $PSScriptRoot -Parent) '${rest}'`;
      });
      line = line.replace(/Set-Location\s+['"]D:\\opt\\replay-autopilot['"]/, 'Set-Location (Split-Path $PSScriptRoot -Parent)');
    }

    for (const [match, repl] of subMap) {
      const singleRe = new RegExp("'" + match.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + "([^']*)'", 'g');
      line = line.replace(singleRe, (m, rest) => `"${repl}${rest}"`);
      const doubleRe = new RegExp('"' + match.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '([^"]*)"', 'g');
      line = line.replace(doubleRe, (m, rest) => `"${repl}${rest}"`);
    }

    const looksDoc = /^\s*(#|\.|Path to|Root directory|Replay root:|current project|- )/i.test(line)
      || /default:|e\.g\.|must exist|should be invoked|Copy this folder|project codebase/i.test(line);
    if (looksDoc && line.includes('D:\\opt')) {
      line = line
        .replace(/D:\\opt\\replay-autopilot/g, '<REPLAY_AUTOPILOT_ROOT>')
        .replace(/D:\\opt\\replay-evidence/g, '<REPLAY_EVIDENCE_ROOT>')
        .replace(/D:\\opt\\claim/g, '<PROJECT_ROOT>')
        .replace(/D:\\opt\b/g, '<OPT_ROOT>');
    }

    if (line !== before) { edits.push({ line: i + 1, before: before.trim().slice(0, 70), after: line.trim().slice(0, 70) }); lines[i] = line; }
  }
  return { edits, content: lines.join(original.includes('\r\n') ? '\r\n' : '\n') };
}

// --- .md processing (README, prompts, EVOLUTION docs) ---
// Command examples assume cwd = replay-autopilot root, so repo script
// paths become .\scripts\... . Evidence/project roots use $env: (runnable
// in pasted PowerShell commands). Specific replay-run dirs -> placeholder.
function processMd(original) {
  const lines = original.split(/\r?\n/);
  const edits = [];
  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    if (!line.includes('D:\\opt')) continue;
    const before = line;
    // specific replay run dirs: D:\opt\claim-codex-replay-vNNN-...
    line = line.replace(/D:\\opt\\claim-codex-replay-v[0-9]+[a-zA-Z0-9_-]*/g, '<REPLAY_RUN_ROOT>');
    // repo script/tool refs in commands -> relative (cwd = autopilot root)
    line = line.replace(/D:\\opt\\replay-autopilot\\scripts\\/g, '.\\scripts\\');
    line = line.replace(/D:\\opt\\replay-autopilot\\/g, '<REPLAY_AUTOPILOT_ROOT>\\');
    // evidence / project roots -> env-var (runnable in PS commands)
    line = line.replace(/D:\\opt\\replay-evidence/g, '$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT');
    line = line.replace(/D:\\opt\\claim/g, '<PROJECT_ROOT>');
    line = line.replace(/D:\\opt\\/g, '<OPT_ROOT>\\');
    if (line !== before) { edits.push({ line: i + 1, before: before.trim().slice(0, 70), after: line.trim().slice(0, 70) }); lines[i] = line; }
  }
  return { edits, content: lines.join(original.includes('\r\n') ? '\r\n' : '\n') };
}

// --- .sh processing (shell scripts) ---
function processSh(original) {
  const lines = original.split(/\r?\n/);
  const edits = [];
  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    if (!line.includes('D:\\opt')) continue;
    const before = line;
    line = line.replace(/D:\\opt\\replay-autopilot/g, '$AI_WORKFLOW_REPLAY_AUTOPILOT_ROOT');
    line = line.replace(/D:\\opt\\claim/g, '$AI_WORKFLOW_PROJECT_ROOT');
    line = line.replace(/D:\\opt\\/g, '$AI_WORKFLOW_OPT_ROOT\\');
    if (line !== before) { edits.push({ line: i + 1, before: before.trim().slice(0, 70), after: line.trim().slice(0, 70) }); lines[i] = line; }
  }
  return { edits, content: lines.join(original.includes('\r\n') ? '\r\n' : '\n') };
}

const processors = { '.ps1': processPs1, '.md': processMd, '.sh': processSh };
const files = listFiles(replayRoot, ['.ps1', '.md', '.sh']);
const changes = [];
const remaining = [];

for (const full of files) {
  const rel = path.relative(replayRoot, full);
  const ext = path.extname(full);
  const original = fs.readFileSync(full, 'utf8');
  const { edits, content } = processors[ext](original);
  if (edits.length) changes.push({ file: rel, edits, content });
  // remaining
  const lines = content.split(/\r?\n/);
  lines.forEach((ln, i) => {
    if (ln.includes('D:\\opt')) remaining.push({ file: rel, line: i + 1, text: ln.trim().slice(0, 90) });
  });
}

console.log(`\n=== Parameterization ${write ? 'WRITE' : 'DRY-RUN'} ===\n`);
let total = 0;
for (const c of changes) {
  console.log(`📄 ${norm(c.file)}`);
  for (const e of c.edits) { console.log(`   L${e.line}: ${e.before}`); console.log(`       → ${e.after}`); total++; }
}
console.log(`\nFiles changed: ${changes.length}   Edits: ${total}`);
if (remaining.length) {
  console.log(`\n⚠️  Remaining D:\\opt (${remaining.length}):`);
  for (const r of remaining) console.log(`   ${norm(r.file)}:${r.line}  ${r.text}`);
} else console.log('\n✅ No remaining D:\\opt.');

if (write) {
  for (const c of changes) fs.writeFileSync(path.join(replayRoot, c.file), c.content, 'utf8');
  console.log(`\n✅ Wrote ${changes.length} files.`);
} else console.log('\n(dry-run — re-run with --write to apply.)');
