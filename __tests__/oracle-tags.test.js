jest.mock('axios');

const fs = require('fs');
const os = require('os');
const path = require('path');
const { Readable } = require('stream');
const zlib = require('zlib');

describe('Oracle Tags bulk loading', () => {
  test('should download, cache, and load streamed JSONL oracle tags', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'oracle-tags-'));
    const originalEnv = { ...process.env };
    const tags = [
      {
        id: 'tag-1',
        slug: 'treasure',
        label: 'Treasure',
        aliases: ['Gold'],
        taggings: [{ oracle_id: 'oracle-1' }]
      }
    ];
    const jsonl = `${tags.map(JSON.stringify).join('\n')}\n`;

    try {
      process.env.BULK_DATA_PATH = tempDir;

      jest.resetModules();
      let oracleTags;
      let axios;
      jest.isolateModules(() => {
        axios = require('axios');
        axios.get.mockReset();
        axios.get.mockImplementation((url) => {
          if (String(url).includes('/bulk-data/')) {
            return Promise.resolve({
              data: {
                jsonl_download_uri: 'https://data.scryfall.test/oracle-tags.jsonl',
                size: Buffer.byteLength(jsonl),
                updated_at: '2026-07-02T00:00:00Z'
              }
            });
          }

          return Promise.resolve({
            data: Readable.from([Buffer.from(jsonl, 'utf8')]),
            headers: { 'content-type': 'application/x-ndjson' },
            config: { url }
          });
        });
        oracleTags = require('../lib/oracle-tags');
      });

      await oracleTags.loadOracleTags({ forceRefresh: true });

      expect(oracleTags.getOracleIdsForTerm('treasure')).toEqual(['oracle-1']);
      expect(oracleTags.getOracleIdsForTerm('gold')).toEqual(['oracle-1']);
      expect(fs.existsSync(path.join(tempDir, 'oracle_tags.json.gz'))).toBe(true);
      expect(fs.existsSync(path.join(tempDir, 'oracle_tags.json.gz.manifest.json'))).toBe(true);
      expect(axios.get.mock.calls[1][1]).toMatchObject({
        responseType: 'stream',
        decompress: false
      });
    } finally {
      Object.keys(process.env).forEach((key) => {
        if (!(key in originalEnv)) {
          delete process.env[key];
        }
      });
      Object.assign(process.env, originalEnv);
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });

  test('should refresh existing oracle tags when manifest is missing', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'oracle-tags-'));
    const originalEnv = { ...process.env };
    const staleTags = [
      {
        id: 'tag-old',
        slug: 'old-tag',
        label: 'Old Tag',
        aliases: [],
        taggings: [{ oracle_id: 'oracle-old' }]
      }
    ];
    const freshTags = [
      {
        id: 'tag-new',
        slug: 'new-tag',
        label: 'New Tag',
        aliases: [],
        taggings: [{ oracle_id: 'oracle-new' }]
      }
    ];
    const freshJsonl = `${freshTags.map(JSON.stringify).join('\n')}\n`;

    try {
      process.env.BULK_DATA_PATH = tempDir;
      fs.writeFileSync(
        path.join(tempDir, 'oracle_tags.json.gz'),
        zlib.gzipSync(Buffer.from(JSON.stringify(staleTags), 'utf8'))
      );

      jest.resetModules();
      let oracleTags;
      let axios;
      jest.isolateModules(() => {
        axios = require('axios');
        axios.get.mockReset();
        axios.get.mockImplementation((url) => {
          if (String(url).includes('/bulk-data/')) {
            return Promise.resolve({
              data: {
                jsonl_download_uri: 'https://data.scryfall.test/oracle-tags.jsonl',
                size: Buffer.byteLength(freshJsonl),
                updated_at: '2026-07-09T00:00:00Z'
              }
            });
          }

          return Promise.resolve({
            data: Readable.from([Buffer.from(freshJsonl, 'utf8')]),
            headers: { 'content-type': 'application/x-ndjson' },
            config: { url }
          });
        });
        oracleTags = require('../lib/oracle-tags');
      });

      await oracleTags.loadOracleTags();

      expect(oracleTags.getOracleIdsForTerm('new-tag')).toEqual(['oracle-new']);
      expect(oracleTags.getOracleIdsForTerm('old-tag')).toEqual([]);
      expect(fs.existsSync(path.join(tempDir, 'oracle_tags.json.gz.manifest.json'))).toBe(true);
      expect(axios.get).toHaveBeenCalledTimes(2);
    } finally {
      Object.keys(process.env).forEach((key) => {
        if (!(key in originalEnv)) {
          delete process.env[key];
        }
      });
      Object.assign(process.env, originalEnv);
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });
});
