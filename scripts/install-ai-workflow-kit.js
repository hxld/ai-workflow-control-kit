#!/usr/bin/env node
'use strict';

const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

function parseArgs(argv) {
  const result = {
    agentsHome: path.join(os.homedir(), '.agents'),
    codexHome: path.join(os.homedir(), '.codex'),
    claudeHome: path.join(os.homedir(), '.claude'),
    replayAutopilotRoot: path.join(os.homedir(), '.ai-workflow-control-kit', 'replay-autopilot'),
    claimProjectRoot: '',
    knowledgeRepo: '.',
    backupExisting: false,
    dryRun: false,
    skipCcSwitchConfig: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--agents-home') result.agentsHome = argv[++i];
    else if (arg === '--codex-home') result.codexHome = argv[++i];
    else if (arg === '--claude-home') result.claudeHome = argv[++i];
    else if (arg === '--replay-autopilot-root') result.replayAutopilotRoot = argv[++i];
    else if (arg === '--claim-project-root') result.claimProjectRoot = argv[++i] || '';
    else if (arg === '--knowledge-repo') result.knowledgeRepo = argv[++i] || '.';
    else if (arg === '--backup-existing') result.backupExisting = true;
    else if (arg === '--dry-run') result.dryRun = true;
    else if (arg === '--skip-cc-switch-config') result.skipCcSwitchConfig = true;
    else if (arg === '--help' || arg === '-h') {
      console.log(`Usage: node scripts/install-ai-workflow-kit.js [options]

Options:
  --agents-home <path>
  --codex-home <path>
  --claude-home <path>
  --replay-autopilot-root <path>
  --claim-project-root <path>
  --knowledge-repo <path>
  --backup-existing
  --dry-run
  --skip-cc-switch-config`);
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return result;
}

function step(message) {
  console.log(`[workflow-kit] ${message}`);
}

function slashPath(value) {
  return String(value || '').replace(/\\/g, '/');
}

function escapedBackslashPath(value) {
  return String(value || '').replace(/\\/g, '\\\\');
}

function placeholderMap(options) {
  return {
    '<USERPROFILE>': os.homedir(),
    '<USERPROFILE_SLASH>': slashPath(os.homedir()),
    '<USERPROFILE_ESCAPED>': escapedBackslashPath(os.homedir()),
    '<AGENTS_HOME>': options.agentsHome,
    '<AGENTS_HOME_SLASH>': slashPath(options.agentsHome),
    '<CODEX_HOME>': options.codexHome,
    '<CODEX_HOME_SLASH>': slashPath(options.codexHome),
    '<CLAUDE_HOME>': options.claudeHome,
    '<CLAUDE_HOME_SLASH>': slashPath(options.claudeHome),
    '<CLAIM_PROJECT_ROOT>': options.claimProjectRoot || '',
    '<CLAIM_PROJECT_ROOT_SLASH>': slashPath(options.claimProjectRoot || ''),
    '<KNOWLEDGE_REPO>': options.knowledgeRepo || '.',
    '<KNOWLEDGE_REPO_SLASH>': slashPath(options.knowledgeRepo || '.'),
    '<REPLAY_AUTOPILOT_ROOT>': options.replayAutopilotRoot,
    '<REPLAY_AUTOPILOT_ROOT_SLASH>': slashPath(options.replayAutopilotRoot),
  };
}

function expandText(text, options) {
  let expanded = text;
  for (const [key, value] of Object.entries(placeholderMap(options))) {
    expanded = expanded.split(key).join(value);
  }
  return expanded;
}

function isTextTemplate(filePath) {
  return ['.cmd', '.json', '.md', '.ps1', '.rules', '.toml', '.txt', '.yaml', '.yml', '.js'].includes(path.extname(filePath).toLowerCase());
}

function backupPath(target, options) {
  if (!fs.existsSync(target)) return null;
  if (!options.backupExisting) throw new Error(`Target exists and --backup-existing was not supplied: ${target}`);
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+$/, '').replace('T', '-');
  const backup = `${target}.backup-${stamp}`;
  step(`Backup ${target} -> ${backup}`);
  if (!options.dryRun) fs.renameSync(target, backup);
  return backup;
}

function ensureParent(filePath, options) {
  if (!options.dryRun) fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function copyFile(source, destination, options, replace = true) {
  if (!fs.existsSync(source)) return;
  if (replace && fs.existsSync(destination)) backupPath(destination, options);
  step(`Copy ${source} -> ${destination}`);
  if (options.dryRun) return;
  ensureParent(destination, options);
  if (isTextTemplate(source)) {
    fs.writeFileSync(destination, expandText(fs.readFileSync(source, 'utf8'), options), 'utf8');
  } else {
    fs.copyFileSync(source, destination);
  }
}

function copyTree(source, destination, options, replace = true, preserveSystemSkills = false) {
  if (!fs.existsSync(source)) return;
  const shouldRestoreSystem = preserveSystemSkills && fs.existsSync(path.join(destination, '.system'));
  let backup = null;
  if (replace && fs.existsSync(destination)) backup = backupPath(destination, options);
  step(`Copy ${source} -> ${destination}`);
  if (options.dryRun) return;
  ensureParent(destination, options);
  fs.cpSync(source, destination, { recursive: true, force: true });
  if (shouldRestoreSystem && backup && fs.existsSync(path.join(backup, '.system'))) {
    const systemDestination = path.join(destination, '.system');
    step(`Restore Codex runtime system skills ${path.join(backup, '.system')} -> ${systemDestination}`);
    fs.cpSync(path.join(backup, '.system'), systemDestination, { recursive: true, force: true });
  }
}

function linkDirectory(target, destination, options) {
  if (!fs.existsSync(target)) throw new Error(`Link target does not exist: ${target}`);
  const targetReal = fs.realpathSync(target).toLowerCase();
  if (fs.existsSync(destination)) {
    const destinationReal = fs.realpathSync(destination).toLowerCase();
    if (destinationReal === targetReal) {
      step(`Link already exists ${destination} -> ${target}`);
      return;
    }
    backupPath(destination, options);
  }
  step(`Link ${destination} -> ${target}`);
  if (options.dryRun) return;
  ensureParent(destination, options);
  fs.symlinkSync(target, destination, 'junction');
}

function disableLegacyCodexHooksJson(codexHome, options) {
  const legacyHooks = path.join(codexHome, 'hooks.json');
  if (!fs.existsSync(legacyHooks)) return;
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+$/, '').replace('T', '-');
  const disabled = `${legacyHooks}.disabled-${stamp}`;
  step(`Disable legacy Codex hooks.json -> ${disabled}`);
  if (!options.dryRun) fs.renameSync(legacyHooks, disabled);
}

function expandPlaceholdersInFile(filePath, options) {
  if (!fs.existsSync(filePath) || !isTextTemplate(filePath)) return;
  const text = fs.readFileSync(filePath, 'utf8');
  const expanded = expandText(text, options);
  if (expanded !== text) {
    step(`Expand placeholders in ${filePath}`);
    if (!options.dryRun) fs.writeFileSync(filePath, expanded, 'utf8');
  }
}

function applyCcSwitchConfig(repo, options) {
  const dbPath = path.join(os.homedir(), '.cc-switch', 'cc-switch.db');
  const installer = path.join(repo, 'scripts', 'install-cc-switch-common-config.js');
  if (options.skipCcSwitchConfig) {
    step('Skip cc-switch common config by request.');
    return;
  }
  if (!fs.existsSync(dbPath)) {
    step('Skip cc-switch common config; cc-switch.db was not found.');
    return;
  }
  if (!options.backupExisting && !options.dryRun) {
    step('Skip cc-switch common config; pass --backup-existing to update cc-switch.db with a backup.');
    return;
  }
  step('Apply cc-switch common config from templates.');
  const args = [installer, '--cc-switch-home', path.join(os.homedir(), '.cc-switch')];
  if (options.claimProjectRoot) args.push('--claim-project-root', options.claimProjectRoot);
  if (options.backupExisting) args.push('--backup-existing');
  if (options.dryRun) args.push('--dry-run');
  childProcess.execFileSync(process.execPath, args, { windowsHide: true, stdio: 'inherit' });
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const repo = path.resolve(__dirname, '..');
  step(`Repository: ${repo}`);
  if (options.dryRun) step('DryRun enabled; no files will be written.');

  copyFile(path.join(repo, 'agents', 'AGENTS.md'), path.join(options.agentsHome, 'AGENTS.md'), options);
  copyFile(path.join(repo, 'agents', '.skill-lock.json'), path.join(options.agentsHome, '.skill-lock.json'), options);
  copyTree(path.join(repo, 'agents', 'hooks'), path.join(options.agentsHome, 'hooks'), options);
  copyTree(path.join(repo, 'agents', 'skills'), path.join(options.agentsHome, 'skills'), options, true, true);
  copyTree(path.join(repo, 'agents', 'templates'), path.join(options.agentsHome, 'templates'), options);

  copyFile(path.join(repo, 'codex', 'AGENTS.md'), path.join(options.codexHome, 'AGENTS.md'), options);
  copyFile(path.join(repo, 'codex', 'RTK.md'), path.join(options.codexHome, 'RTK.md'), options);
  copyFile(path.join(repo, 'codex', 'skill-rules.json'), path.join(options.codexHome, 'skill-rules.json'), options);
  copyTree(path.join(repo, 'codex', 'hooks'), path.join(options.codexHome, 'hooks'), options);
  disableLegacyCodexHooksJson(options.codexHome, options);
  copyTree(path.join(repo, 'codex', 'rules'), path.join(options.codexHome, 'rules'), options);
  linkDirectory(path.join(options.agentsHome, 'skills'), path.join(options.codexHome, 'skills'), options);
  if (!fs.existsSync(path.join(options.codexHome, 'config.toml'))) {
    copyFile(path.join(repo, 'codex', 'config.toml.example'), path.join(options.codexHome, 'config.toml'), options, false);
  } else {
    step('Skip Codex config.toml; merge manually from codex/config.toml.example');
  }

  copyFile(path.join(repo, 'claude', 'config.json'), path.join(options.claudeHome, 'config.json'), options);
  copyTree(path.join(repo, 'claude', 'agents'), path.join(options.claudeHome, 'agents'), options);
  copyTree(path.join(repo, 'claude', 'commands'), path.join(options.claudeHome, 'commands'), options);
  copyTree(path.join(repo, 'claude', 'hooks'), path.join(options.claudeHome, 'hooks'), options);
  copyTree(path.join(repo, 'claude', 'rules'), path.join(options.claudeHome, 'rules'), options);
  linkDirectory(path.join(options.agentsHome, 'skills'), path.join(options.claudeHome, 'skills'), options);
  copyTree(path.join(repo, 'claude', 'templates'), path.join(options.claudeHome, 'templates'), options);
  copyTree(path.join(repo, 'claude', 'output-styles'), path.join(options.claudeHome, 'output-styles'), options);
  if (!fs.existsSync(path.join(options.claudeHome, 'settings.json'))) {
    copyFile(path.join(repo, 'claude', 'settings.example.json'), path.join(options.claudeHome, 'settings.json'), options, false);
  } else {
    step('Skip Claude settings.json; merge manually from claude/settings.example.json');
  }

  applyCcSwitchConfig(repo, options);

  copyTree(path.join(repo, 'replay-autopilot'), options.replayAutopilotRoot, options);
  expandPlaceholdersInFile(path.join(options.replayAutopilotRoot, 'config.yaml'), options);

  step('Install completed.');
  step('Manual step: restore auth tokens and credential placeholders from your password manager, not from this repo.');
}

try {
  main();
} catch (error) {
  console.error(`[workflow-kit] ERROR: ${error.message}`);
  process.exit(1);
}
