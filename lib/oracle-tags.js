'use strict';

const axios = require('axios');
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const stream = require('stream');
const zlib = require('zlib');
const streamArray = require('stream-json/streamers/stream-array.js');
const { pipeline } = require('stream/promises');

const packageVersion = require('../package.json').version;

const BULK_DATA_DIR = process.env.BULK_DATA_PATH || path.join(__dirname, '../data');
const ORACLE_TAGS_FILE = path.join(BULK_DATA_DIR, 'oracle_tags.json.gz');
const ORACLE_TAGS_MANIFEST_FILE = `${ORACLE_TAGS_FILE}.manifest.json`;
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

function isGzipEncodedResponse(response) {
  const encoding = String(response?.headers?.['content-encoding'] || '').toLowerCase();
  const contentType = String(response?.headers?.['content-type'] || '').toLowerCase();
  const url = String(response?.request?.res?.responseUrl || response?.config?.url || '').toLowerCase();

  return encoding.includes('gzip') || contentType.includes('gzip') || /\.gz(?:[?#]|$)/.test(url);
}

function readJsonFile(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

async function writeJsonFileAtomic(filePath, value) {
  const tempPath = `${filePath}.tmp`;
  await fs.promises.writeFile(tempPath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  await fs.promises.rename(tempPath, filePath);
}

function manifestMatchesBulkInfo(manifest, bulkInfo, downloadUrl, downloadFormat) {
  if (!manifest || typeof manifest !== 'object') {
    return false;
  }
  return manifest.schemaVersion === 1
    && manifest.updatedAt === (bulkInfo.updated_at || null)
    && manifest.size === (bulkInfo.size || null)
    && manifest.selectedDownloadUri === downloadUrl
    && manifest.sourceFormat === downloadFormat;
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

  const downloadUrl = bulkInfo.jsonl_download_uri || bulkInfo.download_uri;
  const downloadFormat = bulkInfo.jsonl_download_uri ? 'streaming JSONL' : 'legacy JSON';
  if (!downloadUrl) {
    throw new Error('No download URI found for oracle_tags');
  }

  const existingManifest = readJsonFile(ORACLE_TAGS_MANIFEST_FILE);
  if (fs.existsSync(ORACLE_TAGS_FILE) && manifestMatchesBulkInfo(existingManifest, bulkInfo, downloadUrl, downloadFormat)) {
    return false;
  }

  const tempPath = `${ORACLE_TAGS_FILE}.tmp`;
  const response = await axios.get(downloadUrl, {
    responseType: 'stream',
    decompress: false,
    timeout: 120000,
    headers: {
      'User-Agent': `MTGCardImporterTTS/${packageVersion}`,
      'Accept': '*/*'
    }
  });

  let downloadedBytes = 0;
  const progressStream = new stream.Transform({
    transform(chunk, _encoding, callback) {
      downloadedBytes += chunk.length;
      callback(null, chunk);
    }
  });

  const pipelineStreams = [response.data, progressStream];
  if (!isGzipEncodedResponse(response)) {
    pipelineStreams.push(zlib.createGzip());
  }
  pipelineStreams.push(fs.createWriteStream(tempPath));

  try {
    await pipeline(...pipelineStreams);
    await fs.promises.rename(tempPath, ORACLE_TAGS_FILE);
    const fileStats = await fs.promises.stat(ORACLE_TAGS_FILE);
    await writeJsonFileAtomic(ORACLE_TAGS_MANIFEST_FILE, {
      schemaVersion: 1,
      type: ORACLE_TAGS_BULK_TYPE,
      localFile: path.basename(ORACLE_TAGS_FILE),
      sourceFormat: downloadFormat,
      updatedAt: bulkInfo.updated_at || null,
      size: bulkInfo.size || null,
      contentType: bulkInfo.content_type || null,
      downloadUri: bulkInfo.download_uri || null,
      jsonlDownloadUri: bulkInfo.jsonl_download_uri || null,
      selectedDownloadUri: downloadUrl,
      compressed: true,
      cacheFileSize: fileStats.size,
      downloadedBytes,
      downloadedAt: new Date().toISOString()
    });
    return true;
  } finally {
    if (fs.existsSync(tempPath)) {
      await fs.promises.unlink(tempPath).catch(() => {});
    }
  }
}

async function readOracleTagsFromDisk() {
  return new Promise((resolve, reject) => {
    const tags = [];
    let settled = false;
    let parserAttached = false;
    const readStream = fs.createReadStream(ORACLE_TAGS_FILE);
    const gunzip = zlib.createGunzip();
    const pass = new stream.PassThrough();

    const settleResolve = () => {
      if (!settled) {
        settled = true;
        resolve(tags);
      }
    };

    const handleError = (error) => {
      if (!settled) {
        settled = true;
        readStream.destroy();
        gunzip.destroy();
        pass.destroy();
        reject(error);
      }
    };

    const attachArrayParser = () => {
      const arrayStreamer = streamArray.withParserAsStream();
      arrayStreamer.on('data', ({ value }) => tags.push(value));
      arrayStreamer.on('end', settleResolve);
      arrayStreamer.on('error', handleError);
      pass.pipe(arrayStreamer);
      parserAttached = true;
    };

    const attachJsonlParser = () => {
      const lineReader = readline.createInterface({ input: pass, crlfDelay: Infinity });
      lineReader.on('line', (line) => {
        const trimmed = line.trim();
        if (!trimmed) {
          return;
        }
        try {
          tags.push(JSON.parse(trimmed));
        } catch (error) {
          handleError(error);
        }
      });
      lineReader.on('close', settleResolve);
      lineReader.on('error', handleError);
      parserAttached = true;
    };

    const detectFormat = (chunk) => {
      const text = chunk.toString('utf8', 0, Math.min(chunk.length, 128)).trimLeft();
      if (text.startsWith('[')) {
        attachArrayParser();
      } else {
        attachJsonlParser();
      }
      pass.unshift(chunk);
      pass.resume();
    };

    pass.once('data', detectFormat);
    pass.once('end', () => {
      if (!parserAttached) {
        settleResolve();
      }
    });
    pass.on('error', handleError);
    gunzip.on('error', handleError);
    readStream.on('error', handleError);

    readStream.pipe(gunzip).pipe(pass);
  });
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
    const previousState = {
      loaded,
      termToOracleIds,
      stats
    };

    if (forceRefresh || !fs.existsSync(ORACLE_TAGS_FILE)) {
      await downloadOracleTagsFile();
    }

    try {
      const tags = await readOracleTagsFromDisk();
      buildOracleTagLookup(tags);
      loaded = true;
    } catch (error) {
      if (previousState.loaded) {
        loaded = previousState.loaded;
        termToOracleIds = previousState.termToOracleIds;
        stats = previousState.stats;
      }
      throw error;
    }
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
  return {
    ...stats,
    manifest: readJsonFile(ORACLE_TAGS_MANIFEST_FILE)
  };
}

module.exports = {
  loadOracleTags,
  isLoaded,
  getOracleIdsForTerm,
  getStats,
  normalizeTerm
};
