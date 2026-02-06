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
  getCardRulings: jest.fn(),
  getTokens: jest.fn(),
  getPrintings: jest.fn(),
  deckFromList: jest.fn(),
  parseDecklist: jest.fn()
}));

const bulkData = require('../lib/bulk-data');
const scryfallLib = require('../lib/scryfall');
const app = require('../server');

describe('Tokens endpoint - Random usage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('does not call random card APIs when fetching tokens', async () => {
    bulkData.isLoaded.mockReturnValue(true);
    bulkData.getCardByName.mockReturnValue(null);
    bulkData.searchCards.mockResolvedValue([]);
    scryfallLib.getTokens.mockResolvedValue([]);

    const response = await request(app)
      .get('/tokens/treasure');

    expect(response.status).toBe(200);
    expect(scryfallLib.getRandomCard).not.toHaveBeenCalled();
    expect(bulkData.getRandomCard).not.toHaveBeenCalled();
  });
});
