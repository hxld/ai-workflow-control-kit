#!/usr/bin/env node
'use strict';

const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const args = new Set(process.argv.slice(2));
const asJson = args.has('--json');
const killHungAstParser = args.has('--kill-hung-ast-parser');

const IS_WIN32 = os.platform() === 'win32';

function execFile(file, argv, options = {}) {
  return childProcess.execFileSync(file, argv, {
    encoding: 'utf8',
    windowsHide: true,
    maxBuffer: 1024 * 1024 * 20,
    ...options,
  });
}

function main() {
  if (!IS_WIN32) {
    console.log('diagnose-powershell-r6016 is Windows-only (uses WMI, tasklist.exe, cscript.exe).');
    console.log('On macOS/Linux, PowerShell runs via pwsh and is not affected by R6016.');
    process.exit(0);
  }

  const scriptPath = writeTempWmiScript();
  let processes;
  try {
    const raw = execFile('cscript.exe', ['//NoLogo', scriptPath]);
    processes = JSON.parse(raw || '[]');
  } finally {
    try {
      fs.rmSync(scriptPath, { force: true });
    } catch {
      // Ignore cleanup failures.
    }
  }

  const tasklistCsv = tasklistRows();
  const summary = summarize(processes, tasklistCsv);
  const killed = killHungAstParser ? killHungAstParsers(summary) : [];
  const result = {
    generatedAt: new Date().toISOString(),
    killHungAstParser,
    processes: summary,
    killed,
  };

  if (asJson) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    printHuman(summary, killed);
  }

  const killedPidSet = new Set(killed.filter((item) => typeof item === 'number'));
  const dangerous = summary.filter((item) =>
    !killedPidSet.has(item.pid) && (
    item.classification === 'rtk_proxy_powershell' ||
    item.classification === 'build_via_powershell' ||
    (item.classification === 'codex_ast_parser' && item.notResponding)
    )
  );
  process.exit(dangerous.length > 0 ? 2 : 0);
}

function writeTempWmiScript() {
  const script = String.raw`
function esc(s) {
  if (s === null || s === undefined) return "";
  return String(s)
    .replace(/\\/g, "\\\\")
    .replace(/"/g, "\\\"")
    .replace(/\r/g, "\\r")
    .replace(/\n/g, "\\n");
}
function q(s) { return "\"" + esc(s) + "\""; }
function firstProcessByPid(svc, pid) {
  var e = new Enumerator(svc.ExecQuery(
    "SELECT ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate FROM Win32_Process WHERE ProcessId=" + pid
  ));
  if (e.atEnd()) return null;
  return e.item();
}
var svc = GetObject("winmgmts:{impersonationLevel=impersonate}!\\\\.\\root\\cimv2");
var rows = [];
var e = new Enumerator(svc.ExecQuery(
  "SELECT ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,CreationDate FROM Win32_Process WHERE Name='powershell.exe' OR Name='pwsh.exe'"
));
for (; !e.atEnd(); e.moveNext()) {
  var p = e.item();
  var parent = firstProcessByPid(svc, p.ParentProcessId);
  rows.push("{"
    + "\"pid\":" + p.ProcessId + ","
    + "\"ppid\":" + p.ParentProcessId + ","
    + "\"name\":" + q(p.Name) + ","
    + "\"created\":" + q(p.CreationDate) + ","
    + "\"exe\":" + q(p.ExecutablePath) + ","
    + "\"command\":" + q(p.CommandLine) + ","
    + "\"parentName\":" + q(parent ? parent.Name : "") + ","
    + "\"parentExe\":" + q(parent ? parent.ExecutablePath : "") + ","
    + "\"parentCommand\":" + q(parent ? parent.CommandLine : "")
    + "}");
}
WScript.Echo("[" + rows.join(",") + "]");
`;

  const filePath = path.join(os.tmpdir(), `diagnose-powershell-r6016-${process.pid}.js`);
  fs.writeFileSync(filePath, script, 'utf8');
  return filePath;
}

function decodeEncodedCommand(command) {
  const match = String(command || '').match(/-EncodedCommand\s+([A-Za-z0-9+/=]+)/i);
  if (!match) return '';
  try {
    return Buffer.from(match[1], 'base64').toString('utf16le');
  } catch {
    return '';
  }
}

function classify(processInfo) {
  const command = String(processInfo.command || '');
  const decoded = decodeEncodedCommand(command);
  const all = `${command}\n${decoded}`.toLowerCase();
  const parent = String(processInfo.parentName || '').toLowerCase();

  if (decoded.includes('Long-lived PowerShell AST parser used by the Rust command-safety layer on Windows.')) {
    return 'codex_ast_parser';
  }
  if (all.includes('get-ciminstance win32_perfformatteddata_perfproc_process')) {
    return 'codex_process_monitor';
  }
  if (parent === 'rtk.exe' || all.includes('rtk proxy powershell') || all.includes('rtk run powershell')) {
    return 'rtk_proxy_powershell';
  }
  if (all.includes('mvn --%') || all.includes('mvn.cmd') || all.includes('mvn ')) {
    return 'build_via_powershell';
  }
  if (parent.includes('codex')) {
    return 'codex_spawned_powershell';
  }
  if (parent.includes('claude')) {
    return 'claude_spawned_powershell';
  }
  return 'unknown_powershell';
}

function tasklistRows() {
  try {
    const raw = execFile('tasklist.exe', ['/FI', 'IMAGENAME eq powershell.exe', '/V', '/FO', 'CSV']);
    return raw;
  } catch {
    return '';
  }
}

function isNotResponding(pid, tasklistCsv) {
  return String(tasklistCsv || '')
    .split(/\r?\n/)
    .some((line) => line.includes(`"${pid}"`) && /Not Responding/i.test(line));
}

function compactCommand(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function summarize(processes, tasklistCsv) {
  return processes.map((item) => {
    const decoded = decodeEncodedCommand(item.command);
    return {
      pid: item.pid,
      ppid: item.ppid,
      name: item.name,
      parentName: item.parentName,
      classification: classify(item),
      notResponding: isNotResponding(item.pid, tasklistCsv),
      command: compactCommand(item.command).slice(0, 500),
      decodedFirstLine: decoded.split(/\r?\n/).find((line) => line.trim()) || '',
    };
  });
}

function killHungAstParsers(summary) {
  const killed = [];
  for (const item of summary) {
    if (item.classification !== 'codex_ast_parser' || !item.notResponding) continue;
    try {
      execFile('taskkill.exe', ['/PID', String(item.pid), '/F']);
      killed.push(item.pid);
    } catch (error) {
      killed.push({ pid: item.pid, error: error.message });
    }
  }
  return killed;
}

function printHuman(summary, killed) {
  if (summary.length === 0) {
    console.log('No powershell.exe or pwsh.exe processes found.');
    return;
  }

  console.log('PowerShell process diagnosis');
  console.log('');
  for (const item of summary) {
    const status = item.notResponding ? 'Not Responding' : 'Running/Unknown';
    console.log(`PID ${item.pid} <- ${item.parentName || 'unknown'} | ${item.classification} | ${status}`);
    if (item.decodedFirstLine) console.log(`  decoded: ${item.decodedFirstLine}`);
    console.log(`  command: ${item.command}`);
  }

  if (killed.length > 0) {
    console.log('');
    console.log(`Killed hung Codex AST parser PID(s): ${killed.join(', ')}`);
  }

  console.log('');
  console.log('Guidance:');
  console.log('- codex_ast_parser means Codex Desktop internal Windows command-safety parsing, not workflow-kit hooks.');
  console.log('- rtk_proxy_powershell means a command explicitly used RTK with Windows PowerShell; prefer direct executables.');
  console.log('- build_via_powershell means a build/test command is still routed through Windows PowerShell.');
}

main();
