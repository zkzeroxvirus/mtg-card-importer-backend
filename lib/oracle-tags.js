'use strict';

const axios = require('axios');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { pipeline } = require('stream/promises');

const packageVersion = require('../package.json').version;

const BULK_DATA_DIR = process.env.BULK_DATA_PATH || path.join(__dirname, '../data');
const ORACLE_TAGS_FILE = path.join(BULK_DATA_DIR, 'oracle_tags.json.gz');
const ORACLE_TAGS_BULK_TYPE = 'oracle_tags';

let loaded = false;
let loadPromise = null;
let termToOracleIds = new Map();
let stats = {
  tags: 0,
  terms: 0,
  oracleIds: 0,
  filePath: ORACLE_TAGS_FILE,
  loadedAt: null
};

function normalizeTerm(term) {
  return String(term || '').trim().toLowerCase();
}

async function downloadOracleTagsFile() {
  await fs.promises.mkdir(BULK_DATA_DIR, { recursive: true });

  const { data: bulkInfo } = await axios.get(`https://api.scryfall.com/bulk-data/${ORACLE_TAGS_BULK_TYPE}`, {
    headers: {
      'User-Agent': `MTGCardImporterTTS/${packageVersion}`,
      'Accept': 'application/json'
    },
    timeout: 10000
  });

  const tempPath = `${ORACLE_TAGS_FILE}.tmp`;
  const response = await axios.get(bulkInfo.download_uri, {
    responseType: 'stream',
    timeout: 120000,
    headers: {
      'User-Agent': `MTGCardImporterTTS/${packageVersion}`,
      'Accept': '*/*'
    }
  });

  try {
    await pipeline(
      response.data,
      zlib.createGzip(),
      fs.createWriteStream(tempPath)
    );
    await fs.promises.rename(tempPath, ORACLE_TAGS_FILE);
  } finally {
    if (fs.existsSync(tempPath)) {
      await fs.promises.unlink(tempPath).catch(() => {});
    }
  }
}

async function readOracleTagsFromDisk() {
  const compressed = await fs.promises.readFile(ORACLE_TAGS_FILE);
  const raw = await new Promise((resolve, reject) => {
    zlib.gunzip(compressed, (err, buffer) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(buffer.toString('utf8'));
    });
  });
  const parsed = JSON.parse(raw);
  return Array.isArray(parsed) ? parsed : [];
}

function collectTagOracleIds(tag, byId, memo, visiting) {
  const tagId = String(tag?.id || '');
  if (!tagId) {
    return new Set();
  }

  if (memo.has(tagId)) {
    return memo.get(tagId);
  }

  if (visiting.has(tagId)) {
    return new Set();
  }

  visiting.add(tagId);

  const oracleIds = new Set();
  const taggings = Array.isArray(tag.taggings) ? tag.taggings : [];
  for (const tagging of taggings) {
    const oracleId = String(tagging?.oracle_id || '').trim();
    if (oracleId) {
      oracleIds.add(oracleId);
    }
  }

  const childIds = Array.isArray(tag.child_ids) ? tag.child_ids : [];
  for (const childIdRaw of childIds) {
    const childId = String(childIdRaw || '').trim();
    if (!childId) {
      continue;
    }
    const childTag = byId.get(childId);
    if (!childTag) {
      continue;
    }
    const childOracleIds = collectTagOracleIds(childTag, byId, memo, visiting);
    for (const oracleId of childOracleIds) {
      oracleIds.add(oracleId);
    }
  }

  visiting.delete(tagId);
  memo.set(tagId, oracleIds);
  return oracleIds;
}

function buildOracleTagLookup(tags) {
  const byId = new Map();
  for (const tag of tags) {
    if (!tag || typeof tag !== 'object') {
      continue;
    }
    const tagId = String(tag.id || '').trim();
    if (!tagId) {
      continue;
    }
    byId.set(tagId, tag);
  }

  const memo = new Map();
  const lookup = new Map();

  for (const tag of byId.values()) {
    const oracleIds = collectTagOracleIds(tag, byId, memo, new Set());
    if (oracleIds.size === 0) {
      continue;
    }

    const keys = new Set();
    keys.add(normalizeTerm(tag.slug));
    keys.add(normalizeTerm(tag.label));

    const aliases = Array.isArray(tag.aliases) ? tag.aliases : [];
    for (const alias of aliases) {
      keys.add(normalizeTerm(alias));
    }

    for (const key of keys) {
      if (!key) {
        continue;
      }
      const existing = lookup.get(key) || new Set();
      for (const oracleId of oracleIds) {
        existing.add(oracleId);
      }
      lookup.set(key, existing);
    }
  }

  termToOracleIds = lookup;

  const allOracleIds = new Set();
  for (const ids of lookup.values()) {
    for (const id of ids) {
      allOracleIds.add(id);
    }
  }

  stats = {
    tags: byId.size,
    terms: lookup.size,
    oracleIds: allOracleIds.size,
    filePath: ORACLE_TAGS_FILE,
    loadedAt: new Date().toISOString()
  };
}

async function loadOracleTags(options = {}) {
  const forceRefresh = options.forceRefresh === true;

  if (loaded && !forceRefresh) {
    return true;
  }

  if (loadPromise) {
    await loadPromise;
    return loaded;
  }

  loadPromise = (async () => {
    if (forceRefresh || !fs.existsSync(ORACLE_TAGS_FILE)) {
      await downloadOracleTagsFile();
    }

    const tags = await readOracleTagsFromDisk();
    buildOracleTagLookup(tags);
    loaded = true;
  })();

  try {
    await loadPromise;
    return true;
  } finally {
    loadPromise = null;
  }
}

function isLoaded() {
  return loaded;
}

function getOracleIdsForTerm(term) {
  if (!loaded) {
    return null;
  }
  const normalized = normalizeTerm(term);
  const ids = termToOracleIds.get(normalized);
  if (!ids) {
    return [];
  }
  return [...ids];
}

function getStats() {
  return { ...stats };
}

module.exports = {
  loadOracleTags,
  isLoaded,
  getOracleIdsForTerm,
  getStats,
  normalizeTerm
};
