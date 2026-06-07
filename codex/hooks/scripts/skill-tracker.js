#!/usr/bin/env node
/**
 * skill-tracker.js — RSU 事件追踪
 * 挂载在 Claude Code / Cursor / Codex hooks，解析 prompt/transcript 检测 skill 调用并上报
 *
 * 调用方式（Claude Code）：
 *   node skill-tracker.js               ← Stop hook，上报 skill_invoke + session_stop
 *   node skill-tracker.js task_completed ← TaskCompleted hook，上报 task_completed
 *
 * 调用方式（Cursor）：
 *   node skill-tracker.js before_read_file ← beforeReadFile hook，记录隐性读取
 *   node skill-tracker.js session_stop     ← stop hook，桥接隐性读取到 RSU
 *
 * 调用方式（Codex）：
 *   node skill-tracker.js codex_user_prompt_submit ← UserPromptSubmit hook，记录显式 skill 提及
 *   node skill-tracker.js codex_stop               ← Stop hook，结合 transcript 补报 skill_invoke + session_stop
 *
 * skill 识别支持两种方式：
 *   1. Claude 主动调用 Skill 工具 → tool_use block, name="Skill"
 *   2. 用户 slash 命令 /rdc-git   → user message 含 <command-name>/xxx</command-name>
 *                                    且紧跟 "Base directory for this skill:" 文本
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const REPORTED_DIR = path.join(os.homedir(), '.agents', 'hz-cache', 'reported-skills');
const RSU_PATH = path.join(__dirname, 'rsu.min.js');
const CURSOR_STATE_DIR = path.join(os.homedir(), '.cursor', 'hooks', 'state', 'skill-tracker');
const CODEX_STATE_DIR = path.join(os.homedir(), '.codex', 'hooks', 'state', 'skill-tracker');

/** Windows Cursor 可能向 stdin 写入带 UTF-8 BOM 的 JSON */
function stripUtf8Bom(s) {
  if (typeof s !== 'string' || s.length === 0) return s;
  return s.charCodeAt(0) === 0xfeff ? s.slice(1) : s;
}

const MODE = (() => {
  const arg = process.argv[2];
  if (arg === 'task_completed') return 'task_completed';
  if (arg === 'before_read_file') return 'before_read_file';
  if (arg === 'session_stop') return 'cursor_session_stop';
  if (arg === 'codex_user_prompt_submit') return 'codex_user_prompt_submit';
  if (arg === 'codex_stop') return 'codex_stop';
  return 'skill_invoke';
})();

function loadReported(sessionId) {
  try {
    const f = path.join(REPORTED_DIR, sessionId + '.json');
    if (fs.existsSync(f)) return new Set(JSON.parse(fs.readFileSync(f, 'utf-8')));
  } catch (e) {}
  return new Set();
}

function saveReported(sessionId, set) {
  try {
    fs.mkdirSync(REPORTED_DIR, { recursive: true });
    fs.writeFileSync(path.join(REPORTED_DIR, sessionId + '.json'), JSON.stringify([...set]), 'utf-8');
  } catch (e) {}
}

function parseTranscript(transcriptPath) {
  try {
    return fs.readFileSync(transcriptPath, 'utf-8').trim().split('\n')
      .map(l => { try { return JSON.parse(l); } catch (e) { return null; } })
      .filter(Boolean);
  } catch (e) { return []; }
}

// 模式1：Claude 调用 Skill 工具（tool_use block）
function findToolUseSkills(messages, reported, dedupPrefix) {
  const results = [];
  for (const msg of messages) {
    const content = (msg.message && msg.message.content) || msg.content || [];
    if (!Array.isArray(content)) continue;
    for (const b of content) {
      if (b && b.type === 'tool_use' && b.name === 'Skill' && b.id) {
        const skill = b.input && b.input.skill;
        if (!skill) continue;
        const id = dedupPrefix + b.id;
        if (!reported.has(id)) results.push({ id, skill, source: 'tool_use', timestamp: msg.timestamp || null });
      }
    }
  }
  return results;
}

// 模式2：用户 slash 命令（/rdc-git）
// 需要后续消息包含 "Base directory for this skill:" 才认定为真实 skill
function findSlashCommandSkills(messages, reported, dedupPrefix) {
  const results = [];
  for (let i = 0; i < messages.length; i++) {
    const msgData = messages[i].message || messages[i];
    if (msgData.role !== 'user') continue;
    const content = msgData.content;
    if (typeof content !== 'string') continue;

    const match = content.match(/<command-name>\/([^<]+)<\/command-name>/);
    if (!match) continue;

    let isRealSkill = false;
    for (let j = i + 1; j < Math.min(i + 4, messages.length); j++) {
      const nextData = messages[j].message || messages[j];
      if (nextData.role !== 'user') continue;
      const c = nextData.content;
      if (typeof c === 'string' && c.includes('Base directory for this skill:')) {
        isRealSkill = true; break;
      }
      if (Array.isArray(c)) {
        for (const b of c) {
          if (b && typeof b.text === 'string' && b.text.includes('Base directory for this skill:')) {
            isRealSkill = true; break;
          }
        }
      }
      if (isRealSkill) break;
    }
    if (!isRealSkill) continue;

    const id = dedupPrefix + 'slash:' + (messages[i].uuid || match[1] + ':' + messages[i].timestamp);
    if (!reported.has(id)) results.push({ id, skill: match[1], source: 'slash', timestamp: messages[i].timestamp || null });
  }
  return results;
}

// 获取 session 内所有 skill（去重，只取 skill 名）
function getAllSkillsInSession(messages) {
  const seen = new Set();
  const results = [];
  const addSkill = (skill) => {
    if (!seen.has(skill)) { seen.add(skill); results.push(skill); }
  };
  for (const msg of messages) {
    const content = (msg.message && msg.message.content) || msg.content || [];
    if (Array.isArray(content)) {
      for (const b of content) {
        if (b && b.type === 'tool_use' && b.name === 'Skill') {
          const skill = b.input && b.input.skill;
          if (skill) addSkill(skill);
        }
      }
    }
  }
  for (let i = 0; i < messages.length; i++) {
    const msgData = messages[i].message || messages[i];
    if (msgData.role !== 'user') continue;
    const content = msgData.content;
    if (typeof content !== 'string') continue;
    const match = content.match(/<command-name>\/([^<]+)<\/command-name>/);
    if (!match) continue;
    let isRealSkill = false;
    for (let j = i + 1; j < Math.min(i + 4, messages.length); j++) {
      const nextData = messages[j].message || messages[j];
      if (nextData.role !== 'user') continue;
      const c = nextData.content;
      if (typeof c === 'string' && c.includes('Base directory for this skill:')) { isRealSkill = true; break; }
      if (Array.isArray(c)) for (const b of c) if (b && b.text && b.text.includes('Base directory for this skill:')) { isRealSkill = true; break; }
      if (isRealSkill) break;
    }
    if (isRealSkill) addSkill(match[1]);
  }
  return results;
}

function extractModel(messages) {
  for (const msg of messages) {
    const m = (msg.message && msg.message.model) || msg.model;
    if (m) return m;
  }
  return null;
}

async function reportEvent(skillId, event, hookData, model, timestamp) {
  if (!fs.existsSync(RSU_PATH)) return;
  try {
    process.argv[2] = skillId.startsWith('huize/') ? skillId : 'huize/' + skillId;
    process.argv[3] = event;
    process.env.RSU_HOOK_DATA = JSON.stringify({
      session_id: hookData.session_id || null,
      model: model || null,
      task_id: hookData.task_id || null,
      task_subject: hookData.task_subject || null,
      ts: timestamp || null,
    });
    delete require.cache[require.resolve(RSU_PATH)];
    await require(RSU_PATH).run();
  } catch (e) {}
}

// ── Cursor 隐性追踪（beforeReadFile + session_stop）────────────────────────

/**
 * 从文件路径判断是否为某个 skill 的 SKILL.md，返回 skill 名或 null。
 * 匹配规则：路径含 /skills/<skill-name>/SKILL.md
 */
function detectSkillFileRead(filePath) {
  if (!filePath || path.basename(filePath) !== 'SKILL.md') return null;
  const parts = path.normalize(filePath).split(path.sep).filter(Boolean);
  const idx = parts.lastIndexOf('skills');
  if (idx < 0 || !parts[idx + 1]) return null;
  return parts[idx + 1];
}

function loadCursorState(conversationId) {
  try {
    return JSON.parse(fs.readFileSync(path.join(CURSOR_STATE_DIR, conversationId + '.json'), 'utf-8'));
  } catch (e) { return { skills: {} }; }
}

function saveCursorState(conversationId, state) {
  try {
    fs.mkdirSync(CURSOR_STATE_DIR, { recursive: true });
    fs.writeFileSync(path.join(CURSOR_STATE_DIR, conversationId + '.json'), JSON.stringify(state), 'utf-8');
  } catch (e) {}
}

function clearCursorState(conversationId) {
  try { fs.unlinkSync(path.join(CURSOR_STATE_DIR, conversationId + '.json')); } catch (e) {}
}

// ── Codex 追踪（UserPromptSubmit + Stop）────────────────────────────────────

function loadCodexState(sessionId) {
  try {
    return JSON.parse(fs.readFileSync(path.join(CODEX_STATE_DIR, sessionId + '.json'), 'utf-8'));
  } catch (e) {
    return { skills: {} };
  }
}

function saveCodexState(sessionId, state) {
  try {
    fs.mkdirSync(CODEX_STATE_DIR, { recursive: true });
    fs.writeFileSync(path.join(CODEX_STATE_DIR, sessionId + '.json'), JSON.stringify(state), 'utf-8');
  } catch (e) {}
}

function clearCodexState(sessionId) {
  try { fs.unlinkSync(path.join(CODEX_STATE_DIR, sessionId + '.json')); } catch (e) {}
}

function getCodexSessionId(hookData) {
  return hookData.session_id || hookData.sessionId || hookData.conversation_id || hookData.conversationId || null;
}

function collectSkillNamesFromRoot(rootDir, out) {
  try {
    if (!rootDir || !fs.existsSync(rootDir)) return;
    for (const entry of fs.readdirSync(rootDir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const first = path.join(rootDir, entry.name);
      const directSkill = path.join(first, 'SKILL.md');
      if (fs.existsSync(directSkill)) {
        out.add(entry.name);
        continue;
      }
      for (const child of fs.readdirSync(first, { withFileTypes: true })) {
        if (!child.isDirectory()) continue;
        const nestedSkill = path.join(first, child.name, 'SKILL.md');
        if (fs.existsSync(nestedSkill)) out.add(child.name);
      }
    }
  } catch (e) {}
}

let installedSkillNamesCache = null;
function getInstalledSkillNames(cwd) {
  if (installedSkillNamesCache) return installedSkillNamesCache;
  const names = new Set();
  const home = os.homedir();
  collectSkillNamesFromRoot(path.join(home, '.agents', 'skills'), names);
  collectSkillNamesFromRoot(path.join(home, '.codex', 'skills'), names);
  collectSkillNamesFromRoot(path.join(home, '.claude', 'skills'), names);
  if (cwd) collectSkillNamesFromRoot(path.join(cwd, 'skills'), names);
  installedSkillNamesCache = [...names];
  return installedSkillNamesCache;
}

function getAllStringsDeep(value, out) {
  if (typeof value === 'string') {
    out.push(value);
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) getAllStringsDeep(item, out);
    return;
  }
  if (value && typeof value === 'object') {
    for (const v of Object.values(value)) getAllStringsDeep(v, out);
  }
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function detectPromptSkills(prompt, installedSkills) {
  const result = {};
  const text = typeof prompt === 'string' ? prompt : '';
  if (!text) return result;

  const contextualMention = /(skill|skills|技能|使用|调用|invoke|use)/i.test(text);
  for (const skill of installedSkills) {
    const escaped = escapeRegex(skill);
    const hit = { prompt_hits: 0, explicit: false };

    const slashMatches = text.match(new RegExp(`(^|\\s)/${escaped}(?=\\s|$)`, 'g'));
    const dollarMatches = text.match(new RegExp(`\\$${escaped}(?=\\b|\\s|$)`, 'g'));
    if (slashMatches) {
      hit.prompt_hits += slashMatches.length;
      hit.explicit = true;
    }
    if (dollarMatches) {
      hit.prompt_hits += dollarMatches.length;
      hit.explicit = true;
    }

    if (hit.prompt_hits === 0) {
      const bareMention = new RegExp(`(^|[^a-zA-Z0-9-])${escaped}(?=[^a-zA-Z0-9-]|$)`, 'i').test(text);
      if (bareMention && contextualMention) hit.prompt_hits = 1;
    }

    if (hit.prompt_hits > 0) result[skill] = hit;
  }
  return result;
}

function detectSkillsFromStrings(strings, installedSkills) {
  const result = new Set();
  const combined = strings.join('\n');

  for (const raw of combined.matchAll(/(?:^|[\/\\])skills[\/\\](?:[^\/\\]+[\/\\])?([a-zA-Z0-9-]+)[\/\\]SKILL\.md/gi)) {
    if (raw[1]) result.add(raw[1]);
  }
  for (const raw of combined.matchAll(/Skill Name:\s*([a-zA-Z0-9-]+)/g)) {
    result.add(raw[1]);
  }

  for (const skill of installedSkills) {
    const escaped = escapeRegex(skill);
    const pathPattern = new RegExp(`(?:^|[\\/])${escaped}(?:[\\/])SKILL\\.md`, 'i');
    const usingPattern = new RegExp(`Using\\s+${escaped}\\b`, 'i');
    const attachedPattern = new RegExp(`Base directory for this skill:[^\\n]*${escaped}\\b`, 'i');
    if (pathPattern.test(combined) || usingPattern.test(combined) || attachedPattern.test(combined)) {
      result.add(skill);
    }
  }

  return result;
}

function extractTextBlocks(content) {
  if (typeof content === 'string') return [content];
  if (!Array.isArray(content)) return [];
  return content.map(b => (b && typeof b.text === 'string') ? b.text : '').filter(Boolean);
}

function detectSkillPathInReadCommand(command, installedSkills) {
  if (typeof command !== 'string') return null;
  if (!/\b(cat|sed|nl|head|tail|less)\b/.test(command)) return null;

  for (const skill of installedSkills) {
    const escaped = escapeRegex(skill);
    const pathPattern = new RegExp(`(?:^|[\\/])${escaped}[\\/]SKILL\\.md(?:\\b|['"\\s])`, 'i');
    if (pathPattern.test(command)) return skill;
  }
  return null;
}

function detectCodexTranscriptSkills(messages, installedSkills) {
  const result = new Set();

  for (const msg of messages) {
    const msgData = msg.payload || msg.message || msg;
    const role = msgData.role || msg.role || '';

    // Codex stores global skill catalogs and developer instructions in the
    // transcript. Those contain every SKILL.md path and must not count as use.
    if (role === 'system' || role === 'developer') continue;

    if (msgData.type === 'function_call' && msgData.name === 'exec_command') {
      try {
        const args = typeof msgData.arguments === 'string' ? JSON.parse(msgData.arguments) : msgData.arguments;
        const skill = detectSkillPathInReadCommand(args && args.cmd, installedSkills);
        if (skill) result.add(skill);
      } catch (e) {}
      continue;
    }

    const texts = extractTextBlocks(msgData.content);
    const combined = texts.join('\n');
    if (!combined) continue;

    for (const skill of installedSkills) {
      const escaped = escapeRegex(skill);
      const usingPattern = new RegExp(`Using\\s+\`?(?:[^\\s\`]+:)?${escaped}\`?\\b`, 'i');
      const enabledPattern = new RegExp(`已启用\\s+\`?(?:[^\\s\`]+:)?${escaped}\`?\\b`, 'i');
      const attachedPattern = new RegExp(`Base directory for this skill:[^\\n]*[\\/]${escaped}\\b`, 'i');
      if (usingPattern.test(combined) || enabledPattern.test(combined) || attachedPattern.test(combined)) {
        result.add(skill);
      }
    }
  }

  return result;
}

function getCodexTranscriptStartIndex(messages, state) {
  const lastCount = state && Number.isInteger(state.last_transcript_line_count)
    ? state.last_transcript_line_count
    : 0;
  if (lastCount < 0 || lastCount > messages.length) return 0;
  return lastCount;
}

function detectCodexTranscriptSkillsSince(messages, installedSkills, state) {
  return detectCodexTranscriptSkills(
    messages.slice(getCodexTranscriptStartIndex(messages, state)),
    installedSkills
  );
}

function planCodexReports(state, transcriptSkills) {
  const nextState = {
    ...state,
    skills: { ...(state && state.skills ? state.skills : {}) },
  };
  const finalSkills = new Set(transcriptSkills);

  for (const [skillName, info] of Object.entries(nextState.skills)) {
    if (info && info.prompt_hits > 0) finalSkills.add(skillName);
  }

  const reports = [];
  for (const skillName of finalSkills) {
    const current = nextState.skills[skillName] || {};
    const info = {
      prompt_hits: current.prompt_hits || 0,
      explicit: current.explicit || false,
      invoke_reported: current.invoke_reported || false,
      first_seen_at: current.first_seen_at || new Date().toISOString(),
      last_seen_at: new Date().toISOString(),
    };

    if (!info.invoke_reported && (info.explicit || transcriptSkills.has(skillName))) {
      reports.push({ skill: skillName, event: 'skill_invoke' });
      info.invoke_reported = true;
    }
    reports.push({ skill: skillName, event: 'session_stop' });
    info.prompt_hits = 0;

    nextState.skills[skillName] = info;
  }

  return { reports, state: nextState };
}

async function handleCodexUserPromptSubmit(hookData) {
  const sessionId = getCodexSessionId(hookData);
  if (sessionId) {
    const state = loadCodexState(sessionId);
    const installedSkills = getInstalledSkillNames(hookData.cwd);
    const detected = detectPromptSkills(hookData.prompt, installedSkills);
    for (const [skillName, info] of Object.entries(detected)) {
      const cur = state.skills[skillName] || { prompt_hits: 0, explicit: false, invoke_reported: false };
      state.skills[skillName] = {
        prompt_hits: cur.prompt_hits + info.prompt_hits,
        explicit: cur.explicit || info.explicit,
        invoke_reported: cur.invoke_reported || false,
        first_seen_at: cur.first_seen_at || new Date().toISOString(),
        last_seen_at: new Date().toISOString(),
      };
    }
    saveCodexState(sessionId, state);
  }
  process.stdout.write(JSON.stringify({ continue: true }));
}

async function handleCodexStop(hookData) {
  const sessionId = getCodexSessionId(hookData);
  const state = loadCodexState(sessionId || '');
  const messages = parseTranscript(hookData.transcript_path);
  const model = hookData.model || extractModel(messages);
  const installedSkills = getInstalledSkillNames(hookData.cwd);
  const transcriptSkills = detectCodexTranscriptSkillsSince(messages, installedSkills, state);
  const planned = planCodexReports(state, transcriptSkills);
  planned.state.last_transcript_line_count = messages.length;

  for (const report of planned.reports) {
    await reportEvent(report.skill, report.event, { session_id: sessionId }, model);
  }

  if (sessionId) saveCodexState(sessionId, planned.state);
  process.stdout.write(JSON.stringify({ continue: true }));
}

/**
 * 从 transcript 收集手动附加 / tool_use 方式的 skill 名（Set）。
 * slash 命令由 cursor-rsu.js 已上报，此处仅收集另外两种，用于判断是否需要桥接。
 */
function getCursorExplicitSkills(messages) {
  const result = new Set();
  for (const msg of messages) {
    const content = (msg.message && msg.message.content) || msg.content;
    if (Array.isArray(content)) {
      for (const b of content) {
        if (!b) continue;
        if (b.type === 'tool_use' && b.name === 'Skill') {
          const skill = b.input && b.input.skill;
          if (skill) result.add(skill.replace(/^huize\//, ''));
        }
        const text = typeof b.text === 'string' ? b.text : '';
        if (text.includes('<manually_attached_skills>')) {
          for (const m of text.matchAll(/Skill Name:\s*(\S+)/g)) result.add(m[1]);
        }
      }
    }
    if (typeof content === 'string' && content.includes('<manually_attached_skills>')) {
      for (const m of content.matchAll(/Skill Name:\s*(\S+)/g)) result.add(m[1]);
    }
  }
  return result;
}

/** 收集通过 slash 命令调用的 skill 名（Set）——用于跳过已被 cursor-rsu.js 上报的 skill。 */
function getCursorSlashSkills(messages) {
  const result = new Set();
  for (let i = 0; i < messages.length; i++) {
    const msgData = messages[i].message || messages[i];
    if (msgData.role !== 'user' || typeof msgData.content !== 'string') continue;
    const m = msgData.content.match(/<command-name>\/([^<]+)<\/command-name>/);
    if (!m) continue;
    for (let j = i + 1; j < Math.min(i + 4, messages.length); j++) {
      const next = messages[j].message || messages[j];
      const nc = next.content;
      const nt = typeof nc === 'string' ? nc
               : Array.isArray(nc) ? nc.map(b => (b && b.text) || '').join('') : '';
      if (nt.includes('Base directory for this skill:')) { result.add(m[1]); break; }
    }
  }
  return result;
}

async function handleBeforeReadFile(hookData) {
  const skillName = detectSkillFileRead(hookData.file_path || hookData.filePath);
  if (skillName) {
    const cid = hookData.conversation_id || hookData.conversationId || hookData.session_id;
    if (cid) {
      const state = loadCursorState(cid);
      const cur = state.skills[skillName] || { read_count: 0 };
      state.skills[skillName] = {
        read_count: cur.read_count + 1,
        first_seen_at: cur.first_seen_at || new Date().toISOString(),
        last_seen_at: new Date().toISOString(),
      };
      saveCursorState(cid, state);
    }
  }
  process.stdout.write(JSON.stringify({ permission: 'allow' }));
}

async function handleCursorSessionStop(hookData) {
  const cid = hookData.conversation_id || hookData.conversationId || hookData.session_id;
  const state = loadCursorState(cid || '');
  const messages = parseTranscript(hookData.transcript_path);
  const model = hookData.model || extractModel(messages);
  const slashSkills = getCursorSlashSkills(messages);
  const explicitSkills = getCursorExplicitSkills(messages);

  // 隐性读取的 skill：跳过已被 cursor-rsu.js 通过 slash 上报的
  for (const [skillName, info] of Object.entries(state.skills || {})) {
    if (slashSkills.has(skillName)) continue;
    if (info.read_count > 0 || explicitSkills.has(skillName)) {
      await reportEvent(skillName, 'session_stop', { session_id: cid }, model);
    }
  }

  // attached / tool_use 但没有读取记录的也补报
  for (const skillName of explicitSkills) {
    if (slashSkills.has(skillName)) continue;
    if (!state.skills || !state.skills[skillName]) {
      await reportEvent(skillName, 'session_stop', { session_id: cid }, model);
    }
  }

  if (cid) clearCursorState(cid);
}

// ── main ────────────────────────────────────────────────────────────────────

async function main() {
  let hookData = {};
  try {
    const raw = stripUtf8Bom(fs.readFileSync(0, 'utf-8'));
    hookData = raw.trim() ? JSON.parse(raw.trim()) : {};
  } catch (e) {}

  if (MODE === 'before_read_file') { await handleBeforeReadFile(hookData); return; }
  if (MODE === 'cursor_session_stop') { await handleCursorSessionStop(hookData); return; }
  if (MODE === 'codex_user_prompt_submit') { await handleCodexUserPromptSubmit(hookData); return; }
  if (MODE === 'codex_stop') { await handleCodexStop(hookData); return; }

  const { session_id, transcript_path } = hookData;
  if (!session_id || !transcript_path) return;

  const messages = parseTranscript(transcript_path);
  const reported = loadReported(session_id);
  const model = extractModel(messages);

  if (MODE === 'skill_invoke') {
    // 1. skill_invoke：用户 slash 主动调用，每个 skill 只报一次（tool_use 被动调用不计）
    const newInvocations = [
      ...findSlashCommandSkills(messages, reported, ''),
    ];
    for (const { id, skill, timestamp } of newInvocations) {
      await reportEvent(skill, 'skill_invoke', hookData, model, timestamp);
      reported.add(id);
    }

    // 2. session_stop：每次 Stop 都报，统计回合数
    const allSkills = getAllSkillsInSession(messages);
    for (const skill of allSkills) {
      await reportEvent(skill, 'session_stop', hookData, model);
    }

  } else if (MODE === 'task_completed') {
    const skills = getAllSkillsInSession(messages);
    if (skills.length === 0) return;
    const taskId = hookData.task_id || '';
    const newSkills = skills.filter(s => !reported.has('tc:' + taskId + ':' + s));
    if (newSkills.length === 0) return;
    for (const skill of newSkills) {
      await reportEvent(skill, 'task_completed', hookData, model);
      reported.add('tc:' + taskId + ':' + skill);
    }
  }

  saveReported(session_id, reported);
}

if (require.main === module) {
  main().catch(() => {});
}

module.exports = {
  __test: {
    detectCodexTranscriptSkills,
    detectCodexTranscriptSkillsSince,
    planCodexReports,
  },
};
