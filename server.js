const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const scryfallLib = require('./lib/scryfall');
const bulkData = require('./lib/bulk-data');

const app = express();
const PORT = process.env.PORT || 3000;
const DEFAULT_BACK = process.env.DEFAULT_CARD_BACK || 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';
const USE_BULK_DATA = process.env.USE_BULK_DATA === 'true';
const MAX_DECK_SIZE = parseInt(process.env.MAX_DECK_SIZE || '500');

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
app.use(express.raw({ limit: '10mb' }));  // Accept raw body as Buffer, parse manually

/**
 * Analyzes a Scryfall query and provides helpful hints for common syntax errors
 */
function getQueryHint(query) {
  const q = query.toLowerCase();
  
  // Common keyword mistakes - missing colons
  const keywordPatterns = [
    { pattern: /\bcmc\d/, correct: 'cmc:', example: 'cmc:3', desc: 'mana value' },
    { pattern: /\bmv\d/, correct: 'mv:', example: 'mv:3', desc: 'mana value' },
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
  
  // Check for comparison operators without colons
  if (/\b(cmc|mv|pow|power|tou|toughness|loy|loyalty)[<>=]/.test(q)) {
    const match = q.match(/\b(cmc|mv|pow|power|tou|toughness|loy|loyalty)([<>=]+)/);
    if (match) {
      return ` (Did you mean "${match[1]}:${match[2]}"? Comparison operators need a colon)`;
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
  
  // Clean up old entries periodically
  if (failedQueryCache.size > 100) {
    const now = Date.now();
    for (const [key, value] of failedQueryCache.entries()) {
      if (now - value.timestamp > FAILED_QUERY_CACHE_TTL) {
        failedQueryCache.delete(key);
      }
    }
  }
}

// Health check
app.get('/', (req, res) => {
  const bulkStats = bulkData.getStats();
  res.json({
    status: 'ok',
    service: 'MTG Card Importer Backend',
    version: '1.0.0',
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
      bulkStats: 'GET /bulk/stats'
    }
  });
});

/**
 * GET /card/:name
 * Get a single card - returns raw Scryfall JSON
 * Uses bulk data if available (exact name match only), falls back to API for fuzzy search
 */
app.get('/card/:name', async (req, res) => {
  try {
    const { name } = req.params;
    const { set } = req.query;

    if (!name) {
      return res.status(400).json({ error: 'Card name required' });
    }

    let scryfallCard;
    
    // Bulk data only supports exact name matching, API supports fuzzy matching
    if (USE_BULK_DATA && bulkData.isLoaded() && !set) {
      scryfallCard = bulkData.getCardByName(name);
      if (!scryfallCard) {
        // Fall back to API for fuzzy matching
        scryfallCard = await scryfallLib.getCard(name, set);
      }
    } else {
      scryfallCard = await scryfallLib.getCard(name, set);
    }
    
    // Return raw Scryfall format - Lua code will convert to TTS
    res.json(scryfallCard);
  } catch (error) {
    console.error('Error fetching card:', error.message);
    res.status(404).json({ object: 'error', details: error.message });
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

    const scryfallCard = await scryfallLib.getCardById(id);
    
    // Return raw Scryfall format
    res.json(scryfallCard);
  } catch (error) {
    console.error('Error fetching card by ID:', error.message);
    res.status(404).json({ object: 'error', details: error.message });
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

    const scryfallCard = await scryfallLib.getCardBySetNumber(set, number, lang || 'en');
    
    // Return raw Scryfall format
    res.json(scryfallCard);
  } catch (error) {
    console.error('Error fetching card by set/number:', error.message);
    res.status(404).json({ object: 'error', details: error.message });
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

    // Try to parse as JSON
    if (bodyText.trim().startsWith('{')) {
      try {
        const parsed = JSON.parse(bodyText);
        data = parsed.data;
        back = parsed.back;
        hand = parsed.hand;
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
 * GET /random
 * Get random card(s) - returns raw Scryfall card or list
 * Uses bulk data if available, falls back to API
 * Rate limited: 50 bulk requests per minute per IP
 */
app.get('/random', randomLimiter, async (req, res) => {
  try {
    const { count, q = '' } = req.query;
    const numCards = count ? Math.min(parseInt(count) || 1, 100) : 1;
    
    console.log(`GET /random - count: ${numCards}, query: "${q}"`);

    // Check if this query recently failed
    if (q) {
      const cachedError = isQueryCachedAsFailed(q);
      if (cachedError) {
        console.log(`Returning cached error for query: "${q}"`);
        return res.status(400).json({ object: 'error', details: cachedError });
      }
    }

    if (numCards === 1) {
      // Single random card
      let scryfallCard;
      
      if (USE_BULK_DATA && bulkData.isLoaded()) {
        scryfallCard = bulkData.getRandomCard(q);
      } else {
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
      
      if (USE_BULK_DATA && bulkData.isLoaded()) {
        // Bulk data - instant responses
        for (let i = 0; i < numCards; i++) {
          try {
            const card = bulkData.getRandomCard(q);
            cards.push(card);
          } catch (error) {
            console.warn(`Random card failed: ${error.message}`);
          }
        }
      } else {
        // API - Test first request to validate query before fetching all cards
        // If query is malformed, this fails fast instead of wasting API calls
        let firstCard;
        try {
          firstCard = await scryfallLib.getRandomCard(q);
          cards.push(firstCard);
        } catch (error) {
          // First request failed - likely invalid query
          if (error.response?.status === 404) {
            const hint = getQueryHint(q);
            throw new Error(`Invalid search query: "${q}"${hint}. No cards match this query.`);
          }
          throw error;
        }
        
        // First card succeeded, fetch the rest in parallel
        if (numCards > 1) {
          const cardPromises = [];
          for (let i = 1; i < numCards; i++) {
            // Stagger request starts slightly to spread load without blocking
            const promise = new Promise(resolve => {
              setTimeout(async () => {
                try {
                  const scryfallCard = await scryfallLib.getRandomCard(q);
                  resolve(scryfallCard);
                } catch (error) {
                  console.warn(`Random card ${i + 1} failed: ${error.message}`);
                  resolve(null);
                }
              }, i * 15); // 15ms stagger between request initiations
            });
            cardPromises.push(promise);
          }
          const results = await Promise.all(cardPromises);
          results.forEach(card => {
            if (card) cards.push(card);
          });
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
    
    res.status(error.response?.status || 400).json({ object: 'error', details: error.message });
  }
});

/**
 * GET /search
 * Search for cards - returns Scryfall list format
 * Uses bulk data if available, falls back to API
 */
app.get('/search', async (req, res) => {
  try {
    const { q, limit = 100 } = req.query;

    if (!q) {
      return res.status(400).json({ error: 'Query required' });
    }

    let scryfallCards;
    
    if (USE_BULK_DATA && bulkData.isLoaded()) {
      scryfallCards = bulkData.searchCards(q, parseInt(limit));
    } else {
      scryfallCards = await scryfallLib.searchCards(q, parseInt(limit));
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
    res.status(500).json({ object: 'error', details: error.message });
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
    res.status(404).json({ object: 'error', details: error.message });
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

    const tokens = await scryfallLib.getTokens(name);
    
    // Return array of Scryfall token cards
    res.json(tokens);
  } catch (error) {
    console.error('Error fetching tokens:', error.message);
    res.status(404).json({ object: 'error', details: error.message });
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
    res.status(404).json({ object: 'error', details: error.message });
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
    res.status(404).json({ object: 'error', details: error.message });
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
    
    const cardData = await scryfallLib.proxyUri(uri);
    res.json(cardData);
    
  } catch (error) {
    console.error('[Proxy] Error:', error.message);
    res.status(error.status || 500).json({
      object: 'error',
      status: error.status || 500,
      details: error.message
    });
  }
});

/**
 * Error handler
 */
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ 
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// Start server with bulk data initialization
app.listen(PORT, async () => {
  console.log(`MTG Card Importer Backend running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/`);
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
