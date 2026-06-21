#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

function parseArgs(argv) {
  const options = {
    root: path.resolve(__dirname, '..'),
    skillLockPath: '',
    goalSpecPaths: [],
    strictSkillLock: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--root') options.root = path.resolve(argv[++i]);
    else if (arg === '--skill-lock') options.skillLockPath = argv[++i];
    else if (arg === '--goal-spec') options.goalSpecPaths.push(argv[++i]);
    else if (arg === '--strict-skill-lock') options.strictSkillLock = true;
    else if (arg === '--help' || arg === '-h') {
      console.log(`Usage: node scripts/verify-control-contracts.js [options]

Options:
  --root <path>             Repository root. Defaults to this repository.
  --skill-lock <path>       Skill lock file. Defaults to agents/.skill-lock.json.
  --goal-spec <path>        GoalSpec YAML file. Can be repeated.
  --strict-skill-lock       Treat missing or non-SHA hashes as failures.`);
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!options.skillLockPath) {
    options.skillLockPath = path.join(options.root, 'agents', '.skill-lock.json');
  } else {
    options.skillLockPath = path.resolve(options.skillLockPath);
  }

  if (options.goalSpecPaths.length === 0) {
    options.goalSpecPaths.push(path.join(
      options.root,
      'agents',
      'skills',
      'goal-mode',
      'templates',
      'goalspec-autonomous-task.yaml',
    ));
  } else {
    options.goalSpecPaths = options.goalSpecPaths.map((entry) => path.resolve(entry));
  }

  return options;
}

let failures = 0;
let warnings = 0;

function writeCheck(name, ok, detail = '', warning = false) {
  const prefix = ok ? 'PASS' : warning ? 'WARN' : 'FAIL';
  console.log(detail ? `${prefix}: ${name} - ${detail}` : `${prefix}: ${name}`);
  if (!ok && warning) warnings += 1;
  if (!ok && !warning) failures += 1;
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function checkSkillLock(filePath, strict) {
  writeCheck('skill-lock:file-exists', fs.existsSync(filePath), filePath);
  if (!fs.existsSync(filePath)) return;

  let lock;
  try {
    lock = loadJson(filePath);
    writeCheck('skill-lock:json-parse', true, filePath);
  } catch (error) {
    writeCheck('skill-lock:json-parse', false, error.message);
    return;
  }

  const skills = lock && typeof lock.skills === 'object' && lock.skills ? lock.skills : null;
  const names = skills ? Object.keys(skills) : [];
  writeCheck('skill-lock:skills-present', names.length > 0, `${names.length} skill entries`);
  if (!skills) return;

  const allowedSourceTypes = new Set(['github', 'git', 'local']);
  const missingRequired = [];
  const invalidSourceTypes = [];
  const missingHashes = [];
  const invalidHashes = [];

  for (const name of names) {
    const entry = skills[name] || {};
    for (const field of ['source', 'sourceType', 'skillPath']) {
      if (!String(entry[field] || '').trim()) missingRequired.push(`${name}.${field}`);
    }
    if (entry.sourceType && !allowedSourceTypes.has(entry.sourceType)) {
      invalidSourceTypes.push(`${name}.${entry.sourceType}`);
    }

    const hashField = Object.prototype.hasOwnProperty.call(entry, 'computedHash')
      ? 'computedHash'
      : Object.prototype.hasOwnProperty.call(entry, 'skillFolderHash')
        ? 'skillFolderHash'
        : '';
    const hash = hashField ? String(entry[hashField] || '').trim() : '';
    if (!hash) {
      missingHashes.push(`${name}.${hashField || 'hash'}`);
    } else if (!/^(sha256:)?[a-f0-9]{64}$/i.test(hash)) {
      invalidHashes.push(`${name}.${hashField}`);
    }
  }

  writeCheck(
    'skill-lock:required-fields',
    missingRequired.length === 0,
    missingRequired.slice(0, 5).join('; ') || 'source/sourceType/skillPath present',
  );
  writeCheck(
    'skill-lock:source-types',
    invalidSourceTypes.length === 0,
    invalidSourceTypes.slice(0, 5).join('; ') || 'github/git/local',
  );

  const hashOk = missingHashes.length === 0 && invalidHashes.length === 0;
  const hashDetail = hashOk
    ? 'all entries have SHA-256 style hashes'
    : `missing=${missingHashes.length}, invalid=${invalidHashes.length}`;
  writeCheck('skill-lock:hash-integrity', hashOk, hashDetail, !strict);
}

function stripQuotes(value) {
  const trimmed = String(value || '').trim();
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function parseScalar(value) {
  const stripped = stripQuotes(value);
  if (/^(true|false)$/i.test(stripped)) return /^true$/i.test(stripped);
  if (/^\d+$/.test(stripped)) return Number(stripped);
  return stripped;
}

function extractYaml(text) {
  const match = text.match(/```ya?ml\s*([\s\S]*?)```/i);
  return match ? match[1] : text;
}

function parseLiteYaml(text) {
  const result = {};
  let currentKey = '';

  for (const rawLine of extractYaml(text).split(/\r?\n/)) {
    const line = rawLine.replace(/\s+#.*$/, '');
    if (!line.trim() || line.trim().startsWith('#')) continue;

    const top = line.match(/^([A-Za-z_][A-Za-z0-9_-]*):(?:\s*(.*))?$/);
    if (top) {
      currentKey = top[1];
      const value = top[2] || '';
      result[currentKey] = value.trim() ? parseScalar(value) : {};
      continue;
    }

    if (!currentKey) continue;
    const item = line.match(/^\s+-\s+(.+)$/);
    if (item) {
      if (!Array.isArray(result[currentKey])) result[currentKey] = [];
      result[currentKey].push(parseScalar(item[1]));
      continue;
    }

    const nested = line.match(/^\s+([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$/);
    if (nested) {
      if (!result[currentKey] || Array.isArray(result[currentKey]) || typeof result[currentKey] !== 'object') {
        result[currentKey] = {};
      }
      result[currentKey][nested[1]] = parseScalar(nested[2]);
    }
  }

  return result;
}

function hasPositiveInteger(object, field) {
  return Number.isInteger(object[field]) && object[field] > 0;
}

function checkGoalSpec(filePath) {
  writeCheck('goalspec:file-exists', fs.existsSync(filePath), filePath);
  if (!fs.existsSync(filePath)) return;

  let spec;
  try {
    spec = parseLiteYaml(fs.readFileSync(filePath, 'utf8'));
    writeCheck('goalspec:parse-lite-yaml', true, filePath);
  } catch (error) {
    writeCheck('goalspec:parse-lite-yaml', false, error.message);
    return;
  }

  const requiredTopLevel = ['target', 'desired_outcome', 'success_criteria', 'stop_policy', 'budget', 'audit'];
  const missingTopLevel = requiredTopLevel.filter((field) => spec[field] === undefined);
  writeCheck('goalspec:required-top-level', missingTopLevel.length === 0, missingTopLevel.join(', ') || requiredTopLevel.join(', '));

  const allowedOutcomes = new Set(['mr_draft', 'implementation_complete', 'verified_fix', 'release', 'report']);
  writeCheck(
    'goalspec:desired-outcome',
    allowedOutcomes.has(spec.desired_outcome),
    `value=${spec.desired_outcome}; allowed=${Array.from(allowedOutcomes).join('|')}`,
  );

  writeCheck(
    'goalspec:success-criteria',
    Array.isArray(spec.success_criteria) && spec.success_criteria.length > 0,
    Array.isArray(spec.success_criteria) ? `${spec.success_criteria.length} entries` : 'not a non-empty list',
  );

  const stopPolicy = spec.stop_policy || {};
  const requiredStopPolicy = ['ask_on_high_risk', 'ask_before_schema_change', 'ask_on_credentials_or_secrets', 'no_merge'];
  const missingStopPolicy = requiredStopPolicy.filter((field) => typeof stopPolicy[field] !== 'boolean');
  writeCheck('goalspec:stop-policy-booleans', missingStopPolicy.length === 0, missingStopPolicy.join(', ') || requiredStopPolicy.join(', '));

  const unsafeStopPolicy = requiredStopPolicy.filter((field) => stopPolicy[field] !== true);
  writeCheck('goalspec:stop-policy-true', unsafeStopPolicy.length === 0, unsafeStopPolicy.join(', ') || requiredStopPolicy.join(', '));

  const budget = spec.budget || {};
  writeCheck(
    'goalspec:budget',
    hasPositiveInteger(budget, 'max_minutes') && hasPositiveInteger(budget, 'max_steps'),
    `max_minutes=${budget.max_minutes}, max_steps=${budget.max_steps}`,
  );

  const audit = spec.audit || {};
  const requiredAudit = ['record_decisions', 'record_verification', 'record_stop_reason'];
  const missingAudit = requiredAudit.filter((field) => audit[field] !== true);
  writeCheck('goalspec:audit', missingAudit.length === 0, missingAudit.join(', ') || requiredAudit.join(', '));
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  checkSkillLock(options.skillLockPath, options.strictSkillLock);
  for (const goalSpecPath of options.goalSpecPaths) checkGoalSpec(goalSpecPath);

  if (failures > 0) {
    console.log(`Control contract verification failed with ${failures} failure(s) and ${warnings} warning(s).`);
    process.exit(1);
  }
  console.log(`Control contract verification passed with ${warnings} warning(s).`);
}

try {
  main();
} catch (error) {
  console.error(`FAIL: verify-control-contracts - ${error.message}`);
  process.exit(1);
}
