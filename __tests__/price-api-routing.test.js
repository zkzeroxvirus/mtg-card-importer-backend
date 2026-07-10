/**
 * Tests to verify routing behavior:
 * - Price filters now use bulk data when available (default_cards has price fields)
 * - otag/arttag/function filters can use shared tag cache over bulk data when available
 */

const request = require('supertest');

// Mock modules
jest.mock('../lib/scryfall');
jest.mock('../lib/bulk-data');
jest.mock('../lib/oracle-tags');

const scryfallLib = require('../lib/scryfall');
const bulkData = require('../lib/bulk-data');
const oracleTags = require('../lib/oracle-tags');
const tagCache = require('../lib/tag-cache');

describe('Price Filter API Routing', () => {
  let app;
  let originalEnv;

  beforeAll(() => {
    // Save original env
    originalEnv = process.env.USE_BULK_DATA;
    process.env.USE_BULK_DATA = 'true';
    
    // Clear module cache and reload server
    delete require.cache[require.resolve('../server.js')];
    app = require('../server.js');
  });

  afterAll(() => {
    // Restore env
    process.env.USE_BULK_DATA = originalEnv;
  });

  beforeEach(() => {
    jest.clearAllMocks();
    tagCache.clear();
    
    // Setup default mocks
    bulkData.isLoaded.mockReturnValue(true);
    bulkData.searchCards.mockResolvedValue([
      {
        id: '1',
        oracle_id: 'oracle-1',
        name: 'Test Card 1',
        type_line: 'Artifact',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        prices: { usd: '10.00' },
        games: ['paper']
      }
    ]);
    bulkData.getRandomCard.mockResolvedValue(
      { id: '2', name: 'Test Card 2', prices: { usd: '5.00' } }
    );
    bulkData.getRandomCards.mockResolvedValue([
      { id: '2', oracle_id: 'oracle-2', name: 'Test Card 2', prices: { usd: '5.00' } },
      { id: '9', oracle_id: 'oracle-9', name: 'Test Card 9', prices: { usd: '6.00' } },
      { id: '10', oracle_id: 'oracle-10', name: 'Test Card 10', prices: { usd: '7.00' } }
    ]);
    bulkData.getPrintingsByOracleId.mockImplementation((oracleId) => ([
      {
        id: `${oracleId}-printing`,
        oracle_id: oracleId,
        name: `Bulk ${oracleId}`,
        type_line: 'Artifact',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        games: ['paper']
      }
    ]));
    bulkData.isNonPlayableCard.mockReturnValue(false);
    bulkData.getQueryExplain.mockReturnValue({
      mode: 'random',
      totalCards: 100,
      prefilteredCount: 12,
      finalCount: 5
    });

    oracleTags.isLoaded.mockReturnValue(true);
    oracleTags.loadOracleTags.mockResolvedValue(true);
    oracleTags.getOracleIdsForTerm.mockImplementation((term) => {
      const key = String(term || '').toLowerCase();
      if (key.includes('builddraw')) {
        return ['oracle-fn-1', 'oracle-fn-2'];
      }
      if (key.includes('manarock')) {
        return ['oracle-manarock-1', 'oracle-manarock-2', 'oracle-manarock-3'];
      }
      if (key.includes('draw')) {
        return ['oracle-otag-1', 'oracle-otag-2', 'oracle-otag-3'];
      }
      return [];
    });
    
    scryfallLib.searchCards.mockResolvedValue([
      { id: '3', oracle_id: 'oracle-3', name: 'API Card 1', type_line: 'Artifact', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, prices: { usd: '15.00' }, games: ['paper'] },
      { id: '4', oracle_id: 'oracle-4', name: 'API Card 2', type_line: 'Artifact', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, prices: { usd: '7.50' }, games: ['paper'] },
      { id: '5', oracle_id: 'oracle-5', name: 'API Card 3', type_line: 'Artifact', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, prices: { usd: '12.00' }, games: ['paper'] },
      { id: '6', oracle_id: 'oracle-6', name: 'API Card 4', type_line: 'Artifact', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, prices: { usd: '20.00' }, games: ['paper'] },
      { id: '7', oracle_id: 'oracle-7', name: 'API Card 5', type_line: 'Artifact', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, prices: { usd: '25.00' }, games: ['paper'] }
    ]);
    scryfallLib.getRandomCard.mockResolvedValue(
      { id: '8', name: 'API Card 6', prices: { usd: '9.00' } }
    );
  });

  describe('GET /search with price filters', () => {
    test('should use bulk for usd>= filter', async () => {
      await request(app)
        .get('/search?q=t:artifact+usd>=50')
        .expect(200);

      // Should call bulk data (default_cards has price fields)
      expect(bulkData.searchCards).toHaveBeenCalledWith(
        't:artifact usd>=50',
        expect.any(Number)
      );
      // Should NOT call API when bulk returns results
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });

    test('should use bulk for usd< filter', async () => {
      await request(app)
        .get('/search?q=usd<2')
        .expect(200);

      expect(bulkData.searchCards).toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });

    test('should use bulk for eur: filter', async () => {
      await request(app)
        .get('/search?q=eur>10')
        .expect(200);

      expect(bulkData.searchCards).toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });

    test('should use bulk for tix: filter', async () => {
      await request(app)
        .get('/search?q=tix>=5')
        .expect(200);

      expect(bulkData.searchCards).toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });

    test('should use bulk data for non-price queries', async () => {
      await request(app)
        .get('/search?q=t:goblin+c:r')
        .expect(200);

      // Should call bulk data first
      expect(bulkData.searchCards).toHaveBeenCalled();
      // Should NOT call API (bulk returns results)
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });

    test('should use bulk for mixed query with price filter', async () => {
      await request(app)
        .get('/search?q=t:artifact+c:r+usd>=10')
        .expect(200);

      expect(bulkData.searchCards).toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });

    test('should use shared tag cache path for otag filters', async () => {
      const response = await request(app)
        .get('/search?q=otag:draw')
        .expect(200);

      expect(response.headers['x-query-plan']).toBe('api:api_only_filter');
      expect(bulkData.getPrintingsByOracleId).toHaveBeenCalled();
      expect(bulkData.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });
  });

  describe('GET /random with price filters', () => {
    test('should use bulk for single random with usd filter', async () => {
      await request(app)
        .get('/random?q=usd>=50')
        .expect(200);

      expect(bulkData.getRandomCard).toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should use bulk for multiple random with eur filter', async () => {
      await request(app)
        .get('/random?count=5&q=eur<10')
        .expect(200);

      expect(bulkData.getRandomCards).toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });

    test('should use bulk data for non-price random queries', async () => {
      await request(app)
        .get('/random?q=t:goblin')
        .expect(200);

      expect(bulkData.getRandomCard).toHaveBeenCalled();
    });

    test('should use bulk data for t:vanguard random query', async () => {
      await request(app)
        .get('/random?q=t:vanguard')
        .expect(200);

      expect(bulkData.getRandomCard).toHaveBeenCalledWith('t:vanguard lang:en');
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should use bulk multi-card sampler for non-price random count queries', async () => {
      await request(app)
        .get('/random?count=3&q=t:goblin')
        .expect(200);

      expect(bulkData.getRandomCards).toHaveBeenCalledWith('t:goblin lang:en f:commander', 3, true);
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });

    test('should use bulk multi-card sampler for t:vanguard count queries', async () => {
      await request(app)
        .get('/random?count=2&q=t:vanguard')
        .expect(200);

      expect(bulkData.getRandomCards).toHaveBeenCalledWith('t:vanguard lang:en', 2, true);
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });

    test('should use bulk for tix filter in random', async () => {
      await request(app)
        .get('/random?q=tix>=5')
        .expect(200);

      expect(bulkData.getRandomCard).toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should use shared tag cache path for random queries with otag filter', async () => {
      bulkData.searchCards.mockResolvedValueOnce([
        { id: 'otag-bulk-1', oracle_id: 'oracle-otag-1', name: 'Otag Card 1', type_line: 'Sorcery', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] },
        { id: 'otag-bulk-2', oracle_id: 'oracle-otag-2', name: 'Otag Card 2', type_line: 'Sorcery', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] },
        { id: 'otag-bulk-3', oracle_id: 'oracle-otag-3', name: 'Otag Card 3', type_line: 'Sorcery', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] }
      ]);

      const response = await request(app)
        .get('/random?count=3&q=otag:draw')
        .expect(200);

      expect(response.headers['x-query-plan']).toBe('api:api_only_filter');
      expect(bulkData.getRandomCards).not.toHaveBeenCalled();
      expect(bulkData.searchCards).toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should use shared tag cache path for random queries with function tag alias', async () => {
      bulkData.searchCards.mockResolvedValueOnce([
        { id: 'fn-bulk-1', oracle_id: 'oracle-fn-1', name: 'Function Card 1', type_line: 'Sorcery', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] },
        { id: 'fn-bulk-2', oracle_id: 'oracle-fn-2', name: 'Function Card 2', type_line: 'Sorcery', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] }
      ]);

      const response = await request(app)
        .get('/random?count=2&q=function:draw')
        .expect(200);

      expect(response.headers['x-query-plan']).toBe('api:api_only_filter');
      expect(bulkData.getRandomCards).not.toHaveBeenCalled();
      expect(bulkData.searchCards).toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should use bulk for set:lea random queries', async () => {
      const response = await request(app)
        .get('/random?count=3&q=set:lea')
        .expect(200);

      expect(response.headers['x-query-plan']).toMatch(/^bulk:/);
      expect(bulkData.getRandomCards).toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

  });

  describe('POST /random/build with price filters', () => {
    test('should use bulk for random/build with usd filter', async () => {
      const response = await request(app)
        .post('/random/build')
        .set('Content-Type', 'application/json')
        .send({ q: 'usd>=50 t:artifact', count: 1, enforceCommander: true })
        .expect(200);

      expect(response.headers['x-query-plan']).toMatch(/^bulk:/);
      expect(bulkData.getRandomCard).toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should use bulk multi-card sampler for non-price random/build queries', async () => {
      scryfallLib.convertToTTSCard = jest.fn((card) => ({
        Name: 'Card',
        Nickname: card.name,
        Memo: card.oracle_id,
        CustomDeck: {
          '1': {
            FaceURL: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg',
            BackURL: 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'
          }
        }
      }));

      bulkData.getRandomCards.mockResolvedValueOnce([
        {
          id: 'bulk-rb-1',
          oracle_id: 'bulk-rb-o1',
          name: 'Bulk Build Card 1',
          type_line: 'Artifact',
          image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
          games: ['paper']
        },
        {
          id: 'bulk-rb-2',
          oracle_id: 'bulk-rb-o2',
          name: 'Bulk Build Card 2',
          type_line: 'Artifact',
          image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
          games: ['paper']
        }
      ]);

      const response = await request(app)
        .post('/random/build')
        .set('Content-Type', 'application/json')
        .send({ q: 't:artifact', count: 2, enforceCommander: true })
        .expect(200);

      expect(response.headers['x-query-plan']).toMatch(/^bulk:/);
      expect(bulkData.getRandomCards).toHaveBeenCalledWith('t:artifact lang:en f:commander', 2, true, false);
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should bypass commander legality for random/build type:vanguard query', async () => {
      scryfallLib.convertToTTSCard = jest.fn((card) => ({
        Name: 'Card',
        Nickname: card.name,
        Memo: card.oracle_id,
        CustomDeck: {
          '1': {
            FaceURL: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg',
            BackURL: 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'
          }
        }
      }));

      bulkData.getRandomCards.mockResolvedValueOnce([
        {
          id: 'bulk-vg-1',
          oracle_id: 'bulk-vg-o1',
          name: 'Vanguard Card 1',
          layout: 'vanguard',
          type_line: 'Vanguard',
          image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
          games: ['paper']
        },
        {
          id: 'bulk-vg-2',
          oracle_id: 'bulk-vg-o2',
          name: 'Vanguard Card 2',
          layout: 'vanguard',
          type_line: 'Vanguard',
          image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
          games: ['paper']
        }
      ]);

      await request(app)
        .post('/random/build')
        .set('Content-Type', 'application/json')
        .send({ q: 't:vanguard', count: 2, enforceCommander: true })
        .expect(200);

      expect(bulkData.getRandomCards).toHaveBeenCalledWith('t:vanguard lang:en', 2, true, false);
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should use shared tag cache path for random/build queries with otag filter', async () => {
      bulkData.searchCards.mockResolvedValueOnce([
        { id: 'otag-card', oracle_id: 'oracle-otag-1', name: 'Otag Card', type_line: 'Creature', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] },
        { id: 'otag-card-2', oracle_id: 'oracle-otag-2', name: 'Otag Card 2', type_line: 'Creature', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] }
      ]);
      scryfallLib.convertToTTSCard = jest.fn((card) => ({
        Name: 'Card',
        Nickname: card.name,
        Memo: card.oracle_id,
        CustomDeck: {
          '1': {
            FaceURL: card.image_uris.normal,
            BackURL: 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'
          }
        }
      }));

      const response = await request(app)
        .post('/random/build')
        .set('Content-Type', 'application/json')
        .send({ q: 'otag:draw', count: 2, enforceCommander: true })
        .expect(200);

      expect(response.headers['x-query-plan']).toBe('api:api_only_filter');
      expect(bulkData.getRandomCards).not.toHaveBeenCalled();
      expect(bulkData.searchCards).toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should strip otag terms before applying remaining filters for random/build count queries', async () => {
      bulkData.searchCards.mockResolvedValueOnce([
        { id: 'manarock-rare-1', oracle_id: 'oracle-manarock-1', name: 'Manarock Rare 1', type_line: 'Artifact', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] },
        { id: 'manarock-rare-2', oracle_id: 'oracle-manarock-2', name: 'Manarock Rare 2', type_line: 'Artifact', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] },
        { id: 'other-rare', oracle_id: 'oracle-other', name: 'Other Rare', type_line: 'Artifact', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] }
      ]);
      scryfallLib.convertToTTSCard = jest.fn((card) => ({
        Name: 'Card',
        Nickname: card.name,
        Memo: card.oracle_id,
        CustomDeck: {
          '1': {
            FaceURL: card.image_uris.normal,
            BackURL: 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'
          }
        }
      }));

      const response = await request(app)
        .post('/random/build')
        .set('Content-Type', 'application/json')
        .send({ q: 'otag:manarock+id:r', count: 2, enforceCommander: true })
        .expect(200);

      expect(response.text).toContain('Manarock Rare');
      expect(response.text).not.toContain('Other Rare');
      expect(bulkData.searchCards).toHaveBeenCalledWith('id:r lang:en f:commander', Number.MAX_SAFE_INTEGER, true);
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should use shared tag cache path for random/build queries with function tag alias', async () => {
      bulkData.searchCards.mockResolvedValueOnce([
        { id: 'function-card', oracle_id: 'oracle-fn-1', name: 'Function Card', type_line: 'Creature', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] },
        { id: 'function-card-2', oracle_id: 'oracle-fn-2', name: 'Function Card 2', type_line: 'Creature', image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' }, games: ['paper'] }
      ]);
      scryfallLib.convertToTTSCard = jest.fn((card) => ({
        Name: 'Card',
        Nickname: card.name,
        Memo: card.oracle_id,
        CustomDeck: {
          '1': {
            FaceURL: card.image_uris.normal,
            BackURL: 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'
          }
        }
      }));

      const response = await request(app)
        .post('/random/build')
        .set('Content-Type', 'application/json')
        .send({ q: 'function:builddraw', count: 2, enforceCommander: true })
        .expect(200);

      expect(response.headers['x-query-plan']).toBe('api:api_only_filter');
      expect(bulkData.getRandomCards).not.toHaveBeenCalled();
      expect(bulkData.searchCards).toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });

    test('should use bulk for set:lea random/build queries', async () => {
      bulkData.getRandomCard.mockResolvedValueOnce({
        id: 'lea-bulk-1',
        oracle_id: 'lea-oracle-1',
        name: 'LEA Bulk Card 1',
        type_line: 'Creature',
        image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
        games: ['paper']
      });
      scryfallLib.convertToTTSCard = jest.fn((card) => ({
        Name: 'Card',
        Nickname: card.name,
        Memo: card.oracle_id,
        CustomDeck: {
          '1': {
            FaceURL: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg',
            BackURL: 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'
          }
        }
      }));

      const response = await request(app)
        .post('/random/build')
        .set('Content-Type', 'application/json')
        .send({ q: 'set:lea', count: 1, enforceCommander: true })
        .expect(200);

      expect(response.headers['x-query-plan']).toMatch(/^bulk:/);
      expect(bulkData.getRandomCard).toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    });
  });

  describe('Price filter detection regex', () => {
    const testQueries = [
      { query: 'usd>=50', shouldMatch: true, desc: 'usd>=' },
      { query: 'usd>50', shouldMatch: true, desc: 'usd>' },
      { query: 'usd<=10', shouldMatch: true, desc: 'usd<=' },
      { query: 'usd<10', shouldMatch: true, desc: 'usd<' },
      { query: 'usd:5', shouldMatch: true, desc: 'usd:' },
      { query: 'usd=5', shouldMatch: true, desc: 'usd=' },
      { query: 'eur>=50', shouldMatch: true, desc: 'eur>=' },
      { query: 'tix<10', shouldMatch: true, desc: 'tix<' },
      { query: 't:artifact usd>=50', shouldMatch: true, desc: 'mixed with usd' },
      { query: 't:artifact', shouldMatch: false, desc: 'no price filter' },
      { query: 'c:r id:wubr', shouldMatch: false, desc: 'no price filter (id:)' },
    ];

    testQueries.forEach(({ query, shouldMatch, desc }) => {
      test(`should ${shouldMatch ? '' : 'not '}match: ${desc}`, async () => {
        await request(app)
          .get(`/search?q=${encodeURIComponent(query)}`)
          .expect(200);

        if (shouldMatch) {
          // Price filters now use bulk data (default_cards has price fields)
          expect(bulkData.searchCards).toHaveBeenCalled();
          expect(scryfallLib.searchCards).not.toHaveBeenCalled();
        } else {
          expect(bulkData.searchCards).toHaveBeenCalled();
        }
      });
    });
  });

  describe('Combined filters', () => {
    test('should use bulk for query with both price and type filters', async () => {
      await request(app)
        .get('/search?q=t:token+usd>=5')
        .expect(200);

      expect(bulkData.searchCards).toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    });
  });

  describe('Power/Toughness equals normalization', () => {
    test('should normalize spaced power/toughness equals on /search', async () => {
      const response = await request(app)
        .get('/search')
        .query({ q: 't:creature power = 2 toughness = 2' })
        .expect(200);

      expect(bulkData.searchCards).toHaveBeenCalledWith(
        't:creature power=2 toughness=2',
        expect.any(Number)
      );
      expect(response.headers['x-query-warning']).toContain('Normalized query operators');
    });

    test('should normalize spaced pow/tou comparisons on /search', async () => {
      const response = await request(app)
        .get('/search')
        .query({ q: 't:creature pow >= 1 tou <= 5' })
        .expect(200);

      expect(bulkData.searchCards).toHaveBeenCalledWith(
        't:creature pow>=1 tou<=5',
        expect.any(Number)
      );
      expect(response.headers['x-query-warning']).toContain('Normalized query operators');
    });

    test('should normalize spaced power equals on /random', async () => {
      const response = await request(app)
        .get('/random')
        .query({ q: 'power = 3' })
        .expect(200);

      expect(bulkData.getRandomCard).toHaveBeenCalledWith('power=3 lang:en f:commander');
      expect(response.headers['x-query-warning']).toContain('Normalized query operators');
    });

    test('should normalize spaced toughness comparison on /random', async () => {
      const response = await request(app)
        .get('/random')
        .query({ q: 'tou >= 5' })
        .expect(200);

      expect(bulkData.getRandomCard).toHaveBeenCalledWith('tou>=5 lang:en f:commander');
      expect(response.headers['x-query-warning']).toContain('Normalized query operators');
    });

    test('should normalize colorless color filter to color identity on /search', async () => {
      const response = await request(app)
        .get('/search')
        .query({ q: 'c=c' })
        .expect(200);

      expect(bulkData.searchCards).toHaveBeenCalledWith('id=c', expect.any(Number));
      expect(response.headers['x-query-warning']).toContain('Normalized query operators');
    });

    test('should normalize colorless color filter to color identity on /random', async () => {
      const response = await request(app)
        .get('/random')
        .query({ q: 'color:colorless' })
        .expect(200);

      expect(bulkData.getRandomCard).toHaveBeenCalledWith('id=c lang:en f:commander');
      expect(response.headers['x-query-warning']).toContain('Normalized query operators');
    });

    test('should include query plan and explain headers on /random with explain=true', async () => {
      const response = await request(app)
        .get('/random')
        .query({ q: 't:artifact', explain: 'true' })
        .expect(200);

      expect(response.headers['x-query-plan']).toMatch(/^bulk:/);
      expect(response.headers['x-query-explain']).toContain('mode=random');
      expect(bulkData.getQueryExplain).toHaveBeenCalledWith('t:artifact lang:en f:commander', 'random');
    });

    test('should include query plan header on /search', async () => {
      const response = await request(app)
        .get('/search')
        .query({ q: 't:artifact' })
        .expect(200);

      expect(response.headers['x-query-plan']).toBe('bulk:bulk_loaded');
    });
  });
});
