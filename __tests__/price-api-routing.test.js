/**
 * Tests to verify price and token filters force API routing for real-time/complete data
 */

const request = require('supertest');
const express = require('express');

// Mock modules
jest.mock('../lib/scryfall');
jest.mock('../lib/bulk-data');

const scryfallLib = require('../lib/scryfall');
const bulkData = require('../lib/bulk-data');

describe('Price and Token Filter API Routing', () => {
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
    
    scryfallLib.searchCards.mockResolvedValue([
      { id: '3', name: 'API Card 1', prices: { usd: '15.00' } }
    ]);
    scryfallLib.getRandomCard.mockResolvedValue(
      { id: '4', name: 'API Card 2', prices: { usd: '7.50' } }
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
        't:artifact+usd>=50',
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
      expect(scryfallLib.getRandomCard).toHaveBeenCalled();
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

    test('should use API for single random with token filter', async () => {
      await request(app)
        .get('/random?q=t:token')
        .expect(200);

      expect(bulkData.getRandomCard).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).toHaveBeenCalled();
    });

    test('should use API for multiple random with token filter', async () => {
      await request(app)
        .get('/random?count=5&q=is:token')
        .expect(200);

      expect(bulkData.getRandomCard).not.toHaveBeenCalled();
      expect(scryfallLib.getRandomCard).toHaveBeenCalled();
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

  describe('Token filter detection regex', () => {
    const testQueries = [
      { query: 't:token', shouldMatch: true, desc: 't:token' },
      { query: 'type:token', shouldMatch: true, desc: 'type:token' },
      { query: 'is:token', shouldMatch: true, desc: 'is:token' },
      { query: 't:token name:treasure', shouldMatch: true, desc: 't:token with name' },
      { query: 'is:token c:r', shouldMatch: true, desc: 'is:token with color' },
      { query: 't:goblin', shouldMatch: false, desc: 't:goblin (not token)' },
      { query: 'c:r t:creature', shouldMatch: false, desc: 'no token filter' },
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

  describe('Combined price and token filters', () => {
    test('should use API for query with both price and token filters', async () => {
      await request(app)
        .get('/search?q=t:token+usd>=5')
        .expect(200);

      expect(scryfallLib.searchCards).toHaveBeenCalled();
      expect(bulkData.searchCards).not.toHaveBeenCalled();
    });
  });
});
