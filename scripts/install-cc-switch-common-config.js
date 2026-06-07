#!/usr/bin/env node
'use strict';

const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

function parseArgs(argv) {
  const result = {
    ccSwitchHome: path.join(os.homedir(), '.cc-switch'),
    claimProjectRoot: '',
    backupExisting: false,
    dryRun: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--cc-switch-home') result.ccSwitchHome = argv[++i];
    else if (arg === '--claim-project-root') result.claimProjectRoot = argv[++i] || '';
    else if (arg === '--backup-existing') result.backupExisting = true;
    else if (arg === '--dry-run') result.dryRun = true;
    else if (arg === '--help' || arg === '-h') {
      console.log(`Usage: node scripts/install-cc-switch-common-config.js [options]

Options:
  --cc-switch-home <path>       Defaults to %USERPROFILE%\\.cc-switch
  --claim-project-root <path>   Optional project path placeholder
  --backup-existing             Back up cc-switch.db before writing
  --dry-run                     Print planned changes without writing`);
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return result;
}

function slashPath(value) {
  return String(value || '').replace(/\\/g, '/');
}

function expandTemplate(text, options) {
  const home = os.homedir();
  const map = {
    '<USERPROFILE>': home,
    '<USERPROFILE_SLASH>': slashPath(home),
    '<CODEX_HOME>': path.join(home, '.codex'),
    '<CODEX_HOME_SLASH>': slashPath(path.join(home, '.codex')),
    '<CLAIM_PROJECT_ROOT>': options.claimProjectRoot || '',
    '<CLAIM_PROJECT_ROOT_SLASH>': slashPath(options.claimProjectRoot || ''),
  };

  let expanded = text;
  for (const [key, value] of Object.entries(map)) {
    expanded = expanded.split(key).join(value);
  }
  return expanded;
}

function runPythonSqlite(dbPath, codexConfig, claudeConfig) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switch-common-config-'));
  const codexFile = path.join(tempDir, 'common_config_codex.toml');
  const claudeFile = path.join(tempDir, 'common_config_claude.json');
  fs.writeFileSync(codexFile, codexConfig, 'utf8');
  fs.writeFileSync(claudeFile, claudeConfig, 'utf8');

  const pythonCode = `
import json
import sqlite3
import sys

db_path, codex_path, claude_path = sys.argv[1:4]
with open(codex_path, "r", encoding="utf-8") as fh:
    codex_config = fh.read()
with open(claude_path, "r", encoding="utf-8") as fh:
    claude_config = fh.read()

try:
    import tomllib
    tomllib.loads(codex_config)
except ModuleNotFoundError:
    pass

json.loads(claude_config)

con = sqlite3.connect(db_path)
try:
    con.execute(
        "insert or replace into settings(key, value) values(?, ?)",
        ("common_config_codex", codex_config),
    )
    con.execute(
        "insert or replace into settings(key, value) values(?, ?)",
        ("common_config_claude", claude_config),
    )

    for app_type in ("codex", "claude"):
        rows = con.execute(
            "select id, meta from providers where app_type = ? and is_current = 1",
            (app_type,),
        ).fetchall()
        for provider_id, meta_text in rows:
            try:
                meta = json.loads(meta_text or "{}")
            except json.JSONDecodeError:
                meta = {}
            meta["commonConfigEnabled"] = True
            con.execute(
                "update providers set meta = ? where app_type = ? and id = ?",
                (json.dumps(meta, ensure_ascii=False, separators=(",", ":")), app_type, provider_id),
            )
    con.commit()
finally:
    con.close()
`;

  try {
    childProcess.execFileSync('python', ['-c', pythonCode, dbPath, codexFile, claudeFile], {
      windowsHide: true,
      stdio: 'pipe',
    });
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const repo = path.resolve(__dirname, '..');
  const dbPath = path.join(options.ccSwitchHome, 'cc-switch.db');
  const codexTemplate = path.join(repo, 'cc-switch', 'common_config_codex.toml.template');
  const claudeTemplate = path.join(repo, 'cc-switch', 'common_config_claude.json.template');

  if (!fs.existsSync(dbPath)) {
    console.log(`[cc-switch-config] Skip; cc-switch database not found: ${dbPath}`);
    return;
  }

  const codexConfig = expandTemplate(fs.readFileSync(codexTemplate, 'utf8'), options);
  const claudeConfig = expandTemplate(fs.readFileSync(claudeTemplate, 'utf8'), options);
  JSON.parse(claudeConfig);

  if (options.dryRun) {
    console.log(`[cc-switch-config] DryRun: would update common_config_codex and common_config_claude in ${dbPath}`);
    console.log('[cc-switch-config] DryRun: would enable commonConfigEnabled for current codex and claude providers.');
    return;
  }

  if (options.backupExisting) {
    const backup = `${dbPath}.backup-${new Date().toISOString().replace(/[-:]/g, '').replace(/\..+$/, '').replace('T', '-')}`;
    fs.copyFileSync(dbPath, backup);
    console.log(`[cc-switch-config] Backup ${dbPath} -> ${backup}`);
  } else {
    console.log('[cc-switch-config] No --backup-existing supplied; updating cc-switch.db without creating a backup.');
  }

  runPythonSqlite(dbPath, codexConfig, claudeConfig);
  console.log('[cc-switch-config] Updated common_config_codex/common_config_claude and enabled current providers.');
}

try {
  main();
} catch (error) {
  console.error(`[cc-switch-config] ERROR: ${error.message}`);
  process.exit(1);
}
