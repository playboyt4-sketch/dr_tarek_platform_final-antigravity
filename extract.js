const fs = require('fs');
const content = fs.readFileSync('C:\\Users\\tarek el araby\\.gemini\\antigravity-ide\\brain\\c61d3566-eb62-48b5-bd12-38a482be067a\\verification_report.md', 'utf8');
const startIndex = content.indexOf('## 2. File Diffs');
if (startIndex !== -1) {
    let endIndex = content.indexOf('## 3.', startIndex);
    if (endIndex === -1) endIndex = content.length;
    const diffs = content.substring(startIndex, endIndex);
    fs.writeFileSync('C:\\Users\\tarek el araby\\.gemini\\antigravity-ide\\brain\\c61d3566-eb62-48b5-bd12-38a482be067a\\diffs_extracted.txt', diffs);
}
