#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const home = os.homedir();

function log(message) {
  try {
    const logDir = path.join(home, '.agents', 'logs');
    fs.mkdirSync(logDir, { recursive: true });
    const stamp = new Date().toISOString().replace('T', ' ').replace(/\..+$/, '');
    fs.appendFileSync(path.join(logDir, 'skill-hooks.log'), `[${stamp}][claude-node] ${message}\n`, 'utf8');
  } catch {
    // Hook logging must never block the host.
  }
}

function readStdin() {
  return fs.readFileSync(0, 'utf8');
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function realPathIfExists(value) {
  if (!value) return '';
  try {
    return fs.realpathSync(value);
  } catch {
    return value;
  }
}

function projectHash(projectDir) {
  if (!projectDir) return '';
  return crypto.createHash('md5').update(projectDir.toLowerCase(), 'utf8').digest('hex');
}

function consumePendingReceipt(projectDir) {
  const receiptDir = path.join(home, '.agents', 'state', 'skill-feedback');
  if (!fs.existsSync(receiptDir)) return null;

  const candidates = [];
  const resolvedProjectDir = realPathIfExists(projectDir);
  const hash = projectHash(resolvedProjectDir);
  if (hash) candidates.push(path.join(receiptDir, `${hash}.json`));
  candidates.push(path.join(receiptDir, 'latest.json'));

  for (const candidate of [...new Set(candidates)]) {
    if (!fs.existsSync(candidate)) continue;
    try {
      const receipt = readJson(candidate);
      if (
        resolvedProjectDir &&
        receipt &&
        receipt.projectRoot &&
        realPathIfExists(receipt.projectRoot) !== resolvedProjectDir
      ) {
        continue;
      }
      fs.rmSync(candidate, { force: true });
      return receipt;
    } catch {
      try {
        fs.rmSync(candidate, { force: true });
      } catch {
        // Ignore cleanup failures.
      }
    }
  }

  return null;
}

function getPrompt(payload) {
  if (!payload || typeof payload !== 'object') return '';
  for (const key of ['prompt', 'message', 'userPrompt']) {
    if (typeof payload[key] === 'string' && payload[key].trim()) return payload[key];
  }
  return '';
}

function shouldSkipReadOnly(promptText) {
  const markers = [
    '不要修改',
    '不修改',
    '别修改',
    '不用修改',
    '不要动',
    '只读',
    '只解释',
    '解释一下',
    '说明一下',
  ];
  return markers.some((marker) => promptText.includes(marker));
}

function priorityLabel(priority) {
  const labels = {
    critical: 'critical',
    high: 'high',
    medium: 'medium',
  };
  return labels[priority] || priority || 'normal';
}

function findMatches(promptText, rules) {
  const lower = promptText.toLowerCase();
  const skills = rules && rules.skills ? rules.skills : {};
  const matches = [];

  for (const [name, skill] of Object.entries(skills)) {
    const keywords = skill && skill.triggers && Array.isArray(skill.triggers.keywords)
      ? skill.triggers.keywords
      : [];

    for (const keyword of keywords) {
      if (!keyword) continue;
      if (lower.includes(String(keyword).toLowerCase())) {
        matches.push({
          name,
          priority: skill.priority || 'medium',
          description: skill.description || '',
          autoApply: Boolean(skill.auto_apply),
          trigger: keyword,
          feedbackSummary: skill.feedback_summary || '',
        });
        break;
      }
    }
  }

  return matches;
}

function uniqueByName(items) {
  const seen = new Set();
  const result = [];
  for (const item of items) {
    if (seen.has(item.name)) continue;
    seen.add(item.name);
    result.push(item);
  }
  return result.sort((a, b) => a.name.localeCompare(b.name));
}

function render(matches, receipt) {
  const lines = [];
  const uniqueMatches = uniqueByName(matches);
  const hasReceipt = receipt && Array.isArray(receipt.summaries) && receipt.summaries.length > 0;

  lines.push('-----------------------------------------');
  lines.push('HOOK skill hint');
  lines.push('-----------------------------------------');
  lines.push('');

  if (hasReceipt) {
    lines.push('Last confirmed effect:');
    for (const item of receipt.summaries) {
      lines.push(`  -> ${item.skillName || 'unknown'}: ${item.message || ''}`);
    }
    lines.push('');
  }

  if (uniqueMatches.length > 0) {
    lines.push('Matched skills:');
    for (const skill of uniqueMatches) {
      const mode = skill.autoApply ? 'auto-apply candidate' : 'suggest only';
      lines.push(`  -> ${skill.name} [${priorityLabel(skill.priority)}, ${mode}]`);
      lines.push(`     trigger: ${skill.trigger}`);
    }
    lines.push('');

    const withFeedback = uniqueMatches.filter((skill) => skill.feedbackSummary);
    if (withFeedback.length > 0) {
      lines.push('Planned visible effect:');
      for (const skill of withFeedback) {
        lines.push(`  -> ${skill.name}: ${skill.feedbackSummary}`);
      }
      lines.push('');
    }

    const autoApply = uniqueMatches.filter((skill) => skill.autoApply);
    const manual = uniqueMatches.filter((skill) => !skill.autoApply);
    const critical = manual.filter((skill) => skill.priority === 'critical');
    const high = manual.filter((skill) => skill.priority === 'high');
    const medium = manual.filter((skill) => skill.priority === 'medium');

    if (autoApply.length > 0 && critical.length === 0 && high.length === 0) {
      lines.push('Auto-apply candidates:');
      for (const skill of autoApply) lines.push(`  -> ${skill.name}: ${skill.description}`);
      lines.push('');
    }

    if (critical.length > 0) {
      lines.push('Critical suggestions:');
      for (const skill of critical) lines.push(`  -> ${skill.name}: ${skill.description}`);
      lines.push('');
    }

    if (high.length > 0) {
      lines.push('High-priority suggestions:');
      for (const skill of high) lines.push(`  -> ${skill.name}: ${skill.description}`);
      lines.push('');
    }

    if (medium.length > 0) {
      lines.push('Medium-priority suggestions:');
      for (const skill of medium) lines.push(`  -> ${skill.name}: ${skill.description}`);
      lines.push('');
    }

    lines.push('-----------------------------------------');
    lines.push('Action: use the matching skills when they fit the user request; ask before applying higher-risk workflow rules.');
    lines.push('-----------------------------------------');
  }

  return `${lines.join('\n')}\n`;
}

function main() {
  const rawInput = readStdin();
  if (!rawInput.trim()) {
    log('skip empty hook input');
    return;
  }

  let payload;
  try {
    payload = JSON.parse(rawInput);
  } catch {
    log('skip invalid hook json');
    return;
  }

  const promptText = getPrompt(payload);
  if (!promptText.trim()) {
    log('skip empty prompt');
    return;
  }

  if (shouldSkipReadOnly(promptText)) {
    log('skip read-only prompt marker');
    return;
  }

  const rulesPath = path.join(home, '.agents', 'skills', 'skill-rules.json');
  if (!fs.existsSync(rulesPath)) {
    log(`missing rules file: ${rulesPath}`);
    return;
  }

  let rules;
  try {
    rules = readJson(rulesPath);
  } catch (error) {
    log(`invalid rules json: ${error.message}`);
    return;
  }

  // Merge optional company-specific overlay (personal installs can simply omit this file)
  const companyRulesPath = path.join(path.dirname(rulesPath), 'skill-rules.company.json');
  if (fs.existsSync(companyRulesPath)) {
    try {
      const companyRules = readJson(companyRulesPath);
      if (companyRules && companyRules.skills) {
        rules.skills = { ...rules.skills, ...companyRules.skills };
        log('merged company-specific skill overlay');
      }
    } catch (error) {
      log(`skip company rules overlay: ${error.message}`);
    }
  }

  const projectDir = process.env.CLAUDE_PROJECT_DIR || payload.cwd || process.cwd();
  const matches = findMatches(promptText, rules);
  const receipt = consumePendingReceipt(projectDir);

  if (matches.length === 0 && !(receipt && Array.isArray(receipt.summaries) && receipt.summaries.length > 0)) {
    log('no matched skills');
    return;
  }

  if (matches.length > 0) {
    log(`matched skills: ${matches.map((item) => `${item.name} via [${item.trigger}]`).join(', ')}`);
  } else {
    log('show pending execution receipt');
  }

  process.stdout.write(render(matches, receipt));
}

try {
  main();
} catch (error) {
  log(`hook error: ${error && error.message ? error.message : String(error)}`);
  process.exit(0);
}
