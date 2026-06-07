const { readFileSync, writeFileSync, mkdirSync } = require('fs');
const { join } = require('path');

const args = process.argv.slice(2);
let inputFile = './yuque_content.html';
let outputFile = './yuque_cleaned.html';
let assetsDir = '';

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--input' && args[i + 1]) inputFile = args[i + 1];
  if (args[i] === '--output' && args[i + 1]) outputFile = args[i + 1];
  if (args[i] === '--assets-dir' && args[i + 1]) assetsDir = args[i + 1];
}

let html = readFileSync(inputFile, 'utf8');

// 1. Remove "返回文档" navigation button (must be first to prevent greedy match)
html = html.replace(/<div class="ne-viewer-header"><button[^>]*>[^<]*<\/button><\/div>/gi, '');

// 2. Extract flowchart SVG and save as local file
const boardMatches = [];
const boardRe = /<ne-card[^>]*data-card-name="board"[^>]*>([\s\S]*?)<\/ne-card>/gi;
let boardIdx = 0;
html = html.replace(boardRe, (match) => {
  const svgMatch = match.match(/(<svg[\s\S]*?<\/svg>)/i);
  if (svgMatch && assetsDir) {
    boardIdx++;
    mkdirSync(assetsDir, { recursive: true });
    const svgFile = join(assetsDir, `flowchart-${boardIdx}.svg`);
    writeFileSync(svgFile, '<?xml version="1.0" encoding="UTF-8"?>\n' + svgMatch[1], 'utf8');
    boardMatches.push(svgFile);
    return `\n![流程图${boardIdx > 1 ? ' ' + boardIdx : ''}](flowchart-${boardIdx}.svg)\n`;
  }
  return '\n';
});

// 3. Remove OCR text layers
html = html.replace(/<div class="ne-ui-image-ocr-text"[^>]*>[\s\S]*?<\/div>/gi, '');

// 4. Remove remaining SVGs (icons etc)
html = html.replace(/<svg[\s\S]*?<\/svg>/gi, '');

writeFileSync(outputFile, html, 'utf8');
console.log(`Pre-cleaned: ${inputFile} -> ${outputFile}`);
if (boardMatches.length > 0) {
  console.log(`Extracted ${boardMatches.length} flowchart(s): ${boardMatches.join(', ')}`);
}
