#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const MAX_RECENT_EDITS = 40;

function stripUtf8Bom(s) {
  if (typeof s !== 'string' || s.length === 0) return s;
  return s.charCodeAt(0) === 0xfeff ? s.slice(1) : s;
}

function readStdinJson() {
  try {
    const raw = stripUtf8Bom(fs.readFileSync(0, 'utf8'));
    return raw.trim() ? JSON.parse(raw.trim()) : {};
  } catch (e) {
    return {};
  }
}

function resolveProjectRoot(input) {
  const candidates = [];
  if (typeof input.workspaceRoot === 'string') candidates.push(input.workspaceRoot);
  if (typeof input.cwd === 'string') candidates.push(input.cwd);
  if (typeof input.projectDir === 'string') candidates.push(input.projectDir);
  if (typeof input.workspace === 'string') candidates.push(input.workspace);
  if (input.workspace && typeof input.workspace === 'object') {
    if (typeof input.workspace.root === 'string') candidates.push(input.workspace.root);
    if (typeof input.workspace.path === 'string') candidates.push(input.workspace.path);
  }

  for (const candidate of candidates) {
    try {
      if (candidate && fs.existsSync(candidate)) {
        return fs.realpathSync(candidate);
      }
    } catch (e) {}
  }
  return null;
}

function resolveEditedPath(input) {
  const candidates = [
    input.filePath,
    input.file_path,
    input.targetFile,
    input.target_file,
    input.path,
    input.file,
  ];

  for (const candidate of candidates) {
    try {
      if (typeof candidate === 'string' && candidate.trim()) {
        if (fs.existsSync(candidate)) return fs.realpathSync(candidate);
        return path.resolve(candidate);
      }
    } catch (e) {}
  }
  return null;
}

function ensureDir(dir) {
  try {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  } catch (e) {}
}

function getStatePath(projectRoot) {
  const stateDir = path.join(os.homedir(), '.cursor', 'hooks', 'state', 'workflow-sync');
  const hash = crypto.createHash('md5').update(projectRoot.toLowerCase()).digest('hex');
  ensureDir(stateDir);
  return path.join(stateDir, `${hash}.json`);
}

function readState(statePath) {
  try {
    return JSON.parse(fs.readFileSync(statePath, 'utf8'));
  } catch (e) {
    return {};
  }
}

function writeState(statePath, state) {
  try {
    fs.writeFileSync(statePath, JSON.stringify(state, null, 2), 'utf8');
  } catch (e) {}
}

function isUnderDir(filePath, dirPath) {
  const normalizedFile = path.normalize(filePath).toLowerCase();
  const normalizedDir = path.normalize(dirPath).toLowerCase();
  return normalizedFile === normalizedDir || normalizedFile.startsWith(normalizedDir + path.sep);
}

function classifyEdit(projectRoot, filePath) {
  if (!projectRoot || !filePath || !isUnderDir(filePath, projectRoot)) return null;

  const relativePath = path.relative(projectRoot, filePath);
  const normalized = relativePath.split(path.sep).join('/');
  const lower = normalized.toLowerCase();

  if (
    lower.startsWith('.cursor/') ||
    lower.startsWith('.claude/') ||
    lower.startsWith('.agents/') ||
    lower.startsWith('.git/') ||
    lower.startsWith('node_modules/') ||
    lower.startsWith('target/') ||
    lower.startsWith('logs/')
  ) {
    return null;
  }

  if (lower.startsWith('.doc/')) {
    return {
      category: 'doc',
      relativePath: normalized,
      fileName: path.basename(lower),
    };
  }

  if (lower.startsWith('openspec/')) {
    return {
      category: 'openspec',
      relativePath: normalized,
      fileName: path.basename(lower),
    };
  }

  if (lower.startsWith('.memory/')) {
    return {
      category: 'memory',
      relativePath: normalized,
      fileName: path.basename(lower),
    };
  }

  return {
    category: 'code',
    relativePath: normalized,
    fileName: path.basename(lower),
  };
}

function touchCategory(state, key, now, filePath) {
  state[key] = now;
  state.lastEditedPath = filePath;
}

function appendRecentEdit(state, edit, now) {
  const recentEdits = Array.isArray(state.recentEdits) ? state.recentEdits : [];
  recentEdits.push({
    at: now,
    category: edit.category,
    relativePath: edit.relativePath,
    fileName: edit.fileName,
  });
  state.recentEdits = recentEdits.slice(-MAX_RECENT_EDITS);
}

function main() {
  const input = readStdinJson();
  const projectRoot = resolveProjectRoot(input);
  const filePath = resolveEditedPath(input);
  if (!projectRoot || !filePath) process.exit(0);

  const edit = classifyEdit(projectRoot, filePath);
  if (!edit) process.exit(0);

  const statePath = getStatePath(projectRoot);
  const state = readState(statePath);
  const now = new Date().toISOString();

  state.projectRoot = projectRoot;
  state.lastSeenAt = now;
  appendRecentEdit(state, edit, now);

  switch (edit.category) {
    case 'code':
      touchCategory(state, 'lastCodeEditAt', now, edit.relativePath);
      break;
    case 'doc':
      touchCategory(state, 'lastDocEditAt', now, edit.relativePath);
      if (edit.fileName === 'tech-design.md') touchCategory(state, 'lastDocTechDesignEditAt', now, edit.relativePath);
      if (edit.fileName === 'task_plan.md') touchCategory(state, 'lastDocTaskPlanEditAt', now, edit.relativePath);
      if (edit.fileName === 'code-change.md') touchCategory(state, 'lastDocCodeChangeEditAt', now, edit.relativePath);
      break;
    case 'openspec':
      touchCategory(state, 'lastOpenSpecEditAt', now, edit.relativePath);
      break;
    case 'memory':
      touchCategory(state, 'lastMemoryEditAt', now, edit.relativePath);
      if (edit.fileName === 'progress.md') touchCategory(state, 'lastMemoryProgressEditAt', now, edit.relativePath);
      if (edit.fileName === 'findings.md') touchCategory(state, 'lastMemoryFindingsEditAt', now, edit.relativePath);
      break;
    default:
      break;
  }

  writeState(statePath, state);
}

main();
