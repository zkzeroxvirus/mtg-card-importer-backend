'use strict';

/**
 * File-backed tag cache for otag:/atag:/arttag:/function: Scryfall queries.
 *
 * These filters are not present in any bulk data export, so the first request
 * for a given tag must call the Scryfall API.  After that, the matched oracle_ids
 * are persisted to data/tag-cache.json.gz so subsequent requests (and server
 * restarts) can be served instantly from bulk.
 *
 * Strategy: stale-while-revalidate
 *   - warm  : served from in-memory cache, TTL < 24 h
 *   - stale : served from (slightly outdated) in-memory cache immediately,
 *             background refresh queued so the next request gets fresh data
 *   - cold  : API call required; result stored and broadcast to all workers
 */

const path = require('path');
const fs   = require('fs');
const zlib = require('zlib');

const BULK_DATA_DIR  = process.env.BULK_DATA_PATH || path.join(__dirname, '../data');
const TAG_CACHE_FILE = path.join(BULK_DATA_DIR, 'tag-cache.json.gz');
const TAG_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

// In-memory store: normalizedKey -> { oracle_ids: string[], fetched_at: number }
const cacheStore = new Map();

// Key helpers

/**
 * Consistent normalisation so "Otag:Equipment" and "otag:equipment" share
 * a single cache entry.
 */
function normalizeKey(query) {
  return String(query || '').trim().toLowerCase();
}

// Read

/**
 * Return the cached entry for a query, or null if not present.
 * @param {string} query  Raw Scryfall query string.
 * @returns {{ oracle_ids: string[], fetched_at: number } | null}
 */
function get(query) {
  return cacheStore.get(normalizeKey(query)) || null;
}

/**
 * Returns true when no valid cache entry exists OR the entry has expired.
 */
function isStale(query) {
  const entry = get(query);
  if (!entry) {
    return true;
  }
  return (Date.now() - entry.fetched_at) >= TAG_CACHE_TTL_MS;
}

/** True once at least one entry has been loaded / populated. */
function isLoaded() {
  return cacheStore.size > 0;
}

// Write

/**
 * Store oracle_ids for a query.
 * @param {string}   query     Raw or normalised Scryfall query.
 * @param {string[]} oracleIds Array of oracle_id strings.
 */
function set(query, oracleIds) {
  cacheStore.set(normalizeKey(query), {
    oracle_ids: oracleIds,
    fetched_at: Date.now()
  });
}

// Persistence

/** Load the on-disk cache into memory.  Safe to call on worker startup. */
async function load() {
  if (!fs.existsSync(TAG_CACHE_FILE)) {
    return;
  }
  try {
    const compressed = await fs.promises.readFile(TAG_CACHE_FILE);
    const raw = await new Promise((resolve, reject) => {
      zlib.gunzip(compressed, (err, buf) =>
        err ? reject(err) : resolve(buf.toString('utf8'))
      );
    });
    const data = JSON.parse(raw);
    cacheStore.clear();
    for (const [key, entry] of Object.entries(data)) {
      if (
        entry &&
        Array.isArray(entry.oracle_ids) &&
        typeof entry.fetched_at === 'number'
      ) {
        cacheStore.set(key, entry);
      }
    }
  } catch (err) {
    console.error('[TagCache] Failed to load cache file:', err.message);
  }
}

/** Persist the current in-memory cache to disk.  Fire-and-forget. */
async function save() {
  try {
    await fs.promises.mkdir(BULK_DATA_DIR, { recursive: true });
    const data = Object.fromEntries(cacheStore);
    const raw  = JSON.stringify(data);
    const compressed = await new Promise((resolve, reject) => {
      zlib.gzip(Buffer.from(raw, 'utf8'), (err, buf) =>
        err ? reject(err) : resolve(buf)
      );
    });
    await fs.promises.writeFile(TAG_CACHE_FILE, compressed);
  } catch (err) {
    console.error('[TagCache] Failed to save cache file:', err.message);
  }
}

// IPC helpers

/**
 * Serialise the full cache for broadcasting via IPC.
 * @returns {Object}
 */
function serializeForIPC() {
  return Object.fromEntries(cacheStore);
}

/**
 * Merge an IPC-broadcast update from the primary/another worker into the
 * local in-memory store.  Only entries newer than the local copy are applied.
 * @param {Object} data  Plain object from serializeForIPC().
 */
function ingestUpdate(data) {
  try {
    if (!data || typeof data !== 'object') {
      return;
    }
    for (const [key, entry] of Object.entries(data)) {
      if (
        entry &&
        Array.isArray(entry.oracle_ids) &&
        typeof entry.fetched_at === 'number'
      ) {
        const existing = cacheStore.get(key);
        if (!existing || entry.fetched_at > existing.fetched_at) {
          cacheStore.set(key, entry);
        }
      }
    }
  } catch (err) {
    console.error('[TagCache] Failed to ingest IPC update:', err.message);
  }
}

// Stats

/** Summary suitable for /metrics or debug logging. */
function getStats() {
  const now = Date.now();
  let staleCount = 0;
  let totalIds   = 0;
  for (const entry of cacheStore.values()) {
    totalIds += entry.oracle_ids.length;
    if ((now - entry.fetched_at) >= TAG_CACHE_TTL_MS) {
      staleCount++;
    }
  }
  return {
    entries:    cacheStore.size,
    stale:      staleCount,
    totalIds,
    filePath:   TAG_CACHE_FILE
  };
}

module.exports = {
  load,
  save,
  get,
  set,
  isStale,
  isLoaded,
  getStats,
  normalizeKey,
  ingestUpdate,
  serializeForIPC
};
