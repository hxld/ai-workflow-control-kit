#!/usr/bin/env node
'use strict';

/**
 * start-requirement-workspace.js
 *
 * 为需求创建隔离工作空间，支持多服务多分支。
 * 每个需求是一个独立工作空间，包含 PRD、技术方案、测试方案等骨架文件，
 * 以及该需求涉及的每个服务的代码分支（git worktree）。
 *
 * Usage:
 *   node scripts/start-requirement-workspace.js <req-id> --services svc-a,svc-b,svc-c
 *   node scripts/start-requirement-workspace.js <req-id> --services svc-a --base-dir ./workspaces
 *   node scripts/start-requirement-workspace.js --dry-run --req-name "用户登录优化"
 *
 * 典型的完整需求工作空间结构：
 *   workspaces/
 *     req-<id>/
 *       README.md              # 空间入口
 *       req-manifest.yaml      # 需求元信息
 *       prd/                   # PRD 相关
 *       plan/                  # 技术方案
 *       test/                  # 测试方案
 *       services/
 *         svc-a/               # 服务 A 的 worktree（feature/req-<id>）
 *         svc-b/               # 服务 B 的 worktree（feature/req-<id>）
 */

const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

// ── 参数解析 ──────────────────────────────────────────────────

function parseArgs(argv) {
  const result = {
    reqId: '',
    services: [],
    baseDir: path.join(process.cwd(), 'workspaces'),
    repoBaseDir: process.cwd(),
    gitRemote: 'origin',
    branchPrefix: 'feature',
    dryRun: false,
    interactive: false,
  };

  let i = 0;
  // 第一个非 flag 参数作为 reqId
  if (i < argv.length && !argv[i].startsWith('--')) {
    result.reqId = argv[i];
    i += 1;
  }

  for (; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--services' || arg === '-s') {
      result.services = (argv[++i] || '').split(',').filter(Boolean);
    } else if (arg === '--base-dir') {
      result.baseDir = path.resolve(process.cwd(), argv[++i] || 'workspaces');
    } else if (arg === '--repo-base-dir') {
      result.repoBaseDir = path.resolve(process.cwd(), argv[++i] || '');
    } else if (arg === '--git-remote') {
      result.gitRemote = argv[++i] || 'origin';
    } else if (arg === '--branch-prefix') {
      result.branchPrefix = argv[++i] || 'feature';
    } else if (arg === '--dry-run') {
      result.dryRun = true;
    } else if (arg === '--interactive') {
      result.interactive = true;
    } else if (arg === '--req-name') {
      // 仅用于 dry-run 标注
      result.reqName = argv[++i] || '';
    } else if (!result.reqId && !arg.startsWith('--')) {
      result.reqId = arg;
    }
  }

  return result;
}

// ── 工具函数 ──────────────────────────────────────────────────

function execFile(command, args = [], opts = {}) {
  const defaults = { stdio: 'pipe', encoding: 'utf-8', timeout: 30000, windowsHide: true };
  const merged = { ...defaults, ...opts };
  try {
    const r = childProcess.execFileSync(command, args, merged);
    return { ok: true, stdout: (r || '').toString().trim(), stderr: '' };
  } catch (e) {
    return { ok: false, stdout: (e.stdout || '').toString().trim(), stderr: (e.stderr || '').toString().trim() };
  }
}

function requireGit(args, detail) {
  const result = execFile('git', args);
  if (!result.ok) {
    const message = result.stderr || result.stdout || 'unknown git failure';
    throw new Error(`${detail}: ${message}`);
  }
  return result;
}

function dryRunLog(msg) {
  process.stderr.write(`  [dry-run] ${msg}\n`);
}

function log(level, msg) {
  const prefix = level === 'ok' ? '✅' : level === 'warn' ? '⚠️' : level === 'err' ? '❌' : '➡️';
  console.log(`${prefix} ${msg}`);
}

function mkdirIfNotExists(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

// ── 核心逻辑 ──────────────────────────────────────────────────

function createWorkspace(args) {
  const { reqId, services, baseDir, dryRun, repoBaseDir, gitRemote, branchPrefix } = args;
  const branchName = `${branchPrefix}/req-${reqId}`;
  const wsDir = path.join(baseDir, `req-${reqId}`);
  const servicesDir = path.join(wsDir, 'services');

  log('ok', `需求工作空间: ${wsDir}`);
  if (dryRun) log('warn', '只运行 dry-run，不会实际创建');

  // ── Step 1: 创建主目录结构 ──
  log('ok', `[1/6] 创建目录结构...`);
  if (dryRun) {
    dryRunLog(`mkdir -p ${wsDir}/{prd,plan,test,services}`);
  } else {
    mkdirIfNotExists(wsDir);
    mkdirIfNotExists(path.join(wsDir, 'prd'));
    mkdirIfNotExists(path.join(wsDir, 'plan'));
    mkdirIfNotExists(path.join(wsDir, 'test'));
    mkdirIfNotExists(servicesDir);
  }

  // ── Step 2: 创建需求清单文件 ──
  log('ok', `[2/6] 创建需求元信息...`);
  if (!dryRun) {
    const manifest = `# 需求清单

req-id: ${reqId}
created: ${new Date().toISOString().split('T')[0]}
services: [${services.join(', ')}]
branch: ${branchName}
status: initialized

## 目录

- \`prd/\` — PRD 相关文档
- \`plan/\` — 技术方案
- \`test/\` — 测试方案
- \`services/\` — 各服务 worktree
`;
    fs.writeFileSync(path.join(wsDir, 'README.md'), manifest, 'utf-8');

    // req-manifest.yaml
    const yaml = `req_id: "${reqId}"
created: "${new Date().toISOString().split('T')[0]}"
status: initialized
services:
${services.map((s) => `  - "${s}"`).join('\n')}
branch: "${branchName}"
artifacts:
  prd: "prd/"
  plan: "plan/"
  test: "test/"
`;
    fs.writeFileSync(path.join(wsDir, 'req-manifest.yaml'), yaml, 'utf-8');
  }

  // ── Step 3: 创建骨架文档 ──
  log('ok', `[3/6] 创建骨架文档...`);
  if (!dryRun) {
    const prdSkeleton = `# PRD: ${reqId}

## 项目背景

<!-- 描述为什么要做这个需求 -->

## 业务目标

<!-- 描述要达到什么效果 -->

## 涉及部门

<!-- 列出参与团队 -->

## 影响系统

${services.map((s) => `- ${s}`).join('\n')}

## 验收标准

<!-- 如何判断做完 -->

## 时间期望

<!-- 期望上线时间 -->
`;
    fs.writeFileSync(path.join(wsDir, 'prd', 'README.md'), prdSkeleton, 'utf-8');

    const planSkeleton = `# 技术方案: ${reqId}

## 概述

<!-- 方案一句话描述 -->

## 涉及服务

${services.map((s) => `- ${s}`).join('\n')}

## 方案要点

<!-- 核心设计决策 -->

## 影响面分析

<!-- 哪些模块/接口会变化 -->

## 风险与降级

<!-- 潜在风险和应对 -->

## 验收方式

<!-- 如何验证方案正确 -->
`;
    fs.writeFileSync(path.join(wsDir, 'plan', 'README.md'), planSkeleton, 'utf-8');

    const testSkeleton = `# 测试方案: ${reqId}

## 测试范围

<!-- 哪些功能点需要测试 -->

## 测试策略

<!-- 单元测试 / 集成测试 / E2E -->

## 边界用例

<!-- 异常路径、边界值 -->

## 回归关注点

<!-- 修改影响到的已有功能 -->
`;
    fs.writeFileSync(path.join(wsDir, 'test', 'README.md'), testSkeleton, 'utf-8');
  }

  // ── Step 4: 为每个服务创建 worktree ──
  if (services.length > 0) {
    log('ok', `[4/6] 创建服务 worktree（${services.length} 个服务）...`);

    for (const svc of services) {
      const svcPath = path.join(repoBaseDir, svc);

      if (!dryRun) {
        // 检查服务目录是否存在
        if (!fs.existsSync(svcPath)) {
          log('warn', `服务目录不存在: ${svcPath}，跳过 worktree`);
          const svcReadme = `# ${svc}

<!-- 服务 ${svc} 尚未配置 worktree，请在对应仓库中创建 feature 分支 -->
`;
          fs.writeFileSync(path.join(servicesDir, `${svc}.md`), svcReadme, 'utf-8');
          continue;
        }

        // 检查 git repo
        const gitCheck = execFile('git', ['-C', svcPath, 'rev-parse', '--git-dir']);
        if (!gitCheck.ok) {
          log('warn', `不是 git 仓库: ${svcPath}，跳过 worktree`);
          continue;
        }

        // 检查分支是否已存在
        const branchCheck = execFile('git', ['-C', svcPath, 'rev-parse', '--verify', branchName]);
        const svcWorktreeDir = path.join(servicesDir, svc);
        if (fs.existsSync(svcWorktreeDir)) {
          throw new Error(`worktree 目标目录已存在: ${svcWorktreeDir}`);
        }

        if (branchCheck.ok) {
          // 分支已存在 → add worktree
          log('ok', `  分支 ${branchName} 已存在于 ${svc}，添加 worktree`);
          requireGit(['-C', svcPath, 'worktree', 'add', svcWorktreeDir, branchName], `添加 worktree 失败: ${svc}`);
        } else {
          // 分支不存在 → worktree add -b 在隔离目录创建，避免污染主工作区当前分支。
          const head = requireGit(['-C', svcPath, 'rev-parse', '--verify', 'HEAD'], `读取基线提交失败: ${svc}`).stdout;
          log('ok', `  从当前 HEAD 创建 ${branchName} 于 ${svc}，添加 worktree`);
          requireGit(['-C', svcPath, 'worktree', 'add', '-b', branchName, svcWorktreeDir, head], `创建分支和 worktree 失败: ${svc}`);
        }

        log('ok', `  worktree: ${svcWorktreeDir}`);
      } else {
        dryRunLog(`git -C "${svcPath}" worktree add -b "${branchName}" "${servicesDir}/${svc}" HEAD`);
      }
    }
  } else {
    log('warn', `[4/6] 跳过 worktree（未指定 --services）`);
  }

  // ── Step 5: 注入知识库上下文（可选）─
  log('ok', `[5/6] 注入 Kit 知识库引用...`);
  if (!dryRun) {
    const kitRef = `# Kit 知识库引用

> 以下引用指向 ai-workflow-control-kit 的方法论文档，供 Agent 执行时加载。

## 知识分类体系

- 四类知识：\`agents/reference/knowledge-base-design/knowledge-taxonomy.md\`
- 三循环运营：\`agents/reference/knowledge-base-design/three-loops.md\`

## 系统蒸馏方法论（如本需求涉及已有业务系统分析）

- 蒸馏概览：\`agents/reference/distillation-methodology/OVERVIEW.md\`
- 七阶段流程：\`agents/reference/distillation-methodology/process-s0-to-s6.md\`

## 工作流编排

- 完整链路：\`docs/WORKFLOW_MAP.md\`
`;
    fs.writeFileSync(path.join(wsDir, '.kit-references.md'), kitRef, 'utf-8');
  }

  // ── Step 6: 输出总结 ──
  log('ok', `[6/6] 工作空间初始化完成`);
  console.log(``);
  console.log(`📂 工作空间: ${wsDir}`);
  console.log(`   ├── prd/          PRD 文档`);
  console.log(`   ├── plan/         技术方案`);
  console.log(`   ├── test/         测试方案`);
  console.log(`   ├── services/     服务 worktree`);
  console.log(`   ├── .kit-references.md  知识库引用`);
  console.log(`   └── req-manifest.yaml   需求元信息`);

  if (services.length > 0) {
    console.log(`\n🌿 分支: ${branchName}`);
    services.forEach((s) => {
      console.log(`   ${s}: ${branchPrefix}/req-${reqId}`);
    });
  }

  console.log(`\n💡 下一步: 编辑 prd/README.md 补充 PRD，然后运行 dev-workflow 开始开发`);
}

// ── 入口 ──────────────────────────────────────────────────────

function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.interactive) {
    console.log('=== 需求工作空间向导 ===\n');
    const readline = require('readline');
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

    const q = (query) => new Promise((resolve) => rl.question(query, resolve));

    (async () => {
      args.reqId = args.reqId || (await q('需求 ID（必填）: '));
      const svcInput = await q('涉及服务（逗号分隔，如 svc-a,svc-b）: ');
      args.services = svcInput.split(',').map((s) => s.trim()).filter(Boolean);
      const baseDirInput = await q(`工作空间根目录（默认: ${args.baseDir}）: `);
      if (baseDirInput.trim()) args.baseDir = path.resolve(process.cwd(), baseDirInput.trim());
      const dryRunInput = await q('只 dry-run？（y/N）: ');
      if (dryRunInput.toLowerCase() === 'y') args.dryRun = true;

      rl.close();
      createWorkspace(args);
    })();
    return;
  }

  if (!args.reqId) {
    console.error('❌ 错误：请提供需求 ID');
    console.error('用法: node scripts/start-requirement-workspace.js <req-id> --services svc-a,svc-b');
    console.error('       node scripts/start-requirement-workspace.js --interactive');
    process.exit(1);
  }

  createWorkspace(args);
}

main();
