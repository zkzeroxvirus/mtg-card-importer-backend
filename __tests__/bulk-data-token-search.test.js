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

  test('getRandomCard should return token cards for token queries', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bulk-token-random-'));
    const cardBasename = 'oracle_cards';
    const cardFile = path.join(tempDir, `${cardBasename}.json.gz`);
    const cards = [
      {
        name: 'Treasure',
        type_line: 'Token Artifact — Treasure',
        layout: 'token',
        oracle_id: 'treasure-token-1',
        lang: 'en'
      },
      {
        name: 'Treasure',
        type_line: 'Token Artifact — Treasure',
        layout: 'double_faced_token',
        oracle_id: 'treasure-token-2',
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
      const result = await bulkData.getRandomCard('t:token name:treasure');

      expect(result).toBeTruthy();
      expect(result.layout).toBe('token');
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

  test('should correctly parse quoted multi-word name filters for token searches', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bulk-token-quoted-name-'));
    const cardBasename = 'oracle_cards';
    const cardFile = path.join(tempDir, `${cardBasename}.json.gz`);
    const cards = [
      {
        name: 'A Mysterious Creature',
        type_line: 'Token Creature — Weird',
        layout: 'token',
        lang: 'en'
      },
      {
        name: 'A',
        type_line: 'Token Creature — Weird',
        layout: 'token',
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
      const results = await bulkData.searchCards('t:token name:"A Mysterious Creature"', 10);

      expect(results).toHaveLength(1);
      expect(results[0].name).toBe('A Mysterious Creature');
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

  test('getExactTokenByName should return fast exact token match (exclude DFC)', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bulk-token-exact-'));
    const cardBasename = 'oracle_cards';
    const cardFile = path.join(tempDir, `${cardBasename}.json.gz`);
    const cards = [
      {
        name: 'Fish',
        type_line: 'Token Creature — Fish',
        layout: 'double_faced_token',
        lang: 'en',
        set: 'set1'
      },
      {
        name: 'Fish',
        type_line: 'Token Creature — Fish',
        layout: 'token',
        lang: 'es',
        set: 'set1'
      },
      {
        name: 'Fish',
        type_line: 'Token Creature — Fish',
        layout: 'token',
        lang: 'en',
        set: 'set2'
      },
      {
        name: 'Fish',
        type_line: 'Creature — Fish',
        layout: 'normal',
        lang: 'en',
        set: 'set3'
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

      const exactAnySet = bulkData.getExactTokenByName('fish');
      expect(exactAnySet).toBeTruthy();
      expect(exactAnySet.layout).toBe('token');
      expect(exactAnySet.lang).toBe('en');
      expect(exactAnySet.set).toBe('set2');

      const exactSet1 = bulkData.getExactTokenByName('fish', 'set1');
      expect(exactSet1).toBeTruthy();
      expect(exactSet1.layout).toBe('token');
      expect(exactSet1.set).toBe('set1');
      expect(exactSet1.lang).toBe('es');
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
