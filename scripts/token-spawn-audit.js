const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const axios = require('axios');

const ROOT = path.resolve(__dirname, '..');
const DATA_FILE = path.join(ROOT, 'data', 'oracle_cards.json.gz');
const REPORT_DIR = path.join(ROOT, 'reports');
const BASE_URL = process.env.AUDIT_BASE_URL || 'http://localhost:3000';
const CONCURRENCY = Math.max(parseInt(process.env.AUDIT_CONCURRENCY || '6', 10) || 6, 1);
const LIMIT = Math.max(parseInt(process.env.TOKEN_AUDIT_LIMIT || '0', 10) || 0, 0);
const REQUEST_TIMEOUT_MS = Math.max(parseInt(process.env.AUDIT_REQUEST_TIMEOUT_MS || '12000', 10) || 12000, 1000);
const ONLY_AMBIGUOUS = String(process.env.AUDIT_ONLY_AMBIGUOUS || '').toLowerCase() === 'true';
const AUDIT_COUNT = Math.min(Math.max(parseInt(process.env.AUDIT_COUNT || '1', 10) || 1, 1), 100);

function readBulkCards() {
  if (!fs.existsSync(DATA_FILE)) {
    throw new Error(`Bulk data file not found: ${DATA_FILE}`);
  }
  const compressed = fs.readFileSync(DATA_FILE);
  const jsonText = zlib.gunzipSync(compressed).toString('utf8');
  const cards = JSON.parse(jsonText);
  if (!Array.isArray(cards)) {
    throw new Error('Bulk data is not an array of cards.');
  }
  return cards;
}

function isTokenCard(card) {
  const layout = String(card.layout || '').toLowerCase();
  const typeLine = String(card.type_line || '').toLowerCase();
  return layout === 'token' || layout === 'double_faced_token' || typeLine.includes('token');
}

function buildTokenNameStats(cards) {
  const statsByName = new Map();

  for (const card of cards) {
    if (!isTokenCard(card)) {
      continue;
    }

    const rawName = String(card.name || '').trim();
    if (!rawName) {
      continue;
    }

    const key = rawName.toLowerCase();
    if (!statsByName.has(key)) {
      statsByName.set(key, {
        name: rawName,
        count: 0,
        layouts: new Set(),
        sets: new Set(),
        languages: new Set()
      });
    }

    const entry = statsByName.get(key);
    entry.count += 1;
    if (card.layout) entry.layouts.add(String(card.layout));
    if (card.set) entry.sets.add(String(card.set));
    if (card.lang) entry.languages.add(String(card.lang));
  }

  const tokenStats = Array.from(statsByName.values()).map(entry => ({
    name: entry.name,
    count: entry.count,
    layouts: Array.from(entry.layouts).sort(),
    sets: Array.from(entry.sets).sort(),
    languages: Array.from(entry.languages).sort()
  }));

  tokenStats.sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  return tokenStats;
}

function quoteForScryfall(value) {
  return `"${String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

async function probeSpawn(tokenName) {
  const q = `t:token name:${quoteForScryfall(tokenName)}`;
  const payload = {
    q,
    count: AUDIT_COUNT,
    explain: true,
    enforceCommander: false
  };

  const started = Date.now();
  const response = await axios.post(`${BASE_URL}/random/build`, payload, {
    timeout: REQUEST_TIMEOUT_MS,
    validateStatus: () => true,
    headers: {
      Accept: 'application/x-ndjson',
      'Content-Type': 'application/json'
    }
  });
  const elapsedMs = Date.now() - started;

  const bodyText = typeof response.data === 'string'
    ? response.data
    : JSON.stringify(response.data || '');

  const lines = bodyText.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const hasDeckPayload = lines.some(line => line.includes('"Name":"DeckCustom"') || line.includes('"ContainedObjects"'));

  return {
    tokenName,
    query: q,
    status: response.status,
    elapsedMs,
    hasDeckPayload,
    lineCount: lines.length,
    headers: {
      plan: response.headers['x-query-plan'] || null,
      explain: response.headers['x-query-explain'] || null,
      fallback: response.headers['x-bulk-fallback'] || null
    },
    errorDetails: response.status >= 400 ? bodyText.slice(0, 1000) : null
  };
}

async function runPool(items, concurrency, worker) {
  const results = new Array(items.length);
  let index = 0;

  async function runner() {
    while (true) {
      const current = index;
      index += 1;
      if (current >= items.length) {
        return;
      }

      try {
        results[current] = await worker(items[current], current);
      } catch (error) {
        results[current] = {
          tokenName: items[current],
          status: 0,
          elapsedMs: null,
          hasDeckPayload: false,
          headers: { plan: null, explain: null, fallback: null },
          errorDetails: error.message
        };
      }
    }
  }

  const runners = Array.from({ length: concurrency }, () => runner());
  await Promise.all(runners);
  return results;
}

function ensureReportDir() {
  if (!fs.existsSync(REPORT_DIR)) {
    fs.mkdirSync(REPORT_DIR, { recursive: true });
  }
}

async function main() {
  console.log(`[Audit] Loading bulk token data from ${DATA_FILE}`);
  const cards = readBulkCards();
  const tokenStats = buildTokenNameStats(cards);
  const baseList = ONLY_AMBIGUOUS
    ? tokenStats.filter(entry => entry.count > 1)
    : tokenStats;
  const allTokenNames = baseList.map(entry => entry.name);
  const tokenNames = LIMIT > 0 ? allTokenNames.slice(0, LIMIT) : allTokenNames;

  console.log(`[Audit] Found ${tokenStats.length} unique token names.`);
  if (ONLY_AMBIGUOUS) {
    console.log(`[Audit] Ambiguous-only mode: ${allTokenNames.length} token names with multiple hits.`);
  }
  console.log(`[Audit] Probing ${tokenNames.length} token names against ${BASE_URL}/random/build (concurrency=${CONCURRENCY}, timeout=${REQUEST_TIMEOUT_MS}ms).`);

  const spawnResults = await runPool(tokenNames, CONCURRENCY, async (name, idx) => {
    const result = await probeSpawn(name);
    if ((idx + 1) % 50 === 0 || idx === tokenNames.length - 1) {
      console.log(`[Audit] Progress ${idx + 1}/${tokenNames.length}`);
    }
    return result;
  });

  const failed = spawnResults.filter(r => r.status >= 400 || !r.hasDeckPayload);
  const withFallback = spawnResults.filter(r => r.headers && r.headers.fallback);
  const ambiguous = tokenStats.filter(entry => entry.count > 1);

  const lookup = new Map(tokenStats.map(entry => [entry.name.toLowerCase(), entry]));
  const soldier = lookup.get('soldier') || null;
  const fish = lookup.get('fish') || null;

  const summary = {
    generatedAt: new Date().toISOString(),
    baseUrl: BASE_URL,
    totalUniqueTokenNames: allTokenNames.length,
    testedTokenNames: tokenNames.length,
    ambiguousOnlyMode: ONLY_AMBIGUOUS,
    requestedCount: AUDIT_COUNT,
    okCount: spawnResults.length - failed.length,
    failedCount: failed.length,
    fallbackCount: withFallback.length,
    ambiguousTokenNameCount: ambiguous.length,
    soldier,
    fish,
    topAmbiguous: ambiguous.slice(0, 25),
    sampleFailures: failed.slice(0, 50)
  };

  ensureReportDir();

  fs.writeFileSync(path.join(REPORT_DIR, 'token-name-counts.json'), JSON.stringify(tokenStats, null, 2));
  fs.writeFileSync(path.join(REPORT_DIR, 'token-spawn-audit.json'), JSON.stringify(spawnResults, null, 2));
  fs.writeFileSync(path.join(REPORT_DIR, 'token-spawn-failures.json'), JSON.stringify(failed, null, 2));
  fs.writeFileSync(path.join(REPORT_DIR, 'token-spawn-summary.json'), JSON.stringify(summary, null, 2));

  console.log('[Audit] Summary:', JSON.stringify(summary, null, 2));
  console.log('[Audit] Reports written to reports/token-*.json');
}

main().catch(error => {
  console.error('[Audit] Failed:', error);
  process.exit(1);
});
