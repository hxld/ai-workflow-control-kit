#!/usr/bin/env node
/**
 * cursor-rsu.js - Cursor hook adapter for RSU usage tracking
 *
 * Handles:
 *   skill_invoke  — via beforeSubmitPrompt (extracts rule attachments)
 *   session_stop  — via stop hook
 *
 * Usage:
 *   node cursor-rsu.js skill_invoke   (stdin: beforeSubmitPrompt payload)
 *   node cursor-rsu.js session_stop   (stdin: stop payload)
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync, spawn } = require('child_process');

const HOME_DIR = os.homedir();
const AGENTS_DIR = path.join(HOME_DIR, '.agents');
const CACHE_DIR = path.join(AGENTS_DIR, 'hz-cache');
const QUEUE_PATH = path.join(CACHE_DIR, 'pending-events.jsonl');
const DISABLE_FILE = path.join(AGENTS_DIR, '.hz-tracking-disabled');
const SESSION_SKILLS_PATH = path.join(CACHE_DIR, 'cursor-session-skills.json');
const RSU_PATH = path.join(__dirname, 'rsu.min.js');
const SKILL_NAMESPACE = (process.env.AI_WORKFLOW_SKILL_NAMESPACE || 'local').replace(/^\/+|\/+$/g, '') || 'local';

/** Windows Cursor 可能向 stdin 写入带 UTF-8 BOM 的 JSON */
function stripUtf8Bom(s) {
  if (typeof s !== 'string' || s.length === 0) return s;
  return s.charCodeAt(0) === 0xfeff ? s.slice(1) : s;
}

function normalizeSkillId(skillId) {
  const raw = String(skillId || 'unknown').trim() || 'unknown';
  return raw.includes('/') ? raw : `${SKILL_NAMESPACE}/${raw}`;
}

function ensureDir(dir) {
  try {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  } catch (e) {}
}

function readStdin() {
  try {
    const text = stripUtf8Bom(fs.readFileSync(0, 'utf-8'));
    return text.trim() ? JSON.parse(text.trim()) : {};
  } catch (e) {
    return {};
  }
}

/**
 * Append an event directly to the queue (fast, no child process).
 * Mirrors the format used by rsu.min.js appendToQueue.
 */
function appendToQueue(skillId, event, extra) {
  try {
    ensureDir(CACHE_DIR);
    const entry = { v: 1, s: skillId, e: event, ts: Math.floor(Date.now() / 1000) };
    if (extra) Object.assign(entry, extra);
    fs.appendFileSync(QUEUE_PATH, JSON.stringify(entry) + '\n', 'utf-8');
  } catch (e) {}
}

/**
 * Delegate to rsu.min.js for operations that need flush + env cache management.
 */
function callRsu(skillId, event, hookData) {
  try {
    spawnSync('node', [RSU_PATH, skillId, event], {
      env: { ...process.env, RSU_HOOK_DATA: JSON.stringify(hookData || {}) },
      timeout: 8000,
      stdio: ['ignore', 'ignore', 'ignore'],
    });
  } catch (e) {}
}

/**
 * Track skills active in current session.
 * Since beforeSubmitPrompt has no session_id, we maintain a simple set
 * of skill IDs seen since the last stop — reset on session_stop.
 */
function readSessionSkills() {
  try {
    return JSON.parse(fs.readFileSync(SESSION_SKILLS_PATH, 'utf-8'));
  } catch (e) {
    return [];
  }
}

function writeSessionSkills(skills) {
  try {
    ensureDir(CACHE_DIR);
    fs.writeFileSync(SESSION_SKILLS_PATH, JSON.stringify([...new Set(skills)]), 'utf-8');
  } catch (e) {}
}

function clearSessionSkills() {
  try { fs.unlinkSync(SESSION_SKILLS_PATH); } catch (e) {}
}


/**
 * Extract <namespace>/<skill-id> from a slash command prompt.
 * Validates against ~/.agents/skills/ to avoid false positives on
 * Cursor built-in commands (/explain, /fix, etc.).
 *
 * Examples:
 *   "/rdc-git 帮我提交"  → local/rdc-git  (if dir exists)
 *   "/explain ..."       → null            (not an installed skill)
 */
function extractSkillIdFromPrompt(prompt) {
  const m = (prompt || '').match(/^\/([a-zA-Z][a-zA-Z0-9-]+)(?:\s|$)/);
  if (!m) return null;
  const name = m[1];
  const skillDir = path.join(AGENTS_DIR, 'skills', name);
  if (!fs.existsSync(skillDir)) return null;
  return normalizeSkillId(name);
}

// ── main ────────────────────────────────────────────────────────────────────

if (fs.existsSync(DISABLE_FILE)) {
  if (process.argv[2] === 'skill_invoke') {
    process.stdout.write(JSON.stringify({ continue: true }));
  }
  process.exit(0);
}

const event = process.argv[2] || 'unknown';
const input = readStdin();

if (event === 'skill_invoke') {
  // beforeSubmitPrompt: detect skill invocation from slash command in prompt
  const skillId = extractSkillIdFromPrompt(input.prompt);

  if (skillId) {
    // Immediately report in background (non-blocking)
    try {
      const child = spawn('node', [RSU_PATH, skillId, 'skill_invoke'], {
        env: { ...process.env, RSU_HOOK_DATA: JSON.stringify({ model: input.model || null, session_id: input.conversation_id || null }) },
        stdio: ['ignore', 'ignore', 'ignore'],
        detached: true,
      });
      child.unref();
    } catch (e) {}

    // Remember for session_stop
    const prev = readSessionSkills();
    writeSessionSkills([...prev, skillId]);
  }

  // beforeSubmitPrompt requires a response; always allow
  process.stdout.write(JSON.stringify({ continue: true }));

} else if (event === 'session_stop') {
  const skills = readSessionSkills();
  const hookData = {
    session_id: input.conversation_id || null,
    model: input.model || null,
  };
  for (const skillId of skills) {
    callRsu(skillId, 'session_stop', hookData);
  }
  clearSessionSkills();
}
