const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');

describe('Bulk Data - Commander Filter', () => {
  test('should not treat back-face-only legendary creature DFC as is:commander', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bulk-commander-'));
    const cardBasename = 'oracle_cards';
    const cardFile = path.join(tempDir, `${cardBasename}.json.gz`);
    const cards = [
      {
        id: 'bad-dfc',
        oracle_id: 'oracle-bad-dfc',
        name: 'Not a Commander Front // Commander Back',
        type_line: 'Artifact // Legendary Creature — Dragon',
        layout: 'transform',
        games: ['paper'],
        set: 'tst',
        set_type: 'expansion',
        lang: 'en',
        card_faces: [
          {
            name: 'Not a Commander Front',
            type_line: 'Artifact',
            oracle_text: ''
          },
          {
            name: 'Commander Back',
            type_line: 'Legendary Creature — Dragon',
            oracle_text: ''
          }
        ]
      },
      {
        id: 'good-commander',
        oracle_id: 'oracle-good-commander',
        name: 'Good Commander',
        type_line: 'Legendary Creature — Human Wizard',
        oracle_text: '',
        layout: 'normal',
        games: ['paper'],
        set: 'tst',
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
      const card = await bulkData.getRandomCard('is:commander game:paper');
      randomSpy.mockRestore();

      expect(card).toBeTruthy();
      expect(card.id).toBe('good-commander');
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

  test('should enforce f:commander legality in random query filters', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bulk-commander-legality-'));
    const cardBasename = 'oracle_cards';
    const cardFile = path.join(tempDir, `${cardBasename}.json.gz`);
    const cards = [
      {
        id: 'mana-crypt',
        oracle_id: 'oracle-mana-crypt',
        name: 'Mana Crypt',
        type_line: 'Artifact',
        layout: 'normal',
        games: ['paper'],
        set: '2xm',
        set_type: 'expansion',
        lang: 'en',
        cmc: 0,
        legalities: {
          commander: 'banned'
        }
      },
      {
        id: 'everflowing-chalice',
        oracle_id: 'oracle-everflowing-chalice',
        name: 'Everflowing Chalice',
        type_line: 'Artifact',
        layout: 'normal',
        games: ['paper'],
        set: 'wwk',
        set_type: 'expansion',
        lang: 'en',
        cmc: 0,
        legalities: {
          commander: 'legal'
        }
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
      const card = await bulkData.getRandomCard('cmc=0 t:artifact f:commander');
      randomSpy.mockRestore();

      expect(card).toBeTruthy();
      expect(card.name).toBe('Everflowing Chalice');

      const randomAliasSpy = jest.spyOn(Math, 'random').mockReturnValue(0);
      const aliasCard = await bulkData.getRandomCard('cmc=0 t:artifact f:c');
      randomAliasSpy.mockRestore();

      expect(aliasCard).toBeTruthy();
      expect(aliasCard.name).toBe('Everflowing Chalice');
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
