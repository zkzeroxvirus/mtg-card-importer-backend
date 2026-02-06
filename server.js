const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const compression = require('compression');
require('dotenv').config();

const scryfallLib = require('./lib/scryfall');
const bulkData = require('./lib/bulk-data');

const app = express();
const PORT = process.env.PORT || 3000;
const DEFAULT_BACK = process.env.DEFAULT_CARD_BACK || 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';
const USE_BULK_DATA = process.env.USE_BULK_DATA === 'true';
const MAX_DECK_SIZE = parseInt(process.env.MAX_DECK_SIZE || '500');

// Security: Input validation constants
const MAX_INPUT_LENGTH = 10000; // 10KB max for card names, queries, etc.
const MAX_SEARCH_LIMIT = 1000; // Maximum cards to return in search
const MAX_CACHE_SIZE = parseInt(process.env.MAX_CACHE_SIZE || '5000', 10); // Maximum size for failed query and error caches

// Random card deduplication constants
// When fetching multiple random cards, request extra to account for duplicates
// A 1.5x multiplier balances between API efficiency and getting enough unique cards
const DUPLICATE_BUFFER_MULTIPLIER = 1.5;
const MAX_RETRY_ATTEMPTS_MULTIPLIER = 3; // Retry up to 3x the requested count for bulk data

// Security: Validate card back URL is from allowed domains
function isValidCardBackURL(url) {
  if (!url || typeof url !== 'string') return false;
  try {
    const parsed = new URL(url);
    // Allow common image hosting domains used by TTS community
    const allowedDomains = [
      'steamusercontent-a.akamaihd.net',
      'steamusercontent.com',
      'steamuserimages-a.akamaihd.net',
      'i.imgur.com',
      'imgur.com'
    ];
    return allowedDomains.some(domain => parsed.hostname.endsWith(domain));
  } catch (e) {
    // Invalid URL format
    console.debug('Invalid card back URL:', e.message);
    return false;
  }
}

// Validate the default card back URL on startup
if (!isValidCardBackURL(DEFAULT_BACK)) {
  console.error('ERROR: DEFAULT_CARD_BACK URL is not from an allowed domain. Server will not start.');
  console.error('Allowed domains: Steam CDN, Imgur');
  process.exit(1);
}

// Rate limiters
const randomLimiter = rateLimit({
  windowMs: 60 * 1000,      // 1 minute
  max: 50,                  // 50 requests per minute per IP
  keyGenerator: (req) => req.ip,
  message: 'Too many random card requests from this IP, please try again later',
  skip: (req) => {
    // Allow unlimited single-card requests, only limit bulk requests
    const count = req.query.count ? parseInt(req.query.count) : 1;
    return count === 1;
  }
});

// Middleware
app.use(cors());

// Enable compression for all responses (improves bandwidth efficiency)
app.use(compression({
  filter: (req, res) => {
    if (req.headers['x-no-compression']) {
      return false;
    }
    return compression.filter(req, res);
  },
  level: 6 // Balance between compression speed and ratio
}));

app.use(express.raw({ limit: '10mb' }));  // Accept raw body as Buffer, parse manually

// Performance metrics tracking
const metrics = {
  requests: 0,
  errors: 0,
  startTime: Date.now()
};

// Request counter middleware
app.use((req, res, next) => {
  metrics.requests++;
  
  // Track response time
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    if (res.statusCode >= 500) {
      metrics.errors++;
    }
    
    // Log slow requests (> 5 seconds)
    if (duration > 5000) {
      console.warn(`[Perf] Slow request: ${req.method} ${req.path} took ${duration}ms`);
    }
  });
  
  next();
});

// Normalize errors from Scryfall/API calls into consistent JSON for the importer
function normalizeError(error, defaultStatus = 502) {
  let status = error?.response?.status;
  if (!status) {
    if (error?.code === 'ECONNABORTED') {
      status = 504; // Gateway Timeout
    } else if (error?.message && /not found/i.test(error.message)) {
      status = 404;
    } else {
      status = defaultStatus;
    }
  }

  const details =
    error?.response?.data?.details ||
    error?.response?.data?.error ||
    error?.message ||
    'Request failed';

  return { status, details };
}

function filterTokenParts(allParts) {
  if (!Array.isArray(allParts)) {
    return [];
  }
  return allParts.filter(part => {
    const typeLine = (part.type_line || '').toLowerCase();
    const component = (part.component || '').toLowerCase();
    return typeLine.includes('token') ||
      typeLine.includes('emblem') ||
      component === 'token' ||
      component === 'emblem';
  });
}

function isTokenOrEmblemCard(card) {
  const typeLine = (card?.type_line || '').toLowerCase();
  return typeLine.includes('token') || typeLine.includes('emblem');
}

function sanitizeTokenSearchName(name) {
  return String(name || '')
    .replace(/[\\"]/g, '')
    .replace(/[^\w\s'-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function getBulkCardFromUri(uri) {
  if (!USE_BULK_DATA || !bulkData.isLoaded()) {
    return null;
  }
  try {
    const urlObj = new URL(uri);
    const pathSegments = urlObj.pathname.split('/').filter(Boolean);
    if (pathSegments[0] !== 'cards') {
      return null;
    }

    const blockedIdentifiers = new Set([
      'named',
      'search',
      'random',
      'collection',
      'autocomplete',
      'multiverse',
      'arena',
      'mtgo',
      'tcgplayer'
    ]);

    if (pathSegments.length === 2) {
      const cardId = pathSegments[1];
      if (blockedIdentifiers.has(cardId)) {
        return null;
      }
      return bulkData.getCardById(cardId);
    }

    if (pathSegments.length >= 3) {
      if (blockedIdentifiers.has(pathSegments[1]) || pathSegments[2] === 'rulings') {
        return null;
      }
      return bulkData.getCardBySetNumber(pathSegments[1], pathSegments[2], pathSegments[3] || 'en');
    }
  } catch {
    return null;
  }
  return null;
}

async function getTokensFromBulkData(cardName) {
  if (!USE_BULK_DATA || !bulkData.isLoaded()) {
    return null;
  }

  const MAX_TOKENS = 16;
  const sanitizedName = sanitizeTokenSearchName(cardName);
  if (!sanitizedName) {
    return [];
  }

  let baseCard = null;

  try {
    baseCard = bulkData.getCardByName(sanitizedName);
  } catch {
    baseCard = null;
  }

  if (baseCard?.all_parts?.length) {
    const tokenParts = filterTokenParts(baseCard.all_parts).slice(0, MAX_TOKENS);
    const tokensFromParts = tokenParts
      .map(part => bulkData.getCardById(part.id))
      .filter(Boolean);
    if (tokensFromParts.length > 0) {
      return tokensFromParts;
    }
  }

  const typeQuery = `t:token name:"${sanitizedName}"`;
  const typeResults = await bulkData.searchCards(typeQuery, MAX_TOKENS);
  if (Array.isArray(typeResults) && typeResults.length > 0) {
    return typeResults.filter(isTokenOrEmblemCard).slice(0, MAX_TOKENS);
  }

  const createQuery = `o:"create ${sanitizedName}"`;
  const createResults = await bulkData.searchCards(createQuery, MAX_TOKENS);
  if (Array.isArray(createResults) && createResults.length > 0) {
    return createResults.filter(isTokenOrEmblemCard).slice(0, MAX_TOKENS);
  }

  return [];
}

/**
 * Analyzes a Scryfall query and provides helpful hints for common syntax errors
 */
function getQueryHint(query) {
  const q = query.toLowerCase();
  
  // Check for common typos in color identity
  // Match "idXX" where XX are 2-3 lowercase letters (like "idgu" or "idub")
  // But only in search context - check if query has other search operators
  if (/\bid[a-z]{2,3}\b/.test(q) && (q.includes('t:') || q.includes('c:') || q.includes('s:') || q.includes('r:'))) {
    return ' (Did you mean "id:" or "identity:" for color identity? Example: id:gu for Simic)';
  }
  
  // Common keyword mistakes - missing colons or comparison operators
  const keywordPatterns = [
    { pattern: /\bcmc\d/, correct: 'cmc:', example: 'cmc:3 or cmc>=3', desc: 'mana value' },
    { pattern: /\bmv\d/, correct: 'mv:', example: 'mv:3 or mv<=3', desc: 'mana value' },
    { pattern: /\bpow(er)?\d/, correct: 'power:', example: 'power>=5', desc: 'power' },
    { pattern: /\btou(ghness)?\d/, correct: 'toughness:', example: 'toughness<=2', desc: 'toughness' },
    { pattern: /\bloy(alty)?\d/, correct: 'loyalty:', example: 'loyalty:3', desc: 'loyalty' },
    { pattern: /\brarity[a-z]/, correct: 'rarity:', example: 'rarity:mythic', desc: 'rarity' },
    { pattern: /\bcolor[wubrg]/, correct: 'color:', example: 'color:red', desc: 'color' },
    { pattern: /\btype[a-z]/, correct: 'type:', example: 'type:creature', desc: 'type' },
  ];
  
  for (const { pattern, correct, example, desc } of keywordPatterns) {
    if (pattern.test(q)) {
      return ` (Did you mean "${correct}" for ${desc}? Example: ${example})`;
    }
  }
  
  // Check for comparison operators written incorrectly (e.g., "mv=0=type" instead of "mv=0 type")
  if (/\b(cmc|mv|pow|power|tou|toughness|loy|loyalty)=\d+=[a-z]/.test(q)) {
    const match = q.match(/\b(cmc|mv|pow|power|tou|toughness|loy|loyalty)=(\d+)=/);
    if (match) {
      // "mv=0=type" should use space or + to separate: "mv=0 type:artifact" or "mv=0+type:artifact"
      return ` (Use spaces or "+" to separate conditions: "${match[1]}=${match[2]} type:..." not "${match[1]}=${match[2]}=type")`;
    }
  }
  
  // Common misspellings
  const misspellings = {
    'legnedary': 'legendary',
    'legndary': 'legendary',
    'planeswaker': 'planeswalker',
    'planeswalke': 'planeswalker',
    'insant': 'instant',
    'sorcry': 'sorcery',
    'creautre': 'creature',
    'enchantmnet': 'enchantment',
    'artifcat': 'artifact',
  };
  
  for (const [wrong, right] of Object.entries(misspellings)) {
    if (q.includes(wrong)) {
      return ` (Did you mean "${right}"?)`;
    }
  }
  
  // Check for invalid color abbreviations
  if (/\bc:[^wubrgcm\s<>=]/.test(q)) {
    return ' (Color codes are: w=white, u=blue, b=black, r=red, g=green, c=colorless, m=multicolor)';
  }
  
  // Check for mana symbols without braces for complex symbols
  if (/\b(m|mana):.*\d\/[wubrg]/i.test(q)) {
    return ' (Hybrid mana symbols need braces: {2/G} not 2/G)';
  }
  
  // Check for set code format errors
  if (/\b(s|set|e|edition):[A-Z]{4,}/.test(q)) {
    return ' (Set codes are usually 3 characters: "s:war" not "s:warof")';
  }
  
  // Check for rarity abbreviations
  if (/\br:(c|u|r|m)\b/.test(q)) {
    return ' (Use full rarity names: rarity:common, rarity:uncommon, rarity:rare, rarity:mythic)';
  }
  
  // Check for format names
  const invalidFormats = ['edh', 'cedh', 'canlander'];
  for (const fmt of invalidFormats) {
    if (new RegExp(`\\bf:${fmt}\\b`).test(q)) {
      const corrections = {
        'edh': 'commander',
        'cedh': 'commander',
        'canlander': 'duel'
      };
      return ` (Use "f:${corrections[fmt]}" for ${fmt.toUpperCase()})`;
    }
  }
  
  // Check for missing quotes around multi-word phrases
  if (/\bo:[a-z]+\s+[a-z]+(?!\s*\+)/.test(q) && !/"/.test(q)) {
    return ' (Use quotes for multi-word oracle text: o:"card name" or use + between words: o:card+name)';
  }
  
  return '';
}

// Cache for failed queries to prevent repeated API calls for same bad query
const failedQueryCache = new Map();
const FAILED_QUERY_CACHE_TTL = 60000; // 1 minute

// Track when we last showed detailed error for a query (to avoid spamming TTS chat)
const lastDetailedErrorTime = new Map();
const DETAILED_ERROR_COOLDOWN = 5000; // 5 seconds

// Helper: Evict oldest entries from a Map (LRU-style)
function evictOldestEntries(map, maxSize) {
  if (map.size <= maxSize) return;
  const entriesToRemove = map.size - maxSize;
  let removed = 0;
  for (const key of map.keys()) {
    map.delete(key);
    removed++;
    if (removed >= entriesToRemove) break;
  }
}

function isQueryCachedAsFailed(query) {
  const cached = failedQueryCache.get(query);
  if (cached && Date.now() - cached.timestamp < FAILED_QUERY_CACHE_TTL) {
    return cached.error;
  }
  return null;
}

function cacheFailedQuery(query, errorMessage) {
  failedQueryCache.set(query, {
    error: errorMessage,
    timestamp: Date.now()
  });
  
  // Enforce maximum cache size to prevent unbounded memory growth
  if (failedQueryCache.size > MAX_CACHE_SIZE) {
    const now = Date.now();
    // First try to clean up expired entries
    for (const [key, value] of failedQueryCache.entries()) {
      if (now - value.timestamp > FAILED_QUERY_CACHE_TTL) {
        failedQueryCache.delete(key);
      }
    }
    // If still over limit, evict oldest entries
    if (failedQueryCache.size > MAX_CACHE_SIZE) {
      evictOldestEntries(failedQueryCache, MAX_CACHE_SIZE);
    }
  }
}

function shouldShowDetailedError(query) {
  const lastShown = lastDetailedErrorTime.get(query);
  const now = Date.now();
  
  if (!lastShown || now - lastShown > DETAILED_ERROR_COOLDOWN) {
    lastDetailedErrorTime.set(query, now);
    
    // Enforce maximum cache size to prevent unbounded memory growth
    if (lastDetailedErrorTime.size > MAX_CACHE_SIZE) {
      // First try to clean up expired entries
      for (const [key, time] of lastDetailedErrorTime.entries()) {
        if (now - time > DETAILED_ERROR_COOLDOWN) {
          lastDetailedErrorTime.delete(key);
        }
      }
      // If still over limit, evict oldest entries
      if (lastDetailedErrorTime.size > MAX_CACHE_SIZE) {
        evictOldestEntries(lastDetailedErrorTime, MAX_CACHE_SIZE);
      }
    }
    
    return true;
  }
  
  return false;
}

// Health check with metrics
app.get('/', (req, res) => {
  const bulkStats = bulkData.getStats();
  const uptime = Math.floor((Date.now() - metrics.startTime) / 1000);
  const memUsage = process.memoryUsage();
  
  res.json({
    status: 'ok',
    service: 'MTG Card Importer Backend',
    version: '1.0.0',
    uptime: `${uptime}s`,
    metrics: {
      totalRequests: metrics.requests,
      errors: metrics.errors,
      errorRate: metrics.requests > 0 ? (metrics.errors / metrics.requests * 100).toFixed(2) + '%' : '0%',
      memoryMB: Math.round(memUsage.heapUsed / 1024 / 1024)
    },
    bulkData: {
      enabled: USE_BULK_DATA,
      loaded: bulkStats.loaded,
      cardCount: bulkStats.cardCount
    },
    endpoints: {
      card: 'GET /card/:name',
      deck: 'POST /deck',
      random: 'GET /random',
      search: 'GET /search',
      bulkStats: 'GET /bulk/stats',
      metrics: 'GET /metrics'
    }
  });
});

// Dedicated metrics endpoint for monitoring
app.get('/metrics', (req, res) => {
  const uptime = Math.floor((Date.now() - metrics.startTime) / 1000);
  const memUsage = process.memoryUsage();
  const bulkStats = bulkData.getStats();
  
  res.json({
    uptime: uptime,
    requests: {
      total: metrics.requests,
      errors: metrics.errors,
      errorRate: metrics.requests > 0 ? metrics.errors / metrics.requests : 0
    },
    memory: {
      heapUsed: memUsage.heapUsed,
      heapTotal: memUsage.heapTotal,
      external: memUsage.external,
      rss: memUsage.rss
    },
    bulkData: {
      enabled: USE_BULK_DATA,
      loaded: bulkStats.loaded,
      cardCount: bulkStats.cardCount,
      lastUpdate: bulkStats.lastUpdate
    },
    process: {
      pid: process.pid,
      version: process.version,
      platform: process.platform
    }
  });
});

// Readiness probe for load balancers
app.get('/ready', (req, res) => {
  const bulkStats = bulkData.getStats();
  
  // Server is ready if:
  // 1. Either bulk data is disabled OR bulk data is loaded
  // 2. Memory usage is reasonable (< 1GB heap)
  const memUsage = process.memoryUsage();
  const heapUsedMB = memUsage.heapUsed / 1024 / 1024;
  
  const isReady = (!USE_BULK_DATA || bulkStats.loaded) && heapUsedMB < 1024;
  
  if (isReady) {
    res.json({ ready: true });
  } else {
    res.status(503).json({ 
      ready: false,
      reason: USE_BULK_DATA && !bulkStats.loaded ? 'bulk data loading' : 'high memory usage'
    });
  }
});

/**
 * GET /card/:name
 * Get a single card - returns raw Scryfall JSON
 * Uses bulk data if available (exact name match only), falls back to API for fuzzy search
 */
app.get('/card/:name', async (req, res) => {
  const { name } = req.params;
  const { set } = req.query;
  
  try {

    if (!name) {
      return res.status(400).json({ object: 'error', details: 'Card name required' });
    }

    // Security: Validate input length to prevent DoS
    if (name.length > MAX_INPUT_LENGTH) {
      return res.status(400).json({ 
        object: 'error', 
        details: `Card name too long (max ${MAX_INPUT_LENGTH} characters)` 
      });
    }

    if (set && set.length > 10) {
      return res.status(400).json({ 
        object: 'error', 
        details: 'Set code too long (max 10 characters)' 
      });
    }

    // Validate input: detect if query string is being passed as card name
    if (name.includes('?q=')) {
      return res.status(400).json({ 
        object: 'error',
        details: 'Invalid card name. Did you mean to use /search or /random endpoint? Card name should not contain query parameters.'
      });
    }

    // Detect common search syntax in card name (indicates wrong endpoint usage)
    // Check for known search operators at word boundaries (colon, equals, comparison)
    // Valid Scryfall syntax uses these operators, so we detect them in card names
    const hasSearchOperator = /\b(id|c|t|type|s|set|r|rarity|cmc|mv|pow|power|tou|toughness)[:=<>]/i.test(name);
    if (hasSearchOperator) {
      return res.status(400).json({ 
        object: 'error',
        details: 'Invalid card name. This looks like a search query. Use /search or /random endpoint for queries.'
      });
    }

    let scryfallCard;
    
    // Bulk data only supports exact name matching, API supports fuzzy matching
    if (USE_BULK_DATA && bulkData.isLoaded()) {
      scryfallCard = bulkData.getCardByName(name, set || null);
    }

    if (!scryfallCard) {
      // Fall back to API for fuzzy matching
      scryfallCard = await scryfallLib.getCard(name, set);
    }
    
    // Filter all_parts to only include tokens and emblems (for TTS token spawning)
    if (scryfallCard.all_parts && Array.isArray(scryfallCard.all_parts)) {
      scryfallCard.all_parts = filterTokenParts(scryfallCard.all_parts);
    }
    
    // Return raw Scryfall format - Lua code will convert to TTS
    res.json(scryfallCard);
  } catch (error) {
    console.error('Error fetching card:', error.message);
    const { status, details } = normalizeError(error, 502);

    // Fuzzy recovery: if card not found, try autocomplete and fetch best suggestion
    if (status === 404) {
      try {
        const suggestions = await scryfallLib.autocompleteCardName(name);
        if (suggestions && suggestions.length > 0) {
          const suggestion = suggestions[0];
          try {
            const corrected = await scryfallLib.getCard(suggestion, set || null);
            corrected._corrected_name = suggestion;
            corrected._original_name = name;
            return res.json(corrected);
          } catch (fallbackError) {
            // If set-specific lookup failed, try without set
            console.debug('Set-specific fallback failed:', fallbackError.message);
            if (set) {
              try {
                const corrected = await scryfallLib.getCard(suggestion, null);
                corrected._corrected_name = suggestion;
                corrected._original_name = name;
                return res.json(corrected);
              } catch (e) {
                // fall through to error response
                console.debug('Fallback without set also failed:', e.message);
              }
            }
          }

          const suggestionList = suggestions.slice(0, 5).join(', ');
          return res.status(404).json({
            object: 'error',
            details: `Card not found: ${name}. Did you mean: ${suggestionList}?`
          });
        }
      } catch (e) {
        // Ignore autocomplete failures and return original error
        console.debug('Autocomplete suggestion failed:', e.message);
      }
    }

    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /cards/:id
 * Get a card by Scryfall ID - returns raw Scryfall JSON
 */
app.get('/cards/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (!id) {
      return res.status(400).json({ error: 'Card ID required' });
    }

    let scryfallCard = null;
    if (USE_BULK_DATA && bulkData.isLoaded()) {
      scryfallCard = bulkData.getCardById(id);
    }
    if (!scryfallCard) {
      scryfallCard = await scryfallLib.getCardById(id);
    }
    
    // Return raw Scryfall format
    res.json(scryfallCard);
  } catch (error) {
    console.error('Error fetching card by ID:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /cards/:set/:number
 * GET /cards/:set/:number/:lang
 * Get a card by set code and collector number - returns raw Scryfall JSON
 */
app.get('/cards/:set/:number/:lang?', async (req, res) => {
  try {
    const { set, number, lang } = req.params;

    if (!set || !number) {
      return res.status(400).json({ error: 'Set code and collector number required' });
    }

    // Security: Validate input lengths
    if (set.length > 10) {
      return res.status(400).json({ error: 'Set code too long' });
    }
    if (number.length > 10) {
      return res.status(400).json({ error: 'Collector number too long' });
    }

    // Security: Validate language code format (2-3 letters)
    const langCode = lang || 'en';
    if (langCode && !/^[a-z]{2,3}$/i.test(langCode)) {
      return res.status(400).json({ error: 'Invalid language code format' });
    }

    let scryfallCard = null;
    if (USE_BULK_DATA && bulkData.isLoaded()) {
      scryfallCard = bulkData.getCardBySetNumber(set, number, langCode);
    }
    if (!scryfallCard) {
      scryfallCard = await scryfallLib.getCardBySetNumber(set, number, langCode);
    }
    
    // Return raw Scryfall format
    res.json(scryfallCard);
  } catch (error) {
    console.error('Error fetching card by set/number:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * POST /deck
 * Build a deck from decklist
 * Accepts either:
 *   - JSON body: { "decklist": "...", "back": "..." }
 *   - Plain text body: decklist lines (back uses default)
 * Returns NDJSON (newline-delimited JSON)
 */
app.post('/deck', async (req, res) => {
  try {
    let decklist = null;
    let back = null;

    // req.body is a Buffer from express.raw(); convert to string
    const bodyText = req.body ? req.body.toString('utf8') : '';
    
    console.log('POST /deck raw bodyText (first 200 chars):', bodyText.substring(0, 200));
    console.log('POST /deck bodyText length:', bodyText.length, 'type:', typeof bodyText);
    
    if (!bodyText || bodyText.trim().length === 0) {
      console.error('POST /deck: empty body');
      return res.status(400).json({ error: 'decklist required' });
    }

    // Security: Validate body size
    if (bodyText.length > 1024 * 1024) { // 1MB limit for decklist
      return res.status(400).json({ error: 'Decklist too large (max 1MB)' });
    }

    // Try to parse as JSON
    if (bodyText.trim().startsWith('{')) {
      try {
        const parsed = JSON.parse(bodyText);
        console.log('Parsed JSON. Type of parsed.decklist:', typeof parsed.decklist);
        
        // Handle case where decklist is an object that should be a string
        if (typeof parsed.decklist === 'object' && parsed.decklist !== null) {
          console.error('POST /deck: decklist is an object, not a string. Object keys:', Object.keys(parsed.decklist));
          // Try to convert object to decklist lines
          decklist = Object.keys(parsed.decklist).join('\n');
        } else if (typeof parsed.decklist === 'string') {
          decklist = parsed.decklist;
        } else {
          console.error('POST /deck: unexpected type for decklist:', typeof parsed.decklist, 'value:', parsed.decklist);
        }
        back = parsed.back;
        
        // Security: Validate custom card back URL if provided
        if (back && !isValidCardBackURL(back)) {
          return res.status(400).json({ 
            error: 'Invalid card back URL. Must be from allowed domains (Steam CDN, Imgur)' 
          });
        }
      } catch (e) {
        console.error('JSON parse error:', e.message, 'body was:', bodyText);
        // Not valid JSON; treat entire body as plain text decklist
        decklist = bodyText;
      }
    } else {
      // Not JSON-like; treat as plain text decklist
      console.log('POST /deck: treating body as plain text decklist');
      decklist = bodyText;
    }

    const cardBack = back || DEFAULT_BACK;

    if (!decklist || decklist.trim().length === 0) {
      console.error('POST /deck: no decklist parsed. bodyText length:', bodyText.length, 'bodyText:', bodyText);
      return res.status(400).json({ error: 'decklist required' });
    }

    const cards = scryfallLib.parseDecklist(decklist);
    
    console.log(`POST /deck: parsed decklist. decklist length: ${decklist.length}, cards found: ${cards.length}`);
    console.log(`First 200 chars of decklist: ${decklist.substring(0, 200)}`);
    
    if (cards.length === 0) {
      console.error('POST /deck: no valid cards in decklist. Full text:', decklist);
      return res.status(400).json({ error: 'No valid cards in decklist' });
    }

    // Validate deck size to prevent API abuse
    const totalCards = cards.reduce((sum, card) => sum + card.count, 0);
    if (totalCards > MAX_DECK_SIZE) {
      return res.status(400).json({ 
        error: `Deck too large (${totalCards} > ${MAX_DECK_SIZE} card limit)` 
      });
    }

    res.setHeader('Content-Type', 'application/x-ndjson');

    let cardCount = 0;
    for (const { count, name } of cards) {
      try {
        const scryfallCard = await scryfallLib.getCard(name);
        
        for (let i = 0; i < count; i++) {
          const ttsCard = scryfallLib.convertToTTSCard(scryfallCard, cardBack);
          // Write just the TTS object (no wrapping)
          res.write(JSON.stringify(ttsCard) + '\n');
          cardCount++;
        }
      } catch (error) {
        console.warn(`Skipped: ${name} - ${error.message}`);
        // Continue with next card on error
      }
    }

    console.log(`Deck spawned: ${cardCount} cards`);
    res.end();
  } catch (error) {
    console.error('Error building deck:', error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /build
 * Alias for /deck endpoint (for compatibility with bundled importer)
 * Build a deck from decklist with hand position
 * Returns NDJSON (newline-delimited JSON)
 */
app.post('/build', async (req, res) => {
  try {
    let data = null;
    let back = null;
    let hand = null;

    // req.body is a Buffer from express.raw(); parse it
    const bodyText = req.body ? req.body.toString('utf8') : '';
    
    if (!bodyText || bodyText.trim().length === 0) {
      return res.status(400).json({ error: 'Decklist required' });
    }

    // Security: Validate body size
    if (bodyText.length > 1024 * 1024) { // 1MB limit for decklist
      return res.status(400).json({ error: 'Decklist too large (max 1MB)' });
    }

    // Try to parse as JSON
    if (bodyText.trim().startsWith('{')) {
      try {
        const parsed = JSON.parse(bodyText);
        data = parsed.data;
        back = parsed.back;
        hand = parsed.hand;
        
        // Security: Validate custom card back URL if provided
        if (back && !isValidCardBackURL(back)) {
          return res.status(400).json({ 
            error: 'Invalid card back URL. Must be from allowed domains (Steam CDN, Imgur)' 
          });
        }
      } catch (e) {
        console.error('JSON parse error:', e.message);
        data = bodyText;
      }
    } else {
      data = bodyText;
    }

    const cardBack = back || DEFAULT_BACK;

    if (!data) {
      return res.status(400).json({ error: 'Decklist required' });
    }

    const cards = scryfallLib.parseDecklist(data);
    
    if (cards.length === 0) {
      return res.status(400).json({ error: 'No valid cards in decklist' });
    }

    // Validate deck size to prevent API abuse
    const totalCards = cards.reduce((sum, card) => sum + card.count, 0);
    if (totalCards > MAX_DECK_SIZE) {
      return res.status(400).json({ 
        error: `Deck too large (${totalCards} > ${MAX_DECK_SIZE} card limit)` 
      });
    }

    res.setHeader('Content-Type', 'application/x-ndjson');

    let cardCount = 0;
    for (const { count, name } of cards) {
      try {
        const scryfallCard = await scryfallLib.getCard(name);
        
        for (let i = 0; i < count; i++) {
          // Pass hand position to cards - stack them slightly in Z direction
          let cardPosition = null;
          if (hand && hand.position) {
            cardPosition = {
              x: hand.position.x || 0,
              y: hand.position.y || 0,
              z: (hand.position.z || 0) + (i * 0.1),  // Stack cards slightly
              rotX: hand.rotation && hand.rotation.x || 0,
              rotY: hand.rotation && hand.rotation.y || 0,
              rotZ: hand.rotation && hand.rotation.z || 0
            };
          }
          const ttsCard = scryfallLib.convertToTTSCard(scryfallCard, cardBack, cardPosition);
          // Write just the TTS object (no wrapping)
          res.write(JSON.stringify(ttsCard) + '\n');
          cardCount++;
        }
      } catch (error) {
        console.warn(`Skipped: ${name} - ${error.message}`);
        // Continue with next card on error
      }
    }

    console.log(`Deck spawned: ${cardCount} cards`);
    res.end();
  } catch (error) {
    console.error('Error building deck:', error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /deck/parse
 * Parse deck from any format and return structured response
 * Accepts: plain text, CSV, JSON, or HTML decklist
 * Returns: { total, detected_format, mainboard, sideboard, metadata }
 */
app.post('/deck/parse', async (req, res) => {
  try {
    const bodyText = req.body ? req.body.toString('utf8') : '';
    
    if (!bodyText || bodyText.trim().length === 0) {
      return res.status(400).json({ error: 'Decklist required' });
    }

    // Security: Validate body size
    if (bodyText.length > 1024 * 1024) {
      return res.status(400).json({ error: 'Decklist too large (max 1MB)' });
    }

    // Detect format
    let detectedFormat = 'unknown';
    let parsedCards = [];
    let sideboard = [];
    
    // Try JSON first (most structured)
    if (bodyText.trim().startsWith('{')) {
      try {
        const json = JSON.parse(bodyText);
        
        // Moxfield format: { main: [...], sideboard: [...] }
        if (json.main || json.mainboard) {
          detectedFormat = 'moxfield_json';
          const mainArray = json.main || json.mainboard;
          if (Array.isArray(mainArray)) {
            for (const card of mainArray) {
              parsedCards.push({
                count: card.quantity || 1,
                name: card.card?.name || card.name || 'Unknown',
                scryfall_id: card.card?.scryfall_id || card.scryfall_id
              });
            }
          }
          const sideArray = json.sideboard;
          if (Array.isArray(sideArray)) {
            for (const card of sideArray) {
              sideboard.push({
                count: card.quantity || 1,
                name: card.card?.name || card.name || 'Unknown'
              });
            }
          }
        }
        // CubeCobra format: { deck: [...] }
        else if (json.deck && Array.isArray(json.deck)) {
          detectedFormat = 'cubecobra_json';
          for (const card of json.deck) {
            parsedCards.push({
              count: card.count || 1,
              name: card.name || 'Unknown'
            });
          }
        }
        // Generic JSON array format
        else if (Array.isArray(json)) {
          detectedFormat = 'json_array';
          for (const card of json) {
            parsedCards.push({
              count: card.count || card.quantity || 1,
              name: card.name || 'Unknown'
            });
          }
        }
      } catch (e) {
        // Not valid JSON, fall through to other formats
        console.debug('JSON parsing failed, trying other formats:', e.message);
      }
    }

    // Try CSV format if not JSON
    if (parsedCards.length === 0 && bodyText.includes('\n') && bodyText.includes(',')) {
      detectedFormat = 'csv';
      const lines = bodyText.split('\n');
      
      for (const line of lines) {
        if (!line.trim() || line.startsWith('#')) continue;
        
        const parts = line.split(',').map(p => p.trim());
        if (parts.length >= 2 && parts[0].match(/^\d+$/)) {
          parsedCards.push({
            count: parseInt(parts[0]),
            name: parts[1],
            set: parts[2] || null,
            collector_number: parts[3] || null
          });
        }
      }
    }

    // Try plain text format if not JSON or CSV
    if (parsedCards.length === 0) {
      const isMainboardFormat = bodyText.includes('[Main]') || bodyText.includes('[Sideboard]');
      detectedFormat = isMainboardFormat ? 'deckstats_text' : 'plain_text';
      
      const lines = bodyText.split('\n');
      let isMainboard = true;
      
      for (let line of lines) {
        line = line.trim();
        
        // Check for section headers
        if (line.match(/^\[Sideboard\]|^Sideboard:/i)) {
          isMainboard = false;
          continue;
        }
        
        // Skip empty lines and comments
        if (!line || line.startsWith('//') || line.startsWith('#')) {
          continue;
        }
        
        // Parse: "4x Island" or "4 Island" or "4x Island (DOM) 264"
        const match = line.match(/^(\d+)x?\s+(.+?)(?:\s*\(([^)]+)\))?(?:\s+\d+)?$/i);
        if (match) {
          const [, count, name, set] = match;
          const card = {
            count: parseInt(count),
            name: name.trim()
          };
          if (set) card.set = set;
          
          (isMainboard ? parsedCards : sideboard).push(card);
        }
      }
    }

    if (parsedCards.length === 0) {
      return res.status(400).json({ 
        error: 'No valid cards found', 
        details: 'Unable to parse decklist. Expected format: 4x Card Name or 4,Card Name,SET'
      });
    }

    // Validate all cards exist in Scryfall
    const warnings = [];
    const validatedMainboard = [];
    
    for (const card of parsedCards) {
      try {
        await scryfallLib.getCard(card.name, card.set || null);
        validatedMainboard.push({
          count: card.count,
          name: card.name,
          cardUrl: `/card/${encodeURIComponent(card.name)}`,
          error: null
        });
      } catch (error) {
        warnings.push(`Card not found: ${card.name}`);
        validatedMainboard.push({
          count: card.count,
          name: card.name,
          cardUrl: null,
          error: error.message
        });
      }
    }

    // Validate sideboard cards
    const validatedSideboard = [];
    for (const card of sideboard) {
      try {
        await scryfallLib.getCard(card.name);
        validatedSideboard.push({
          count: card.count,
          name: card.name,
          cardUrl: `/card/${encodeURIComponent(card.name)}`,
          error: null
        });
      } catch (error) {
        warnings.push(`Sideboard card not found: ${card.name}`);
        validatedSideboard.push({
          count: card.count,
          name: card.name,
          cardUrl: null,
          error: error.message
        });
      }
    }

    // Calculate totals
    const mainboardTotal = validatedMainboard.reduce((sum, c) => sum + c.count, 0);
    const sideboardTotal = validatedSideboard.reduce((sum, c) => sum + c.count, 0);

    res.json({
      total: mainboardTotal + sideboardTotal,
      mainboard_count: mainboardTotal,
      sideboard_count: sideboardTotal,
      detected_format: detectedFormat,
      mainboard: validatedMainboard,
      sideboard: validatedSideboard,
      metadata: {
        warnings,
        invalid_cards: validatedMainboard.filter(c => c.error).length + 
                       validatedSideboard.filter(c => c.error).length
      }
    });
  } catch (error) {
    console.error('Error parsing deck:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ error: details });
  }
});

/**
 * GET /random
 * Get random card(s) - returns raw Scryfall card or list
 * Uses bulk data if available, falls back to API
 * Rate limited: 50 bulk requests per minute per IP
 */
app.get('/random', randomLimiter, async (req, res) => {
  try {
    const { count, q = '' } = req.query;
    // Security: Enforce maximum count to prevent resource exhaustion
    const numCards = count ? Math.min(Math.max(parseInt(count) || 1, 1), 100) : 1;
    
    console.log(`GET /random - count: ${numCards}, query: "${q}"`);

    // Security: Validate query length
    if (q && q.length > MAX_INPUT_LENGTH) {
      return res.status(400).json({ 
        object: 'error', 
        details: `Query too long (max ${MAX_INPUT_LENGTH} characters)` 
      });
    }

    // Check if this query recently failed
    if (q) {
      const cachedError = isQueryCachedAsFailed(q);
      if (cachedError) {
        console.log(`Returning cached error for query: "${q}"`);
        
        // Only show detailed error once per cooldown period to avoid spamming TTS chat
        // When users spawn a 15-card booster with invalid query, show error on first request only
        // Subsequent requests within cooldown get silently suppressed (204 No Content)
        const showDetails = shouldShowDetailedError(q);
        
        if (showDetails) {
          return res.status(400).json({ object: 'error', details: cachedError });
        } else {
          // Silently suppress subsequent failed requests to prevent chat spam
          return res.status(204).send();
        }
      }
    }

    if (numCards === 1) {
      // Single random card
      let scryfallCard = null;
      
      if (USE_BULK_DATA && bulkData.isLoaded()) {
        scryfallCard = await bulkData.getRandomCard(q);
      }
      
      // Fallback to API if bulk data not loaded or returned null
      if (!scryfallCard) {
        try {
          scryfallCard = await scryfallLib.getRandomCard(q);
        } catch (error) {
          // Single card request failed - add helpful hint if it's a 404
          if (error.message && error.message.includes('Scryfall returned 404')) {
            const hint = getQueryHint(q);
            const enhancedError = `Invalid search query: "${q}"${hint}. No cards match this query.`;
            cacheFailedQuery(q, enhancedError);
            throw new Error(enhancedError);
          }
          throw error;
        }
      }
      
      res.json(scryfallCard);
    } else {
      // Multiple random cards - return as list
      const cards = [];
      const seenCardIds = new Set(); // Track card IDs to avoid duplicates
      
      if (USE_BULK_DATA && bulkData.isLoaded()) {
        // Bulk data - instant responses (with logging suppressed)
        // Try up to numCards * MAX_RETRY_ATTEMPTS_MULTIPLIER attempts to account for duplicates
        const maxAttempts = numCards * MAX_RETRY_ATTEMPTS_MULTIPLIER;
        let attempts = 0;
        
        while (cards.length < numCards && attempts < maxAttempts) {
          attempts++;
          try {
            const card = await bulkData.getRandomCard(q, true);  // suppressLog=true
            if (card && !seenCardIds.has(card.id)) {
              seenCardIds.add(card.id);
              cards.push(card);
            }
          } catch (error) {
            console.warn(`Skipped: ${error.message}`);
          }
        }
        
        if (attempts >= maxAttempts && cards.length < numCards) {
          console.log(`[BulkData] Reached max attempts (${maxAttempts}) with ${cards.length}/${numCards} unique cards`);
        }
        
        // Fallback to API if bulk data didn't return enough cards
        if (cards.length < numCards) {
          console.log(`[Fallback] Bulk data returned ${cards.length} cards, switching to API for remaining ${numCards - cards.length}`);
          try {
            // Get remaining cards from API
            const remaining = numCards - cards.length;
            let apiAttempts = 0;
            const maxApiAttempts = remaining * MAX_RETRY_ATTEMPTS_MULTIPLIER;
            
            while (cards.length < numCards && apiAttempts < maxApiAttempts) {
              apiAttempts++;
              const card = await scryfallLib.getRandomCard(q, true);
              if (card && !seenCardIds.has(card.id)) {
                seenCardIds.add(card.id);
                cards.push(card);
              }
            }
          } catch (error) {
            console.warn(`API fallback failed: ${error.message}`);
          }
        }
      } else {
        // API - Test first request to validate query before fetching all cards
        // If query is malformed, this fails fast instead of wasting API calls
        let firstCard;
        try {
          firstCard = await scryfallLib.getRandomCard(q);
          seenCardIds.add(firstCard.id);
          cards.push(firstCard);
        } catch (error) {
          // First request failed - likely invalid query
          if (error.response?.status === 404) {
            const hint = getQueryHint(q);

            const enhancedError = `Invalid search query: "${q}"${hint}. No cards match this query.`;
            cacheFailedQuery(q, enhancedError);
            throw new Error(enhancedError);
          }
          throw error;
        }
        
        // First card succeeded, fetch the rest in parallel with deduplication
        if (numCards > 1) {
          console.log(`Fetching ${numCards - 1} additional random cards (logs suppressed)...`);
          const cardPromises = [];
          const fetchStartTime = Date.now();
          const baseDelay = 100; // Base delay in ms between request starts
          
          // Request extra cards to account for potential duplicates
          const cardsToFetch = Math.ceil((numCards - 1) * DUPLICATE_BUFFER_MULTIPLIER);
          
          for (let i = 0; i < cardsToFetch; i++) {
            // Stagger request starts to spread load and avoid overwhelming rate limits
            // Use linear staggering to space out requests evenly
            const staggerDelay = i * baseDelay;
            
            const promise = new Promise(resolve => {
              setTimeout(async () => {
                try {
                  // Suppress individual API call logs for bulk operations
                  const scryfallCard = await scryfallLib.getRandomCard(q, true);
                  resolve(scryfallCard);
                } catch (error) {
                  console.warn(`Random card ${i + 1} failed: ${error.message}`);
                  resolve(null);
                }
              }, staggerDelay);
            });
            cardPromises.push(promise);
          }
          const results = await Promise.all(cardPromises);
          
          // Calculate failures from results and deduplicate
          let failedCount = 0;
          let duplicateCount = 0;
          
          for (const card of results) {
            if (card === null) {
              failedCount++;
            } else if (cards.length < numCards) {
              if (!seenCardIds.has(card.id)) {
                seenCardIds.add(card.id);
                cards.push(card);
              } else {
                duplicateCount++;
              }
            } else {
              // Already have enough unique cards, count any remaining as excess
              duplicateCount++;
            }
          }
          
          const fetchDuration = Date.now() - fetchStartTime;
          console.log(`Bulk random completed: ${cards.length}/${numCards} unique cards fetched in ${fetchDuration}ms (${failedCount} failed, ${duplicateCount} duplicates/excess skipped)`);
        }
      }
      
      res.json({
        object: 'list',
        total_cards: cards.length,
        data: cards
      });
    }
  } catch (error) {
    console.error('Error getting random cards:', error.message);
    console.error('Error details:', {
      status: error.response?.status,
      statusText: error.response?.statusText,
      data: error.response?.data,
      query: req.query
    });
    
    // Note: Failed queries are now cached at the point of failure (single card or bulk)
    // This ensures the enhanced error message is what gets cached
    
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /search
 * Search for cards - returns Scryfall list format
 * Uses bulk data if available, falls back to API
 */
app.get('/search', async (req, res) => {
  try {
    const { q, limit = 100, unique } = req.query;

    if (!q) {
      return res.status(400).json({ error: 'Query required' });
    }

    // Security: Validate input length
    if (q.length > MAX_INPUT_LENGTH) {
      return res.status(400).json({ 
        error: `Query too long (max ${MAX_INPUT_LENGTH} characters)` 
      });
    }

    const requestedUnique = unique || (q && q.toLowerCase().includes('oracleid:') ? 'prints' : 'cards');
    // Security: Enforce maximum limit to prevent memory exhaustion
    const limitNum = Math.min(parseInt(limit) || 100, MAX_SEARCH_LIMIT);
    
    let scryfallCards = null;
    
    // For full printings list, prefer live API to ensure completeness
    if (requestedUnique === 'prints') {
      scryfallCards = await scryfallLib.searchCards(q, limitNum, requestedUnique);
    } else if (USE_BULK_DATA && bulkData.isLoaded()) {
      scryfallCards = await bulkData.searchCards(q, limitNum);
      
      // Fallback to API if bulk data returned null (no matches)
      if (!scryfallCards) {
        console.log(`[Fallback] Bulk data returned no results for "${q}", using API`);
        scryfallCards = await scryfallLib.searchCards(q, limitNum, requestedUnique);
      }
    } else {
      scryfallCards = await scryfallLib.searchCards(q, limitNum, requestedUnique);
    }
    
    // Ensure scryfallCards is an array
    if (!scryfallCards) {
      scryfallCards = [];
    }
    
    if (scryfallCards.length === 0) {
      return res.json({ 
        object: 'list',
        total_cards: 0,
        data: []
      });
    }

    // Return Scryfall list format
    res.json({
      object: 'list',
      total_cards: scryfallCards.length,
      has_more: false,
      data: scryfallCards
    });
  } catch (error) {
    console.error('Error searching cards:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /rulings/:name
 * Get card rulings from Scryfall - returns Scryfall list format
 */
app.get('/rulings/:name', async (req, res) => {
  try {
    const { name } = req.params;

    if (!name) {
      return res.status(400).json({ error: 'Card name required' });
    }

    const rulings = await scryfallLib.getCardRulings(name);
    
    // Return Scryfall rulings format
    res.json({
      object: 'list',
      has_more: false,
      data: rulings
    });
  } catch (error) {
    console.error('Error fetching rulings:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /tokens/:name
 * Get tokens associated with a card - returns array of Scryfall cards
 */
app.get('/tokens/:name', async (req, res) => {
  try {
    const { name } = req.params;

    if (!name) {
      return res.status(400).json({ error: 'Card name required' });
    }

    let tokens = null;
    if (USE_BULK_DATA && bulkData.isLoaded()) {
      tokens = await getTokensFromBulkData(name);
    }
    if (tokens === null) {
      tokens = await scryfallLib.getTokens(name);
    }
    
    // Return array of Scryfall token cards
    res.json(tokens);
  } catch (error) {
    console.error('Error fetching tokens:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /printings/:name
 * Get all printings of a card - returns Scryfall list format
 */
app.get('/printings/:name', async (req, res) => {
  try {
    const { name } = req.params;

    if (!name) {
      return res.status(400).json({ error: 'Card name required' });
    }

    const printings = await scryfallLib.getPrintings(name);
    
    // Return Scryfall list format with full card data
    res.json({
      object: 'list',
      total_cards: printings.length,
      has_more: false,
      data: printings
    });
  } catch (error) {
    console.error('Error fetching printings:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /sets/:code
 * Get set information by set code - returns raw Scryfall set object
 */
app.get('/sets/:code', async (req, res) => {
  try {
    const { code } = req.params;

    if (!code) {
      return res.status(400).json({ error: 'Set code required' });
    }

    const setData = await scryfallLib.getSet(code);
    
    // Return raw Scryfall set format
    res.json(setData);
  } catch (error) {
    console.error('Error fetching set:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /bulk/stats
 * Get bulk data statistics
 */
app.get('/bulk/stats', (req, res) => {
  const stats = bulkData.getStats();
  res.json({
    ...stats,
    enabled: USE_BULK_DATA,
    fileSizeMB: stats.fileSize ? (stats.fileSize / 1024 / 1024).toFixed(2) : 0
  });
});

/**
 * POST /bulk/reload
 * Manually trigger bulk data reload
 */
app.post('/bulk/reload', async (req, res) => {
  try {
    if (!USE_BULK_DATA) {
      return res.status(400).json({ error: 'Bulk data not enabled' });
    }
    
    console.log('[API] Manual bulk data reload requested');
    await bulkData.downloadBulkData();
    await bulkData.loadBulkData();
    
    res.json({
      success: true,
      message: 'Bulk data reloaded',
      stats: bulkData.getStats()
    });
  } catch (error) {
    console.error('Error reloading bulk data:', error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /proxy?uri=...
 * Proxy a Scryfall API URI through the backend
 * Used for fetching related cards (tokens, etc.) via their API URIs
 */
app.get('/proxy', async (req, res) => {
  try {
    const { uri } = req.query;
    
    if (!uri) {
      return res.status(400).json({ 
        object: 'error', 
        details: 'Missing uri parameter' 
      });
    }
    
    // Validate it's a Scryfall API URL
    if (!uri.startsWith('https://api.scryfall.com/')) {
      return res.status(400).json({ 
        object: 'error', 
        details: 'Invalid URI - must be a Scryfall API URL' 
      });
    }

    // Block expensive/abuse parameters
    const blockedParams = [
      'include_extras=true',
      'include_multilingual=true',
      'order=released',  // Can return thousands
      'order=added',     // Can return thousands
    ];
    const isBlocked = blockedParams.some(param => uri.includes(param));
    if (isBlocked) {
      return res.status(400).json({ 
        object: 'error', 
        details: 'Parameter not allowed in proxied requests' 
      });
    }
    
    const bulkCard = getBulkCardFromUri(uri);
    if (bulkCard) {
      return res.json(bulkCard);
    }

    const cardData = await scryfallLib.proxyUri(uri);
    res.json(cardData);
    
  } catch (error) {
    console.error('[Proxy] Error:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details, status });
  }
});

/**
 * Error handler
 */
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ 
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// Start server with bulk data initialization
// Only start the server if not in test environment
let server;
if (process.env.NODE_ENV !== 'test') {
  server = app.listen(PORT, '0.0.0.0', async () => {
    console.log(`MTG Card Importer Backend running on port ${PORT}`);
    console.log(`Worker PID: ${process.pid}`);
    console.log(`Health check: http://localhost:${PORT}/`);
    console.log(`Metrics: http://localhost:${PORT}/metrics`);
    console.log(`Readiness probe: http://localhost:${PORT}/ready`);
    console.log(`Bulk data enabled: ${USE_BULK_DATA}`);
    
    if (USE_BULK_DATA) {
      console.log('[Init] Loading bulk data in background...');
      bulkData.loadBulkData()
        .then(() => {
          console.log('[Init] Bulk data ready!');
        })
        .catch((error) => {
          console.error('[Init] Failed to load bulk data, falling back to API mode:', error.message);
          console.error('[Init] Server will continue using Scryfall API');
        });
    } else {
      console.log('[Init] Using Scryfall API mode');
    }
  });

  // Configure server timeouts for high concurrency
  server.keepAliveTimeout = 65000; // 65 seconds (higher than common LB timeout of 60s)
  server.headersTimeout = 66000; // Slightly higher than keepAliveTimeout
  server.requestTimeout = 120000; // 2 minutes for long-running deck builds

  // Graceful shutdown handler
  const gracefulShutdown = (signal) => {
    console.log(`\n[Shutdown] Received ${signal}, starting graceful shutdown...`);
    
    server.close(() => {
      console.log('[Shutdown] Server closed, no longer accepting connections');
      console.log('[Shutdown] Exiting process');
      process.exit(0);
    });

    // Force shutdown after 30 seconds if graceful shutdown hangs
    setTimeout(() => {
      console.error('[Shutdown] Graceful shutdown timeout, forcing exit');
      process.exit(1);
    }, 30000);
  };

  process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
  process.on('SIGINT', () => gracefulShutdown('SIGINT'));
}

// Export app for testing
module.exports = app;
