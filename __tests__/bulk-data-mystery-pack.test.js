const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');

describe('Bulk Data - Mystery Pack Overrides', () => {
  test('should allow mystery pack sets to bypass non-playable and booster flag checks', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bulk-mystery-'));
    const cardBasename = 'oracle_cards';
    const cardFile = path.join(tempDir, `${cardBasename}.json.gz`);
    const cards = [
      {
        id: 'cmb1-test-card',
        oracle_id: 'oracle-cmb1-test-card',
        name: 'Playtest Card',
        type_line: 'Creature — Weird',
        layout: 'normal',
        games: ['paper'],
        set: 'cmb1',
        set_type: 'funny',
        lang: 'en'
      },
      {
        id: 'dom-card',
        oracle_id: 'oracle-dom-card',
        name: 'Normal Card',
        type_line: 'Creature — Human',
        layout: 'normal',
        games: ['paper'],
        set: 'dom',
        set_type: 'expansion',
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

      const randomSpy = jest.spyOn(Math, 'random').mockReturnValue(0);
      const mysteryCard = await bulkData.getRandomCard('set:cmb1 is:booster -is:alchemy');
      randomSpy.mockRestore();

      expect(mysteryCard).toBeTruthy();
      expect(mysteryCard.set).toBe('cmb1');

      const nonMysteryCard = await bulkData.getRandomCard('set:dom is:booster');
      expect(nonMysteryCard).toBeNull();
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
