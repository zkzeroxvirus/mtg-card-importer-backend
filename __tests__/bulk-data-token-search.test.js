const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');

describe('Bulk Data - Token Search', () => {
  test('should match token searches for is:token and exclude DFC tokens', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bulk-token-'));
    const cardBasename = 'oracle_cards';
    const cardFile = path.join(tempDir, `${cardBasename}.json.gz`);
    const cards = [
      {
        name: 'Fish',
        type_line: 'Token Creature — Fish',
        layout: 'token',
        lang: 'en'
      },
      {
        name: 'Fish',
        type_line: 'Token Creature — Fish',
        layout: 'double_faced_token',
        lang: 'en'
      },
      {
        name: 'Fishmonger',
        type_line: 'Creature — Human',
        layout: 'normal',
        lang: 'en'
      }
    ];

    fs.writeFileSync(cardFile, zlib.gzipSync(JSON.stringify(cards)));

    const originalEnv = { ...process.env };

    try {
      process.env.BULK_DATA_PATH = tempDir;
      process.env.BULK_DATA_TYPE = cardBasename;
      process.env.BULK_INCLUDE_RULINGS = 'false';

      jest.resetModules();
      let bulkData;
      jest.isolateModules(() => {
        bulkData = require('../lib/bulk-data');
      });

      await bulkData.loadBulkData();
      const results = await bulkData.searchCards('fish is:token', 10);

      expect(results).toHaveLength(1);
      expect(results[0].layout).toBe('token');
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
