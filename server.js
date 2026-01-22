const express = require('express');
const cors = require('cors');
require('dotenv').config();

const scryfallLib = require('./lib/scryfall');

const app = express();
const PORT = process.env.PORT || 3000;
const DEFAULT_BACK = process.env.DEFAULT_CARD_BACK || 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';

// Middleware
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb' }));

// Health check
app.get('/', (req, res) => {
  res.json({
    status: 'ok',
    service: 'MTG Card Importer Backend',
    version: '1.0.0',
    endpoints: {
      card: 'GET /card/:name',
      deck: 'POST /deck',
      random: 'GET /random',
      search: 'GET /search'
    }
  });
});

/**
 * GET /card/:name
 * Get a single card - returns raw Scryfall JSON
 */
app.get('/card/:name', async (req, res) => {
  try {
    const { name } = req.params;
    const { set } = req.query;

    if (!name) {
      return res.status(400).json({ error: 'Card name required' });
    }

    const scryfallCard = await scryfallLib.getCard(name, set);
    
    // Return raw Scryfall format - Lua code will convert to TTS
    res.json(scryfallCard);
  } catch (error) {
    console.error('Error fetching card:', error.message);
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
 */
app.get('/random', async (req, res) => {
  try {
    const { count, q = '' } = req.query;
    const numCards = count ? Math.min(parseInt(count) || 1, 100) : 1;

    if (numCards === 1) {
      // Single random card
      const scryfallCard = await scryfallLib.getRandomCard(q);
      res.json(scryfallCard);
    } else {
      // Multiple random cards - return as list
      const cards = [];
      for (let i = 0; i < numCards; i++) {
        try {
          const scryfallCard = await scryfallLib.getRandomCard(q);
          cards.push(scryfallCard);
        } catch (error) {
          console.warn(`Random card failed: ${error.message}`);
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
 * Search for cards
 */
app.get('/search',  - returns Scryfall list format
 */
app.get('/search', async (req, res) => {
  try {
    const { q, limit = 100 } = req.query;

    if (!q) {
      return res.status(400).json({ error: 'Query required' });
    }

    const scryfallCards = await scryfallLib.searchCards(q, parseInt(limit));
    
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
    }); - returns Scryfall list format
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
    res.status(404).json({ object: 'error', detailsn({ error: 'Card name required' });
    }

    const rulings = await scryfallLib.getCardRulings(name);
    res.json(rulings);
  } catch (error) {
    console.error('Error fetching ru - returns array of Scryfall cards
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
    res.status(404).json({ object: 'error', details
      }
    }).filter(token => token !== null);

    res.json(ttsTokens);
  } catch (error) {
    console.error('Error fetching tokens:', error.message);
    res.status(404).json({ error: error.message });
  }
});

/**
 * GET /printings/:name
 * Get all printings of a card
 */
app.get('/printings/:name', async (req, res) => {
  try {
    const { name } = req.params;
    const { back } = req.query;
    const cardBack = back || DEFAULT_BACK;

    if (!name) { - returns Scryfall list format
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
    res.status(404).json({ object: 'error', details:', err);
  res.status(500).json({ 
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`MTG Card Importer Backend running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`Scryfall delay: ${process.env.SCRYFALL_DELAY || 100}ms`);
});
