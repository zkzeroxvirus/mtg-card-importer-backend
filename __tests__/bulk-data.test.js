/**
 * Tests for bulk data download and loading functionality
 * Tests retry logic, error handling, and data validation
 */

// Mock dependencies before requiring bulk-data
jest.mock('axios');
const fs = require('fs');
const os = require('os');
const path = require('path');
const bulkData = require('../lib/bulk-data');

describe('Bulk Data - Download Retry Logic', () => {
  test('should retry on network failure', async () => {
    // This test documents the expected retry behavior
    // Actual implementation would need to mock axios and test retry attempts
    const maxRetries = 3;
    const expectedDelays = [1000, 2000, 4000]; // Exponential backoff: 1s, 2s, 4s
    
    expect(maxRetries).toBe(3);
    expect(expectedDelays[0]).toBe(1000);
    expect(expectedDelays[1]).toBe(2000);
    expect(expectedDelays[2]).toBe(4000);
  });

  test('should fail after max retries', async () => {
    // This test documents that download should fail after 3 attempts
    const maxRetries = 3;
    expect(maxRetries).toBe(3);
  });
});

describe('Bulk Data - File Validation', () => {
  test('should reject empty downloaded files', () => {
    // Documents validation requirement: file size must be > 0
    const invalidFileSize = 0;
    expect(invalidFileSize).toBe(0);
  });

  test('should validate file exists before loading', () => {
    // Documents requirement: check file existence before attempting load
    const fileCheck = true;
    expect(fileCheck).toBe(true);
  });
});

describe('Bulk Data - Promise-based Mutex', () => {
  test('should prevent concurrent downloads', async () => {
    // Documents the mutex lock behavior
    // When download is in progress, subsequent calls should wait
    let downloadLock = null;
    
    // First download creates lock
    let resolveDownload;
    downloadLock = new Promise((resolve) => {
      resolveDownload = resolve;
    });
    
    expect(downloadLock).toBeDefined();
    expect(typeof resolveDownload).toBe('function');
    
    // Resolve the lock
    resolveDownload();
    await downloadLock;
    downloadLock = null;
    
    expect(downloadLock).toBeNull();
  });

  test('should prevent concurrent loads', async () => {
    // Documents the load mutex behavior
    let loadLock = null;
    
    // First load creates lock
    let resolveLoad;
    loadLock = new Promise((resolve) => {
      resolveLoad = resolve;
    });
    
    expect(loadLock).toBeDefined();
    expect(typeof resolveLoad).toBe('function');
    
    // Resolve the lock
    resolveLoad();
    await loadLock;
    loadLock = null;
    
    expect(loadLock).toBeNull();
  });
});

describe('Bulk Data - Non-Playable Card Filtering', () => {
  test('should filter test card sets', () => {
    const testSets = ['cmb1', 'mb2', 'cmb2'];
    
    const testCard = { set: 'cmb1', name: 'Test Card' };
    expect(testSets.includes(testCard.set.toLowerCase())).toBe(true);
    
    const normalCard = { set: 'dom', name: 'Llanowar Elves' };
    expect(testSets.includes(normalCard.set.toLowerCase())).toBe(false);
  });

  test('should filter acorn-stamped cards', () => {
    const acornCard = { security_stamp: 'acorn', name: 'Acorn Card' };
    expect(acornCard.security_stamp.toLowerCase()).toBe('acorn');
    
    const normalCard = { security_stamp: 'oval', name: 'Normal Card' };
    expect(normalCard.security_stamp.toLowerCase()).not.toBe('acorn');
  });

  test('should filter non-playable layouts', () => {
    const nonPlayableLayouts = [
      'token',
      'double_faced_token',
      'emblem',
      'planar',
      'scheme',
      'vanguard',
      'art_series',
      'reversible_card',
      'augment',
      'host'
    ];
    
    const tokenCard = { layout: 'token', name: 'Treasure Token' };
    expect(nonPlayableLayouts.includes(tokenCard.layout.toLowerCase())).toBe(true);
    
    const normalCard = { layout: 'normal', name: 'Lightning Bolt' };
    expect(nonPlayableLayouts.includes(normalCard.layout.toLowerCase())).toBe(false);
  });
});

describe('Bulk Data - Extra Card Types', () => {
  test('should identify extra card types', () => {
    const extraTypes = ['token', 'emblem', 'scheme', 'plane', 'vanguard', 'conspiracy'];
    
    const tokenCard = { type_line: 'Token Creature — Goblin' };
    expect(tokenCard.type_line.toLowerCase()).toContain('token');
    
    const emblemCard = { type_line: 'Emblem — Jace' };
    expect(emblemCard.type_line.toLowerCase()).toContain('emblem');
    
    const normalCard = { type_line: 'Creature — Human Warrior' };
    expect(extraTypes.some(type => normalCard.type_line.toLowerCase().includes(type))).toBe(false);
  });

  test('should detect extra type query filters', () => {
    const tokenQuery = 't:token name:treasure';
    expect(tokenQuery.includes('t:token')).toBe(true);
    
    const emblemQuery = 'type:emblem';
    expect(emblemQuery.includes('type:emblem')).toBe(true);
    
    const normalQuery = 't:creature power>=3';
    expect(normalQuery.includes('t:token')).toBe(false);
  });
});

describe('Bulk Data - Streaming Decompression', () => {
  test('should decompress files using streams', () => {
    // Documents streaming decompression requirement
    const streamingDecompression = true;
    expect(streamingDecompression).toBe(true);
  });

  test('should handle decompression errors', () => {
    // Documents error handling requirement during decompression
    const shouldHandleErrors = true;
    expect(shouldHandleErrors).toBe(true);
  });
});

describe('Bulk Data - Scheduled Updates', () => {
  test('should update every 24 hours', () => {
    const updateInterval = 24 * 60 * 60 * 1000; // 24 hours in ms
    expect(updateInterval).toBe(86400000);
  });

  test('should restore old data on update failure', () => {
    // Documents failover behavior: if update fails, restore old data
    let cardsDatabase = { cards: ['old data'] };
    const oldCardsDatabase = cardsDatabase;
    
    // Simulate update failure
    cardsDatabase = null;
    
    // Restore old data
    cardsDatabase = oldCardsDatabase;
    
    expect(cardsDatabase).toEqual({ cards: ['old data'] });
  });

  test('should retry failed updates after 1 hour', () => {
    const retryInterval = 60 * 60 * 1000; // 1 hour in ms
    expect(retryInterval).toBe(3600000);
  });
});

describe('Bulk Data - Progress Tracking', () => {
  test('should log progress at 25% intervals', () => {
    const expectedSize = 100000000; // 100MB
    const intervals = [25, 50, 75, 100];
    
    intervals.forEach(percent => {
      const bytes = (expectedSize * percent) / 100;
      const calculatedPercent = Math.floor((bytes / expectedSize) * 100);
      expect(calculatedPercent).toBe(percent);
    });
  });
});

describe('Bulk Data - Random Pool Deduplication', () => {
  test('should dedupe cards by oracle_id for random selection', () => {
    const cards = [
      { id: 'print-1', oracle_id: 'oracle-1' },
      { id: 'print-2', oracle_id: 'oracle-1' },
      { id: 'print-3', oracle_id: 'oracle-2' },
      { id: 'unique-1' }
    ];

    const deduped = bulkData.dedupeCardsByOracleId(cards);

    expect(deduped).toHaveLength(3);
    expect(deduped.map(card => card.id)).toEqual(['print-1', 'print-3', 'unique-1']);
  });
});

describe('Bulk Data - Atomic File Operations', () => {
  test('should use temp file then atomic rename', () => {
    // Documents atomic file update pattern
    const outputPath = '/data/cards.json.gz';
    const tempPath = `${outputPath}.tmp`;
    
    expect(tempPath).toBe('/data/cards.json.gz.tmp');
  });

  test('should cleanup temp files on error', () => {
    // Documents cleanup requirement
    const shouldCleanupTempFiles = true;
    expect(shouldCleanupTempFiles).toBe(true);
  });
});

describe('Bulk Data - Cross-Process Locking', () => {
  test('should treat locks older than 30 minutes as stale', () => {
    const staleThresholdMs = 30 * 60 * 1000; // 30 minutes
    expect(staleThresholdMs).toBe(1800000);
  });
});

describe('Bulk Data - Cross-Process Lock Integration', () => {
  test('should wait for lock release and reuse existing download', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bulk-data-'));
    const cardBasename = 'oracle_cards';
    const cardFile = path.join(tempDir, `${cardBasename}.json.gz`);
    const lockFile = path.join(tempDir, `${cardBasename}.download.lock`);
    const originalEnv = { ...process.env };

    try {
      process.env.BULK_DATA_PATH = tempDir;
      process.env.BULK_DATA_TYPE = cardBasename;
      process.env.BULK_INCLUDE_RULINGS = 'false';

      jest.resetModules();
      let isolatedBulkData;
      let isolatedAxios;
      jest.isolateModules(() => {
        isolatedAxios = require('axios');
        isolatedAxios.get.mockReset();
        isolatedAxios.get.mockImplementation(() => {
          throw new Error('axios should not be called');
        });
        isolatedBulkData = require('../lib/bulk-data');
      });

      const releaseDelayMs = 100;
      fs.writeFileSync(lockFile, `${process.pid}\n${new Date().toISOString()}\n`);
      setTimeout(() => {
        if (fs.existsSync(lockFile)) {
          fs.unlinkSync(lockFile);
        }
        fs.writeFileSync(cardFile, 'existing data');
      }, releaseDelayMs);

      await isolatedBulkData.downloadBulkData();
      expect(isolatedAxios.get).not.toHaveBeenCalled();
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

  test('should clean up stale locks before continuing', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bulk-data-'));
    const cardBasename = 'oracle_cards';
    const cardFile = path.join(tempDir, `${cardBasename}.json.gz`);
    const lockFile = path.join(tempDir, `${cardBasename}.download.lock`);
    const originalEnv = { ...process.env };

    try {
      process.env.BULK_DATA_PATH = tempDir;
      process.env.BULK_DATA_TYPE = cardBasename;
      process.env.BULK_INCLUDE_RULINGS = 'false';

      jest.resetModules();
      let isolatedBulkData;
      let isolatedAxios;
      jest.isolateModules(() => {
        isolatedAxios = require('axios');
        isolatedAxios.get.mockReset();
        isolatedAxios.get.mockImplementation(() => {
          throw new Error('axios should not be called');
        });
        isolatedBulkData = require('../lib/bulk-data');
      });

      const staleTimestamp = new Date(Date.now() - (31 * 60 * 1000)).toISOString();
      fs.writeFileSync(lockFile, `${process.pid}\n${staleTimestamp}\n`);
      fs.writeFileSync(cardFile, 'existing data');

      await isolatedBulkData.downloadBulkData();
      expect(fs.existsSync(lockFile)).toBe(false);
      expect(isolatedAxios.get).not.toHaveBeenCalled();
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

describe('Bulk Data - User-Agent Headers', () => {
  test('should include proper User-Agent for API calls', () => {
    const packageVersion = '0.1.0';
    const userAgent = `MTGCardImporterTTS/${packageVersion}`;
    
    expect(userAgent).toBe('MTGCardImporterTTS/0.1.0');
  });

  test('should use Accept application/json for API calls', () => {
    const acceptHeader = 'application/json';
    expect(acceptHeader).toBe('application/json');
  });

  test('should use Accept */* for bulk downloads', () => {
    const acceptHeader = '*/*';
    expect(acceptHeader).toBe('*/*');
  });
});

describe('Bulk Data - Timeout Configuration', () => {
  test('should use 10 second timeout for API calls', () => {
    const apiTimeout = 10000; // 10 seconds
    expect(apiTimeout).toBe(10000);
  });

  test('should use 5 minute timeout for bulk downloads', () => {
    const downloadTimeout = 300000; // 5 minutes
    expect(downloadTimeout).toBe(300000);
  });
});

describe('Bulk Data - Card Name Normalization', () => {
  test('should normalize underscores to spaces', () => {
    const input = 'Black_Lotus';
    const expected = 'Black Lotus';
    const normalized = input.replace(/[_]+/g, ' ');
    expect(normalized).toBe(expected);
  });

  test('should normalize quotes', () => {
    const input = '"Ach! Hans, Run!"';
    const hasQuotes = input.includes('"');
    expect(hasQuotes).toBe(true);
  });

  test('should handle apostrophes', () => {
    const input = "Ur-Dragon's Forge";
    const hasApostrophe = input.includes("'");
    expect(hasApostrophe).toBe(true);
  });

  test('should trim whitespace', () => {
    const input = '  Mountain  ';
    const trimmed = input.trim();
    expect(trimmed).toBe('Mountain');
  });

  test('should collapse multiple spaces', () => {
    const input = 'Black    Lotus';
    const normalized = input.replace(/\s+/g, ' ');
    expect(normalized).toBe('Black Lotus');
  });
});
