import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
// Avoid JSON import for broad Node compatibility
const VERSION = '0.1.0';
import { getCard, convertToTTSCard, parseDecklist, searchCards, randomCards, convertToSpawnObject, autocompleteCards, getSets, getSet, getRulingsById, getCollection, getCatalog } from './lib/scryfall.js';

dotenv.config();
const app = express();
app.use(cors());
app.use(express.json({ limit: '1mb' }));

const PORT = process.env.PORT || 3000;
const DEFAULT_CARD_BACK = process.env.DEFAULT_CARD_BACK || 'https://via.placeholder.com/512x512.png?text=Card+Back';

app.get('/', (req, res) => {
  res.json({ ok: true, service: 'mtg-card-importer-backend', version: VERSION, uptime: process.uptime() });
});

app.get('/card/:name', async (req, res) => {
  try {
    const name = req.params.name;
    const set = req.query.set;
    const card = await getCard(name, set);
    const tts = convertToTTSCard(card, DEFAULT_CARD_BACK);
    res.json(tts);
  } catch (err) {
    res.status(404).json({ error: 'Card not found', details: err.message || String(err) });
  }
});

app.post('/deck', async (req, res) => {
  const decklistText = req.body.decklist;
  const set = req.body.set;
  if (!decklistText || typeof decklistText !== 'string') {
    return res.status(400).json({ error: 'Missing decklist string in body' });
  }
  const items = parseDecklist(decklistText);
  res.type('application/x-ndjson');
  for (const item of items) {
    for (let i = 0; i < item.count; i++) {
      try {
        const card = await getCard(item.name, set);
        const tts = convertToTTSCard(card, DEFAULT_CARD_BACK);
        res.write(JSON.stringify(tts) + '\n');
      } catch (err) {
        res.write(JSON.stringify({ error: 'Card not found', name: item.name }) + '\n');
      }
    }
  }
  res.end();
});

// DeckDraftCube-compatible build endpoint
// Accepts { data: string, hand: { position, rotation }, backURL?: string, useStates?: boolean, lang?: string }
// Returns NDJSON of spawnable TTS objects
app.post('/build', async (req, res) => {
  try {
    const data = req.body.data;
    const hand = req.body.hand;
    const set = req.body.set;
    const backURL = req.body.backURL || DEFAULT_CARD_BACK;
    if (!data || typeof data !== 'string') {
      return res.status(400).json({ error: 'Missing data string in body' });
    }
    res.type('application/x-ndjson');
    const isDeck = /\r?\n/.test(data.trim());
    if (isDeck) {
      const items = parseDecklist(data);
      for (const item of items) {
        for (let i = 0; i < item.count; i++) {
          try {
            const card = await getCard(item.name, set);
            const obj = convertToSpawnObject(card, backURL, hand);
            res.write(JSON.stringify(obj) + '\n');
          } catch (err) {
            res.write(JSON.stringify({ error: 'Card not found', name: item.name }) + '\n');
          }
        }
      }
      res.end();
      return;
    }
    // Single card
    try {
      const card = await getCard(data.trim(), set);
      const obj = convertToSpawnObject(card, backURL, hand);
      res.write(JSON.stringify(obj) + '\n');
    } catch (err) {
      res.write(JSON.stringify({ error: 'Card not found', name: data.trim() }) + '\n');
    }
    res.end();
  } catch (err) {
    res.status(500).json({ error: 'Build failed', details: err.message || String(err) });
  }
});

app.get('/random', async (req, res) => {
  try {
    const count = Math.min(parseInt(req.query.count || '1', 10), 100);
    const q = req.query.q;
    const format = String(req.query.format || 'tts');
    const backURL = req.query.backURL || DEFAULT_CARD_BACK;
    const cards = await randomCards(count, q);
    if (format === 'raw') return res.json(cards);
    if (format === 'spawn') {
      const hand = req.query.hand ? JSON.parse(req.query.hand) : undefined;
      const list = cards.map(c => convertToSpawnObject(c, backURL, hand));
      return res.json(list);
    }
    const list = cards.map(c => convertToTTSCard(c, backURL));
    res.json(list);
  } catch (err) {
    res.status(500).json({ error: 'Random fetch failed', details: err.message || String(err) });
  }
});

app.get('/search', async (req, res) => {
  try {
    const q = String(req.query.q || '').trim();
    if (!q) return res.status(400).json({ error: 'Missing query param q' });
    const format = String(req.query.format || 'tts');
    const backURL = req.query.backURL || DEFAULT_CARD_BACK;
    const cards = await searchCards(q);
    if (format === 'raw') return res.json(cards);
    if (format === 'spawn') {
      const hand = req.query.hand ? JSON.parse(req.query.hand) : undefined;
      const list = cards.map(c => convertToSpawnObject(c, backURL, hand));
      return res.json(list);
    }
    const list = cards.map(c => convertToTTSCard(c, backURL));
    res.json(list);
  } catch (err) {
    res.status(500).json({ error: 'Search failed', details: err.message || String(err) });
  }
});

// Autocomplete
app.get('/autocomplete', async (req, res) => {
  try {
    const q = String(req.query.q || '').trim();
    if (!q) return res.status(400).json({ error: 'Missing query param q' });
    const list = await autocompleteCards(q);
    res.json(list);
  } catch (err) {
    res.status(500).json({ error: 'Autocomplete failed', details: err.message || String(err) });
  }
});

// Sets
app.get('/sets', async (_req, res) => {
  try {
    const sets = await getSets();
    res.json(sets);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch sets', details: err.message || String(err) });
  }
});
app.get('/sets/:code', async (req, res) => {
  try {
    const code = req.params.code;
    const set = await getSet(code);
    res.json(set);
  } catch (err) {
    res.status(404).json({ error: 'Set not found', details: err.message || String(err) });
  }
});

// Rulings
app.get('/rulings/:id', async (req, res) => {
  try {
    const id = req.params.id;
    const rulings = await getRulingsById(id);
    res.json(rulings);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch rulings', details: err.message || String(err) });
  }
});

// Collection (identifiers)
app.post('/collection', async (req, res) => {
  try {
    const identifiers = req.body.identifiers;
    const format = String(req.query.format || 'tts');
    const backURL = req.body.backURL || req.query.backURL || DEFAULT_CARD_BACK;
    if (!Array.isArray(identifiers) || identifiers.length === 0) {
      return res.status(400).json({ error: 'Missing identifiers array in body' });
    }
    const cards = await getCollection(identifiers);
    if (format === 'raw') return res.json(cards);
    const list = cards.map(c => (format === 'spawn') ? convertToSpawnObject(c, backURL, req.body.hand) : convertToTTSCard(c, backURL));
    res.json(list);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch collection', details: err.message || String(err) });
  }
});

// Catalog
app.get('/catalog/:type', async (req, res) => {
  try {
    const type = req.params.type;
    const items = await getCatalog(type);
    res.json(items);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch catalog', details: err.message || String(err) });
  }
});

app.listen(PORT, () => {
  console.log(`[mtg-card-importer] listening on :${PORT}`);
});
