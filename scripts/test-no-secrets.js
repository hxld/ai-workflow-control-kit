#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const failures = [];
const forbiddenNames = new Set(['auth.json', 'settings.local.json', 'history.jsonl', 'session_index.jsonl']);
const allowedEnvFiles = new Set([path.normalize('agents/skills/log-investigator/.env')]);
const skipDirs = new Set(['.git', '.memory', 'node_modules']);

function walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    const rel = path.relative(root, full);
    const parts = rel.split(path.sep);
    if (parts.some((part) => skipDirs.has(part))) continue;
    if (entry.isDirectory()) walk(full);
    else checkFile(full, rel);
  }
}

function checkFile(full, rel) {
  const normalizedRel = path.normalize(rel);
  const name = path.basename(full);
  const ext = path.extname(full).toLowerCase();
  const stat = fs.statSync(full);

  if (name === '.env' && !allowedEnvFiles.has(normalizedRel)) {
    failures.push(`forbidden file: ${rel}`);
    return;
  }
  if (forbiddenNames.has(name)) {
    failures.push(`forbidden file: ${rel}`);
    return;
  }
  if (['.sqlite', '.db', '.log'].includes(ext)) {
    failures.push(`forbidden extension: ${rel}`);
    return;
  }
  if (stat.size > 5 * 1024 * 1024) {
    failures.push(`large file >5MB: ${rel}`);
    return;
  }

  let text = '';
  try {
    text = fs.readFileSync(full, 'utf8');
  } catch {
    return;
  }

  const secretPattern = /(ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|GITHUB_TOKEN|GH_TOKEN|GITHUB_PERSONAL_ACCESS_TOKEN)\s*[:=]\s*["']?(?!<SET_ON_NEW_MACHINE>|$)[A-Za-z0-9_.-]{16,}/i;
  if (secretPattern.test(text)) failures.push(`secret-like token: ${rel}`);

  const concreteUserPathPattern = /C:[\\/]+Users[\\/]+(?!<USER>|<USERPROFILE>|%USERPROFILE%|%USERNAME%|\$HOME|\$env:USERPROFILE)[A-Za-z0-9._-]+/i;
  if (concreteUserPathPattern.test(text)) failures.push(`concrete Windows user path: ${rel}`);

  if (name === '.env' || name === '.env.example') {
    for (const line of text.split(/\r?\n/)) {
      if (/^\s*#/.test(line) || !line.includes('=')) continue;
      const [rawKey, ...rest] = line.split('=');
      const key = rawKey.trim();
      const value = rest.join('=').trim();
      if (/(PASSWORD|TOKEN|SECRET|AUTH|CREDENTIAL|API_KEY|USERNAME)/i.test(key) && value && value !== '<SET_ON_NEW_MACHINE>') {
        failures.push(`credential value must be placeholder: ${rel}`);
      }
    }
  }
}

walk(root);

if (failures.length > 0) {
  console.log('Secret scan failed:');
  for (const failure of failures) console.log(` - ${failure}`);
  process.exit(1);
}

console.log('PASS: no forbidden secrets or runtime state files found');
