const fs = require('fs');
const project = JSON.parse(fs.readFileSync(process.argv[1], 'utf-8'));
const tmpl = JSON.parse(fs.readFileSync(process.argv[2], 'utf-8'));

const result = { ...project };
if (tmpl.thresholds) {
  result.thresholds = { ...tmpl.thresholds, ...result.thresholds };
}
if (tmpl.enforcement) {
  result.enforcement = { ...tmpl.enforcement, ...result.enforcement };
}
if (tmpl.$schema && !result.$schema) result.$schema = tmpl.$schema;
if (tmpl.$comment && !result.$comment) result.$comment = tmpl.$comment;

fs.writeFileSync(process.argv[3], JSON.stringify(result, null, 2) + '\n');