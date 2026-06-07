const { readFileSync, writeFileSync } = require('fs');

const args = process.argv.slice(2);
let inputFile = './yuque_cleaned.html';
let outputFile = './output.md';
let docTitle = '';

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--input' && args[i + 1]) inputFile = args[i + 1];
  if (args[i] === '--output' && args[i + 1]) outputFile = args[i + 1];
  if (args[i] === '--title' && args[i + 1]) docTitle = args[i + 1];
}

let md = readFileSync(inputFile, 'utf8');

// === Helper functions ===

function extractText(h) {
  let t = h;
  t = t.replace(/<ne-text[^>]*ne-bold="true"[^>]*>([\s\S]*?)<\/ne-text>/gi, '**$1**');
  t = t.replace(/<ne-text[^>]*style="[^"]*color:\s*rgb\([^"]*\)"[^>]*>([\s\S]*?)<\/ne-text>/gi, '<font color="red">$1</font>');
  t = t.replace(/<ne-text[^>]*>([\s\S]*?)<\/ne-text>/gi, '$1');
  // 仅移除结构化标签，避免把正文里的比较表达式（如 0<a<=b）误删掉。
  t = t.replace(/<\/?[A-Za-z][A-Za-z0-9:-]*(\s[^<>]*)?>/g, '');
  t = t.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
  t = t.replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ');
  return t.trim();
}

function extractCell(h) {
  const ps = [];
  let m;
  const imgRe = /<img[^>]*src="([^"]*)"[^>]*>/gi;
  while ((m = imgRe.exec(h)) !== null) {
    if (m[1] && !m[1].includes('alipayobjects')) {
      ps.push('![](' + m[1] + ')');
    }
  }
  const pRe = /<ne-p[^>]*>([\s\S]*?)<\/ne-p>/gi;
  while ((m = pRe.exec(h)) !== null) {
    const t = extractText(m[1]);
    if (t) ps.push(t);
  }
  const uRe = /<ne-uli-c[^>]*>([\s\S]*?)<\/ne-uli-c>/gi;
  while ((m = uRe.exec(h)) !== null) {
    const t = extractText(m[1]);
    if (t) ps.push('\u2022 ' + t);
  }
  if (!ps.length) return extractText(h);
  return ps.join('%%BR%%');
}

function normalizeHeaderCell(text) {
  return text.replace(/\*\*/g, '').replace(/\s+/g, ' ').trim();
}

function looksLikeFieldIdentifier(text) {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(normalizeHeaderCell(text));
}

function normalizeTableHeaders(rows) {
  if (!rows.length) return rows;

  const header = rows[0].map(normalizeHeaderCell);
  if (
    header.length === 4 &&
    header[0] === '字段名' &&
    header[1] === '字段名' &&
    header[2] === '取值' &&
    header[3] === '备注'
  ) {
    rows[0] = ['字段中文名', '字段标识', '取值', '备注'];
  }

  if (
    header.length === 5 &&
    header[0] === '字段名' &&
    header[1] === '字段名' &&
    header[2] === '字段名' &&
    header[3] === '取值' &&
    header[4] === '备注'
  ) {
    const sampleRows = rows.slice(1, 4);
    const duplicatedLabelPattern = sampleRows.length > 0 && sampleRows.every((row) =>
      row.length >= 5 &&
      normalizeHeaderCell(row[0]) === normalizeHeaderCell(row[1]) &&
      looksLikeFieldIdentifier(row[2])
    );

    if (duplicatedLabelPattern) {
      return rows.map((row, index) => {
        if (index === 0) {
          return ['字段中文名', '字段标识', '取值', '备注'];
        }
        return [row[0], row[2], row[3], row[4]];
      });
    }
  }

  return rows;
}

// ===== 1. Tables (MUST be first, before paragraphs) =====
md = md.replace(/<table[^>]*>([\s\S]*?)<\/table>/gi, (match, tableContent) => {
  const rows = [];
  const trRe = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
  let trm;
  while ((trm = trRe.exec(tableContent)) !== null) {
    const cells = [];
    const cellRe = /<(td|th)([^>]*)>([\s\S]*?)<\/\1>/gi;
    let cellMatch;
    while ((cellMatch = cellRe.exec(trm[1])) !== null) {
      const attrs = cellMatch[2] || '';
      const colspanMatch = attrs.match(/\bcolspan=["']?(\d+)["']?/i);
      const colspan = colspanMatch ? Math.max(parseInt(colspanMatch[1], 10), 1) : 1;
      const value = extractCell(cellMatch[3]).replace(/\|/g, '\\|');
      for (let i = 0; i < colspan; i++) {
        cells.push(value);
      }
    }
    if (cells.length > 0) rows.push(cells);
  }
  if (rows.length === 0) return '';
  const normalizedRows = normalizeTableHeaders(rows);
  const maxCols = Math.max(...normalizedRows.map(r => r.length));
  for (const row of normalizedRows) {
    while (row.length < maxCols) row.push('');
  }
  let result = '\n';
  result += '| ' + normalizedRows[0].join(' | ') + ' |\n';
  result += '| ' + normalizedRows[0].map(() => '---').join(' | ') + ' |\n';
  for (let i = 1; i < normalizedRows.length; i++) {
    result += '| ' + normalizedRows[i].join(' | ') + ' |\n';
  }
  return result + '\n';
});

// ===== 2. Headings (extract from <ne-heading-content>) =====
for (let i = 1; i <= 6; i++) {
  const re = new RegExp('<ne-h' + i + '[^>]*>([\\s\\S]*?)<\\/ne-h' + i + '>', 'gi');
  md = md.replace(re, (match, content) => {
    const contentMatch = content.match(/<ne-heading-content>([\s\S]*?)<\/ne-heading-content>/i);
    const t = contentMatch ? extractText(contentMatch[1]) : extractText(content);
    return t ? '\n' + '#'.repeat(i) + ' ' + t + '\n' : '';
  });
}

// ===== 3. Images =====
md = md.replace(/<img[^>]*src="([^"]*)"[^>]*>/gi, (match, src) => {
  if (!src || src.includes('alipayobjects')) return '';
  return '\n\n![image](' + src + ')\n\n';
});

// ===== 4. Unordered lists =====
md = md.replace(/<ne-uli[^>]*>([\s\S]*?)<\/ne-uli>/gi, (match, content) => {
  const cMatch = content.match(/<ne-uli-c[^>]*>([\s\S]*?)<\/ne-uli-c>/i);
  const t = cMatch ? extractText(cMatch[1]) : extractText(content);
  return t ? '\n- ' + t : '';
});

// ===== 4b. Ordered lists =====
md = md.replace(/<ne-oli[^>]*>([\s\S]*?)<\/ne-oli>/gi, (match, content) => {
  const cMatch = content.match(/<ne-oli-c[^>]*>([\s\S]*?)<\/ne-oli-c>/i);
  const t = cMatch ? extractText(cMatch[1]) : extractText(content);
  return t ? '\n- ' + t : '';
});

// ===== 5. Paragraphs =====
md = md.replace(/<ne-p[^>]*>([\s\S]*?)<\/ne-p>/gi, (match, content) => {
  if (/<ne-h[1-6]/i.test(content) || /<img /i.test(content)) return content;
  const t = extractText(content);
  if (!t) return '\n';
  return '\n' + t + '\n';
});

// ===== 6. Cleanup =====
md = md.replace(/<ne-card[^>]*>[\s\S]*?<\/ne-card>/gi, '');
md = md.replace(/<\/?[A-Za-z][A-Za-z0-9:-]*(\s[^<>]*)?>/g, '');
md = md.replace(/%%BR%%/g, '<br>');
md = md.replace(/\u200B|\uFEFF/g, '');
md = md.replace(/\n{3,}/g, '\n\n').trim();

// ===== 7. Add document title as H1 =====
if (docTitle) {
  md = '# ' + docTitle + '\n\n' + md;
}

writeFileSync(outputFile, md, 'utf8');
console.log(`Converted: ${inputFile} -> ${outputFile}`);
console.log(`Size: ${md.length} chars, ${md.split('\n').length} lines`);
