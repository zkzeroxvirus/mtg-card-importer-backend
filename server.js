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
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

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
 * Returns NDJSON (newline-delimited JSON)
 */
app.post('/deck', async (req, res) => {
  try {
    const { decklist, back } = req.body;
    const cardBack = back || DEFAULT_BACK;

    if (!decklist) {
      return res.status(400).json({ error: 'Decklist required' });
    }

    const cards = scryfallLib.parseDecklist(decklist);
    
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
    const { data, back, hand } = req.body;
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

    if (numCards === 1) {
      // Single random card
      let scryfallCard;
      
      if (USE_BULK_DATA && bulkData.isLoaded()) {
        scryfallCard = bulkData.getRandomCard(q);
      } else {
        scryfallCard = await scryfallLib.getRandomCard(q);
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
        // API - rate limited
        for (let i = 0; i < numCards; i++) {
          try {
            const scryfallCard = await scryfallLib.getRandomCard(q);
            cards.push(scryfallCard);
          } catch (error) {
            console.warn(`Random card failed: ${error.message}`);
          }
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
    res.status(500).json({ object: 'error', details: error.message });
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
    try {
      console.log('[Init] Loading bulk data...');
      await bulkData.loadBulkData();
      bulkData.scheduleUpdateCheck();
      console.log('[Init] Bulk data ready!');
    } catch (error) {
      console.error('[Init] Failed to load bulk data, falling back to API mode:', error.message);
      console.error('[Init] Server will continue using Scryfall API');
    }
  } else {
    console.log('[Init] Using Scryfall API mode');
  }
});
