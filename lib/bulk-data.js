const axios = require('axios');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { pipeline } = require('stream/promises');
const { Readable } = require('stream');

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

let cardsDatabase = null;
let rulingsDatabase = null;
let cardsLoaded = false;
let lastUpdateCheck = 0;
let updateTimeout = null;

// Promise-based mutex locks to prevent race conditions
let downloadLock = null;
let loadLock = null;

// Ensure data directory exists
if (!fs.existsSync(BULK_DATA_DIR)) {
  fs.mkdirSync(BULK_DATA_DIR, { recursive: true });
}

/**
 * Download a single bulk data file from Scryfall using streaming
 */
async function downloadBulkFile(type, outputPath) {
  console.log(`[BulkData] Fetching ${type} bulk data info...`);
  
  try {
    // Get bulk data info from Scryfall API with proper headers
    const { data: bulkInfo } = await axios.get(`https://api.scryfall.com/bulk-data/${type}`, {
      headers: {
        'User-Agent': `MTGCardImporterTTS/${packageVersion}`,
        'Accept': 'application/json'
      }
    });
    const downloadUrl = bulkInfo.download_uri;
    const expectedSize = bulkInfo.size;
    const contentEncoding = bulkInfo.content_encoding?.toLowerCase() ?? '';
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
      decompress: false, // Preserve original encoding to avoid double-gzip
      headers: {
        'User-Agent': `MTGCardImporterTTS/${packageVersion}`,
        'Accept': '*/*'
      }
    });
    
    const responseEncoding = (response.headers?.['content-encoding'] ?? '').toLowerCase();
    const isGzip = contentEncoding === 'gzip' || responseEncoding === 'gzip';
    console.log(`[BulkData] Streaming ${type}${isGzip ? '' : ' and compressing'}...`);
    
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
      if (isGzip) {
        await pipeline(
          response.data,
          fs.createWriteStream(tempPath)
        );
      } else {
        await pipeline(
          response.data,
          zlib.createGzip(),
          fs.createWriteStream(tempPath)
        );
      }
      
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
    console.error(`[BulkData] ${type} download failed:`, error.message);
    throw error;
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
  
  try {
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

/**
 * Parse Scryfall query into filter object
 */
function parseQuery(query) {
  const filters = {
    set: null,
    rarity: [],
    colors: [],
    colorIdentity: [],
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
    idCount: null,
    text: null
  };
  
  if (!query) return filters;
  
  // Split by + but preserve parentheses groups
  const parts = query.match(/\([^)]+\)|[^+]+/g) || [];
  
  parts.forEach(part => {
    part = part.trim();
    
    // Set
    if (part.match(/^s[et]*:/i)) {
      const match = part.match(/s[et]*:(\w+)/i);
      if (match) filters.set = match[1].toLowerCase();
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
    
    // Color
    if (part.match(/^c[:=]/i)) {
      const match = part.match(/c[:=]([wubrgcm])/i);
      if (match) {
        const color = match[1].toLowerCase();
        if (color === 'c') filters.colors = []; // Colorless
        else if (color === 'm') filters.isMulticolor = true;
        else filters.colors.push(color);
      }
    }
    
    // Color identity (for lands)
    if (part.match(/^id[:=]/i)) {
      const match = part.match(/id[:=]([wubrg]+)/i);
      if (match) {
        const colors = match[1].toLowerCase().split('');
        // Only add valid colors and avoid duplicates
        const validColors = new Set(['w', 'u', 'b', 'r', 'g']);
        colors.forEach(c => {
          if (validColors.has(c) && !filters.colorIdentity.includes(c)) {
            filters.colorIdentity.push(c);
          }
        });
      }
    }
    
    if (part.match(/^id>=/i)) {
      const match = part.match(/id>=(\d+)/i);
      if (match) filters.idCount = parseInt(match[1]);
    }
    
    // Type
    if (part.match(/^t:/i)) {
      const match = part.match(/t:(\w+)/i);
      if (match) filters.type.push(match[1].toLowerCase());
    }
    
    if (part.match(/^-t:/i)) {
      const match = part.match(/-t:(\w+)/i);
      if (match) filters.excludeType.push(match[1].toLowerCase());
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
  });
  
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
    if (filters.colors.length > 0) {
      const cardColors = card.colors || [];
      const hasAllColors = filters.colors.every(c => cardColors.includes(c.toUpperCase()));
      if (!hasAllColors) return false;
    }
    
    // Multicolor filter
    if (filters.isMulticolor) {
      const cardColors = card.colors || [];
      if (cardColors.length < 2) return false;
    }
    
    // Colorless filter
    if (filters.colors.length === 0 && filters.colors !== undefined) {
      const cardColors = card.colors || [];
      if (cardColors.length > 0) return false;
    }
    
    // Color identity (for lands)
    if (filters.colorIdentity.length > 0) {
      const cardIdentity = card.color_identity || [];
      const hasAllColors = filters.colorIdentity.every(c => cardIdentity.includes(c.toUpperCase()));
      if (!hasAllColors) return false;
    }
    
    // Color identity count
    if (filters.idCount !== null) {
      const cardIdentity = card.color_identity || [];
      if (cardIdentity.length < filters.idCount) return false;
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
    
    return true;
  });
}

/**
 * Get random card matching query
 */
function getRandomCard(query = '') {
  if (!cardsLoaded || !cardsDatabase) {
    throw new Error('Bulk data not loaded');
  }
  
  const filters = parseQuery(query);
  const matchingCards = filterCards(cardsDatabase, filters);
  
  if (matchingCards.length === 0) {
    // Check for malformed operators (e.g., "mv=0=" instead of "mv>=0" or "mv=0")
    if (query && /\b(id|c|t|type|s|set|r|rarity|cmc|mv|pow|power|tou|toughness)=[<>=]/.test(query)) {
      throw new Error(`No cards found. Malformed operator in "${query}". Use single operators like "mv=0" or "mv>=0", not "mv=0="`);
    }
    throw new Error(`No cards found matching query: ${query}`);
  }
  
  const randomIndex = Math.floor(Math.random() * matchingCards.length);
  return matchingCards[randomIndex];
}

/**
 * Search for cards matching query
 */
function searchCards(query = '', limit = 10) {
  if (!cardsLoaded || !cardsDatabase) {
    throw new Error('Bulk data not loaded');
  }
  
  const filters = parseQuery(query);
  const matchingCards = filterCards(cardsDatabase, filters);
  
  return matchingCards.slice(0, limit);
}

/**
 * Get card by exact name
 */
function getCardByName(name) {
  if (!cardsLoaded || !cardsDatabase) {
    throw new Error('Bulk data not loaded');
  }
  
  const nameLower = name.toLowerCase();
  return cardsDatabase.find(card => card.name.toLowerCase() === nameLower);
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
    }
  }, UPDATE_INTERVAL);
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
  scheduleUpdateCheck,
  getStats
};
