const axios = require('axios');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { pipeline } = require('stream/promises');

// Read version from package.json for User-Agent header
const packageVersion = require('../package.json').version;

const BULK_DATA_DIR = process.env.BULK_DATA_PATH || path.join(__dirname, '../data');
// Allow choosing a smaller dataset to fit memory (oracle_cards is ~161MB compressed)
const BULK_DATA_TYPE = process.env.BULK_DATA_TYPE || 'oracle_cards';
const INCLUDE_RULINGS = process.env.BULK_INCLUDE_RULINGS === 'true';
const CARD_FILE_BASENAME = BULK_DATA_TYPE.replace(/[^a-z_]/gi, '');
const CARD_DATA_FILE = path.join(BULK_DATA_DIR, `${CARD_FILE_BASENAME}.json.gz`);
const RULINGS_FILE = path.join(BULK_DATA_DIR, 'rulings.json.gz');
const UPDATE_INTERVAL = 24 * 60 * 60 * 1000; // 24 hours
const RETRY_INTERVAL = 60 * 60 * 1000; // 1 hour for retrying failed updates
const DOWNLOAD_LOCK_FILE = path.join(BULK_DATA_DIR, `${CARD_FILE_BASENAME}.download.lock`);
const DOWNLOAD_LOCK_STALE_MS = 30 * 60 * 1000; // 30 minutes
const DOWNLOAD_LOCK_POLL_MS = 1000; // 1 second
const DOWNLOAD_LOCK_MAX_POLL_MS = 10000; // 10 seconds

let cardsDatabase = null;
let rulingsDatabase = null;
let cardsLoaded = false;
let lastUpdateCheck = 0;
let updateTimeout = null;

/**
 * Normalize a card name for better fuzzy matching
 */
function normalizeCardName(name) {
  if (!name || typeof name !== 'string') return '';
  return name
    .replace(/[_]+/g, ' ')
    .replace(/[“”]/g, '"')
    .replace(/[’]/g, "'")
    .replace(/[^\w\s'\-:,]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// Include plural variants (tokens/planes/etc.) to mirror common query input.
const EXTRA_CARD_TYPES = [
  'token',
  'tokens',
  'emblem',
  'emblems',
  'scheme',
  'schemes',
  'plane',
  'planes',
  'phenomenon',
  'phenomena',
  'vanguard',
  'vanguards',
  'conspiracy',
  'conspiracies'
];
const EXTRA_CARD_TYPE_SET = new Set(EXTRA_CARD_TYPES);
const EXTRA_CARD_TYPE_PATTERN = EXTRA_CARD_TYPES.join('|');
// Build regex from shared type list to keep type line detection in sync.
const EXTRA_CARD_TYPE_REGEX = new RegExp(`\\b(${EXTRA_CARD_TYPE_PATTERN})\\b`, 'i');

// Known fetchland names for is:fetchland filter
// Note: This list may need periodic updates as new fetchlands are printed
const KNOWN_FETCHLANDS = [
  'polluted delta', 'bloodstained mire', 'wooded foothills', 'windswept heath', 'flooded strand',
  'marsh flats', 'scalding tarn', 'verdant catacombs', 'arid mesa', 'misty rainforest',
  'prismatic vista', 'fabled passage', 'evolving wilds', 'terramorphic expanse'
];

// Known shockland names for is:shockland filter
// Note: This list may need periodic updates as new shocklands are printed
const KNOWN_SHOCKLANDS = [
  'temple garden', 'hallowed fountain', 'watery grave', 'blood crypt', 'stomping ground',
  'godless shrine', 'steam vents', 'overgrown tomb', 'sacred foundry', 'breeding pool'
];
const EXTRA_TYPE_QUERY_REGEX = new RegExp(
  `(?:^|\\s|\\(|\\+)(?:t|type|is):(?:${EXTRA_CARD_TYPE_PATTERN})\\b`,
  'i'
);

function isExtraCard(card) {
  const typeLine = card.type_line || '';
  return EXTRA_CARD_TYPE_REGEX.test(typeLine);
}

function shouldIncludeExtraTypes(filters, query) {
  // parseQuery only captures t: filters, so still scan the raw query for type: /is: extra type filters.
  const typeFilters = (filters.type || []).map(type => type.toLowerCase());
  if (typeFilters.some(type => EXTRA_CARD_TYPE_SET.has(type))) {
    return true;
  }
  return EXTRA_TYPE_QUERY_REGEX.test(query);
}

/**
 * Check if card is not meant for constructed play
 * This includes:
 * - Test cards from Mystery Booster playtest sets (cmb1, mb2, cmb2)
 * - Acorn stamped cards (not tournament legal - casual/Un-sets)
 * - Non-playable layouts (tokens, art cards, emblems, etc.)
 * - Digital-only cards (not available in paper Magic)
 * - Promotional/memorabilia sets (funny, memorabilia, token, minigame)
 * - Oversized cards (vanguard, planechase planes/schemes, commemorative cards)
 */
function isNonPlayableCard(card) {
  // Check for test card sets (Mystery Booster playtest cards)
  const set = card.set || '';
  const testCardSets = ['cmb1', 'mb2', 'cmb2'];
  if (testCardSets.includes(set.toLowerCase())) {
    return true;
  }
  
  // Check for acorn security stamp (not tournament legal - casual/Un-sets)
  const securityStamp = card.security_stamp || '';
  if (securityStamp.toLowerCase() === 'acorn') {
    return true;
  }
  
  // Exclude digital-only cards (not available in paper Magic)
  const games = card.games || [];
  if (!games.includes('paper')) {
    return true;
  }
  
  // Exclude oversized cards (vanguard, planechase planes, archenemy schemes, commemorative cards)
  // These are special format cards not used in regular deck construction
  if (card.oversized === true) {
    return true;
  }
  
  // Exclude promotional and memorabilia set types
  // These are special event cards, oversized cards, or joke cards not meant for regular play
  const setType = card.set_type || '';
  const nonPlayableSetTypes = [
    'funny',        // Un-sets and joke cards (silver-bordered)
    'memorabilia',  // Gold-bordered, oversized, trophy cards
    'token',        // Token-only sets
    'minigame'      // Special minigame cards (e.g., Jumpstart front cards, Hero's Path)
  ];
  if (nonPlayableSetTypes.includes(setType.toLowerCase())) {
    return true;
  }
  
  // Check for non-playable layouts
  // These layouts are not meant for constructed play and should be excluded from random results
  // to match Scryfall's /cards/random endpoint behavior
  const layout = card.layout || '';
  const nonPlayableLayouts = [
    'token',              // Token cards
    'double_faced_token', // Double-faced tokens
    'emblem',             // Emblem cards
    'planar',             // Plane and Phenomenon cards
    'scheme',             // Scheme cards
    'vanguard',           // Vanguard cards
    'art_series',         // Art series collectible cards
    'reversible_card',    // Reversible cards (unrelated faces)
    'augment',            // Augment cards (Unstable)
    'host',               // Host cards (Unstable)
    'dungeon',            // Dungeon cards (Adventures in the Forgotten Realms)
    'hero',               // Hero cards (Theros Beyond Death)
    'attraction',         // Attraction cards (Unfinity)
    'stickers'            // Sticker cards (Unfinity)
  ];
  if (nonPlayableLayouts.includes(layout.toLowerCase())) {
    return true;
  }
  
  // Exclude meld result cards (the backside formed when two cards meld together)
  // Meld results have layout:"meld" and collector numbers ending in "b" (e.g., "123b", "18b")
  // Examples: "Chittering Host" (123b), "Brisela, Voice of Nightmares" (15b)
  // These are not playable cards on their own and should be filtered out
  // This matches Scryfall's /cards/random endpoint behavior
  if (layout.toLowerCase() === 'meld') {
    const collectorNumber = card.collector_number || '';
    // Check if collector number ends with 'b' (case insensitive)
    if (collectorNumber.toLowerCase().endsWith('b')) {
      return true;
    }
  }
  
  // Exclude basic lands (Forest, Island, Mountain, Plains, Swamp, Wastes, Snow-Covered variants)
  // Basic lands have "Basic" in their type_line (e.g., "Basic Land — Forest", "Basic Snow Land — Plains")
  // This matches Scryfall's /cards/random behavior which typically excludes basic lands from random results
  const typeLine = card.type_line || '';
  if (typeLine.toLowerCase().includes('basic')) {
    return true;
  }
  
  return false;
}

function dedupeCardsByOracleId(cards) {
  const seen = new Set();
  return cards.filter(card => {
    const oracleId = card.oracle_id;
    if (!oracleId) {
      return true;
    }
    if (seen.has(oracleId)) {
      return false;
    }
    seen.add(oracleId);
    return true;
  });
}

// Promise-based mutex locks to prevent race conditions
let downloadLock = null;
let loadLock = null;

function tryAcquireDownloadLock() {
  try {
    // Lock file format: line 1 = PID, line 2 = ISO timestamp.
    fs.writeFileSync(DOWNLOAD_LOCK_FILE, `${process.pid}\n${new Date().toISOString()}\n`, { flag: 'wx' });
    return true;
  } catch (error) {
    if (error.code === 'EEXIST') {
      return false;
    }
    throw error;
  }
}

function releaseDownloadLock() {
  try {
    fs.unlinkSync(DOWNLOAD_LOCK_FILE);
  } catch (error) {
    if (error.code !== 'ENOENT') {
      throw error;
    }
  }
}

async function waitForDownloadLockRelease() {
  let pollDelayMs = DOWNLOAD_LOCK_POLL_MS;
  while (true) {
    let lockContents;
    try {
      lockContents = fs.readFileSync(DOWNLOAD_LOCK_FILE, 'utf8');
    } catch (error) {
      if (error.code === 'ENOENT') {
        break;
      }
      throw error;
    }

    const lockLines = lockContents.split('\n');
    const lockTimestampLine = lockLines.length > 1 ? lockLines[1] : '';
    const lockTimestamp = Date.parse(lockTimestampLine);
    const lockAgeMs = Number.isNaN(lockTimestamp)
      ? DOWNLOAD_LOCK_STALE_MS + 1 // Treat invalid timestamps as stale.
      : Date.now() - lockTimestamp;
    if (lockAgeMs > DOWNLOAD_LOCK_STALE_MS) {
      console.warn(`[BulkData] Stale download lock detected (older than ${DOWNLOAD_LOCK_STALE_MS / 60000} minutes), removing...`);
      try {
        fs.unlinkSync(DOWNLOAD_LOCK_FILE);
      } catch (error) {
        if (error.code !== 'ENOENT') {
          throw error;
        }
      }
      break;
    }
    await new Promise(resolve => setTimeout(resolve, pollDelayMs));
    pollDelayMs = Math.min(pollDelayMs * 2, DOWNLOAD_LOCK_MAX_POLL_MS);
  }
}

// Ensure data directory exists
if (!fs.existsSync(BULK_DATA_DIR)) {
  fs.mkdirSync(BULK_DATA_DIR, { recursive: true });
}

/**
 * Download a single bulk data file from Scryfall using streaming with retry logic
 */
async function downloadBulkFile(type, outputPath, maxRetries = 3) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      console.log(`[BulkData] Fetching ${type} bulk data info... (attempt ${attempt + 1}/${maxRetries})`);
      
      // Get bulk data info from Scryfall API with proper headers
      const { data: bulkInfo } = await axios.get(`https://api.scryfall.com/bulk-data/${type}`, {
        headers: {
          'User-Agent': `MTGCardImporterTTS/${packageVersion}`,
          'Accept': 'application/json'
        },
        timeout: 10000
      });
      const downloadUrl = bulkInfo.download_uri;
      const expectedSize = bulkInfo.size;
      const sizeInMB = Math.round(expectedSize / 1024 / 1024);
      
      console.log(`[BulkData] Downloading ${type} (${sizeInMB}MB)...`);
      console.log(`[BulkData] Updated: ${bulkInfo.updated_at}`);
      
      const startTime = Date.now();
      const tempPath = `${outputPath}.tmp`;
      
      // Stream download directly to compressed file
      // Note: Download URL points to *.scryfall.io which doesn't have rate limits per Scryfall docs
      const response = await axios.get(downloadUrl, {
        responseType: 'stream',
        timeout: 300000,  // 5 minute timeout for large files
        headers: {
          'User-Agent': `MTGCardImporterTTS/${packageVersion}`,
          'Accept': '*/*'
        }
      });
      
      console.log(`[BulkData] Streaming and compressing ${type}...`);
      
      let downloadedBytes = 0;
      let lastLoggedPercent = 0;
      
      // Track download progress
      response.data.on('data', (chunk) => {
        downloadedBytes += chunk.length;
        if (expectedSize) {
          const percentCompleted = Math.floor((downloadedBytes / expectedSize) * 100);
          if (percentCompleted >= lastLoggedPercent + 25) {
            console.log(`[BulkData] ${type}: ${percentCompleted}% complete`);
            lastLoggedPercent = percentCompleted;
          }
        }
      });
      
      try {
        // Stream: download -> gzip -> file (memory efficient)
        await pipeline(
          response.data,
          zlib.createGzip(),
          fs.createWriteStream(tempPath)
        );
        
        // Validate downloaded file size
        const stats = fs.statSync(tempPath);
        if (stats.size === 0) {
          throw new Error('Downloaded file is empty');
        }
        
        // Atomic rename to final location
        fs.renameSync(tempPath, outputPath);
      } finally {
        // Cleanup temp file if it still exists
        if (fs.existsSync(tempPath)) {
          fs.unlinkSync(tempPath);
        }
      }
      
      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      console.log(`[BulkData] ${type} download complete in ${duration}s!`);
      return true;
    } catch (error) {
      const isLastAttempt = attempt === maxRetries - 1;
      const errorMessage = error.message || 'Unknown error';
      
      if (isLastAttempt) {
        console.error(`[BulkData] ${type} download failed after ${maxRetries} attempts:`, errorMessage);
        throw error;
      }
      
      // Calculate exponential backoff delay (1s, 2s, 4s)
      const delayMs = Math.pow(2, attempt) * 1000;
      console.warn(
        `[BulkData] ${type} download failed (${errorMessage}), retrying in ${delayMs}ms (attempt ${attempt + 1}/${maxRetries})`
      );
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
}

/**
 * Download all required bulk data from Scryfall
 */
async function downloadBulkData() {
  // Prevent concurrent downloads using promise-based lock
  if (downloadLock) {
    console.log('[BulkData] Download already in progress, waiting...');
    await downloadLock;
    // Another download just completed, so data should be available
    return true;
  }
  
  // Create a promise that will be resolved when download completes
  let resolveDownload;
  downloadLock = new Promise((resolve) => {
    resolveDownload = resolve;
  });
  let processLockAcquired = false;
  let loggedWait = false;
  
  try {
    while (!processLockAcquired) {
      processLockAcquired = tryAcquireDownloadLock();
      if (!processLockAcquired) {
        if (!loggedWait) {
          console.log('[BulkData] Another process is downloading bulk data, waiting for lock...');
          loggedWait = true;
        }
        await waitForDownloadLockRelease();
        const cardsFileExists = fs.existsSync(CARD_DATA_FILE);
        const rulingsFileExists = fs.existsSync(RULINGS_FILE);
        if (cardsFileExists && (!INCLUDE_RULINGS || rulingsFileExists)) {
          return true;
        }
      }
    }

    const startTime = Date.now();
    console.log('[BulkData] Starting bulk data download...');
    
    const tasks = [downloadBulkFile(BULK_DATA_TYPE, CARD_DATA_FILE)];
    if (INCLUDE_RULINGS) {
      tasks.push(downloadBulkFile('rulings', RULINGS_FILE));
    }

    // Use allSettled to handle independent failures gracefully
    const results = await Promise.allSettled(tasks);
    
    // Check if any downloads failed
    const failures = results.filter(r => r.status === 'rejected');
    if (failures.length > 0) {
      const errors = failures.map(f => f.reason.message).join(', ');
      throw new Error(`Download failed: ${errors}`);
    }
    
    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`[BulkData] All downloads complete in ${duration}s`);
    lastUpdateCheck = Date.now();
    return true;
  } catch (error) {
    console.error('[BulkData] Bulk data download failed:', error.message);
    throw error;
  } finally {
    if (processLockAcquired) {
      releaseDownloadLock();
    }
    resolveDownload();
    downloadLock = null;
  }
}

/**
 * Load bulk data into memory using streaming decompression
 */
async function loadBulkData() {
  // Prevent concurrent loading using promise-based lock
  if (loadLock) {
    console.log('[BulkData] Load already in progress, waiting...');
    await loadLock;
    // Check if the previous load succeeded
    if (!cardsLoaded || !cardsDatabase) {
      throw new Error('Previous load operation failed');
    }
    return cardsDatabase;
  }

  if (cardsLoaded) {
    console.log('[BulkData] Already loaded');
    return cardsDatabase;
  }
  
  // Create a promise that will be resolved when loading completes
  let resolveLoad;
  loadLock = new Promise((resolve) => {
    resolveLoad = resolve;
  });
  
  try {
    // Check if files exist
    const cardsFileExists = fs.existsSync(CARD_DATA_FILE);
    const rulingsFileExists = fs.existsSync(RULINGS_FILE);
    
    // Files need to exist AND (rulings not needed OR rulings exists)
    let needsDownload = !cardsFileExists || (INCLUDE_RULINGS && !rulingsFileExists);
  
  // Try to load existing files, but if they're corrupted, delete and re-download
  if (cardsFileExists && !needsDownload) {
    try {
      console.log('[BulkData] Loading bulk data into memory...');
      const startTime = Date.now();
      
      // Load and decompress card data using streaming
      console.log('[BulkData] Loading card data...');
      const cardsJson = await decompressFile(CARD_DATA_FILE);
      cardsDatabase = JSON.parse(cardsJson);
      
      // Load and decompress rulings if enabled AND file exists
      if (INCLUDE_RULINGS && rulingsFileExists) {
        try {
          console.log('[BulkData] Loading rulings...');
          const rulingsJson = await decompressFile(RULINGS_FILE);
          rulingsDatabase = JSON.parse(rulingsJson);
        } catch (rulingsError) {
          console.error('[BulkData] Failed to load rulings:', rulingsError.message);
          rulingsDatabase = null;
        }
      } else {
        rulingsDatabase = null;
      }
      
      const rulingCount = rulingsDatabase ? rulingsDatabase.length : 0;
      const loadTime = ((Date.now() - startTime) / 1000).toFixed(2);
      console.log(`[BulkData] Loaded ${cardsDatabase.length} cards and ${rulingCount} rulings in ${loadTime}s`);
      
      cardsLoaded = true;
      
      // Schedule next update check
      scheduleUpdateCheck();
      
      return cardsDatabase;
    } catch (error) {
      console.error('[BulkData] Failed to parse existing bulk data:', error.message);
      console.log('[BulkData] Deleting corrupted files and re-downloading...');
      
      // Delete corrupted files
      if (fs.existsSync(CARD_DATA_FILE)) {
        fs.unlinkSync(CARD_DATA_FILE);
      }
      if (fs.existsSync(RULINGS_FILE)) {
        fs.unlinkSync(RULINGS_FILE);
      }
      
      needsDownload = true;
    }
  }
  
    // Download if files don't exist or are corrupted
    if (needsDownload) {
      console.log('[BulkData] No local bulk data found, downloading...');
      await downloadBulkData();
      
      // After successful download, load the files
      try {
        console.log('[BulkData] Loading freshly downloaded bulk data...');
        const cardsJson = await decompressFile(CARD_DATA_FILE);
        cardsDatabase = JSON.parse(cardsJson);
        
        if (INCLUDE_RULINGS && fs.existsSync(RULINGS_FILE)) {
          try {
            const rulingsJson = await decompressFile(RULINGS_FILE);
            rulingsDatabase = JSON.parse(rulingsJson);
          } catch (rulingsError) {
            console.error('[BulkData] Failed to load downloaded rulings:', rulingsError.message);
            rulingsDatabase = null;
          }
        } else {
          rulingsDatabase = null;
        }
        
        cardsLoaded = true;
        scheduleUpdateCheck();
        
        const rulingCount = rulingsDatabase ? rulingsDatabase.length : 0;
        console.log(`[BulkData] Bulk data ready! Loaded ${cardsDatabase.length} cards and ${rulingCount} rulings`);
        return cardsDatabase;
      } catch (error) {
        console.error('[BulkData] Failed to load freshly downloaded data:', error.message);
        throw error;
      }
    }
  } finally {
    resolveLoad();
    loadLock = null;
  }
}

/**
 * Decompress a gzipped file using streaming (non-blocking)
 * Note: While chunks are accumulated in memory, this approach is still better than
 * synchronous decompression because:
 * 1. It's non-blocking - doesn't block the event loop
 * 2. Chunks are processed asynchronously
 * 3. Better error handling with streams
 * 4. The entire JSON needs to be in memory anyway for JSON.parse()
 */
async function decompressFile(filePath) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let errorHandled = false; // Guard to ensure reject() is only called once
    const readStream = fs.createReadStream(filePath);
    const gunzip = zlib.createGunzip();
    
    const handleError = (error) => {
      if (!errorHandled) {
        errorHandled = true;
        readStream.destroy();
        gunzip.destroy();
        reject(error);
      }
    };
    
    gunzip.on('data', (chunk) => {
      chunks.push(chunk);
    });
    
    gunzip.on('end', () => {
      resolve(Buffer.concat(chunks).toString('utf8'));
    });
    
    gunzip.on('error', handleError);
    readStream.on('error', handleError);
    
    readStream.pipe(gunzip);
  });
}

/**
 * Get all cards (or undefined if not loaded)
 */
function getCardsDatabase() {
  return cardsDatabase;
}

/**
 * Check if bulk data is loaded
 */
function isLoaded() {
  return cardsLoaded;
}

// Known structured filter prefixes for query parsing
// These are all the filter operators supported by Scryfall query syntax
const STRUCTURED_PREFIXES = [
  's', 'set', 'r', 'rarity', 'c', 'color', 'id', 'identity', 't', 'type', 
  'is', 'o', 'oracle', 'mv', 'cmc', 'manavalue', 'pow', 'power', 
  'tou', 'toughness', 'loy', 'loyalty', 'k', 'keyword', 'a', 'artist', 
  'ft', 'flavor', 'name', 'produces', 'game', 'usd', 'eur', 'tix', 
  'f', 'format', 'legal', 'banned', 'restricted', 'layout', 'm', 'mana', 
  'has', 'block', 'fo', 'fulloracle', 'prints', 'stamp', 'frame', 
  'b', 'border', 'year', 'date'
];

// Build regex to match structured filters: matches "-?prefix[:=<>!]"
const prefixPattern = STRUCTURED_PREFIXES.join('|');
const STRUCTURED_FILTER_REGEX = new RegExp(`^-?(${prefixPattern})[:=<>!]`, 'i');

/**
 * Parse Scryfall query into filter object
 */
function parseQuery(query) {
  const colorAliases = {
    white: 'w',
    blue: 'u',
    black: 'b',
    red: 'r',
    green: 'g',
    colorless: 'c',
    multicolor: 'm',
    azorius: 'wu',
    dimir: 'ub',
    rakdos: 'br',
    gruul: 'rg',
    selesnya: 'gw',
    orzhov: 'wb',
    izzet: 'ur',
    golgari: 'bg',
    boros: 'rw',
    simic: 'gu',
    bant: 'wug',
    esper: 'wub',
    grixis: 'ubr',
    jund: 'brg',
    naya: 'rgw',
    abzan: 'wbg',
    jeskai: 'urw',
    sultai: 'ubg',
    mardu: 'rwb',
    temur: 'gur',
    chaos: 'ubrg',
    aggression: 'brgw',
    altruism: 'gwub',
    growth: 'rgwu',
    artifice: 'wubr'
  };

  function normalizeColorValue(raw) {
    if (!raw) return '';
    const value = raw.toLowerCase();
    if (colorAliases[value]) return colorAliases[value];
    return value;
  }

  const filters = {
    set: null,
    rarity: [],
    colors: [],
    colorsOp: null,
    colorsCount: null,
    colorsCountOp: null,
    isColorless: false,
    colorIdentity: [],
    colorIdentityOp: null,
    colorIdentityCount: null,
    colorIdentityCountOp: null,
    type: [],
    excludeType: [],
    isBooster: false,
    isTransform: false,
    excludeTransform: false,
    frame: null,
    excludeFrame: null,
    language: 'en',
    watermark: null,
    excludeWatermark: false,
    text: null,
    // Mana value / CMC
    mvEquals: null,
    mvLess: null,
    mvLessEqual: null,
    mvGreater: null,
    mvGreaterEqual: null,
    // Power / Toughness
    powerEquals: null,
    powerLess: null,
    powerLessEqual: null,
    powerGreater: null,
    powerGreaterEqual: null,
    toughnessEquals: null,
    toughnessLess: null,
    toughnessLessEqual: null,
    toughnessGreater: null,
    toughnessGreaterEqual: null,
    // Loyalty
    loyaltyEquals: null,
    loyaltyLess: null,
    loyaltyLessEqual: null,
    loyaltyGreater: null,
    loyaltyGreaterEqual: null,
    // Keywords
    keywords: [],
    excludeKeywords: [],
    // Additional is: filters
    isSpell: false,
    isPermanent: false,
    isHistoric: false,
    isCommander: false,
    isCompanion: false,
    isReprint: false,
    isNew: false,
    isPaper: false,
    isDigital: false,
    isPromo: false,
    isFunny: false,
    isFullArt: false,
    isExtendedArt: false,
    isVanilla: false,
    // Border
    border: null,
    // Year / Date
    year: null,
    yearGreater: null,
    yearLess: null,
    // Artist
    artist: null,
    // Flavor text
    flavor: null,
    // Name search
    nameContains: null,
    textTokens: [],
    // Produces mana
    produces: [],
    // Game
    game: null,
    // Price filters (USD, EUR, TIX)
    usdEquals: null,
    usdLess: null,
    usdLessEqual: null,
    usdGreater: null,
    usdGreaterEqual: null,
    eurEquals: null,
    eurLess: null,
    eurLessEqual: null,
    eurGreater: null,
    eurGreaterEqual: null,
    tixEquals: null,
    tixLess: null,
    tixLessEqual: null,
    tixGreater: null,
    tixGreaterEqual: null,
    // Format legality
    legal: null,
    banned: null,
    restricted: null,
    // Layout
    layout: null,
    excludeLayout: null,
    // Mana symbol search
    mana: null,
    // Feature detection (has:)
    hasWatermark: false,
    hasPartner: false,
    hasCompanion: false,
    // Block search
    block: null,
    // Full oracle text (including reminder text)
    fullOracle: null,
    // Number of printings
    printsEquals: null,
    printsLess: null,
    printsLessEqual: null,
    printsGreater: null,
    printsGreaterEqual: null,
    // Security stamp
    stamp: null,
    // Frame effects
    frameEffect: null,
    // Additional is: filters
    isReserved: false,
    isSpotlight: false,
    isFetchland: false,
    isShockland: false,
    isModal: false,
    // Manavalue odd/even
    mvOdd: false,
    mvEven: false
  };
  
  if (!query) return filters;
  
  // Split by + or space, but preserve parentheses groups and quoted strings
  // This handles both "id:rb+t:goblin" and "id:rb t:goblin" formats
  const parts = query.match(/\([^)]+\)|"[^"]+"|[^\s+]+/g) || [];
  
  console.log(`[BulkData] Parsing query: "${query}"`);
  console.log(`[BulkData] Split into ${parts.length} parts:`, parts);
  
  // Collect unstructured text (parts without operators) for name searching
  const unstructuredParts = [];
  
  parts.forEach(part => {
    part = part.trim();
    
    // Check if this part is a structured filter using the shared regex
    const isStructuredFilter = STRUCTURED_FILTER_REGEX.test(part);
    
    if (!isStructuredFilter && !part.startsWith('(') && !part.startsWith('"')) {
      // This is unstructured text (likely a card name)
      unstructuredParts.push(part);
    }
    
    // Set
    if (part.match(/^s[et]*:/i)) {
      const match = part.match(/s[et]*:(\w+)/i);
      if (match) {
        filters.set = match[1].toLowerCase();
      }
    }
    
    // Set with OR
    if (part.match(/^\(s:/i)) {
      const sets = part.match(/s:(\w+)/gi);
      if (sets) {
        filters.setOptions = sets.map(s => s.split(':')[1].toLowerCase());
      }
    }
    
    // Rarity
    if (part.match(/^r[:=<>]/i)) {
      if (part.includes('>=rare')) filters.rarity.push('rare', 'mythic');
      else if (part.includes('>common')) filters.rarity.push('uncommon', 'rare', 'mythic');
      else if (part.includes('<rare')) filters.rarity.push('common', 'uncommon');
      else if (part.includes(':mythic')) filters.rarity.push('mythic');
      else if (part.includes(':rare')) filters.rarity.push('rare');
      else if (part.includes(':uncommon')) filters.rarity.push('uncommon');
      else if (part.includes(':common')) filters.rarity.push('common');
    }
    
    // Color (c: / color:)
    if (part.match(/^(c|color)([:=<>!]{1,2})/i)) {
      const match = part.match(/^(c|color)(<=|>=|!=|=|<|:|>)(.+)$/i);
      if (match) {
        const op = match[2];
        const rawValue = match[3].trim();
        const value = normalizeColorValue(rawValue);

        if (/^\d+$/.test(value)) {
          filters.colorsCount = parseInt(value);
          filters.colorsCountOp = op === ':' ? '=' : op;
        } else if (value === 'c') {
          filters.isColorless = true;
          filters.colorsCount = 0;
          filters.colorsCountOp = op === ':' ? '=' : op;
        } else if (value === 'm') {
          filters.isMulticolor = true;
        } else {
          filters.colors = value.split('').filter(c => ['w', 'u', 'b', 'r', 'g'].includes(c));
          if (op === ':' || op === '>=' ) filters.colorsOp = 'contains';
          else if (op === '<=' ) filters.colorsOp = 'subset';
          else if (op === '=' ) filters.colorsOp = 'exact';
          else if (op === '<' ) filters.colorsOp = 'strict-subset';
          else if (op === '>' ) filters.colorsOp = 'strict-superset';
          else if (op === '!=' ) filters.colorsOp = 'not-equal';
        }
      }
    }
    
    // Color identity (id: / identity:)
    if (part.match(/^(id|identity)([:=<>!]{1,2})/i)) {
      const match = part.match(/^(id|identity)(<=|>=|!=|=|<|:|>)(.+)$/i);
      if (match) {
        const op = match[2];
        const rawValue = match[3].trim();
        const value = normalizeColorValue(rawValue);

        if (/^\d+$/.test(value)) {
          filters.colorIdentityCount = parseInt(value);
          filters.colorIdentityCountOp = op === ':' ? '=' : op;
        } else if (value === 'c') {
          filters.colorIdentity = [];
          filters.colorIdentityOp = 'exact';
          filters.colorIdentityCount = 0;
          filters.colorIdentityCountOp = op === ':' ? '=' : op;
        } else {
          filters.colorIdentity = value.split('').filter(c => ['w', 'u', 'b', 'r', 'g'].includes(c));
          if (op === ':' || op === '<=' ) filters.colorIdentityOp = 'subset';
          else if (op === '>=' ) filters.colorIdentityOp = 'contains';
          else if (op === '=' ) filters.colorIdentityOp = 'exact';
          else if (op === '<' ) filters.colorIdentityOp = 'strict-subset';
          else if (op === '>' ) filters.colorIdentityOp = 'strict-superset';
          else if (op === '!=' ) filters.colorIdentityOp = 'not-equal';
        }
      }
    }
    
    // Type - but SKIP if it's actually a malformed id:x pattern
    const typeMatch = part.match(/^(?:t|type):(\w+)/i);
    if (typeMatch && !part.match(/^t:id:/i)) {
      filters.type.push(typeMatch[1].toLowerCase());
    }
    
    const excludeTypeMatch = part.match(/^-(?:t|type):(\w+)/i);
    if (excludeTypeMatch) {
      filters.excludeType.push(excludeTypeMatch[1].toLowerCase());
    }
    
    // is:token / is:emblem should behave like type filters
    const extraTypeMatch = part.match(/^is:(\w+)/i);
    if (extraTypeMatch) {
      const extraType = extraTypeMatch[1].toLowerCase();
      if (EXTRA_CARD_TYPE_SET.has(extraType)) {
        filters.type.push(extraType);
      }
    }
    
    const excludeExtraTypeMatch = part.match(/^-is:(\w+)/i);
    if (excludeExtraTypeMatch) {
      const extraType = excludeExtraTypeMatch[1].toLowerCase();
      if (EXTRA_CARD_TYPE_SET.has(extraType)) {
        filters.excludeType.push(extraType);
      }
    }
    
    // Is booster
    if (part.match(/is:booster/i)) {
      filters.isBooster = true;
    }
    
    // Transform
    if (part.match(/^is:transform/i)) {
      filters.isTransform = true;
    }
    
    if (part.match(/^-is:transform/i)) {
      filters.excludeTransform = true;
    }
    
    // Frame
    if (part.match(/frame:(\d+)/i)) {
      const match = part.match(/frame:(\d+)/i);
      if (match) filters.frame = match[1];
    }
    
    if (part.match(/-frame:(\d+)/i)) {
      const match = part.match(/-frame:(\d+)/i);
      if (match) filters.excludeFrame = match[1];
    }
    
    // Language
    if (part.match(/lang:(\w+)/i)) {
      const match = part.match(/lang:(\w+)/i);
      if (match) filters.language = match[1].toLowerCase();
    }
    
    // Watermark
    if (part.match(/^wm:/i)) {
      const match = part.match(/wm:(\w+)/i);
      if (match) filters.watermark = match[1].toLowerCase();
    }
    
    if (part.match(/^-wm:/i)) {
      filters.excludeWatermark = true;
    }
    
    // Standard format
    if (part.match(/f:standard/i)) {
      filters.format = 'standard';
    }
    
    // Oracle text search
    if (part.match(/^o:/i)) {
      const match = part.match(/o:"([^"]+)"/i) || part.match(/o:(\w+)/i);
      if (match) filters.text = match[1].toLowerCase();
    }
    
    // Mana value / CMC (mv: or cmc:)
    if (part.match(/^(mv|cmc)[:=<>]/i)) {
      // Handle >= first (before >)
      if (part.match(/(mv|cmc)>=(\d+)/i)) {
        const match = part.match(/(mv|cmc)>=(\d+)/i);
        filters.mvGreaterEqual = parseInt(match[2]);
      } else if (part.match(/(mv|cmc)<=(\d+)/i)) {
        const match = part.match(/(mv|cmc)<=(\d+)/i);
        filters.mvLessEqual = parseInt(match[2]);
      } else if (part.match(/(mv|cmc)>(\d+)/i)) {
        const match = part.match(/(mv|cmc)>(\d+)/i);
        filters.mvGreater = parseInt(match[2]);
      } else if (part.match(/(mv|cmc)<(\d+)/i)) {
        const match = part.match(/(mv|cmc)<(\d+)/i);
        filters.mvLess = parseInt(match[2]);
      } else if (part.match(/(mv|cmc)[:=](\d+)/i)) {
        const match = part.match(/(mv|cmc)[:=](\d+)/i);
        filters.mvEquals = parseInt(match[2]);
      }
    }
    
    // Power
    if (part.match(/^pow(er)?[:=<>]/i)) {
      if (part.match(/pow(er)?>=?(\d+)/i)) {
        const match = part.match(/pow(er)?>=?(\d+)/i);
        if (part.includes('>=')) {
          filters.powerGreaterEqual = parseInt(match[2]);
        } else if (part.includes('>')) {
          filters.powerGreater = parseInt(match[2]);
        } else {
          filters.powerEquals = parseInt(match[2]);
        }
      } else if (part.match(/pow(er)?<=?(\d+)/i)) {
        const match = part.match(/pow(er)?<=?(\d+)/i);
        if (part.includes('<=')) {
          filters.powerLessEqual = parseInt(match[2]);
        } else {
          filters.powerLess = parseInt(match[2]);
        }
      }
    }
    
    // Toughness
    if (part.match(/^tou(ghness)?[:=<>]/i)) {
      if (part.match(/tou(ghness)?>=?(\d+)/i)) {
        const match = part.match(/tou(ghness)?>=?(\d+)/i);
        if (part.includes('>=')) {
          filters.toughnessGreaterEqual = parseInt(match[2]);
        } else if (part.includes('>')) {
          filters.toughnessGreater = parseInt(match[2]);
        } else {
          filters.toughnessEquals = parseInt(match[2]);
        }
      } else if (part.match(/tou(ghness)?<=?(\d+)/i)) {
        const match = part.match(/tou(ghness)?<=?(\d+)/i);
        if (part.includes('<=')) {
          filters.toughnessLessEqual = parseInt(match[2]);
        } else {
          filters.toughnessLess = parseInt(match[2]);
        }
      }
    }
    
    // Loyalty
    if (part.match(/^loy(alty)?[:=<>]/i)) {
      if (part.match(/loy(alty)?>=?(\d+)/i)) {
        const match = part.match(/loy(alty)?>=?(\d+)/i);
        if (part.includes('>=')) {
          filters.loyaltyGreaterEqual = parseInt(match[2]);
        } else if (part.includes('>')) {
          filters.loyaltyGreater = parseInt(match[2]);
        } else {
          filters.loyaltyEquals = parseInt(match[2]);
        }
      } else if (part.match(/loy(alty)?<=?(\d+)/i)) {
        const match = part.match(/loy(alty)?<=?(\d+)/i);
        if (part.includes('<=')) {
          filters.loyaltyLessEqual = parseInt(match[2]);
        } else {
          filters.loyaltyLess = parseInt(match[2]);
        }
      }
    }
    
    // Keywords
    if (part.match(/^keyword:/i)) {
      const match = part.match(/keyword:(\w+)/i);
      if (match) filters.keywords.push(match[1].toLowerCase());
    }
    
    if (part.match(/^-keyword:/i)) {
      const match = part.match(/-keyword:(\w+)/i);
      if (match) filters.excludeKeywords.push(match[1].toLowerCase());
    }
    
    // Additional is: filters
    if (part.match(/^is:spell$/i)) filters.isSpell = true;
    if (part.match(/^is:permanent$/i)) filters.isPermanent = true;
    if (part.match(/^is:historic$/i)) filters.isHistoric = true;
    if (part.match(/^is:commander$/i)) filters.isCommander = true;
    if (part.match(/^is:companion$/i)) filters.isCompanion = true;
    if (part.match(/^is:reprint$/i)) filters.isReprint = true;
    if (part.match(/^is:new$/i)) filters.isNew = true;
    if (part.match(/^is:paper$/i)) filters.isPaper = true;
    if (part.match(/^is:digital$/i)) filters.isDigital = true;
    if (part.match(/^is:promo$/i)) filters.isPromo = true;
    if (part.match(/^is:funny$/i)) filters.isFunny = true;
    if (part.match(/^is:full-?art$/i)) filters.isFullArt = true;
    if (part.match(/^is:extended-?art$/i)) filters.isExtendedArt = true;
    if (part.match(/^is:vanilla$/i)) filters.isVanilla = true;
    
    // Border
    if (part.match(/^border:/i)) {
      const match = part.match(/border:(\w+)/i);
      if (match) filters.border = match[1].toLowerCase();
    }
    
    // Year
    if (part.match(/^year[:=<>]/i)) {
      if (part.match(/year>=?(\d{4})/i)) {
        const match = part.match(/year>=?(\d{4})/i);
        if (part.includes('>')) {
          filters.yearGreater = parseInt(match[1]);
        } else {
          filters.year = parseInt(match[1]);
        }
      } else if (part.match(/year<(\d{4})/i)) {
        const match = part.match(/year<(\d{4})/i);
        filters.yearLess = parseInt(match[1]);
      }
    }
    
    // Artist
    if (part.match(/^a(rtist)?:/i)) {
      const match = part.match(/a(rtist)?:"([^"]+)"/i) || part.match(/a(rtist)?:(\w+)/i);
      if (match) filters.artist = (match[2] || match[3]).toLowerCase();
    }
    
    // Flavor text
    if (part.match(/^ft:/i)) {
      const match = part.match(/ft:"([^"]+)"/i) || part.match(/ft:(\w+)/i);
      if (match) filters.flavor = match[1].toLowerCase();
    }
    
    // Name contains
    if (part.match(/^name:/i)) {
      const match = part.match(/name:"([^"]+)"/i) || part.match(/name:(\w+)/i);
      if (match) {
        const normalizedName = normalizeCardName(match[1]).toLowerCase();
        if (normalizedName) {
          filters.nameContains = normalizedName;
          filters.textTokens = normalizedName.split(' ').filter(Boolean);
        }
      }
    }
    
    // Produces mana
    if (part.match(/^produces:/i)) {
      const match = part.match(/produces:([wubrg]+)/i);
      if (match) {
        const colors = match[1].toLowerCase().split('');
        filters.produces = colors.filter(c => ['w', 'u', 'b', 'r', 'g'].includes(c));
      }
    }
    
    // Game
    if (part.match(/^game:/i)) {
      const match = part.match(/game:(\w+)/i);
      if (match) filters.game = match[1].toLowerCase();
    }
    
    // Price filters helper function to avoid duplication
    const parsePriceFilter = (part, currency, filters) => {
      const prefix = currency.toLowerCase();
      let match;
      
      // Handle >= first (before >)
      if ((match = part.match(new RegExp(`^${prefix}>=([0-9.]+)`, 'i')))) {
        filters[`${currency}GreaterEqual`] = parseFloat(match[1]);
      } else if ((match = part.match(new RegExp(`^${prefix}<=([0-9.]+)`, 'i')))) {
        filters[`${currency}LessEqual`] = parseFloat(match[1]);
      } else if ((match = part.match(new RegExp(`^${prefix}>([0-9.]+)`, 'i')))) {
        filters[`${currency}Greater`] = parseFloat(match[1]);
      } else if ((match = part.match(new RegExp(`^${prefix}<([0-9.]+)`, 'i')))) {
        filters[`${currency}Less`] = parseFloat(match[1]);
      } else if ((match = part.match(new RegExp(`^${prefix}[:=]([0-9.]+)`, 'i')))) {
        filters[`${currency}Equals`] = parseFloat(match[1]);
      }
    };
    
    // USD price filter
    if (part.match(/^usd[:=<>]/i)) {
      parsePriceFilter(part, 'usd', filters);
    }
    
    // EUR price filter
    if (part.match(/^eur[:=<>]/i)) {
      parsePriceFilter(part, 'eur', filters);
    }
    
    // TIX price filter (MTGO tickets)
    if (part.match(/^tix[:=<>]/i)) {
      parsePriceFilter(part, 'tix', filters);
    }
    
    // Format legality filters
    if (part.match(/^legal:/i)) {
      const match = part.match(/legal:(\w+)/i);
      if (match) filters.legal = match[1].toLowerCase();
    }
    
    if (part.match(/^banned:/i)) {
      const match = part.match(/banned:(\w+)/i);
      if (match) filters.banned = match[1].toLowerCase();
    }
    
    if (part.match(/^restricted:/i)) {
      const match = part.match(/restricted:(\w+)/i);
      if (match) filters.restricted = match[1].toLowerCase();
    }
    
    // Layout filter
    if (part.match(/^layout:/i)) {
      const match = part.match(/layout:(\w+)/i);
      if (match) filters.layout = match[1].toLowerCase();
    }
    
    if (part.match(/^-layout:/i)) {
      const match = part.match(/-layout:(\w+)/i);
      if (match) filters.excludeLayout = match[1].toLowerCase();
    }
    
    // Mana symbol search (m: / mana:)
    if (part.match(/^(m|mana):/i)) {
      const match = part.match(/^(m|mana):(.+)$/i);
      if (match) filters.mana = match[2].toLowerCase();
    }
    
    // Feature detection (has:)
    if (part.match(/^has:watermark$/i)) filters.hasWatermark = true;
    if (part.match(/^has:partner$/i)) filters.hasPartner = true;
    if (part.match(/^has:companion$/i)) filters.hasCompanion = true;
    
    // Block search
    if (part.match(/^block:/i)) {
      const match = part.match(/block:"([^"]+)"/i) || part.match(/block:(\w+)/i);
      if (match) filters.block = match[1].toLowerCase();
    }
    
    // Full oracle text (fo: / fulloracle:)
    if (part.match(/^(fo|fulloracle):/i)) {
      const match = part.match(/^(fo|fulloracle):"([^"]+)"/i) || part.match(/^(fo|fulloracle):(\w+)/i);
      if (match) filters.fullOracle = match[2].toLowerCase();
    }
    
    // Number of printings (prints:)
    if (part.match(/^prints[:=<>]/i)) {
      let match;
      if ((match = part.match(/^prints>=(\d+)/i))) {
        filters.printsGreaterEqual = parseInt(match[1]);
      } else if ((match = part.match(/^prints<=(\d+)/i))) {
        filters.printsLessEqual = parseInt(match[1]);
      } else if ((match = part.match(/^prints>(\d+)/i))) {
        filters.printsGreater = parseInt(match[1]);
      } else if ((match = part.match(/^prints<(\d+)/i))) {
        filters.printsLess = parseInt(match[1]);
      } else if ((match = part.match(/^prints[:=](\d+)/i))) {
        filters.printsEquals = parseInt(match[1]);
      }
    }
    
    // Security stamp
    if (part.match(/^stamp:/i)) {
      const match = part.match(/stamp:(\w+)/i);
      if (match) filters.stamp = match[1].toLowerCase();
    }
    
    // Frame effects
    if (part.match(/^frameeffect:/i)) {
      const match = part.match(/frameeffect:(\w+)/i);
      if (match) filters.frameEffect = match[1].toLowerCase();
    }
    
    // Additional is: filters
    if (part.match(/^is:reserved$/i)) filters.isReserved = true;
    if (part.match(/^is:spotlight$/i)) filters.isSpotlight = true;
    if (part.match(/^is:fetchland$/i)) filters.isFetchland = true;
    if (part.match(/^is:shockland$/i)) filters.isShockland = true;
    if (part.match(/^is:modal$/i)) filters.isModal = true;
    
    // Manavalue odd/even
    if (part.match(/^(mv|manavalue|cmc):odd$/i)) filters.mvOdd = true;
    if (part.match(/^(mv|manavalue|cmc):even$/i)) filters.mvEven = true;
  });
  
  // Process unstructured parts (card names) if any were collected
  if (unstructuredParts.length > 0) {
    const nameQuery = unstructuredParts.join(' ');
    const normalizedName = normalizeCardName(nameQuery).toLowerCase();
    if (normalizedName) {
      filters.nameContains = normalizedName;
      filters.textTokens = normalizedName.split(' ').filter(Boolean);
      console.log(`[BulkData] Extracted name filter: "${normalizedName}" from unstructured parts:`, unstructuredParts);
    }
  }
  
  console.log(`[BulkData] Parsed filters:`, JSON.stringify({
    colorIdentity: filters.colorIdentity,
    type: filters.type,
    colors: filters.colors,
    mvEquals: filters.mvEquals,
    powerGreaterEqual: filters.powerGreaterEqual,
    keywords: filters.keywords,
    nameContains: filters.nameContains
  }, null, 2));
  
  return filters;
}

/**
 * Filter cards based on query
 */
function filterCards(cards, filters) {
  return cards.filter(card => {
    // Skip non-English unless specifically requested
    if (card.lang !== filters.language) return false;
    
    // Set filter
    if (filters.set && card.set !== filters.set) return false;
    
    // Set options (OR)
    if (filters.setOptions && !filters.setOptions.includes(card.set)) return false;
    
    // Booster filter
    if (filters.isBooster && !card.booster) return false;
    
    // Rarity filter
    if (filters.rarity.length > 0 && !filters.rarity.includes(card.rarity)) return false;
    
    // Color filter
    if (filters.colorsCount !== null) {
      const cardColors = card.colors || [];
      const count = cardColors.length;
      const op = filters.colorsCountOp || '=';
      if (op === '=' && count !== filters.colorsCount) return false;
      if (op === '!=' && count === filters.colorsCount) return false;
      if (op === '>' && count <= filters.colorsCount) return false;
      if (op === '>=' && count < filters.colorsCount) return false;
      if (op === '<' && count >= filters.colorsCount) return false;
      if (op === '<=' && count > filters.colorsCount) return false;
    } else if (filters.colors.length > 0) {
      const cardColors = (card.colors || []).map(c => c.toUpperCase());
      const queryColors = filters.colors.map(c => c.toUpperCase());
      const hasAll = queryColors.every(c => cardColors.includes(c));
      const isSubset = cardColors.every(c => queryColors.includes(c));
      const isExact = hasAll && isSubset;
      const op = filters.colorsOp || 'contains';

      if (op === 'contains' && !hasAll) return false;
      if (op === 'subset' && !isSubset) return false;
      if (op === 'exact' && !isExact) return false;
      if (op === 'strict-subset' && (!isSubset || isExact)) return false;
      if (op === 'strict-superset' && (!hasAll || isExact)) return false;
      if (op === 'not-equal' && isExact) return false;
    }
    
    // Multicolor filter
    if (filters.isMulticolor) {
      const cardColors = card.colors || [];
      if (cardColors.length < 2) return false;
    }
    
    // Colorless filter (only when explicitly requested)
    if (filters.isColorless) {
      const cardColors = card.colors || [];
      if (cardColors.length > 0) return false;
    }
    
    // Color identity filter
    if (filters.colorIdentityCount !== null) {
      const cardIdentity = card.color_identity || [];
      const count = cardIdentity.length;
      const op = filters.colorIdentityCountOp || '=';
      if (op === '=' && count !== filters.colorIdentityCount) return false;
      if (op === '!=' && count === filters.colorIdentityCount) return false;
      if (op === '>' && count <= filters.colorIdentityCount) return false;
      if (op === '>=' && count < filters.colorIdentityCount) return false;
      if (op === '<' && count >= filters.colorIdentityCount) return false;
      if (op === '<=' && count > filters.colorIdentityCount) return false;
    } else if (filters.colorIdentity.length > 0) {
      const cardIdentity = (card.color_identity || []).map(c => c.toUpperCase());
      const queryIdentity = filters.colorIdentity.map(c => c.toUpperCase());
      const hasAll = queryIdentity.every(c => cardIdentity.includes(c));
      const isSubset = cardIdentity.every(c => queryIdentity.includes(c));
      const isExact = hasAll && isSubset;
      const op = filters.colorIdentityOp || 'subset';

      if (op === 'contains' && !hasAll) return false;
      if (op === 'subset' && !isSubset) return false;
      if (op === 'exact' && !isExact) return false;
      if (op === 'strict-subset' && (!isSubset || isExact)) return false;
      if (op === 'strict-superset' && (!hasAll || isExact)) return false;
      if (op === 'not-equal' && isExact) return false;
    }
    
    // Type filter
    if (filters.type.length > 0) {
      const typeLine = (card.type_line || '').toLowerCase();
      const hasAllTypes = filters.type.every(t => typeLine.includes(t));
      if (!hasAllTypes) return false;
    }
    
    // Exclude type filter
    if (filters.excludeType.length > 0) {
      const typeLine = (card.type_line || '').toLowerCase();
      const hasExcludedType = filters.excludeType.some(t => typeLine.includes(t));
      if (hasExcludedType) return false;
    }
    
    // Transform filter
    if (filters.isTransform) {
      const layout = card.layout || '';
      if (!['transform', 'modal_dfc', 'reversible_card'].includes(layout)) return false;
    }
    
    if (filters.excludeTransform) {
      const layout = card.layout || '';
      if (['transform', 'modal_dfc', 'reversible_card'].includes(layout)) return false;
    }
    
    // Frame filter
    if (filters.frame && card.frame !== filters.frame) return false;
    if (filters.excludeFrame && card.frame === filters.excludeFrame) return false;
    
    // Watermark filter
    if (filters.watermark && card.watermark !== filters.watermark) return false;
    if (filters.excludeWatermark && card.watermark) return false;
    
    // Format filter (standard)
    if (filters.format === 'standard') {
      if (!card.legalities || card.legalities.standard !== 'legal') return false;
    }
    
    // Oracle text search
    if (filters.text) {
      const oracleText = (card.oracle_text || '').toLowerCase();
      if (!oracleText.includes(filters.text)) return false;
    }
    
    // Mana value / CMC filters
    if (filters.mvEquals !== null && card.cmc !== filters.mvEquals) return false;
    if (filters.mvGreater !== null && card.cmc <= filters.mvGreater) return false;
    if (filters.mvGreaterEqual !== null && card.cmc < filters.mvGreaterEqual) return false;
    if (filters.mvLess !== null && card.cmc >= filters.mvLess) return false;
    if (filters.mvLessEqual !== null && card.cmc > filters.mvLessEqual) return false;
    
    // Power filters
    if (filters.powerEquals !== null || filters.powerGreater !== null || filters.powerGreaterEqual !== null || filters.powerLess !== null || filters.powerLessEqual !== null) {
      const power = card.power;
      if (!power || power === '*') return false;
      const powerNum = parseInt(power);
      if (isNaN(powerNum)) return false;
      if (filters.powerEquals !== null && powerNum !== filters.powerEquals) return false;
      if (filters.powerGreater !== null && powerNum <= filters.powerGreater) return false;
      if (filters.powerGreaterEqual !== null && powerNum < filters.powerGreaterEqual) return false;
      if (filters.powerLess !== null && powerNum >= filters.powerLess) return false;
      if (filters.powerLessEqual !== null && powerNum > filters.powerLessEqual) return false;
    }
    
    // Toughness filters
    if (filters.toughnessEquals !== null || filters.toughnessGreater !== null || filters.toughnessGreaterEqual !== null || filters.toughnessLess !== null || filters.toughnessLessEqual !== null) {
      const toughness = card.toughness;
      if (!toughness || toughness === '*') return false;
      const toughnessNum = parseInt(toughness);
      if (isNaN(toughnessNum)) return false;
      if (filters.toughnessEquals !== null && toughnessNum !== filters.toughnessEquals) return false;
      if (filters.toughnessGreater !== null && toughnessNum <= filters.toughnessGreater) return false;
      if (filters.toughnessGreaterEqual !== null && toughnessNum < filters.toughnessGreaterEqual) return false;
      if (filters.toughnessLess !== null && toughnessNum >= filters.toughnessLess) return false;
      if (filters.toughnessLessEqual !== null && toughnessNum > filters.toughnessLessEqual) return false;
    }
    
    // Loyalty filters
    if (filters.loyaltyEquals !== null || filters.loyaltyGreater !== null || filters.loyaltyGreaterEqual !== null || filters.loyaltyLess !== null || filters.loyaltyLessEqual !== null) {
      const loyalty = card.loyalty;
      if (!loyalty) return false;
      const loyaltyNum = parseInt(loyalty);
      if (isNaN(loyaltyNum)) return false;
      if (filters.loyaltyEquals !== null && loyaltyNum !== filters.loyaltyEquals) return false;
      if (filters.loyaltyGreater !== null && loyaltyNum <= filters.loyaltyGreater) return false;
      if (filters.loyaltyGreaterEqual !== null && loyaltyNum < filters.loyaltyGreaterEqual) return false;
      if (filters.loyaltyLess !== null && loyaltyNum >= filters.loyaltyLess) return false;
      if (filters.loyaltyLessEqual !== null && loyaltyNum > filters.loyaltyLessEqual) return false;
    }
    
    // Keyword filters
    if (filters.keywords.length > 0) {
      const cardKeywords = (card.keywords || []).map(k => k.toLowerCase());
      const hasAllKeywords = filters.keywords.every(k => cardKeywords.includes(k));
      if (!hasAllKeywords) return false;
    }
    
    if (filters.excludeKeywords.length > 0) {
      const cardKeywords = (card.keywords || []).map(k => k.toLowerCase());
      const hasExcludedKeyword = filters.excludeKeywords.some(k => cardKeywords.includes(k));
      if (hasExcludedKeyword) return false;
    }
    
    // is:spell - instants and sorceries
    if (filters.isSpell) {
      const typeLine = (card.type_line || '').toLowerCase();
      if (!typeLine.includes('instant') && !typeLine.includes('sorcery')) return false;
    }
    
    // is:permanent - not instants or sorceries
    if (filters.isPermanent) {
      const typeLine = (card.type_line || '').toLowerCase();
      if (typeLine.includes('instant') || typeLine.includes('sorcery')) return false;
    }
    
    // is:historic - legendary, artifact, or saga
    if (filters.isHistoric) {
      const typeLine = (card.type_line || '').toLowerCase();
      if (!typeLine.includes('legendary') && !typeLine.includes('artifact') && !typeLine.includes('saga')) return false;
    }
    
    // is:commander - legendary creature or planeswalker with "can be your commander"
    if (filters.isCommander) {
      const typeLine = (card.type_line || '').toLowerCase();
      const oracleText = (card.oracle_text || '').toLowerCase();
      const isLegendaryCreature = typeLine.includes('legendary') && typeLine.includes('creature');
      const canBeCommander = oracleText.includes('can be your commander');
      if (!isLegendaryCreature && !canBeCommander) return false;
    }
    
    // is:companion - has companion keyword
    if (filters.isCompanion) {
      const cardKeywords = (card.keywords || []).map(k => k.toLowerCase());
      if (!cardKeywords.includes('companion')) return false;
    }
    
    // is:reprint - printed in multiple sets
    if (filters.isReprint) {
      if (!card.reprint) return false;
    }
    
    // is:new - first printing
    if (filters.isNew) {
      if (card.reprint) return false;
    }
    
    // is:paper - available in paper
    if (filters.isPaper) {
      const games = card.games || [];
      if (!games.includes('paper')) return false;
    }
    
    // is:digital - digital only
    if (filters.isDigital) {
      if (!card.digital) return false;
    }
    
    // is:promo - promotional printing
    if (filters.isPromo) {
      if (!card.promo) return false;
    }
    
    // is:funny - un-sets or acorn stamped
    if (filters.isFunny) {
      const set = card.set || '';
      const border = card.border_color || '';
      if (!set.match(/^(ust|und|unh|unf|cmb1|cmb2)$/) && border !== 'silver') return false;
    }
    
    // is:full-art
    if (filters.isFullArt) {
      if (!card.full_art) return false;
    }
    
    // is:extended-art
    if (filters.isExtendedArt) {
      const frameEffects = card.frame_effects || [];
      if (!frameEffects.includes('extendedart')) return false;
    }
    
    // is:vanilla - no rules text
    if (filters.isVanilla) {
      const oracleText = card.oracle_text || '';
      if (oracleText.trim().length > 0) return false;
    }
    
    // Border filter
    if (filters.border) {
      if (card.border_color !== filters.border) return false;
    }
    
    // Year filters
    if (filters.year !== null || filters.yearGreater !== null || filters.yearLess !== null) {
      const releaseDate = card.released_at;
      if (!releaseDate) return false;
      const year = parseInt(releaseDate.split('-')[0]);
      if (filters.year !== null && year !== filters.year) return false;
      if (filters.yearGreater !== null && year <= filters.yearGreater) return false;
      if (filters.yearLess !== null && year >= filters.yearLess) return false;
    }
    
    // Artist filter
    if (filters.artist) {
      const artist = (card.artist || '').toLowerCase();
      if (!artist.includes(filters.artist)) return false;
    }
    
    // Flavor text filter
    if (filters.flavor) {
      const flavorText = (card.flavor_text || '').toLowerCase();
      if (!flavorText.includes(filters.flavor)) return false;
    }
    
    // Name contains filter
    if (filters.nameContains) {
      const normalizedName = normalizeCardName(card.name || '').toLowerCase();
      if (!normalizedName.includes(filters.nameContains)) return false;
      if (filters.textTokens.length > 0) {
        const nameTokens = normalizedName.split(' ').filter(Boolean);
        const hasAllTokens = filters.textTokens.every(token => nameTokens.includes(token));
        if (!hasAllTokens) return false;
      }
    }
    
    // Produces mana filter
    if (filters.produces.length > 0) {
      const producedMana = card.produced_mana || [];
      const hasAllColors = filters.produces.every(c => producedMana.includes(c.toUpperCase()));
      if (!hasAllColors) return false;
    }
    
    // Game filter
    if (filters.game) {
      const games = card.games || [];
      if (!games.includes(filters.game)) return false;
    }
    
    // USD price filters
    if (filters.usdEquals !== null || filters.usdGreater !== null || filters.usdGreaterEqual !== null || filters.usdLess !== null || filters.usdLessEqual !== null) {
      const usdPrice = card.prices?.usd;
      // If no USD price is available, exclude the card from results
      if (!usdPrice) return false;
      const usdNum = parseFloat(usdPrice);
      if (isNaN(usdNum)) return false;
      if (filters.usdEquals !== null && usdNum !== filters.usdEquals) return false;
      if (filters.usdGreater !== null && usdNum <= filters.usdGreater) return false;
      if (filters.usdGreaterEqual !== null && usdNum < filters.usdGreaterEqual) return false;
      if (filters.usdLess !== null && usdNum >= filters.usdLess) return false;
      if (filters.usdLessEqual !== null && usdNum > filters.usdLessEqual) return false;
    }
    
    // EUR price filters
    if (filters.eurEquals !== null || filters.eurGreater !== null || filters.eurGreaterEqual !== null || filters.eurLess !== null || filters.eurLessEqual !== null) {
      const eurPrice = card.prices?.eur;
      if (!eurPrice) return false;
      const eurNum = parseFloat(eurPrice);
      if (isNaN(eurNum)) return false;
      if (filters.eurEquals !== null && eurNum !== filters.eurEquals) return false;
      if (filters.eurGreater !== null && eurNum <= filters.eurGreater) return false;
      if (filters.eurGreaterEqual !== null && eurNum < filters.eurGreaterEqual) return false;
      if (filters.eurLess !== null && eurNum >= filters.eurLess) return false;
      if (filters.eurLessEqual !== null && eurNum > filters.eurLessEqual) return false;
    }
    
    // TIX price filters (MTGO tickets)
    if (filters.tixEquals !== null || filters.tixGreater !== null || filters.tixGreaterEqual !== null || filters.tixLess !== null || filters.tixLessEqual !== null) {
      const tixPrice = card.prices?.tix;
      if (!tixPrice) return false;
      const tixNum = parseFloat(tixPrice);
      if (isNaN(tixNum)) return false;
      if (filters.tixEquals !== null && tixNum !== filters.tixEquals) return false;
      if (filters.tixGreater !== null && tixNum <= filters.tixGreater) return false;
      if (filters.tixGreaterEqual !== null && tixNum < filters.tixGreaterEqual) return false;
      if (filters.tixLess !== null && tixNum >= filters.tixLess) return false;
      if (filters.tixLessEqual !== null && tixNum > filters.tixLessEqual) return false;
    }
    
    // Format legality filters
    if (filters.legal) {
      const legalities = card.legalities || {};
      if (legalities[filters.legal] !== 'legal') return false;
    }
    
    if (filters.banned) {
      const legalities = card.legalities || {};
      if (legalities[filters.banned] !== 'banned') return false;
    }
    
    if (filters.restricted) {
      const legalities = card.legalities || {};
      if (legalities[filters.restricted] !== 'restricted') return false;
    }
    
    // Layout filter
    if (filters.layout && card.layout !== filters.layout) return false;
    if (filters.excludeLayout && card.layout === filters.excludeLayout) return false;
    
    // Mana symbol search
    if (filters.mana) {
      const manaCost = (card.mana_cost || '').toLowerCase();
      if (!manaCost.includes(filters.mana)) return false;
    }
    
    // Feature detection (has:)
    if (filters.hasWatermark) {
      if (!card.watermark) return false;
    }
    
    if (filters.hasPartner) {
      const oracleText = (card.oracle_text || '').toLowerCase();
      const keywords = (card.keywords || []).map(k => k.toLowerCase());
      if (!keywords.includes('partner') && !oracleText.includes('partner')) return false;
    }
    
    if (filters.hasCompanion) {
      const keywords = (card.keywords || []).map(k => k.toLowerCase());
      if (!keywords.includes('companion')) return false;
    }
    
    // Block search
    if (filters.block) {
      // Note: Scryfall doesn't include block data in oracle_cards, so we'll check set_name
      const setName = (card.set_name || '').toLowerCase();
      if (!setName.includes(filters.block)) return false;
    }
    
    // Full oracle text (including reminder text)
    // Note: In Scryfall, fulloracle searches oracle text including reminder text, not flavor text
    if (filters.fullOracle) {
      const oracleText = (card.oracle_text || '').toLowerCase();
      if (!oracleText.includes(filters.fullOracle)) return false;
    }
    
    // Number of printings - requires counting unique sets per oracle_id
    // Note: This is a simplified check - in reality, we'd need to count all printings
    // For now, we'll just check if it's a reprint as a basic heuristic
    const hasPrintsFilter = [filters.printsEquals, filters.printsGreater, filters.printsGreaterEqual, 
                             filters.printsLess, filters.printsLessEqual].some(v => v !== null);
    if (hasPrintsFilter) {
      // This is a limitation - bulk data doesn't provide printing count
      // We can only approximate: reprints have prints > 1, new cards have prints = 1
      const isReprint = card.reprint || false;
      const estimatedPrints = isReprint ? 2 : 1; // Very rough estimate
      
      if (filters.printsEquals !== null && estimatedPrints !== filters.printsEquals) return false;
      if (filters.printsGreater !== null && estimatedPrints <= filters.printsGreater) return false;
      if (filters.printsGreaterEqual !== null && estimatedPrints < filters.printsGreaterEqual) return false;
      if (filters.printsLess !== null && estimatedPrints >= filters.printsLess) return false;
      if (filters.printsLessEqual !== null && estimatedPrints > filters.printsLessEqual) return false;
    }
    
    // Security stamp
    if (filters.stamp) {
      const securityStamp = card.security_stamp || '';
      if (securityStamp !== filters.stamp) return false;
    }
    
    // Frame effects
    if (filters.frameEffect) {
      const frameEffects = card.frame_effects || [];
      if (!frameEffects.includes(filters.frameEffect)) return false;
    }
    
    // is:reserved - reserved list cards
    if (filters.isReserved) {
      if (!card.reserved) return false;
    }
    
    // is:spotlight - story spotlight cards
    if (filters.isSpotlight) {
      if (!card.story_spotlight) return false;
    }
    
    // is:fetchland - fetch lands
    if (filters.isFetchland) {
      const oracleText = (card.oracle_text || '').toLowerCase();
      const name = (card.name || '').toLowerCase();
      const typeLine = (card.type_line || '').toLowerCase();
      // Fetchlands are lands that can search for other lands
      const isFetch = typeLine.includes('land') && 
                      (oracleText.includes('search your library for a') || 
                       name.includes('fetch') ||
                       KNOWN_FETCHLANDS.some(f => name.includes(f)));
      if (!isFetch) return false;
    }
    
    // is:shockland - shock lands
    if (filters.isShockland) {
      const oracleText = (card.oracle_text || '').toLowerCase();
      const name = (card.name || '').toLowerCase();
      const typeLine = (card.type_line || '').toLowerCase();
      // Shocklands have two basic land types and enter tapped unless 2 life is paid
      const isShock = typeLine.includes('land') && 
                      (oracleText.includes('2 life') || oracleText.includes('pay 2 life') || 
                       KNOWN_SHOCKLANDS.some(s => name.includes(s)));
      if (!isShock) return false;
    }
    
    // is:modal - modal cards
    if (filters.isModal) {
      const oracleText = (card.oracle_text || '').toLowerCase();
      const layout = card.layout || '';
      // Modal cards have "choose one" or similar text, or modal_dfc layout
      const isModal = layout === 'modal_dfc' || 
                      oracleText.includes('choose one') || 
                      oracleText.includes('choose two') || 
                      oracleText.includes('choose three') ||
                      oracleText.includes('choose x');
      if (!isModal) return false;
    }
    
    // Manavalue odd/even
    if (filters.mvOdd) {
      const cmc = card.cmc || 0;
      if (cmc % 2 === 0) return false;
    }
    
    if (filters.mvEven) {
      const cmc = card.cmc || 0;
      if (cmc % 2 !== 0) return false;
    }
    
    return true;
  });
}

/**
 * Get random card matching query
 * Returns null if bulk data not loaded (signals API fallback required)
 */
async function getRandomCard(query = '', suppressLog = false) {
  if (!cardsLoaded || !cardsDatabase) {
    if (!suppressLog) {
      console.log(`[BulkData] getRandomCard: data not loaded, returning null`);
    }
    return null;  // Signal API fallback required
  }
  
  const filters = parseQuery(query);
  let matchingCards = filterCards(cardsDatabase, filters);
  if (!shouldIncludeExtraTypes(filters, query)) {
    matchingCards = matchingCards.filter(card => !isExtraCard(card));
  }
  
  // Exclude non-playable cards (test cards, acorn stamps, tokens, emblems, art cards, etc.) from random results
  matchingCards = matchingCards.filter(card => !isNonPlayableCard(card));
  matchingCards = dedupeCardsByOracleId(matchingCards);
  
  // Log filter results for debugging (unless suppressed)
  if (query && !suppressLog) {
    console.log(`[BulkData] Query: "${query}" matched ${matchingCards.length} cards`);
    if (matchingCards.length > 0 && matchingCards.length <= 5) {
      console.log(`[BulkData] Sample matches:`, matchingCards.map(c => c.name).join(', '));
    }
  }
  
  if (matchingCards.length === 0) {
    // Check for malformed operators (e.g., "mv=0=" instead of "mv>=0" or "mv=0")
    if (query && /\b(id|c|t|type|s|set|r|rarity|cmc|mv|pow|power|tou|toughness)=[<>=]/.test(query)) {
      throw new Error(`No cards found. Malformed operator in "${query}". Use single operators like "mv=0" or "mv>=0", not "mv=0="`);
    }
    if (!suppressLog) {
      console.log(`[BulkData] Query "${query}" matched 0 cards, returning null for API fallback`);
    }
    return null;  // Signal API fallback required
  }
  
  const randomIndex = Math.floor(Math.random() * matchingCards.length);
  return matchingCards[randomIndex];
}

/**
 * Search for cards matching query
 * Returns null if bulk data not loaded (signals API fallback required)
 */
async function searchCards(query = '', limit = 10, _suppressLog = false) {
  if (!cardsLoaded || !cardsDatabase) {
    return null;  // Signal API fallback required
  }
  
  const filters = parseQuery(query);
  let matchingCards = filterCards(cardsDatabase, filters);
  if (filters.type.includes('token')) {
    matchingCards = matchingCards.filter(card => (card.layout || '').toLowerCase() !== 'double_faced_token');
  }
  
  if (matchingCards.length === 0) {
    return null;  // Signal API fallback required
  }
  
  return matchingCards.slice(0, limit);
}

/**
 * Get card by exact name
 */
function getCardByName(name, set = null) {
  if (!cardsLoaded || !cardsDatabase) {
    throw new Error('Bulk data not loaded');
  }
  
  const nameLower = name.toLowerCase();
  const setCode = set ? set.toLowerCase() : null;
  const normalizedName = normalizeCardName(name).toLowerCase();
  return cardsDatabase.find(card => {
    const cardName = card.name || '';
    if (cardName.toLowerCase() === nameLower) {
      return !setCode || card.set === setCode;
    }
    return (!setCode || card.set === setCode) &&
      normalizeCardName(cardName).toLowerCase() === normalizedName;
  });
}

/**
 * Get card by ID
 */
function getCardById(id) {
  if (!cardsLoaded || !cardsDatabase) {
    throw new Error('Bulk data not loaded');
  }
  
  return cardsDatabase.find(card => card.id === id);
}

/**
 * Get card by set code and collector number
 */
function getCardBySetNumber(set, number, lang = 'en') {
  if (!cardsLoaded || !cardsDatabase) {
    throw new Error('Bulk data not loaded');
  }
  
  const setCode = set.toLowerCase();
  const collectorNumber = String(number);
  const collectorNumberLower = collectorNumber.toLowerCase();
  const langCode = (lang || 'en').toLowerCase();
  
  return cardsDatabase.find(card =>
    card.set === setCode &&
    (String(card.collector_number || '').toLowerCase() === collectorNumberLower) &&
    card.lang === langCode
  );
}

/**
 * Get rulings for a card by ID
 */
function getRulings(oracleId) {
  if (!INCLUDE_RULINGS) {
    return [];
  }
  if (!cardsLoaded || !rulingsDatabase) {
    return [];
  }
  return rulingsDatabase.filter(ruling => ruling.oracle_id === oracleId) || [];
}

/**
 * Schedule automatic update check
 */
function scheduleUpdateCheck() {
  // Clear existing timeout
  if (updateTimeout) {
    clearTimeout(updateTimeout);
  }
  
  // Schedule next update
  updateTimeout = setTimeout(async () => {
    try {
      console.log('[BulkData] Running scheduled 24-hour update...');
      await downloadBulkData();
      
      // Store the old data temporarily in case reload fails
      const oldCardsDatabase = cardsDatabase;
      const oldRulingsDatabase = rulingsDatabase;
      
      // Reset loaded flag and reload - loadBulkData will handle locking
      cardsLoaded = false;
      cardsDatabase = null;
      rulingsDatabase = null;
      
      try {
        await loadBulkData();
        console.log('[BulkData] Scheduled update complete!');
      } catch (reloadError) {
        // Restore old data if reload failed
        console.error('[BulkData] Failed to reload after update:', reloadError.message);
        cardsDatabase = oldCardsDatabase;
        rulingsDatabase = oldRulingsDatabase;
        cardsLoaded = oldCardsDatabase !== null;
        console.log('[BulkData] Restored previous data after reload failure');
      }
    } catch (error) {
      console.error('[BulkData] Scheduled update failed:', error.message);
      // Clear the current timeout and try again in 1 hour if update fails
      if (updateTimeout) {
        clearTimeout(updateTimeout);
      }
      updateTimeout = setTimeout(() => scheduleUpdateCheck(), RETRY_INTERVAL);
      if (updateTimeout.unref) {
        updateTimeout.unref();
      }
    }
  }, UPDATE_INTERVAL);
  if (updateTimeout.unref) {
    updateTimeout.unref();
  }
}

/**
 * Get statistics
 */
function getStats() {
  if (!cardsLoaded) {
    return {
      loaded: false,
      cardCount: 0,
      rulingsCount: 0
    };
  }
  
  return {
    loaded: true,
    cardCount: cardsDatabase.length,
    rulingsCount: INCLUDE_RULINGS && rulingsDatabase ? rulingsDatabase.length : 0,
    cardsFileSize: fs.existsSync(CARD_DATA_FILE) ? fs.statSync(CARD_DATA_FILE).size : 0,
    rulingsFileSize: INCLUDE_RULINGS && fs.existsSync(RULINGS_FILE) ? fs.statSync(RULINGS_FILE).size : 0,
    cardsModified: fs.existsSync(CARD_DATA_FILE) ? fs.statSync(CARD_DATA_FILE).mtime : null,
    rulingsModified: INCLUDE_RULINGS && fs.existsSync(RULINGS_FILE) ? fs.statSync(RULINGS_FILE).mtime : null,
    lastUpdateCheck: new Date(lastUpdateCheck)
  };
}

module.exports = {
  downloadBulkData,
  loadBulkData,
  getCardsDatabase,
  isLoaded,
  getRulings,
  getRandomCard,
  searchCards,
  getCardByName,
  getCardById,
  getCardBySetNumber,
  dedupeCardsByOracleId,
  scheduleUpdateCheck,
  getStats
};
