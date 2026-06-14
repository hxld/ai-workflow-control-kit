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
    runReplayValidate: false,
    allowWindowsPowerShellReplay: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--agents-home') result.agentsHome = argv[++i];
    else if (arg === '--codex-home') result.codexHome = argv[++i];
    else if (arg === '--claude-home') result.claudeHome = argv[++i];
    else if (arg === '--replay-autopilot-root') result.replayAutopilotRoot = argv[++i];
    else if (arg === '--run-replay-validate') result.runReplayValidate = true;
    else if (arg === '--allow-windows-powershell-replay') result.allowWindowsPowerShellReplay = true;
    else if (arg === '--help' || arg === '-h') {
      console.log(`Usage: node scripts/verify-ai-workflow-kit.js [options]

Options:
  --agents-home <path>
  --codex-home <path>
  --claude-home <path>
  --replay-autopilot-root <path>
  --run-replay-validate              Run replay ValidateOnly through pwsh when available
  --allow-windows-powershell-replay  Allow fallback to Windows PowerShell 5.1`);
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return result;
}

let failures = 0;
let warnings = 0;

function writeCheck(name, ok, detail = '', warning = false) {
  const prefix = ok ? 'PASS' : warning ? 'WARN' : 'FAIL';
  console.log(detail ? `${prefix} ${name} - ${detail}` : `${prefix} ${name}`);
  if (!ok && warning) warnings += 1;
  if (!ok && !warning) failures += 1;
}

function exists(filePath) {
  return fs.existsSync(filePath);
}

function commandAvailable(name) {
  try {
    // Use platform-appropriate command locator
    const locator = os.platform() === 'win32' ? 'where.exe' : 'which';
    childProcess.execFileSync(locator, [name], { windowsHide: true, stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

function testCommand(name, required) {
  writeCheck(`command:${name}`, commandAvailable(name), required ? 'required' : 'recommended', !required);
}

function realPathOrEmpty(filePath) {
  try {
    return fs.realpathSync(filePath);
  } catch {
    return '';
  }
}

function testPath(name, filePath) {
  writeCheck(name, exists(filePath), filePath);
}

function testLink(name, linkPath, targetPath) {
  if (!exists(linkPath)) {
    writeCheck(name, false, `missing: ${linkPath}`);
    return;
  }
  const actual = realPathOrEmpty(linkPath);
  const expected = realPathOrEmpty(targetPath);
  writeCheck(name, Boolean(actual && expected && actual.toLowerCase() === expected.toLowerCase()), `${linkPath} -> ${actual}`);
}

function readJsonIfExists(filePath) {
  if (!exists(filePath)) return null;
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function commandLinesFromToml(filePath) {
  if (!exists(filePath)) return [];
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  return lines
    .map((line, index) => ({ line: index + 1, text: line.trim() }))
    .filter((entry) => /^command\s*=/.test(entry.text));
}

function inspectCcSwitch(dbPath) {
  if (!exists(dbPath)) {
    writeCheck('cc-switch:db', false, dbPath, true);
    return;
  }
  if (!commandAvailable('python')) {
    writeCheck('cc-switch:inspect', false, 'python unavailable; cannot inspect sqlite without shell', true);
    return;
  }

  const code = `
import json
import sqlite3
import sys

db_path = sys.argv[1]
con = sqlite3.connect(db_path)
try:
    rows = con.execute("select key, value from settings where key in ('common_config_codex','common_config_claude')").fetchall()
    out = {}
    for key, value in rows:
        low = value.lower()
        out[key] = {
            "has_powershell": "powershell" in low,
            "has_ps1": ".ps1" in low,
            "has_node_prompt_hook": "skill-activation-prompt.js" in low,
        }
    print(json.dumps(out, ensure_ascii=False))
finally:
    con.close()
`;
  try {
    const output = childProcess.execFileSync('python', ['-c', code, dbPath], {
      windowsHide: true,
      encoding: 'utf8',
      stdio: 'pipe',
    });
    const parsed = JSON.parse(output);
    for (const key of ['common_config_codex', 'common_config_claude']) {
      if (!parsed[key]) {
        writeCheck(`cc-switch:${key}`, false, 'missing', true);
        continue;
      }
      writeCheck(`cc-switch:${key}:no-powershell`, !parsed[key].has_powershell && !parsed[key].has_ps1, 'avoid shell-backed hooks');
    }
    if (parsed.common_config_claude) {
      writeCheck('cc-switch:claude-node-prompt-hook', parsed.common_config_claude.has_node_prompt_hook, 'skill-activation-prompt.js');
    }
  } catch (error) {
    writeCheck('cc-switch:inspect', false, error.message, true);
  }
}

function runReplayValidate(options) {
  const replayControl = path.join(options.replayAutopilotRoot, 'scripts', 'Run-UnattendedReplayControl.ps1');
  testPath('replay:control-script', replayControl);
  if (!exists(replayControl)) return;

  if (!options.runReplayValidate) {
    writeCheck('replay:validate-only', false, 'skipped by default to avoid launching PowerShell; pass --run-replay-validate', true);
    return;
  }

  const runner = commandAvailable('pwsh.exe')
    ? 'pwsh.exe'
    : options.allowWindowsPowerShellReplay && commandAvailable('powershell.exe')
      ? 'powershell.exe'
      : '';
  if (!runner) {
    writeCheck('replay:validate-only', false, 'pwsh unavailable; Windows PowerShell fallback not allowed', true);
    return;
  }

  try {
    const output = childProcess.execFileSync(runner, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', replayControl, '-ValidateOnly'], {
      windowsHide: true,
      encoding: 'utf8',
      stdio: 'pipe',
      timeout: 120000,
    });
    writeCheck('replay:validate-only', /"status"\s*:\s*"VALID"/.test(output), runner);
  } catch (error) {
    writeCheck('replay:validate-only', false, error.message);
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));

  testCommand('git', true);
  testCommand('node', true);
  testCommand('python', false);
  testCommand('rtk', false);
  testCommand('pwsh.exe', false);

  const agentsSkills = path.join(options.agentsHome, 'skills');
  testPath('agents:skills', agentsSkills);
  testPath('agents:skill-rules', path.join(agentsSkills, 'skill-rules.json'));
  testPath('agents:hooks', path.join(options.agentsHome, 'hooks'));
  testPath('agents:skill-receipt-hook', path.join(options.agentsHome, 'hooks', 'skill-execution-receipt.js'));
  testPath('agents:workflow-sync-hook', path.join(options.agentsHome, 'hooks', 'workflow-sync-state.js'));
  testPath('agents:node-skill-activation-hook', path.join(options.agentsHome, 'hooks', 'skill-activation-prompt.js'));

  testPath('codex:AGENTS', path.join(options.codexHome, 'AGENTS.md'));
  testPath('codex:RTK', path.join(options.codexHome, 'RTK.md'));
  testPath('codex:skill-rules', path.join(options.codexHome, 'skill-rules.json'));
  testPath('codex:hook-scripts', path.join(options.codexHome, 'hooks', 'scripts'));
  testLink('codex:skills-link', path.join(options.codexHome, 'skills'), agentsSkills);
  writeCheck('codex:no-active-hooks-json', !exists(path.join(options.codexHome, 'hooks.json')), path.join(options.codexHome, 'hooks.json'));

  const codexHookCommands = commandLinesFromToml(path.join(options.codexHome, 'config.toml'));
  const codexPowershellHooks = codexHookCommands.filter((entry) => /powershell|\.ps1/i.test(entry.text));
  writeCheck('codex:hooks-no-powershell', codexPowershellHooks.length === 0, codexPowershellHooks.map((entry) => `${entry.line}:${entry.text}`).join('; ') || 'node/default only');

  testPath('claude:config', path.join(options.claudeHome, 'config.json'));
  testPath('claude:hooks', path.join(options.claudeHome, 'hooks'));
  testLink('claude:skills-link', path.join(options.claudeHome, 'skills'), agentsSkills);

  const claudeSettingsPath = path.join(options.claudeHome, 'settings.json');
  const claudeSettings = readJsonIfExists(claudeSettingsPath);
  if (claudeSettings && claudeSettings.hooks && claudeSettings.hooks.UserPromptSubmit) {
    const commands = [];
    for (const group of claudeSettings.hooks.UserPromptSubmit) {
      for (const hook of group.hooks || []) if (hook.command) commands.push(String(hook.command));
    }
    writeCheck('claude:user-prompt-hook-no-windows-powershell', !commands.some((cmd) => /powershell|\.ps1/i.test(cmd)), 'avoid R6016');
    writeCheck('claude:user-prompt-hook-node', commands.some((cmd) => /node\b/i.test(cmd) && /skill-activation-prompt\.js/i.test(cmd)), 'node skill-activation-prompt.js');
  } else {
    writeCheck('claude:settings-user-prompt-hook', false, 'missing or no UserPromptSubmit hook', true);
  }

  inspectCcSwitch(path.join(os.homedir(), '.cc-switch', 'cc-switch.db'));
  runReplayValidate(options);

  if (failures > 0) {
    console.log(`Verification failed with ${failures} failure(s) and ${warnings} warning(s).`);
    process.exit(1);
  }
  console.log(`Verification passed with ${warnings} warning(s).`);
}

try {
  main();
} catch (error) {
  console.error(`FAIL verify - ${error.message}`);
  process.exit(1);
}
