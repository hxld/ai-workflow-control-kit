#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');

const LAYER_MAP = {
  'workflow-router': 'L0',
  'restore-context': 'L0',
  'pre-flight-check': 'L1',
  'sync-progress': 'L1',
  'retro': 'L3',
  'compound-learning': 'L3',
  'knowledge-refresh': 'L3',
};

function parseArgs(argv) {
  const args = {
    days: 7,
    top: 10,
    format: 'markdown',
    log: path.join(os.homedir(), '.agents', 'logs', 'skill-hooks.log'),
    out: path.join(os.homedir(), '.agents', 'logs', 'skill-hooks-dashboard.md'),
  };

  for (let i = 0; i < argv.length; i += 1) {
    const current = argv[i];
    const next = argv[i + 1];
    if (current === '--days' && next) {
      args.days = Math.max(1, Number.parseInt(next, 10) || 7);
      i += 1;
    } else if (current === '--top' && next) {
      args.top = Math.max(1, Number.parseInt(next, 10) || 10);
      i += 1;
    } else if (current === '--format' && next) {
      args.format = next === 'json' ? 'json' : 'markdown';
      i += 1;
    } else if (current === '--json') {
      args.format = 'json';
    } else if (current === '--log' && next) {
      args.log = path.resolve(next);
      i += 1;
    } else if (current === '--out' && next) {
      args.out = path.resolve(next);
      i += 1;
    }
  }

  if (!argv.includes('--out') && args.format === 'json') {
    args.out = path.join(os.homedir(), '.agents', 'logs', 'skill-hooks-dashboard.json');
  }

  return args;
}

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function readLines(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`日志文件不存在: ${filePath}`);
  }
  return fs.readFileSync(filePath, 'utf8').split(/\r?\n/).filter(Boolean);
}

function parseTimestamp(raw) {
  return new Date(raw.replace(' ', 'T'));
}

function makeCounter() {
  return new Map();
}

function increment(counter, key, amount = 1) {
  counter.set(key, (counter.get(key) || 0) + amount);
}

function sortCounter(counter) {
  return Array.from(counter.entries()).sort((a, b) => {
    if (b[1] !== a[1]) return b[1] - a[1];
    return a[0].localeCompare(b[0], 'zh-CN');
  });
}

function topRows(counter, limit) {
  return sortCounter(counter).slice(0, limit);
}

function layerOf(skill) {
  return LAYER_MAP[skill] || 'L2';
}

function comboKey(skills) {
  return skills.slice().sort((a, b) => a.localeCompare(b, 'en')).join(' + ');
}

function formatLayers(skills) {
  return Array.from(new Set(skills.map(layerOf))).sort().join(', ');
}

function verdictForCombo(skills) {
  const layers = new Set(skills.map(layerOf));
  const hasL0 = layers.has('L0');
  const hasL3 = layers.has('L3');
  const l2Count = skills.filter((skill) => layerOf(skill) === 'L2').length;
  const nonL1Count = skills.filter((skill) => layerOf(skill) !== 'L1').length;

  if (hasL0 && nonL1Count >= 3) {
    return {
      label: '可疑',
      reason: '入口路由同时叠加了过多执行/沉淀技能',
    };
  }

  if (hasL3 && l2Count >= 1 && !skills.includes('ship-release') && !skills.includes('sync-progress')) {
    return {
      label: '可疑',
      reason: '收尾沉淀技能过早夹在主执行流中',
    };
  }

  return {
    label: '正常',
    reason: '当前更像通用守卫与主技能的正常叠加',
  };
}

function escapeCell(value) {
  return String(value).replace(/\|/g, '\\|');
}

function markdownTable(headers, rows) {
  const head = `| ${headers.join(' | ')} |`;
  const split = `| ${headers.map(() => '---').join(' | ')} |`;
  const body = rows.map((row) => `| ${row.map((cell) => escapeCell(cell)).join(' | ')} |`);
  return [head, split].concat(body).join('\n');
}

function analyze(lines, days) {
  const sourceCounter = makeCounter();
  const skillCounter = makeCounter();
  const recentSkillCounter = makeCounter();
  const comboCounter = makeCounter();
  const recentComboCounter = makeCounter();
  const guardCounter = makeCounter();
  const recentGuardCounter = makeCounter();
  const recentSourceCounter = makeCounter();

  const allMatchEvents = [];
  const recentMatchEvents = [];
  const timestamps = [];
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

  const lineRe = /^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]\[([^\]]+)\] (.+)$/;
  const matchRe = /^matched skills(?: via [^:]+)?: (.+)$/;
  const guardRe = /^blocked (.+)$/;

  for (const line of lines) {
    const match = line.match(lineRe);
    if (!match) continue;

    const [, rawTs, source, message] = match;
    const timestamp = parseTimestamp(rawTs);
    if (Number.isNaN(timestamp.getTime())) continue;

    timestamps.push(timestamp);
    increment(sourceCounter, source);

    const isRecent = timestamp >= cutoff;
    if (isRecent) {
      increment(recentSourceCounter, source);
    }

    const skillMatch = message.match(matchRe);
    if (skillMatch) {
      const skills = skillMatch[1].split(',').map((item) => item.trim()).filter(Boolean);
      if (skills.length > 0) {
        const normalizedCombo = comboKey(skills);
        increment(comboCounter, normalizedCombo);
        allMatchEvents.push({ timestamp, source, skills, combo: normalizedCombo });
        for (const skill of skills) {
          increment(skillCounter, skill);
        }
        if (isRecent) {
          increment(recentComboCounter, normalizedCombo);
          recentMatchEvents.push({ timestamp, source, skills, combo: normalizedCombo });
          for (const skill of skills) {
            increment(recentSkillCounter, skill);
          }
        }
      }
      continue;
    }

    if (source === 'guard') {
      const guardMatch = message.match(guardRe);
      if (guardMatch) {
        increment(guardCounter, guardMatch[1]);
        if (isRecent) {
          increment(recentGuardCounter, guardMatch[1]);
        }
      }
    }
  }

  const firstSeen = timestamps.length > 0 ? new Date(Math.min(...timestamps)) : null;
  const lastSeen = timestamps.length > 0 ? new Date(Math.max(...timestamps)) : null;

  return {
    firstSeen,
    lastSeen,
    sourceCounter,
    recentSourceCounter,
    skillCounter,
    recentSkillCounter,
    comboCounter,
    recentComboCounter,
    guardCounter,
    recentGuardCounter,
    allMatchEvents,
    recentMatchEvents,
    uniqueSkills: skillCounter.size,
  };
}

function suspiciousRows(counter, limit) {
  return sortCounter(counter)
    .map(([combo, count]) => {
      const skills = combo.split(' + ').map((item) => item.trim()).filter(Boolean);
      const verdict = verdictForCombo(skills);
      return { combo, count, layers: formatLayers(skills), verdict };
    })
    .filter((item) => item.verdict.label === '可疑')
    .slice(0, limit);
}

function formatDate(date) {
  return date ? date.toISOString().replace('T', ' ').slice(0, 19) : 'N/A';
}

function formatDateOnly(date) {
  return date ? date.toISOString().slice(0, 10) : null;
}

function totalCount(counter) {
  return Array.from(counter.values()).reduce((sum, value) => sum + value, 0);
}

function counterToRows(counter, mapper) {
  return sortCounter(counter).map(([key, count], index) => mapper(key, count, index));
}

function toSlug(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9\u4e00-\u9fa5]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function buildObsidianPayload(result, args) {
  const generatedAt = new Date();
  const topSkill = topRows(result.recentSkillCounter, 1)[0] || null;
  const topCombo = topRows(result.recentComboCounter, 1)[0] || null;
  const suspicious = suspiciousRows(result.comboCounter, args.top);
  const recentGuardBlocks = totalCount(result.recentGuardCounter);

  return {
    record_type: 'skill-hooks-dashboard',
    generated_at: generatedAt.toISOString(),
    generated_date: formatDateOnly(generatedAt),
    window_days: args.days,
    tags: ['skill-hooks', 'dashboard', 'weekly'],
    frontmatter: {
      type: 'skill-hooks-dashboard',
      generated_at: generatedAt.toISOString(),
      generated_date: formatDateOnly(generatedAt),
      window_days: args.days,
      total_events: totalCount(result.sourceCounter),
      skill_match_events: result.allMatchEvents.length,
      recent_skill_match_events: result.recentMatchEvents.length,
      unique_skills: result.uniqueSkills,
      guard_blocks: totalCount(result.guardCounter),
      recent_guard_blocks: recentGuardBlocks,
      active_sources: result.recentSourceCounter.size,
      top_skill: topSkill ? topSkill[0] : null,
      top_skill_count: topSkill ? topSkill[1] : 0,
      top_combo: topCombo ? topCombo[0] : null,
      top_combo_count: topCombo ? topCombo[1] : 0,
      suspicious_combo_count: suspicious.length,
    },
    summary_cards: [
      { key: 'total_events', label: '日志总事件数', value: totalCount(result.sourceCounter) },
      { key: 'skill_match_events', label: '技能命中事件数', value: result.allMatchEvents.length },
      { key: 'recent_skill_match_events', label: `最近${args.days}天命中`, value: result.recentMatchEvents.length },
      { key: 'unique_skills', label: '唯一命中技能数', value: result.uniqueSkills },
      { key: 'guard_blocks', label: 'Guard阻断次数', value: totalCount(result.guardCounter) },
    ],
    weekly_lines: [
      `本周期（最近 ${args.days} 天）技能命中 ${result.recentMatchEvents.length} 次。`,
      `最常出现的技能：${topRows(result.recentSkillCounter, Math.min(5, args.top)).map(([skill, count]) => `${skill} (${count})`).join('，') || '无'}`,
      `最常见的组合：${topRows(result.recentComboCounter, Math.min(5, args.top)).map(([combo, count]) => `${combo} (${count})`).join('；') || '无'}`,
      `Guard 阻断重点：${topRows(result.recentGuardCounter, Math.min(5, args.top)).map(([reason, count]) => `${reason} (${count})`).join('；') || '无'}`,
    ],
    tables: {
      sources: counterToRows(result.sourceCounter, (source, count) => ({
        source,
        source_key: toSlug(source),
        count,
      })),
      top_skills: topRows(result.skillCounter, args.top).map(([skill, count], index) => ({
        rank: index + 1,
        skill,
        skill_key: toSlug(skill),
        count,
        layer: layerOf(skill),
      })),
      top_combos: topRows(result.comboCounter, args.top).map(([combo, count]) => {
        const skills = combo.split(' + ');
        const verdict = verdictForCombo(skills);
        return {
          combo,
          combo_key: toSlug(combo),
          count,
          layers: Array.from(new Set(skills.map(layerOf))).sort(),
          verdict: verdict.label,
          reason: verdict.reason,
        };
      }),
      suspicious_combos: suspicious.map((item) => ({
        combo: item.combo,
        combo_key: toSlug(item.combo),
        count: item.count,
        layers: item.layers.split(', ').filter(Boolean),
        reason: item.verdict.reason,
      })),
      guard_reasons: counterToRows(result.guardCounter, (reason, count) => ({
        reason,
        reason_key: toSlug(reason),
        count,
      })),
    },
  };
}

function buildJsonReport(result, args) {
  const suspicious = suspiciousRows(result.comboCounter, args.top);

  return {
    generatedAt: new Date().toISOString(),
    logPath: args.log,
    outputPath: args.out,
    format: args.format,
    windowDays: args.days,
    coverage: {
      firstSeenAt: result.firstSeen ? result.firstSeen.toISOString() : null,
      lastSeenAt: result.lastSeen ? result.lastSeen.toISOString() : null,
    },
    summary: {
      totalEvents: totalCount(result.sourceCounter),
      skillMatchEvents: result.allMatchEvents.length,
      recentSkillMatchEvents: result.recentMatchEvents.length,
      uniqueSkills: result.uniqueSkills,
      guardBlocks: totalCount(result.guardCounter),
    },
    weeklySummary: {
      topSkills: topRows(result.recentSkillCounter, Math.min(5, args.top)).map(([skill, count]) => ({ skill, count, layer: layerOf(skill) })),
      topCombos: topRows(result.recentComboCounter, Math.min(5, args.top)).map(([combo, count]) => ({ combo, count })),
      topGuards: topRows(result.recentGuardCounter, Math.min(5, args.top)).map(([reason, count]) => ({ reason, count })),
    },
    sources: counterToRows(result.sourceCounter, (source, count) => ({ source, count })),
    topSkills: topRows(result.skillCounter, args.top).map(([skill, count], index) => ({
      rank: index + 1,
      skill,
      count,
      layer: layerOf(skill),
    })),
    topCombos: topRows(result.comboCounter, args.top).map(([combo, count]) => {
      const skills = combo.split(' + ');
      const verdict = verdictForCombo(skills);
      return {
        combo,
        count,
        layers: Array.from(new Set(skills.map(layerOf))).sort(),
        verdict: verdict.label,
        reason: verdict.reason,
      };
    }),
    suspiciousCombos: suspicious.map((item) => ({
      combo: item.combo,
      count: item.count,
      layers: item.layers.split(', ').filter(Boolean),
      reason: item.verdict.reason,
    })),
    guardReasons: counterToRows(result.guardCounter, (reason, count) => ({ reason, count })),
    recentWindow: {
      summary: {
        matchEvents: result.recentMatchEvents.length,
        uniqueSkills: result.recentSkillCounter.size,
        guardBlocks: totalCount(result.recentGuardCounter),
        activeSources: result.recentSourceCounter.size,
      },
      topSkills: topRows(result.recentSkillCounter, Math.min(5, args.top)).map(([skill, count]) => ({ skill, count, layer: layerOf(skill) })),
      topCombos: topRows(result.recentComboCounter, Math.min(5, args.top)).map(([combo, count]) => ({ combo, count })),
    },
    obsidian: buildObsidianPayload(result, args),
  };
}

function buildReport(result, args) {
  const topSkills = topRows(result.skillCounter, args.top);
  const topRecentSkills = topRows(result.recentSkillCounter, Math.min(5, args.top));
  const topCombos = topRows(result.comboCounter, args.top);
  const topRecentCombos = topRows(result.recentComboCounter, Math.min(5, args.top));
  const topGuards = topRows(result.guardCounter, Math.min(8, args.top));
  const topRecentGuards = topRows(result.recentGuardCounter, Math.min(5, args.top));
  const suspicious = suspiciousRows(result.comboCounter, args.top);
  const topSources = topRows(result.sourceCounter, 8);

  const summaryLines = [
    '# Skill Hooks 日志统计面板',
    '',
    `- 生成时间：${formatDate(new Date())}`,
    `- 日志文件：\`${args.log}\``,
    `- 输出文件：\`${args.out}\``,
    `- 统计窗口：全量日志 + 最近 ${args.days} 天摘要`,
    `- 日志覆盖：${formatDate(result.firstSeen)} -> ${formatDate(result.lastSeen)}`,
    '',
    '## 一页摘要',
    '',
    `- 日志总事件数：${totalCount(result.sourceCounter)}`,
    `- 技能命中事件数：${result.allMatchEvents.length}`,
    `- 最近 ${args.days} 天技能命中事件数：${result.recentMatchEvents.length}`,
    `- 唯一命中技能数：${result.uniqueSkills}`,
    `- Guard 阻断次数：${totalCount(result.guardCounter)}`,
    '',
    '## 可直接贴周报',
    '',
    `- 本周期（最近 ${args.days} 天）技能命中 ${result.recentMatchEvents.length} 次，最常出现的技能是：${topRecentSkills.map(([skill, count]) => `${skill} (${count})`).join('，') || '无'}`,
    `- 本周期最常见的组合是：${topRecentCombos.map(([combo, count]) => `${combo} (${count})`).join('；') || '无'}`,
    `- 本周期 Guard 阻断重点是：${topRecentGuards.map(([reason, count]) => `${reason} (${count})`).join('；') || '无'}`,
    '',
    '## 来源分布',
    '',
    markdownTable(
      ['来源', '事件数'],
      topSources.map(([source, count]) => [source, count]),
    ),
    '',
    '## Top 命中技能',
    '',
    markdownTable(
      ['排名', '技能', '命中次数', '层级'],
      topSkills.map(([skill, count], index) => [index + 1, skill, count, layerOf(skill)]),
    ),
    '',
    '## 常见技能组合',
    '',
    markdownTable(
      ['组合', '次数', '层级', '判定'],
      topCombos.map(([combo, count]) => {
        const skills = combo.split(' + ');
        return [combo, count, formatLayers(skills), verdictForCombo(skills).label];
      }),
    ),
    '',
    '## 可疑组合（启发式）',
    '',
    suspicious.length > 0
      ? markdownTable(
          ['组合', '次数', '层级', '原因'],
          suspicious.map((item) => [item.combo, item.count, item.layers, item.verdict.reason]),
        )
      : '当前未识别出需要额外关注的可疑组合。',
    '',
    '## Guard 阻断原因',
    '',
    topGuards.length > 0
      ? markdownTable(
          ['原因', '次数'],
          topGuards.map(([reason, count]) => [reason, count]),
        )
      : '当前日志中未出现 Guard 阻断。',
    '',
    `## 最近 ${args.days} 天摘要`,
    '',
    markdownTable(
      ['项', '值'],
      [
        ['命中事件数', result.recentMatchEvents.length],
        ['唯一命中技能数', result.recentSkillCounter.size],
        ['Guard 阻断次数', totalCount(result.recentGuardCounter)],
        ['活跃来源数', result.recentSourceCounter.size],
      ],
    ),
    '',
    topRecentSkills.length > 0
      ? markdownTable(
          ['最近 Top 技能', '次数'],
          topRecentSkills.map(([skill, count]) => [skill, count]),
        )
      : '最近窗口内没有技能命中。',
    '',
    topRecentCombos.length > 0
      ? markdownTable(
          ['最近 Top 组合', '次数'],
          topRecentCombos.map(([combo, count]) => [combo, count]),
        )
      : '最近窗口内没有组合命中。',
    '',
    '## 使用说明',
    '',
    '```powershell',
    'node %USERPROFILE%\\.agents\\hooks\\skill-hooks-dashboard.js',
    'node %USERPROFILE%\\.agents\\hooks\\skill-hooks-dashboard.js --json',
    'node %USERPROFILE%\\.agents\\hooks\\skill-hooks-dashboard.js --format json --out D:\\study\\hxld_vault\\learning\\raw\\sources\\ai-knowledge\\skill-hooks-weekly.json',
    'node %USERPROFILE%\\.agents\\hooks\\skill-hooks-dashboard.js --days 14',
    'node %USERPROFILE%\\.agents\\hooks\\skill-hooks-dashboard.js --days 7 --out D:\\study\\hxld_vault\\learning\\raw\\sources\\ai-knowledge\\skill-hooks-weekly.md',
    '```',
    '',
    '判定说明：',
    '- `L0`：入口路由',
    '- `L1`：通用守卫',
    '- `L2`：专用执行',
    '- `L3`：收尾沉淀',
    '- “可疑组合”是启发式提醒，不等于必须修改规则，应结合上下文和真实日志回放判断。',
    '',
  ];

  return summaryLines.join('\n');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const lines = readLines(args.log);
  const result = analyze(lines, args.days);
  const report = args.format === 'json'
    ? `${JSON.stringify(buildJsonReport(result, args), null, 2)}\n`
    : `${buildReport(result, args)}\n`;

  ensureDir(path.dirname(args.out));
  fs.writeFileSync(args.out, report, 'utf8');

  process.stdout.write(report);
}

main();
