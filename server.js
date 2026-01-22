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
 * Get a single card
 */
app.get('/card/:name', async (req, res) => {
  try {
    const { name } = req.params;
    const { set, back } = req.query;
    const cardBack = back || DEFAULT_BACK;

    if (!name) {
      return res.status(400).json({ error: 'Card name required' });
    }

    const scryfallCard = await scryfallLib.getCard(name, set);
    const ttsCard = scryfallLib.convertToTTSCard(scryfallCard, cardBack);

    // Return just the TTS object (no wrapping)
    res.json(ttsCard);
  } catch (error) {
    console.error('Error fetching card:', error.message);
    res.status(404).json({ error: error.message });
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
 * GET /random
 * Get random card(s) - returns JSON array
 */
app.get('/random', async (req, res) => {
  try {
    const { count = 1, back, q = '' } = req.query;
    const cardBack = back || DEFAULT_BACK;
    const numCards = Math.min(parseInt(count) || 1, 100); // Max 100

    const ttsCards = [];

    for (let i = 0; i < numCards; i++) {
      try {
        const scryfallCard = await scryfallLib.getRandomCard(q);
        const ttsCard = scryfallLib.convertToTTSCard(scryfallCard, cardBack);
        ttsCards.push(ttsCard);
      } catch (error) {
        console.warn(`Random card failed: ${error.message}`);
      }
    }

    res.json(ttsCards);
  } catch (error) {
    console.error('Error getting random cards:', error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /search
 * Search for cards
 */
app.get('/search', async (req, res) => {
  try {
    const { q, limit = 10, back } = req.query;
    const cardBack = back || DEFAULT_BACK;

    if (!q) {
      return res.status(400).json({ error: 'Query required' });
    }

    const scryfallCards = await scryfallLib.searchCards(q, parseInt(limit));
    
    if (scryfallCards.length === 0) {
      return res.status(404).json({ error: 'No cards found' });
    }

    const ttsCards = scryfallCards.map(card => {
      try {
        return scryfallLib.convertToTTSCard(card, cardBack);
      } catch (error) {
        console.warn(`Skipped card in search: ${card.name}`);
        return null;
      }
    }).filter(card => card !== null);

    res.json(ttsCards);
  } catch (error) {
    console.error('Error searching cards:', error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /rulings/:cardId
 * Get card rulings from Scryfall
 */
app.get('/rulings/:cardId', async (req, res) => {
  try {
    const { cardId } = req.params;

    if (!cardId) {
      return res.status(400).json({ error: 'Card ID required' });
    }

    const rulings = await scryfallLib.getCardRulings(cardId);
    res.json(rulings);
  } catch (error) {
    console.error('Error fetching rulings:', error.message);
    res.status(404).json({ error: error.message });
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

// Start server
app.listen(PORT, () => {
  console.log(`MTG Card Importer Backend running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`Scryfall delay: ${process.env.SCRYFALL_DELAY || 100}ms`);
});
