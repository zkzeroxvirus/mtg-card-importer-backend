import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
// Avoid JSON import for broad Node compatibility
const VERSION = '0.1.0';
import { getCard, convertToTTSCard, parseDecklist, searchCards, randomCards, convertToSpawnObject } from './lib/scryfall.js';

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
    const count = Math.min(parseInt(req.query.count || '1', 10), 20);
    const q = req.query.q;
    const cards = await randomCards(count, q);
    const list = cards.map(c => convertToTTSCard(c, DEFAULT_CARD_BACK));
    res.json(list);
  } catch (err) {
    res.status(500).json({ error: 'Random fetch failed', details: err.message || String(err) });
  }
});

app.get('/search', async (req, res) => {
  try {
    const q = String(req.query.q || '').trim();
    if (!q) return res.status(400).json({ error: 'Missing query param q' });
    const cards = await searchCards(q);
    const list = cards.map(c => convertToTTSCard(c, DEFAULT_CARD_BACK));
    res.json(list);
  } catch (err) {
    res.status(500).json({ error: 'Search failed', details: err.message || String(err) });
  }
});

app.listen(PORT, () => {
  console.log(`[mtg-card-importer] listening on :${PORT}`);
});
