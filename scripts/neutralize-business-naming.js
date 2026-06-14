#!/usr/bin/env node
/**
 * neutralize-business-naming.js
 *
 * Stage 2b: remove author/company-specific naming from the canonical
 * layer so the kit is project-neutral. The kit's own North Star says
 * "通用技能正文不得写入项目名、仓库路径、业务类名" — this enforces it.
 *
 * Scope: skills, hooks, prompts, README, feature registry, core analysis
 * scripts. Leaves correctly-isolated company skills (rdc-git) and
 * acknowledged author-local test fixtures untouched.
 *
 * Usage:
 *   node scripts/neutralize-business-naming.js --dry-run
 *   node scripts/neutralize-business-naming.js --write
 */
'use strict';

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const write = args.includes('--write');
function norm(p) { return p.split(path.sep).join('/'); }

// Ordered exact-string replacements (longest/most-specific first so we
// never partially consume a longer token). Each: [match, replace, why]
const rules = [
  // --- env var prefix ---
  ['HXLD_AI_KNOWLEDGE_ROOT', 'AI_WORKFLOW_KNOWLEDGE_ROOT', 'author prefix -> neutral'],

  // --- dotted Java package (was missed in pass 1: only slash/backslash forms done) ---
  ['com.huize.claim', 'com.example.project', 'business package (dotted)'],
  ['com.huize', 'com.example', 'business package root (dotted)'],

  // --- PascalCase business class prefixes (catch all AiClaim*/AiAuto* variants) ---
  ['AiAutoClaimFlowService', 'ExampleFlowService', 'business service class'],
  ['AiClaim', 'Example', 'business PascalCase prefix (AiClaim*)'],
  ['AiAuto', 'ExampleAuto', 'business PascalCase prefix (AiAuto*)'],
  ['AiApply', 'ExampleApply', 'business PascalCase prefix (AiApply*)'],
  ['AIClaim', 'ExampleClaim', 'business class token (uppercase)'],

  // --- specific compound carrier/service class names (longest first) ---
  ['AiApplyClaimApiTaskProcessor', 'ExampleApiTaskProcessor', 'business carrier class'],
  ['AiClaimDataAssemblyHelper', 'ExampleDataAssemblyHelper', 'business carrier class'],
  ['AiCalculateLossService', 'ExampleCalculatorService', 'business service class'],
  ['AiApplyClaimService', 'ExampleApplyService', 'business service class'],
  ['AiClaimBaseTaskData', 'ExampleBaseTaskData', 'business DTO class'],
  ['AiClaimBaseRequest', 'ExampleBaseRequest', 'business DTO class'],
  ['AiCalculateLoss', 'ExampleCalculator', 'business class token'],

  // --- insurance-domain class names ---
  ['FillPolicyAndInsureFromBackendSources', 'FillFromBackendSources', 'business method'],
  ['InsureDataFacadeImpl', 'ExampleDataFacadeImpl', 'business facade impl'],
  ['OpenInsureQuery', 'OpenExampleQuery', 'business query class'],
  ['InsureQuery', 'ExampleQuery', 'business query class'],
  ['InsureResult', 'ExampleResult', 'business result class'],

  // --- project / feature name (camelCase) ---
  ['aiClaimV2', 'example-feature', 'business project/feature name'],
  ['aiClaimFacade', 'exampleFacade', 'business facade'],
  ['aiClaimService', 'exampleService', 'business service'],
  ['handleAutoClaim', 'handleExample', 'business method'],
  ['handleAutoFlow', 'handleFlow', 'business method'],
  ['handleAiClaim', 'handleExample', 'business method'],

  // --- package paths (forward + backslash forms) ---
  ['com/huize/claim', 'com/example/project', 'business package'],
  ['com\\huize\\claim', 'com\\example\\project', 'business package (win)'],
  ['claim-core', 'example-core', 'business module'],
  ['claim-domain', 'example-domain', 'business module'],

  // --- Chinese business term in template ---
  ['理赔', '记录', 'business term (Chinese)'],
  ['保司推送', '外部推送', 'business term (Chinese)'],
  ['保司', '外部', 'business term (Chinese)'],
  ['退票', '回调', 'business term (Chinese)'],
  ['投保', '业务', 'business term (Chinese)'],
  ['对接系统', '集成系统', 'business term (Chinese)'],

  // --- business Maven modules (claim-*) ---
  ['claim-server', 'example-server', 'business module'],
  ['claim-management', 'example-management', 'business module'],
  ['claim-calculation', 'example-calculation', 'business module'],
  ['claim-provider', 'example-provider', 'business module'],
  ['claim-system', 'example-system', 'business module'],
  ['claim-common', 'example-common', 'business module'],
  ['claim-web', 'example-web', 'business module'],
  ['claim-api', 'example-api', 'business module'],

  // --- insurance partner/receive classes ---
  ['InsureCompanyReceiveFacade', 'ExampleReceiveFacade', 'business facade'],
  ['InsureCompanyPushService', 'ExamplePushService', 'business service'],
  ['InsureCompanyPush', 'ExamplePush', 'business class'],
  ['InsureCompany', 'ExampleCompany', 'business prefix'],
  ['InsureTarget', 'ExampleTarget', 'business class'],
  ['InsureSource', 'ExampleSource', 'business class'],

  // --- return-ticket classes (退票) ---
  ['ReturnTicketService', 'ExampleTicketService', 'business service'],
  ['ReturnTicketContext', 'ExampleTicketContext', 'business context'],
  ['ReturnTicketParam', 'ExampleTicketParam', 'business param'],
  ['ReturnTicket', 'ExampleTicket', 'business class'],

  // --- fields / methods ---
  ['pushToInsurance', 'pushToExternal', 'business method'],
  ['receiveReturnTicket', 'receiveCallback', 'business method'],
  ['insureNo', 'recordNo', 'business field'],
  ['insure_no', 'record_no', 'business field'],
  ['aiClaim', 'example-feature', 'business name (bare lowercase)'],

  // --- specific author commit hash default ---
  ['$BaselineCommit = "e19c16c"', '$BaselineCommit = ""', 'author baseline hash default'],
  ['default: e19c16c', 'default: <your baseline commit>', 'author hash in doc'],
];

// Directories/files to process (the canonical + public-facing layer).
const targets = [
  'agents/skills',
  'agents/hooks',
  'replay-autopilot/README.md',
  'replay-autopilot/config.yaml',
  'replay-autopilot/features',
  'replay-autopilot/prompts',
  'replay-autopilot/scripts/Analyze-SourceChainContract.ps1',
  'replay-autopilot/scripts/Build-BaselineCarrierIndex.ps1',
];

// Skip author-local / correctly-isolated / historical paths.
const skipRe = /rdc-git|skill-rules\.company|SESSION_|EVOLUTION_V\d+_INTEGRATION|\/tests\/|Test-v\d|test-v\d/i;

function listFiles(p, out) {
  out = out || [];
  let st;
  try { st = fs.statSync(p); } catch { return out; }
  if (st.isDirectory()) {
    for (const e of fs.readdirSync(p)) listFiles(path.join(p, e), out);
  } else if (/\.(md|ps1|js|json|yaml|sh|py|tpl)$/.test(path.extname(p))) out.push(p);
  return out;
}

const files = [];
for (const t of targets) listFiles(path.join(repoRoot, t), files);

const changes = [];
for (const full of files) {
  const rel = path.relative(repoRoot, full);
  if (skipRe.test(rel)) continue;
  const original = fs.readFileSync(full, 'utf8');
  let content = original;
  const fileEdits = [];
  for (const [match, replace, why] of rules) {
    if (!content.includes(match)) continue;
    let idx = 0;
    while ((idx = content.indexOf(match, idx)) !== -1) {
      fileEdits.push({ why, snippet: match });
      content = content.slice(0, idx) + replace + content.slice(idx + match.length);
      idx += replace.length;
    }
  }
  if (content !== original) changes.push({ file: rel, edits: fileEdits, content });
}

console.log(`\n=== Neutralization ${write ? 'WRITE' : 'DRY-RUN'} ===\n`);
let total = 0;
for (const c of changes) {
  const byWhy = {};
  for (const e of c.edits) byWhy[e.why] = (byWhy[e.why] || 0) + 1;
  console.log(`📄 ${norm(c.file)}`);
  for (const [why, n] of Object.entries(byWhy)) { console.log(`   ✏️  [${why}] x${n}`); total += n; }
}
console.log(`\nFiles changed: ${changes.length}   Edits: ${total}`);

if (write) {
  for (const c of changes) fs.writeFileSync(path.join(repoRoot, c.file), c.content, 'utf8');
  console.log(`\n✅ Wrote ${changes.length} files.`);
} else console.log('\n(dry-run — re-run with --write to apply.)');
