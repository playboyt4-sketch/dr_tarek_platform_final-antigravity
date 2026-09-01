const ts = require('typescript');
const fs = require('fs');

const srcPath = 'C:\\\\Users\\\\tarek el araby\\\\.gemini\\\\antigravity-ide\\\\brain\\\\17804667-e6e2-42fa-b868-a8621c2c184a\\\\scratch\\\\old_index.ts';
const content = fs.readFileSync(srcPath, 'utf8');

const sourceFile = ts.createSourceFile(
  'old_index.ts',
  content,
  ts.ScriptTarget.Latest,
  true
);

const missing = [
  'assertStaffDirectoryAllowed',
  'assertLoginNotLocked',
  'recordLoginFailure',
  'clearLoginFailures',
  'SECRET_BUNNY_TOKEN_KEY',
  'SECRET_BUNNY_STORAGE_BASE_URL',
  'SECRET_BUNNY_STORAGE_ZONE_NAME',
  'SECRET_BUNNY_STORAGE_PASSWORD',
  'BUNNY_UPLOAD_CONTENT_TYPES',
  'BUNNY_PROXY_MAX_BYTES',
  'bunnyStorageRequest',
  'buildBunnyResourceAccessUrl',
  'slidingWindowAllowed',
  'MAX_EXAM_ANSWERS',
  'EXAM_SUBMIT_TIME_GRACE_MS',
  'GradingLink',
  'GradingQuestion',
  'ContentEntity',
  'pickDueLectures',
  'contentAuditTrigger'
];

let extracted = '';

function visit(node) {
  let name = null;
  
  if (ts.isFunctionDeclaration(node)) {
    name = node.name ? node.name.text : null;
  } else if (ts.isVariableStatement(node)) {
    const decl = node.declarationList.declarations[0];
    if (decl && ts.isIdentifier(decl.name)) {
      name = decl.name.text;
    }
  } else if (ts.isTypeAliasDeclaration(node) || ts.isInterfaceDeclaration(node)) {
    name = node.name.text;
  }
  
  if (name && missing.includes(name)) {
    const start = node.getStart();
    const end = node.getEnd();
    extracted += content.substring(start, end) + '\\n\\n';
    console.log('Extracted: ' + name);
    missing.splice(missing.indexOf(name), 1);
  }
  
  ts.forEachChild(node, visit);
}

visit(sourceFile);

if (missing.length > 0) {
  console.log('STILL MISSING: ' + missing.join(', '));
}

fs.writeFileSync('C:\\\\Users\\\\tarek el araby\\\\.gemini\\\\antigravity-ide\\\\brain\\\\17804667-e6e2-42fa-b868-a8621c2c184a\\\\scratch\\\\missing_helpers_ts.ts', extracted);
