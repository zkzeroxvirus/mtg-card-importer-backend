const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DEFAULT_CARD_BACK = 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';
process.env.USE_BULK_DATA = 'false';

jest.mock('../lib/scryfall', () => ({
  getCard: jest.fn(),
  searchCards: jest.fn()
}));

jest.mock('../lib/bulk-data', () => ({
  isLoaded: jest.fn(() => false),
  getExactTokensByName: jest.fn(() => []),
  getCardByName: jest.fn(),
  getCardById: jest.fn(),
  getCardBySetNumber: jest.fn(),
  getRandomCard: jest.fn(),
  searchCards: jest.fn(),
  getQueryExplain: jest.fn(),
  getStats: jest.fn(() => ({ loaded: false })),
  loadBulkData: jest.fn(),
  scheduleUpdateCheck: jest.fn(),
  dedupeCardsByOracleId: jest.fn(cards => cards)
}));

const scryfallLib = require('../lib/scryfall');
const bulkData = require('../lib/bulk-data');
const app = require('../server');

describe('Token card lookup', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    bulkData.isLoaded.mockReturnValue(false);
    bulkData.getExactTokensByName.mockReturnValue([]);
  });

  test('should prefer exact token lookup for treasure and exclude DFC token result', async () => {
    scryfallLib.searchCards.mockResolvedValue([
      {
        object: 'card',
        name: 'Treasure',
        type_line: 'Token Artifact — Treasure',
        layout: 'token'
      }
    ]);

    const response = await request(app).get('/card/treasure');

    expect(response.status).toBe(200);
    expect(response.body.name).toBe('Treasure');
    expect(response.body.layout).toBe('token');
    expect(scryfallLib.searchCards).toHaveBeenCalledWith('!"treasure" t:token -is:dfc', 25, 'cards');
    expect(scryfallLib.getCard).not.toHaveBeenCalled();
  });

  test('should prefer exact token lookup for food', async () => {
    scryfallLib.searchCards.mockResolvedValue([
      {
        object: 'card',
        name: 'Food',
        type_line: 'Token Artifact — Food',
        layout: 'token'
      }
    ]);

    const response = await request(app).get('/card/food');

    expect(response.status).toBe(200);
    expect(response.body.name).toBe('Food');
    expect(response.body.layout).toBe('token');
    expect(scryfallLib.searchCards).toHaveBeenCalledWith('!"food" t:token -is:dfc', 25, 'cards');
    expect(scryfallLib.getCard).not.toHaveBeenCalled();
  });

  test('should return list when exact token lookup has multiple unique variants', async () => {
    scryfallLib.searchCards.mockResolvedValue([
      {
        object: 'card',
        id: 'fish-1',
        oracle_id: 'oracle-fish-1',
        name: 'Fish',
        type_line: 'Token Creature — Fish',
        layout: 'token'
      },
      {
        object: 'card',
        id: 'fish-2',
        oracle_id: 'oracle-fish-2',
        name: 'Fish',
        type_line: 'Token Creature — Fish',
        layout: 'token'
      }
    ]);

    const response = await request(app).get('/card/fish');

    expect(response.status).toBe(200);
    expect(response.body.object).toBe('list');
    expect(response.body.total_cards).toBe(2);
    expect(Array.isArray(response.body.data)).toBe(true);
    expect(response.body.data[0].name).toBe('Fish');
    expect(scryfallLib.getCard).not.toHaveBeenCalled();
  });

  test('should fall back to generic card lookup when no exact token exists', async () => {
    scryfallLib.searchCards.mockResolvedValue([]);
    scryfallLib.getCard.mockResolvedValue({
      object: 'card',
      name: 'Treasure Nabber',
      type_line: 'Creature — Goblin Rogue',
      layout: 'normal'
    });

    const response = await request(app).get('/card/treasure%20nabber');

    expect(response.status).toBe(200);
    expect(response.body.name).toBe('Treasure Nabber');
    expect(scryfallLib.searchCards).toHaveBeenCalledWith('!"treasure nabber" t:token -is:dfc', 25, 'cards');
    expect(scryfallLib.getCard).toHaveBeenCalledWith('treasure nabber', undefined);
  });

  test('should bypass commander legality checks for token lookup when enforceCommander=true', async () => {
    scryfallLib.searchCards.mockResolvedValue([
      {
        object: 'card',
        name: 'Treasure',
        type_line: 'Token Artifact — Treasure',
        layout: 'token',
        legalities: {
          commander: 'not_legal'
        }
      }
    ]);

    const response = await request(app)
      .get('/card/treasure')
      .query({ enforceCommander: 'true' });

    expect(response.status).toBe(200);
    expect(response.body.name).toBe('Treasure');
  });
});
