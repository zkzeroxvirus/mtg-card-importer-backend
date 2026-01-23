const axios = require('axios');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { pipeline } = require('stream/promises');

const BULK_DATA_DIR = process.env.BULK_DATA_PATH || path.join(__dirname, '../data');
const BULK_DATA_FILE = path.join(BULK_DATA_DIR, 'oracle-cards.json');
const UPDATE_INTERVAL = 24 * 60 * 60 * 1000; // 24 hours

let cardsDatabase = null;
let cardsLoaded = false;

// Ensure data directory exists
if (!fs.existsSync(BULK_DATA_DIR)) {
  fs.mkdirSync(BULK_DATA_DIR, { recursive: true });
}

/**
 * Download bulk data from Scryfall
 */
async function downloadBulkData() {
  console.log('[BulkData] Fetching bulk data info...');
  
  try {
    // Get bulk data info
    const { data: bulkInfo } = await axios.get('https://api.scryfall.com/bulk-data/oracle-cards');
    const downloadUrl = bulkInfo.download_uri;
    const sizeInMB = Math.round(bulkInfo.size / 1024 / 1024);
    
    console.log(`[BulkData] Downloading Oracle Cards (${sizeInMB}MB compressed)...`);
    console.log(`[BulkData] Updated: ${bulkInfo.updated_at}`);
    
    // Download with streaming
    const response = await axios.get(downloadUrl, {
      responseType: 'stream'
    });
    
    const writer = fs.createWriteStream(BULK_DATA_FILE);
    
    // Decompress gzip on the fly and write
    await pipeline(
      response.data,
      zlib.createGunzip(),
      writer
    );
    
    console.log('[BulkData] Download complete!');
    return true;
  } catch (error) {
    console.error('[BulkData] Download failed:', error.message);
    throw error;
  }
}

/**
 * Load bulk data into memory
 */
async function loadBulkData() {
  if (cardsLoaded) {
    console.log('[BulkData] Already loaded');
    return cardsDatabase;
  }
  
  // Download if file doesn't exist
  if (!fs.existsSync(BULK_DATA_FILE)) {
    console.log('[BulkData] No local bulk data found, downloading...');
    await downloadBulkData();
  }
  
  console.log('[BulkData] Loading bulk data into memory...');
  const startTime = Date.now();
  
  try {
    const data = fs.readFileSync(BULK_DATA_FILE, 'utf8');
    cardsDatabase = JSON.parse(data);
    
    const loadTime = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`[BulkData] Loaded ${cardsDatabase.length} cards in ${loadTime}s`);
    
    cardsLoaded = true;
    return cardsDatabase;
  } catch (error) {
    console.error('[BulkData] Failed to load bulk data:', error.message);
    throw error;
  }
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
      const match = part.match(/id[:=]([wubrg])/i);
      if (match) filters.colorIdentity.push(match[1].toLowerCase());
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
 * Start auto-update timer
 */
function startAutoUpdate() {
  console.log('[BulkData] Auto-update scheduled for every 24 hours');
  
  setInterval(async () => {
    try {
      console.log('[BulkData] Running scheduled update...');
      await downloadBulkData();
      
      // Reload into memory
      cardsLoaded = false;
      await loadBulkData();
      
      console.log('[BulkData] Auto-update complete!');
    } catch (error) {
      console.error('[BulkData] Auto-update failed:', error.message);
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
      cardCount: 0
    };
  }
  
  return {
    loaded: true,
    cardCount: cardsDatabase.length,
    fileSize: fs.existsSync(BULK_DATA_FILE) ? fs.statSync(BULK_DATA_FILE).size : 0,
    lastModified: fs.existsSync(BULK_DATA_FILE) ? fs.statSync(BULK_DATA_FILE).mtime : null
  };
}

module.exports = {
  downloadBulkData,
  loadBulkData,
  getCardsDatabase,
  isLoaded,
  getRandomCard,
  searchCards,
  getCardByName,
  getCardById,
  startAutoUpdate,
  getStats
};
