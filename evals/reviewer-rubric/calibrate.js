#!/usr/bin/env node
'use strict';
// Measures how often the defect judge agrees with hand-checked labels.
//   calibrate.js [labels.json=calibration/replies.json] [out.json]
// Each label is { scenario, defect, reported, reply }. The judge is asked about the
// reply exactly as run.sh asks about a trial, and the agreement report is printed.
// Calls the model ($JUDGE_MODEL, default haiku; about $0.001 a reply); run by hand.
// The prompt, schema, parsing and agreement maths live in score.js and are unit-tested.
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const sc = require('./score.js');

const HERE = __dirname;
const labelsFile = process.argv[2] || path.join(HERE, 'calibration', 'replies.json');
const outFile = process.argv[3];
const MODEL = process.env.JUDGE_MODEL || 'haiku';
const PARALLEL = Number(process.env.JUDGE_PARALLEL || 6);

const metaFor = (s) => JSON.parse(fs.readFileSync(path.join(HERE, 'scenarios', s, 'meta.json'), 'utf8'));

function judge(meta, reply) {
  return new Promise((resolve) => {
    const p = spawn('claude', ['-p', '--model', MODEL, '--tools', '', '--setting-sources', '', '--no-session-persistence',
      '--json-schema', JSON.stringify(sc.judgeSchema(meta)), '--output-format', 'json', '--max-budget-usd', '0.25'],
    { stdio: ['pipe', 'pipe', 'ignore'] });
    let out = '';
    p.stdout.on('data', (d) => { out += d; });
    p.on('close', () => {
      try { resolve(sc.parseJudge(out, meta)); } catch (e) { resolve({ error: e.message }); }
    });
    p.stdin.end(sc.judgePrompt(meta, reply));
  });
}

async function run() {
  const labels = JSON.parse(fs.readFileSync(labelsFile, 'utf8'));
  const results = new Array(labels.length);
  let next = 0;
  let cost = 0;
  const worker = async () => {
    while (next < labels.length) {
      const i = next++;
      const meta = metaFor(labels[i].scenario);
      let r = await judge(meta, labels[i].reply);
      if (r.error) r = await judge(meta, labels[i].reply);  // one retry: judge calls occasionally fail transiently
      results[i] = r.error ? null : r.verdict;
      cost += r.costUsd || 0;
      if (r.error) process.stderr.write(`label ${i}: ${r.error}\n`);
    }
  };
  await Promise.all(Array.from({ length: PARALLEL }, worker));
  const c = sc.calibrate(labels, results);
  if (outFile) fs.writeFileSync(outFile, JSON.stringify({ model: MODEL, costUsd: cost, ...c }, null, 2) + '\n');
  console.log(`judge ${MODEL}: agreed ${c.agree}/${c.judged} judged (${c.total} labels, ${c.unjudged.length} unjudged), cost $${cost.toFixed(3)}`);
  for (const [k, v] of Object.entries(c.byDefect)) console.log(`  ${k} ${v}`);
  for (const d of c.disagreements) console.log(`DISAGREE ${d.scenario}.${d.defect} label=${d.reported} judge=${d.got} quote=${JSON.stringify(d.quote)}\n  reply: ${JSON.stringify(d.reply).slice(0, 300)}`);
}

run();
