/**
 * Tests to verify routing behavior:
 * - Price filters force API routing for real-time data
 */

const request = require('supertest');

// Mock modules
jest.mock('../lib/scryfall');
jest.mock('../lib/bulk-data');

const scryfallLib = require('../lib/scryfall');
const bulkData = require('../lib/bulk-data');

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
    
    // Setup default mocks
    bulkData.isLoaded.mockReturnValue(true);
    bulkData.searchCards.mockResolvedValue([
      { id: '1', name: 'Test Card 1', prices: { usd: '10.00' } }
    ]);
    bulkData.getRandomCard.mockResolvedValue(
      { id: '2', name: 'Test Card 2', prices: { usd: '5.00' } }
    );
    bulkData.getQueryExplain.mockReturnValue({
      mode: 'random',
      totalCards: 100,
      prefilteredCount: 12,
      finalCount: 5
    });
    
    scryfallLib.searchCards.mockResolvedValue([
      { id: '3', name: 'API Card 1', prices: { usd: '15.00' } },
      { id: '4', name: 'API Card 2', prices: { usd: '7.50' } },
      { id: '5', name: 'API Card 3', prices: { usd: '12.00' } },
      { id: '6', name: 'API Card 4', prices: { usd: '20.00' } },
      { id: '7', name: 'API Card 5', prices: { usd: '25.00' } }
    ]);
    scryfallLib.getRandomCard.mockResolvedValue(
      { id: '8', name: 'API Card 6', prices: { usd: '9.00' } }
    );
  });

  describe('GET /search with price filters', () => {
    test('should use API for usd>= filter', async () => {
      await request(app)
        .get('/search?q=t:artifact+usd>=50')
        .expect(200);

      // Should NOT call bulk data
      expect(bulkData.searchCards).not.toHaveBeenCalled();
      // Should call API
      expect(scryfallLib.searchCards).toHaveBeenCalledWith(
        't:artifact usd>=50',
        expect.any(Number),
        'cards'
      );
    });

    test('should use API for usd< filter', async () => {
      await request(app)
        .get('/search?q=usd<2')
        .expect(200);

      expect(bulkData.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.searchCards).toHaveBeenCalled();
    });

    test('should use API for eur: filter', async () => {
      await request(app)
        .get('/search?q=eur>10')
        .expect(200);

      expect(bulkData.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.searchCards).toHaveBeenCalled();
    });

    test('should use API for tix: filter', async () => {
      await request(app)
        .get('/search?q=tix>=5')
        .expect(200);

      expect(bulkData.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.searchCards).toHaveBeenCalled();
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

    test('should use API for mixed query with price filter', async () => {
      await request(app)
        .get('/search?q=t:artifact+c:r+usd>=10')
        .expect(200);

      expect(bulkData.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.searchCards).toHaveBeenCalled();
    });
  });

  describe('GET /random with price filters', () => {
    test('should use API for single random with usd filter', async () => {
      await request(app)
        .get('/random?q=usd>=50')
        .expect(200);

      expect(bulkData.getRandomCard).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).toHaveBeenCalled();
    });

    test('should use API for multiple random with eur filter', async () => {
      await request(app)
        .get('/random?count=5&q=eur<10')
        .expect(200);

      expect(bulkData.getRandomCard).not.toHaveBeenCalled();
      expect(scryfallLib.searchCards).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).toHaveBeenCalledWith('eur<10 lang:en f:commander', true);
    });

    test('should use bulk data for non-price random queries', async () => {
      await request(app)
        .get('/random?q=t:goblin')
        .expect(200);

      expect(bulkData.getRandomCard).toHaveBeenCalled();
    });

    test('should use API for tix filter in random', async () => {
      await request(app)
        .get('/random?q=tix>=5')
        .expect(200);

      expect(bulkData.getRandomCard).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).toHaveBeenCalled();
    });

  });

  describe('POST /random/build with price filters', () => {
    test('should use API for random/build with usd filter', async () => {
      const response = await request(app)
        .post('/random/build')
        .set('Content-Type', 'application/json')
        .send({ q: 'usd>=50 t:artifact', count: 1, enforceCommander: true })
        .expect(200);

      expect(response.headers['x-query-plan']).toBe('api:price_filter');
      expect(bulkData.getRandomCard).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).toHaveBeenCalledWith('usd>=50 t:artifact lang:en f:commander');
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
          expect(scryfallLib.searchCards).toHaveBeenCalled();
          expect(bulkData.searchCards).not.toHaveBeenCalled();
        } else {
          expect(bulkData.searchCards).toHaveBeenCalled();
        }
      });
    });
  });

  describe('Combined filters', () => {
    test('should use API for query with both price and type filters', async () => {
      await request(app)
        .get('/search?q=t:token+usd>=5')
        .expect(200);

      expect(scryfallLib.searchCards).toHaveBeenCalled();
      expect(bulkData.searchCards).not.toHaveBeenCalled();
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

      expect(response.headers['x-query-plan']).toBe('bulk:bulk_loaded');
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
