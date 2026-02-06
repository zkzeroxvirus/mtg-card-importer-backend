const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.USE_BULK_DATA = 'true';

jest.mock('../lib/bulk-data', () => ({
  downloadBulkData: jest.fn(),
  loadBulkData: jest.fn(),
  getCardsDatabase: jest.fn(),
  isLoaded: jest.fn(),
  getRulings: jest.fn(),
  getRandomCard: jest.fn(),
  searchCards: jest.fn(),
  getCardByName: jest.fn(),
  getCardById: jest.fn(),
  getCardBySetNumber: jest.fn(),
  scheduleUpdateCheck: jest.fn(),
  getStats: jest.fn(() => ({ loaded: true, cardCount: 0 }))
}));

jest.mock('../lib/scryfall', () => ({
  proxyUri: jest.fn(),
  getCard: jest.fn(),
  autocompleteCardName: jest.fn(),
  getCardById: jest.fn(),
  getCardBySetNumber: jest.fn(),
  searchCards: jest.fn(),
  getRandomCard: jest.fn(),
  getSet: jest.fn(),
  getPrintings: jest.fn(),
  getCardRulings: jest.fn(),
  getTokens: jest.fn(),
  deckFromList: jest.fn(),
  parseDecklist: jest.fn()
}));

const bulkData = require('../lib/bulk-data');
const app = require('../server');

describe('Search endpoint - Token limits', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('caps token searches to MAX_TOKEN_RESULTS', async () => {
    bulkData.isLoaded.mockReturnValue(true);
    bulkData.searchCards.mockResolvedValue([]);

    const response = await request(app)
      .get('/search')
      .query({ q: 't:token treasure' });

    expect(response.status).toBe(200);
    expect(bulkData.searchCards).toHaveBeenCalledWith('t:token treasure', 16);
  });
});
