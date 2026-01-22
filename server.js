const express = require('express');
const cors = require('cors');
require('dotenv').config();

const scryfallLib = require('./lib/scryfall');

const app = express();
const PORT = process.env.PORT || 3000;
const DEFAULT_BACK = process.env.DEFAULT_CARD_BACK;

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

    // Return wrapped format with card metadata + TTS object
    res.json({
      name: scryfallCard.name,
      set: scryfallCard.set,
      collector_number: scryfallCard.collector_number,
      image_url: scryfallLib.getCardImageUrl(scryfallCard),
      scryfall_id: scryfallCard.id,
      tts: ttsCard
    });
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
          
          // Wrap in format with metadata + TTS
          const cardData = {
            name: scryfallCard.name,
            set: scryfallCard.set,
            collector_number: scryfallCard.collector_number,
            image_url: scryfallLib.getCardImageUrl(scryfallCard),
            scryfall_id: scryfallCard.id,
            tts: ttsCard
          };
          
          res.write(JSON.stringify(cardData) + '\n');
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
    const numCards = Math.min(parseInt(count) || 1, 10); // Max 10

    const cards = [];

    for (let i = 0; i < numCards; i++) {
      try {
        const scryfallCard = await scryfallLib.getRandomCard(q);
        const ttsCard = scryfallLib.convertToTTSCard(scryfallCard, cardBack);
        
        // Wrap in format with metadata + TTS
        cards.push({
          name: scryfallCard.name,
          set: scryfallCard.set,
          collector_number: scryfallCard.collector_number,
          image_url: scryfallLib.getCardImageUrl(scryfallCard),
          scryfall_id: scryfallCard.id,
          tts: ttsCard
        });
      } catch (error) {
        console.warn(`Random card failed: ${error.message}`);
      }
    }

    res.json(cards);
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

    const cards = scryfallCards.map(card => {
      try {
        const ttsCard = scryfallLib.convertToTTSCard(card, cardBack);
        return {
          name: card.name,
          set: card.set,
          collector_number: card.collector_number,
          image_url: scryfallLib.getCardImageUrl(card),
          scryfall_id: card.id,
          tts: ttsCard
        };
      } catch (error) {
        console.warn(`Skipped card in search: ${card.name}`);
        return null;
      }
    }).filter(card => card !== null);

    res.json(cards);
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
