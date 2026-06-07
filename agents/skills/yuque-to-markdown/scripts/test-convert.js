const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const skillRoot = path.resolve(__dirname, '..');
const fixturePath = path.join(skillRoot, 'tests', 'fixtures', 'convert-sample.html');
const convertScript = path.join(__dirname, 'convert.js');

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'yuque-to-markdown-'));
const outputPath = path.join(tempDir, 'output.md');

try {
  execFileSync(process.execPath, [
    convertScript,
    '--input',
    fixturePath,
    '--output',
    outputPath,
    '--title',
    '语雀转换回归测试',
  ], { stdio: 'inherit' });

  const md = fs.readFileSync(outputPath, 'utf8');

  const expectedHeader = '| 字段中文名 | 字段标识 | 取值 | 备注 |';
  const badHeader = '| 字段名 | 取值 | 备注 |  |';
  const badFiveColHeader = '| 字段名 | 字段名 | 字段名 | 取值 | 备注 |';

  assert(md.includes('# 语雀转换回归测试'), '缺少文档标题');
  assert(/^\*\*0<a<=免审批金额（2\.1\.1自动审批管理）时，则：再判断\*\*\s+t_order_approver审批人表是否有数据，如有则进行后续步骤，如无则走人工$/m.test(md), '比较表达式 0<a<=... 被破坏');
  assert(md.includes('**a>免审批金额（2.1.1自动审批管理）or a<=0时，则：保持系统原流程，无需调整**'), '比较表达式 a>...or a<=0... 被破坏');
  assert(md.includes(expectedHeader), '未生成四列表头');
  assert(!md.includes(badHeader), '仍生成旧的错误三列表头');
  assert(!md.includes(badFiveColHeader), '仍生成错误的五列表头');
  assert(md.includes('| 配置项目ID | config_item_id | 取外部系统返回的JSON串item_type对应的ID |  |'), '四列表格数据行不正确');
  assert(md.includes('| 配置项目 | config_item | 取外部系统返回的JSON串item_type |  |'), '五列归一化后的数据行不正确');
  assert(!md.includes('\u200b') && !md.includes('\ufeff'), '输出中仍包含零宽字符');

  console.log('yuque-to-markdown 回归测试通过');
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}
