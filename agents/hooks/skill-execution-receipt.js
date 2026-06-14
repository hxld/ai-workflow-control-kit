#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const WORKFLOW_STATE_DIR = path.join(os.homedir(), '.cursor', 'hooks', 'state', 'workflow-sync');
const CURSOR_SKILL_STATE_DIR = path.join(os.homedir(), '.cursor', 'hooks', 'state', 'skill-tracker');
const RECEIPT_DIR = path.join(os.homedir(), '.agents', 'state', 'skill-feedback');
const RECENT_EDIT_WINDOW_MS = 30 * 60 * 1000;

const SKILL_RECEIPT_RULES = {
  'pre-flight-check': {
    successPrefix: '已确认产出最近变更或验证痕迹到',
    missMessage: '已确认读取该技能；本回合它主要执行预检查，不一定产生新的落盘文件。',
  },
  'restore-context': {
    successPrefix: '已确认在恢复上下文时顺带更新到',
    missMessage: '已确认读取该技能；本回合它主要用于恢复上下文，不一定产生新的落盘文件。',
  },
  'dialogue-learning': {
    exactPaths: [
      '.memory/knowledge-gaps.md',
      '.memory/solution-patterns.md',
    ],
    successPrefix: '已确认实际落盘到',
    missMessage: '已读取该技能，但本回合未检测到 `knowledge-gaps.md` 或 `solution-patterns.md` 的新增落盘记录。',
  },
  'compound-learning': {
    categories: ['memory'],
    successPrefix: '已确认把学习结果落盘到',
    missMessage: '已读取该技能，但本回合未检测到新的 `.memory/` 落盘记录。',
  },
  'sync-progress': {
    pathPrefixes: ['.doc/', 'openspec/'],
    exactPaths: [
      '.memory/progress.md',
      '.memory/findings.md',
    ],
    successPrefix: '已确认同步更新到',
    missMessage: '已读取该技能，但本回合未检测到 `.doc/`、`openspec/` 或进度记忆文件的新增落盘记录。',
  },
  'workflow-router': {
    successPrefix: '已确认在流程选择后更新到',
    missMessage: '已确认读取该技能；本回合它主要用于选择下一步路径，不一定产生新的落盘文件。',
  },
  'dev-workflow': {
    pathPrefixes: ['.doc/', 'openspec/'],
    successPrefix: '已确认开发工作流产出到',
    missMessage: '已读取该技能；本回合它可能处于早期 phase，尚未产生 `.doc/` 或 `openspec/` 落盘记录。',
  },
  'auto-complete': {
    categories: ['code'],
    successPrefix: '已确认代码变更产生到',
    missMessage: '已读取该技能；auto-complete 模式产生代码变更，继续推进即可。',
  },
  'gen-tests': {
    categories: ['code'],
    successPrefix: '已确认测试产出到',
    missMessage: '已读取该技能；本回合未检测到新的测试文件落盘记录。',
  },
  'deep-review': {
    categories: ['doc'],
    successPrefix: '已确认审查发现落盘到',
    missMessage: '已读取该技能；deep-review 主要提供审查意见，不强制产生落盘文件。',
  },
  'deep-plan': {
    pathPrefixes: ['.doc/', 'openspec/'],
    successPrefix: '已确认规划产出到',
    missMessage: '已读取该技能；本回合未检测到 `.doc/` 或 `openspec/` 规划文件的新增落盘记录。',
  },
  'ship-release': {
    pathPrefixes: ['.doc/'],
    successPrefix: '已确认发布记录更新到',
    missMessage: '已读取该技能；本回合未检测到发布相关记录。',
  },
  'requirement-assessment': {
    categories: ['doc'],
    successPrefix: '已确认需求评估记录到',
    missMessage: '已读取该技能；本回合它主要用于评估需求，不一定产生新的落盘文件。',
  },
  'req-alignment-check': {
    categories: ['doc'],
    successPrefix: '已确认需求对齐检查记录到',
    missMessage: '已读取该技能；本回合未检测到需求对齐文件的新增落盘记录。',
  },
};

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

function readJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (e) {
    return fallback;
  }
}

function ensureDir(dir) {
  try {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  } catch (e) {}
}

function computeHash(input) {
  return crypto.createHash('md5').update(String(input || '').toLowerCase()).digest('hex');
}

function normalizePath(value) {
  return String(value || '').split(path.sep).join('/');
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

function loadWorkflowState(projectRoot) {
  if (projectRoot) {
    const exactPath = path.join(WORKFLOW_STATE_DIR, computeHash(projectRoot) + '.json');
    if (fs.existsSync(exactPath)) {
      const state = readJson(exactPath, null);
      if (state) return state;
    }
  }

  try {
    const stateFiles = fs.readdirSync(WORKFLOW_STATE_DIR)
      .filter(name => name.endsWith('.json'))
      .map(name => path.join(WORKFLOW_STATE_DIR, name))
      .map(filePath => ({
        filePath,
        stat: fs.statSync(filePath),
      }))
      .sort((a, b) => b.stat.mtimeMs - a.stat.mtimeMs);

    for (const item of stateFiles) {
      if (Date.now() - item.stat.mtimeMs <= RECENT_EDIT_WINDOW_MS) {
        const state = readJson(item.filePath, null);
        if (state) return state;
      }
    }
  } catch (e) {}

  return null;
}

function parseTranscript(transcriptPath) {
  try {
    return fs.readFileSync(transcriptPath, 'utf8')
      .trim()
      .split('\n')
      .map(line => {
        try {
          return JSON.parse(line);
        } catch (e) {
          return null;
        }
      })
      .filter(Boolean);
  } catch (e) {
    return [];
  }
}

function addSkillName(result, skillName) {
  const normalized = String(skillName || '').replace(/^[^/]+\//, '').trim();
  if (normalized) result.add(normalized);
}

function collectTranscriptSkills(messages) {
  const result = new Set();
  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i].message || messages[i];
    const content = msg.content;

    if (Array.isArray(content)) {
      for (const block of content) {
        if (!block) continue;
        if (block.type === 'tool_use' && block.name === 'Skill') {
          addSkillName(result, block.input && block.input.skill);
        }
        const text = typeof block.text === 'string' ? block.text : '';
        if (text.includes('<manually_attached_skills>')) {
          for (const match of text.matchAll(/Skill Name:\s*(\S+)/g)) {
            addSkillName(result, match[1]);
          }
        }
      }
    }

    if (typeof content === 'string') {
      if (content.includes('<manually_attached_skills>')) {
        for (const match of content.matchAll(/Skill Name:\s*(\S+)/g)) {
          addSkillName(result, match[1]);
        }
      }

      const slashMatch = content.match(/<command-name>\/([^<]+)<\/command-name>/);
      if (slashMatch) {
        for (let j = i + 1; j < Math.min(i + 4, messages.length); j++) {
          const next = messages[j].message || messages[j];
          const nextContent = next.content;
          const nextText = typeof nextContent === 'string'
            ? nextContent
            : Array.isArray(nextContent)
              ? nextContent.map(block => (block && block.text) || '').join('')
              : '';
          if (nextText.includes('Base directory for this skill:')) {
            addSkillName(result, slashMatch[1]);
            break;
          }
        }
      }
    }
  }
  return result;
}

function collectCursorImplicitSkills(input) {
  const cid = input.conversation_id || input.conversationId || input.session_id;
  if (!cid) return new Set();
  const statePath = path.join(CURSOR_SKILL_STATE_DIR, cid + '.json');
  const state = readJson(statePath, {});
  const result = new Set();
  for (const [skillName, info] of Object.entries(state.skills || {})) {
    if ((info && info.read_count > 0) || info) {
      addSkillName(result, skillName);
    }
  }
  return result;
}

function matchesRule(rule, edit) {
  const relativePath = normalizePath(edit.relativePath).toLowerCase();
  const category = String(edit.category || '').toLowerCase();

  if (Array.isArray(rule.exactPaths) && rule.exactPaths.some(item => item.toLowerCase() === relativePath)) {
    return true;
  }

  if (Array.isArray(rule.pathPrefixes) && rule.pathPrefixes.some(prefix => relativePath.startsWith(prefix.toLowerCase()))) {
    return true;
  }

  if (Array.isArray(rule.categories) && rule.categories.includes(category)) {
    return true;
  }

  return false;
}

function formatPathList(paths) {
  const unique = [...new Set(paths)];
  return unique.length > 0 ? unique.join('、') : '';
}

function buildReceiptSummaries(skills, workflowState) {
  const recentEdits = Array.isArray(workflowState && workflowState.recentEdits)
    ? workflowState.recentEdits.filter(edit => {
        const timestamp = Date.parse(edit.at || '');
        return !Number.isNaN(timestamp) && Date.now() - timestamp <= RECENT_EDIT_WINDOW_MS;
      })
    : [];

  const summaries = [];
  for (const skillName of skills) {
    const rule = SKILL_RECEIPT_RULES[skillName];
    if (!rule) continue;

    const matchedEdits = recentEdits.filter(edit => matchesRule(rule, edit));
    if (matchedEdits.length > 0) {
      const paths = matchedEdits.map(edit => normalizePath(edit.relativePath));
      summaries.push({
        skillName,
        status: 'persisted',
        message: `${rule.successPrefix} ${formatPathList(paths)}`,
        paths: [...new Set(paths)],
      });
      continue;
    }

    summaries.push({
      skillName,
      status: 'executed_no_persist',
      message: rule.missMessage,
      paths: [],
    });
  }

  return summaries;
}

function writeReceipt(projectRoot, receipt) {
  ensureDir(RECEIPT_DIR);
  const receiptPath = projectRoot
    ? path.join(RECEIPT_DIR, computeHash(projectRoot) + '.json')
    : path.join(RECEIPT_DIR, 'latest.json');
  fs.writeFileSync(receiptPath, JSON.stringify(receipt, null, 2), 'utf8');
}

function main() {
  const input = readStdinJson();
  const projectRoot = resolveProjectRoot(input);
  const workflowState = loadWorkflowState(projectRoot);
  if (!workflowState) return;

  const messages = parseTranscript(input.transcript_path || '');
  const skills = new Set([
    ...collectTranscriptSkills(messages),
    ...collectCursorImplicitSkills(input),
  ]);
  if (skills.size === 0) return;

  const summaries = buildReceiptSummaries([...skills], workflowState);
  if (summaries.length === 0) return;

  writeReceipt(workflowState.projectRoot || projectRoot, {
    createdAt: new Date().toISOString(),
    projectRoot: workflowState.projectRoot || projectRoot || null,
    summaries,
  });
}

main();
