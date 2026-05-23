const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');

describe('Bulk Data - Grouped Set OR Filters', () => {
  test('should honor grouped set OR filters that use set: prefix', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bulk-set-or-'));
    const cardBasename = 'oracle_cards';
    const cardFile = path.join(tempDir, `${cardBasename}.json.gz`);
    const cards = [
      {
        id: 'rtr-card',
        oracle_id: 'oracle-rtr-card',
        name: 'RTR Card',
        type_line: 'Creature - Human',
        layout: 'normal',
        games: ['paper'],
        set: 'rtr',
        set_type: 'expansion',
        color_identity: ['R'],
        lang: 'en'
      },
      {
        id: 'afr-card',
        oracle_id: 'oracle-afr-card',
        name: 'AFR Card',
        type_line: 'Creature - Human',
        layout: 'normal',
        games: ['paper'],
        set: 'afr',
        set_type: 'expansion',
        color_identity: ['B'],
        lang: 'en'
      },
      {
        id: 'dom-card',
        oracle_id: 'oracle-dom-card',
        name: 'DOM Card',
        type_line: 'Creature - Human',
        layout: 'normal',
        games: ['paper'],
        set: 'dom',
        set_type: 'expansion',
        color_identity: ['R'],
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

      const results = await bulkData.getRandomCards('id:rb+(set:rtr OR set:afr)', 10, true, false);

      expect(results).toBeTruthy();
      expect(results.length).toBeGreaterThan(0);
      expect(results.every(card => ['rtr', 'afr'].includes(card.set))).toBe(true);
      expect(results.some(card => card.set === 'rtr')).toBe(true);
      expect(results.some(card => card.set === 'afr')).toBe(true);
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
