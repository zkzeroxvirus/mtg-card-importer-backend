const fs = require('fs');
const os = require('os');
const path = require('path');

const DAY_MS = 24 * 60 * 60 * 1000;

function loadTagCache(tempDir) {
  process.env.BULK_DATA_PATH = tempDir;
  jest.resetModules();
  return require('../lib/tag-cache');
}

describe('tag-cache', () => {
  let tempDir;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tag-cache-test-'));
  });

  afterEach(() => {
    delete process.env.BULK_DATA_PATH;
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  test('normalizes keys for set/get', () => {
    const tagCache = loadTagCache(tempDir);

    tagCache.set('OTag:Equipment', ['oracle-1']);

    const fromLower = tagCache.get('otag:equipment');
    const fromUpper = tagCache.get('OTAG:EQUIPMENT');

    expect(fromLower).toBeTruthy();
    expect(fromUpper).toBeTruthy();
    expect(fromLower.oracle_ids).toEqual(['oracle-1']);
    expect(fromUpper.oracle_ids).toEqual(['oracle-1']);
  });

  test('marks entries stale after ttl', () => {
    const tagCache = loadTagCache(tempDir);

    const key = tagCache.normalizeKey('otag:equipment');
    tagCache.ingestUpdate({
      [key]: {
        oracle_ids: ['oracle-1'],
        fetched_at: Date.now() - DAY_MS - 1000
      }
    });

    expect(tagCache.isStale('otag:equipment')).toBe(true);
  });

  test('saves to disk and reloads', async () => {
    const tagCache = loadTagCache(tempDir);
    tagCache.set('otag:equipment', ['oracle-1', 'oracle-2']);

    await tagCache.save();

    const reloadedTagCache = loadTagCache(tempDir);
    await reloadedTagCache.load();

    const entry = reloadedTagCache.get('otag:equipment');
    expect(entry).toBeTruthy();
    expect(entry.oracle_ids).toEqual(['oracle-1', 'oracle-2']);
    expect(typeof entry.fetched_at).toBe('number');
  });

  test('ingestUpdate keeps newer local entries', () => {
    const tagCache = loadTagCache(tempDir);

    const key = tagCache.normalizeKey('otag:equipment');
    const newer = Date.now();
    const older = newer - 5000;

    tagCache.ingestUpdate({
      [key]: {
        oracle_ids: ['newer-id'],
        fetched_at: newer
      }
    });

    tagCache.ingestUpdate({
      [key]: {
        oracle_ids: ['older-id'],
        fetched_at: older
      }
    });

    const entry = tagCache.get('otag:equipment');
    expect(entry.oracle_ids).toEqual(['newer-id']);
    expect(entry.fetched_at).toBe(newer);
  });
});
