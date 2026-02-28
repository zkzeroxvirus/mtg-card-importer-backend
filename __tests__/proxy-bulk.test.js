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
  getRandomCards: jest.fn(),
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
  deckFromList: jest.fn(),
  parseDecklist: jest.fn()
}));

const bulkData = require('../lib/bulk-data');
const scryfallLib = require('../lib/scryfall');
const app = require('../server');

describe('Proxy endpoint - Bulk Data', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('should serve card data from bulk data when available', async () => {
    const card = { object: 'card', id: 'bulk-card' };
    bulkData.isLoaded.mockReturnValue(true);
    bulkData.getCardById.mockReturnValue(card);

    const response = await request(app)
      .get('/proxy')
      .query({ uri: 'https://api.scryfall.com/cards/bulk-card' });

    expect(response.status).toBe(200);
    expect(response.body).toEqual(card);
    expect(scryfallLib.proxyUri).not.toHaveBeenCalled();
  });

  test('should fall back to API proxy when bulk data is unavailable', async () => {
    const apiCard = { object: 'card', id: 'api-card' };
    bulkData.isLoaded.mockReturnValue(false);
    scryfallLib.proxyUri.mockResolvedValue(apiCard);

    const response = await request(app)
      .get('/proxy')
      .query({ uri: 'https://api.scryfall.com/cards/api-card' });

    expect(response.status).toBe(200);
    expect(response.body).toEqual(apiCard);
    expect(scryfallLib.proxyUri).toHaveBeenCalledWith('https://api.scryfall.com/cards/api-card');
  });
});
