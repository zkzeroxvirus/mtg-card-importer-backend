/**
 * Integration tests for server endpoints
 * Tests API endpoints, error handling, and validation
 */

const request = require('supertest');

// Mock environment variables before requiring the server
process.env.NODE_ENV = 'test';
process.env.DEFAULT_CARD_BACK = 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';
process.env.USE_BULK_DATA = 'false';

jest.mock('../lib/scryfall', () => {
  let randomCounter = 0;

  const parseDecklist = (decklistText) => {
    const cards = [];
    const lines = String(decklistText || '').split('\n');

    for (let line of lines) {
      line = line.trim();
      if (!line || line.startsWith('//') || line.startsWith('#')) {
        continue;
      }

      const match = line.match(/^(\d+)x?\s+(.+?)(?:\s*\([^)]+\))?(?:\s+\d+)?$/i);
      if (match) {
        cards.push({
          count: parseInt(match[1], 10),
          name: match[2].trim().replace(/\s*\([^)]+\).*$/, '').trim()
        });
      }
    }

    return cards;
  };

  const createCard = (name = 'Mock Card') => ({
    id: `id-${name.toLowerCase().replace(/\s+/g, '-')}`,
    oracle_id: `oracle-${name.toLowerCase().replace(/\s+/g, '-')}`,
    name,
    type_line: 'Creature — Test',
    image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
    games: ['paper']
  });

  return {
    getCard: jest.fn(async (name) => {
      if (/[<>]|\.\.\//.test(String(name || ''))) {
        throw new Error('Invalid card name');
      }
      return createCard(name || 'Mock Card');
    }),
    autocompleteCardName: jest.fn(async () => []),
    getCardById: jest.fn(async (id) => createCard(`Card ${id}`)),
    getCardBySetNumber: jest.fn(async (set, number) => createCard(`${set}-${number}`)),
    searchCards: jest.fn(async (_query, limit = 10) => {
      const size = Math.max(1, Math.min(parseInt(limit, 10) || 10, 1000));
      return Array.from({ length: size }, (_, i) => createCard(`Search Card ${i + 1}`));
    }),
    getRandomCard: jest.fn(async (query = '') => {
      randomCounter += 1;
      return createCard(`Random ${query || 'Card'} ${randomCounter}`);
    }),
    getSet: jest.fn(async (setCode) => {
      if (String(setCode).includes('invalid-set-code')) {
        throw new Error(`Set not found: ${setCode}`);
      }
      return { object: 'set', code: setCode, name: `Set ${setCode}` };
    }),
    getCardRulings: jest.fn(async () => [{ source: 'wotc', comment: 'Mock ruling', published_at: '2024-01-01' }]),
    getTokens: jest.fn(async (name) => [createCard(`${name} Token`)]),
    getPrintings: jest.fn(async (name) => [createCard(name), createCard(`${name} Reprint`)]),
    parseDecklist,
    convertToTTSCard: jest.fn((scryfallCard, cardBack) => ({
      Name: 'Card',
      Nickname: scryfallCard.name,
      Memo: scryfallCard.oracle_id,
      DeckIDs: [100],
      CustomDeck: {
        '1': {
          FaceURL: scryfallCard.image_uris.normal,
          BackURL: cardBack,
          NumWidth: 1,
          NumHeight: 1,
          BackIsHidden: true,
          UniqueBack: false,
          Type: 0
        }
      }
    })),
    getCardImageUrl: jest.fn((card) => card?.image_uris?.normal || null),
    getCardBackUrl: jest.fn((_card, back) => back),
    getOracleText: jest.fn(() => 'Mock oracle text'),
    proxyUri: jest.fn(async (uri) => ({ object: 'card', id: 'proxied', uri })),
    globalQueue: { wait: jest.fn(async () => {}) }
  };
});

const app = require('../server');
const scryfallLib = require('../lib/scryfall');

describe('Server Endpoints - Health Check', () => {
  test('GET / should return 200 status', async () => {
    const response = await request(app).get('/');
    expect(response.status).toBe(200);
  });

  test('GET / should return JSON', async () => {
    const response = await request(app).get('/');
    expect(response.type).toBe('application/json');
  });

  test('GET / should return service status', async () => {
    const response = await request(app).get('/');
    expect(response.body).toHaveProperty('service');
    expect(response.body.service).toBe('MTG Card Importer Backend');
  });

  test('GET / should include endpoints information object', async () => {
    const response = await request(app).get('/');
    expect(response.body).toHaveProperty('endpoints');
    expect(response.body.endpoints).toEqual(expect.objectContaining({
      card: expect.any(String),
      deck: expect.any(String),
      random: expect.any(String),
      search: expect.any(String)
    }));
  });

  test('GET / should include bulkData info', async () => {
    const response = await request(app).get('/');
    expect(response.body).toHaveProperty('bulkData');
    expect(response.body.bulkData).toHaveProperty('enabled');
  });
});

describe('Server Endpoints - Input Validation', () => {
  test('should reject card names that are too long', async () => {
    const longName = 'a'.repeat(10001);
    const response = await request(app).get(`/card/${longName}`);
    expect(response.status).toBe(400);
  });

  test('should reject search queries that are too long', async () => {
    const longQuery = 'a'.repeat(10001);
    const response = await request(app).get('/search').query({ q: longQuery });
    expect(response.status).toBe(400);
  });

  test('should reject invalid card back URLs on /random/build', async () => {
    const response = await request(app)
      .post('/random/build')
      .set('Content-Type', 'application/octet-stream')
      .send(JSON.stringify({
        q: 't:artifact',
        count: 2,
        back: 'http://malicious-site.com/image.jpg'
      }));
    expect(response.status).toBe(400);
    expect(response.body.error).toContain('Invalid card back URL');
  });

  test('should accept valid Steam CDN card back URLs on /random/build', async () => {
    const response = await request(app)
      .post('/random/build')
      .set('Content-Type', 'application/octet-stream')
      .send(JSON.stringify({
        q: 't:artifact',
        count: 2,
        back: 'https://steamusercontent-a.akamaihd.net/ugc/123/image.jpg'
      }));
    expect(response.status).not.toBe(400);
  });

  test('should accept valid Imgur card back URLs on /random/build', async () => {
    const response = await request(app)
      .post('/random/build')
      .set('Content-Type', 'application/octet-stream')
      .send(JSON.stringify({
        q: 't:artifact',
        count: 2,
        back: 'https://i.imgur.com/abc123.jpg'
      }));
    expect(response.status).not.toBe(400);
  });
});

describe('Server Endpoints - Error Responses', () => {
  test('should return 404 for unknown endpoint', async () => {
    const response = await request(app).get('/nonexistent-endpoint');
    expect(response.status).toBe(404);
  });

  test('should return non-200 payload for unknown endpoint', async () => {
    const response = await request(app).get('/nonexistent-endpoint');
    expect(response.status).toBe(404);
    expect(typeof response.text).toBe('string');
  });
});

describe('Server Endpoints - CORS', () => {
  test('should include CORS headers', async () => {
    const response = await request(app).get('/');
    expect(response.headers).toHaveProperty('access-control-allow-origin');
  });
});

describe('Server Endpoints - Deck Building', () => {
  test('POST /deck should return removed status', async () => {
    const response = await request(app)
      .post('/deck')
      .set('Content-Type', 'application/octet-stream')
      .send('{}');
    expect(response.status).toBe(410);
    expect(response.body.details).toContain('removed');
  });

  test('POST /build should return removed status', async () => {
    const response = await request(app)
      .post('/build')
      .set('Content-Type', 'application/octet-stream')
      .send(JSON.stringify({ data: '1 Mountain\n1 Forest' }));
    expect(response.status).toBe(410);
    expect(response.body.details).toContain('removed');
  });

  test('POST /deck/parse should return removed status', async () => {
    const response = await request(app)
      .post('/deck/parse')
      .set('Content-Type', 'application/octet-stream')
      .send('4 Lightning Bolt\n2 Mountain');

    expect(response.status).toBe(410);
    expect(response.body.details).toContain('removed');
  });
});

describe('Server Endpoints - Random Card', () => {
  test('GET /random should accept count parameter', async () => {
    const response = await request(app)
      .get('/random')
      .query({ count: 3 });
    expect(response.status).not.toBe(400);
  });

  test('GET /random should accept query parameter', async () => {
    const response = await request(app)
      .get('/random')
      .query({ q: 't:creature' });
    expect(response.status).not.toBe(400);
  });

  test('GET /random should clamp count over limit', async () => {
    const response = await request(app)
      .get('/random')
      .query({ count: 101, q: 't:creature' });
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('total_cards');
    expect(response.body.total_cards).toBeLessThanOrEqual(100);
  });

  test('GET /random should clamp negative count to valid range', async () => {
    const response = await request(app)
      .get('/random')
      .query({ count: -1 });
    expect(response.status).toBe(200);
  });

  test('GET /random should enforce commander legality in multi-card query mode', async () => {
    scryfallLib.searchCards.mockResolvedValueOnce([
      {
        id: 'id-mana-crypt',
        oracle_id: 'oracle-mana-crypt',
        name: 'Mana Crypt',
        type_line: 'Artifact',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        games: ['paper']
      },
      {
        id: 'id-sol-ring',
        oracle_id: 'oracle-sol-ring',
        name: 'Sol Ring',
        type_line: 'Artifact',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        games: ['paper']
      }
    ]);

    const response = await request(app)
      .get('/random')
      .query({ q: 't:artifact', count: 2 });

    expect(response.status).toBe(200);
    expect(scryfallLib.searchCards).toHaveBeenCalledWith(
      expect.stringContaining('f:commander'),
      2,
      expect.any(String),
      expect.any(String)
    );
  });

  test('GET /random should enforce commander legality in single-card mode', async () => {
    scryfallLib.getRandomCard.mockResolvedValueOnce({
      id: 'id-mana-crypt',
      oracle_id: 'oracle-mana-crypt',
      name: 'Mana Crypt',
      type_line: 'Artifact',
      image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
      games: ['paper']
    });

    const response = await request(app)
      .get('/random')
      .query({ q: 't:artifact', count: 1 });

    expect(response.status).toBe(200);
    expect(scryfallLib.getRandomCard).toHaveBeenCalledWith(expect.stringContaining('f:commander'));
  });

  test('GET /random should normalize f:c shorthand to f:commander', async () => {
    scryfallLib.getRandomCard.mockResolvedValueOnce({
      id: 'id-everflowing-chalice',
      oracle_id: 'oracle-everflowing-chalice',
      name: 'Everflowing Chalice',
      type_line: 'Artifact',
      image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
      games: ['paper']
    });

    const response = await request(app)
      .get('/random')
      .query({ q: 'cmc=0 t:artifact f:c', count: 1 });

    expect(response.status).toBe(200);
    const calledQuery = scryfallLib.getRandomCard.mock.calls.at(-1)[0];
    expect(calledQuery).toContain('f:commander');
    expect(calledQuery).not.toMatch(/\bf:c\b/i);
  });

  test('POST /random/build should return one DeckCustom NDJSON object', async () => {
    scryfallLib.searchCards.mockResolvedValueOnce([
      {
        id: 'id-sol-ring',
        oracle_id: 'oracle-sol-ring',
        name: 'Sol Ring',
        type_line: 'Artifact',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        games: ['paper']
      },
      {
        id: 'id-mana-crypt',
        oracle_id: 'oracle-mana-crypt',
        name: 'Mana Crypt',
        type_line: 'Artifact',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        games: ['paper']
      }
    ]);

    const response = await request(app)
      .post('/random/build')
      .set('Content-Type', 'application/json')
      .send({
        q: 't:artifact',
        count: 2,
        hand: {
          position: { x: 1, y: 2, z: 3 },
          rotation: { x: 0, y: 180, z: 0 }
        }
      });

    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toContain('application/x-ndjson');

    const lines = response.text.split('\n').filter(Boolean).map(line => JSON.parse(line));
    expect(lines).toHaveLength(1);
    expect(lines[0].Name).toBe('DeckCustom');
    expect(Array.isArray(lines[0].ContainedObjects)).toBe(true);
    expect(lines[0].ContainedObjects).toHaveLength(2);
    expect(scryfallLib.searchCards).toHaveBeenCalledWith(
      expect.stringContaining('f:commander'),
      2,
      expect.any(String),
      expect.any(String)
    );
  });

  test('POST /random/build should reject invalid card back URLs', async () => {
    const response = await request(app)
      .post('/random/build')
      .set('Content-Type', 'application/json')
      .send({
        q: 't:artifact',
        count: 2,
        back: 'https://evil-site.com/card-back.jpg'
      });

    expect(response.status).toBe(400);
    expect(response.body).toHaveProperty('error');
  });

  test('POST /random/build should preserve DFC states in DeckCustom output', async () => {
    scryfallLib.searchCards.mockResolvedValueOnce([
      {
        id: 'id-dfc-1',
        oracle_id: 'oracle-dfc-1',
        name: 'Invasion of Zendikar',
        type_line: 'Battle — Siege',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock-front.jpg' },
        games: ['paper']
      }
    ]);

    scryfallLib.convertToTTSCard.mockImplementationOnce((_card, cardBack) => ({
      Name: 'Card',
      Nickname: 'Invasion of Zendikar',
      Description: 'Front text',
      Memo: 'oracle-dfc-1',
      DeckIDs: [100],
      CustomDeck: {
        '1': {
          FaceURL: 'https://cards.scryfall.io/normal/front/0/0/mock-front.jpg',
          BackURL: cardBack,
          NumWidth: 1,
          NumHeight: 1,
          BackIsHidden: true,
          UniqueBack: false
        }
      },
      States: {
        2: {
          Name: 'Card',
          Nickname: 'Awakened Skyclave',
          Description: 'Back text',
          Memo: 'oracle-dfc-1',
          CardID: 200,
          CustomDeck: {
            '2': {
              FaceURL: 'https://cards.scryfall.io/normal/back/0/0/mock-back.jpg',
              BackURL: cardBack,
              NumWidth: 1,
              NumHeight: 1,
              BackIsHidden: true,
              UniqueBack: false
            }
          }
        }
      }
    }));

    const response = await request(app)
      .post('/random/build')
      .set('Content-Type', 'application/json')
      .send({ q: 't:battle', count: 1 });

    expect(response.status).toBe(200);

    const lines = response.text.split('\n').filter(Boolean).map(line => JSON.parse(line));
    expect(lines).toHaveLength(1);
    expect(lines[0].Name).toBe('DeckCustom');
    expect(lines[0].ContainedObjects[0].States).toBeDefined();
    expect(lines[0].ContainedObjects[0].States[2]).toBeDefined();
    expect(lines[0].ContainedObjects[0].States[2].Nickname).toBe('Awakened Skyclave');
  });

  test('POST /random/build should apply commander legality with price filters', async () => {
    scryfallLib.searchCards.mockResolvedValueOnce([
      {
        id: 'id-price-1',
        oracle_id: 'oracle-price-1',
        name: 'Jeweled Lotus',
        type_line: 'Artifact',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        games: ['paper']
      },
      {
        id: 'id-price-2',
        oracle_id: 'oracle-price-2',
        name: 'Mana Crypt',
        type_line: 'Artifact',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        games: ['paper']
      }
    ]);

    const response = await request(app)
      .post('/random/build')
      .set('Content-Type', 'application/json')
      .send({ q: 'usd>=50', count: 2 });

    expect(response.status).toBe(200);
    expect(scryfallLib.searchCards).toHaveBeenCalledWith(
      'usd>=50 f:commander',
      2,
      expect.any(String),
      expect.any(String)
    );
  });

  test('POST /random/build should skip commander legality when enforceCommander is false', async () => {
    scryfallLib.getRandomCard.mockResolvedValueOnce({
      id: 'id-mystery-slot',
      oracle_id: 'oracle-mystery-slot',
      name: 'Mystery Slot Card',
      type_line: 'Creature — Test',
      image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
      games: ['paper']
    });

    const response = await request(app)
      .post('/random/build')
      .set('Content-Type', 'application/json')
      .send({ q: 'set:cmb1', count: 1, enforceCommander: false });

    expect(response.status).toBe(200);
    expect(scryfallLib.getRandomCard).toHaveBeenCalledWith('set:cmb1');
  });

  test('POST /random/build should dedupe duplicates and fallback for unique cards', async () => {
    scryfallLib.searchCards.mockResolvedValueOnce([
      {
        id: 'id-dup-1',
        oracle_id: 'oracle-dup-1',
        name: 'Sol Ring',
        type_line: 'Artifact',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        games: ['paper']
      },
      {
        id: 'id-dup-2',
        oracle_id: 'oracle-dup-1',
        name: 'Sol Ring',
        type_line: 'Artifact',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        games: ['paper']
      }
    ]);

    scryfallLib.getRandomCard.mockResolvedValueOnce({
      id: 'id-fallback-1',
      oracle_id: 'oracle-fallback-1',
      name: 'Arcane Signet',
      type_line: 'Artifact',
      image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
      games: ['paper']
    });

    const response = await request(app)
      .post('/random/build')
      .set('Content-Type', 'application/json')
      .send({ q: 't:artifact', count: 2 });

    expect(response.status).toBe(200);
    expect(scryfallLib.getRandomCard).toHaveBeenCalled();
    const lines = response.text.split('\n').filter(Boolean).map(line => JSON.parse(line));
    expect(lines[0].ContainedObjects).toHaveLength(2);
  });

  test('POST /random/build should hydrate cards without image_uris before conversion', async () => {
    scryfallLib.getRandomCard.mockResolvedValueOnce({
      id: 'id-hydrate-1',
      oracle_id: 'oracle-hydrate-1',
      name: 'Hydrate Test Card',
      type_line: 'Creature — Test',
      games: ['paper']
    });

    scryfallLib.getCardById.mockResolvedValueOnce({
      id: 'id-hydrate-1',
      oracle_id: 'oracle-hydrate-1',
      name: 'Hydrate Test Card',
      type_line: 'Creature — Test',
      image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
      games: ['paper']
    });

    scryfallLib.convertToTTSCard.mockImplementationOnce((card, cardBack) => ({
      Name: 'Card',
      Nickname: card.name,
      Memo: card.oracle_id,
      DeckIDs: [100],
      CustomDeck: {
        '1': {
          FaceURL: card.image_uris?.normal,
          BackURL: cardBack,
          NumWidth: 1,
          NumHeight: 1,
          BackIsHidden: true,
          UniqueBack: false,
          Type: 0
        }
      }
    }));

    const response = await request(app)
      .post('/random/build')
      .set('Content-Type', 'application/json')
      .send({ q: 't:creature', count: 1 });

    expect(response.status).toBe(200);
    const lines = response.text.split('\n').filter(Boolean).map(line => JSON.parse(line));
    expect(lines).toHaveLength(1);
    expect(lines[0].Name).toBe('DeckCustom');
    expect(lines[0].CustomDeck['1'].FaceURL).toBe('https://cards.scryfall.io/normal/front/0/0/mock.jpg');
  });
});

describe('Server Endpoints - Search', () => {
  test('GET /search should require query parameter', async () => {
    const response = await request(app).get('/search');
    expect(response.status).toBe(400);
  });

  test('GET /search should accept valid query', async () => {
    const response = await request(app)
      .get('/search')
      .query({ q: 't:creature' });
    expect(response.status).not.toBe(400);
  });

  test('GET /search should accept limit parameter', async () => {
    const response = await request(app)
      .get('/search')
      .query({ q: 't:creature', limit: 10 });
    expect(response.status).not.toBe(400);
  });

  test('GET /search should clamp high limit values', async () => {
    const response = await request(app)
      .get('/search')
      .query({ q: 't:creature', limit: 2000 });
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('total_cards');
    expect(response.body.total_cards).toBeLessThanOrEqual(1000);
  });
});

describe('Server Endpoints - Card Lookup', () => {
  test('GET /card/:name should accept card name', async () => {
    const response = await request(app).get('/card/Mountain');
    expect(response.status).not.toBe(400);
  });

  test('GET /card/:name should accept set parameter', async () => {
    const response = await request(app)
      .get('/card/Mountain')
      .query({ set: 'dom' });
    expect(response.status).not.toBe(400);
  });

  test('GET /cards/:id should accept card ID', async () => {
    const response = await request(app).get('/cards/some-scryfall-id');
    expect(response.status).not.toBe(400);
  });

  test('GET /cards/:set/:number should accept set and number', async () => {
    const response = await request(app).get('/cards/dom/123');
    expect(response.status).not.toBe(400);
  });

  test('GET /cards/:set/:number/:lang should accept language', async () => {
    const response = await request(app).get('/cards/dom/123/en');
    expect(response.status).not.toBe(400);
  });
});

describe('Server Endpoints - Rulings and Tokens', () => {
  test('GET /rulings/:name should accept card name', async () => {
    const response = await request(app).get('/rulings/Mountain');
    expect(response.status).not.toBe(400);
  });

  test('GET /tokens/:name should accept card name', async () => {
    const response = await request(app).get('/tokens/treasure');
    expect(response.status).not.toBe(400);
  });

  test('GET /printings/:name should accept card name', async () => {
    const response = await request(app).get('/printings/Mountain');
    expect(response.status).not.toBe(400);
  });
});

describe('Server Endpoints - Sets', () => {
  test('GET /sets/:code should return removed status', async () => {
    const response = await request(app).get('/sets/dom');
    expect(response.status).toBe(410);
    expect(response.body.details).toContain('removed');
  });

  test('GET /sets/:code should return removed status for invalid set code', async () => {
    const response = await request(app).get('/sets/invalid-set-code-12345');
    expect(response.status).toBe(410);
    expect(response.body.details).toContain('removed');
  });
});

describe('Server Endpoints - Bulk Data', () => {
  test('GET /bulk/stats should return statistics', async () => {
    const response = await request(app).get('/bulk/stats');
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('loaded');
  });

  test('POST /bulk/reload should reject when bulk mode disabled', async () => {
    const response = await request(app).post('/bulk/reload');
    expect(response.status).toBe(400);
  });
});

describe('Server Endpoints - Proxy', () => {
  test('GET /proxy should require uri parameter', async () => {
    const response = await request(app).get('/proxy');
    expect(response.status).toBe(400);
  });

  test('GET /proxy should accept valid Scryfall URI', async () => {
    const uri = 'https://api.scryfall.com/cards/some-id';
    const response = await request(app)
      .get('/proxy')
      .query({ uri });
    expect(response.status).not.toBe(400);
  });

  test('GET /proxy should reject non-Scryfall URIs', async () => {
    const response = await request(app)
      .get('/proxy')
      .query({ uri: 'https://evil-site.com/api' });
    expect(response.status).toBe(400);
  });
});

describe('Server Endpoints - Security', () => {
  test('should reject potential XSS in card names', async () => {
    const response = await request(app).get('/card/<script>alert("xss")</script>');
    expect(response.status).not.toBe(200);
  });

  test('should reject SQL injection attempts in search', async () => {
    const response = await request(app)
      .get('/search')
      .query({ q: "'; DROP TABLE cards; --" });
    expect(response.status).not.toBe(500);
  });

  test('should reject path traversal attempts', async () => {
    const response = await request(app).get('/card/../../../etc/passwd');
    expect(response.status).not.toBe(200);
  });
});

describe('Server Endpoints - Content Type', () => {
  test('POST /deck should report removed endpoint', async () => {
    const response = await request(app)
      .post('/deck')
      .set('Content-Type', 'application/octet-stream')
      .send(JSON.stringify({
        decklist: '1 Mountain'
      }));
    expect(response.status).toBe(410);
    expect(response.body.details).toContain('removed');
  });

  test('POST /deck should report removed endpoint even for invalid JSON payload shape', async () => {
    const response = await request(app)
      .post('/deck')
      .set('Content-Type', 'application/octet-stream')
      .send('{ invalid json }');
    expect(response.status).toBe(410);
    expect(response.body.details).toContain('removed');
  });
});
