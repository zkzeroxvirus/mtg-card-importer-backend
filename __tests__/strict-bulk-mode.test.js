const request = require('supertest');

const createCard = (name = 'Mock Card') => ({
  object: 'card',
  id: `id-${name.toLowerCase().replace(/\s+/g, '-')}`,
  oracle_id: `oracle-${name.toLowerCase().replace(/\s+/g, '-')}`,
  name,
  layout: 'normal',
  type_line: 'Creature - Test',
  image_uris: { normal: 'https://cards.scryfall.io/normal/front/0/0/mock.jpg' },
  games: ['paper']
});

describe('Strict bulk mode live API fallback behavior', () => {
  let app;
  let scryfallLib;
  let bulkData;

  beforeEach(() => {
    jest.resetModules();

    process.env.NODE_ENV = 'test';
    process.env.USE_BULK_DATA = 'true';
    process.env.STRICT_BULK_MODE = 'true';
    process.env.DEFAULT_CARD_BACK = 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';

    jest.doMock('../lib/scryfall', () => ({
      getCard: jest.fn(async (name) => createCard(name)),
      autocompleteCardName: jest.fn(async () => ['Fallback Suggestion']),
      searchCards: jest.fn(async () => []),
      proxyUri: jest.fn(async (uri) => ({ ...createCard('Proxy Card'), uri })),
      setRequestSignalProvider: jest.fn(),
      setLiveApiGuard: jest.fn(),
      globalQueue: { wait: jest.fn(async () => {}) }
    }));

    jest.doMock('../lib/bulk-data', () => ({
      isLoaded: jest.fn(() => true),
      getStats: jest.fn(() => ({ loaded: true, cardCount: 0, lastUpdate: null })),
      getExactTokensByName: jest.fn(() => []),
      getCardByName: jest.fn(() => null),
      getCardByPartialName: jest.fn(() => null),
      getCardByOracleId: jest.fn(() => null),
      getAllPartsById: jest.fn(() => []),
      getCardById: jest.fn(() => null),
      searchCards: jest.fn(() => []),
      isRulingsLoaded: jest.fn(() => false),
      getRulings: jest.fn(() => []),
      getPrintingsByOracleId: jest.fn(() => []),
      buildSearchResultsWithTagData: jest.fn(() => []),
      getUniqueCards: jest.fn(() => []),
      getUniqueCardsBySet: jest.fn(() => []),
      getRandomCards: jest.fn(() => []),
      getUniqueRandomCards: jest.fn(() => []),
      getCardByUri: jest.fn(() => null)
    }));

    jest.doMock('../lib/tag-cache', () => ({
      getStats: jest.fn(() => ({ entries: 0, stale: 0, totalIds: 0 })),
      load: jest.fn(async () => {}),
      ingestUpdate: jest.fn(),
      getTagsForId: jest.fn(() => null),
      setTagsForId: jest.fn()
    }));

    app = require('../server');
    scryfallLib = require('../lib/scryfall');
    bulkData = require('../lib/bulk-data');
  });

  test('GET /card/:name should not call live API in strict bulk mode without forceApi', async () => {
    bulkData.getExactTokensByName.mockReturnValueOnce([]);
    bulkData.getCardByName.mockReturnValueOnce(null);

    const response = await request(app).get('/card/Missing Card');

    expect(response.status).toBe(404);
    expect(String(response.body.details || '')).toContain('Use forceApi=true');
    expect(response.headers['x-bulk-strict']).toBe('true');
    expect(scryfallLib.getCard).not.toHaveBeenCalled();
    expect(scryfallLib.autocompleteCardName).not.toHaveBeenCalled();
  });

  test('GET /card/:name should resolve partial names from bulk in strict mode without forceApi', async () => {
    bulkData.getExactTokensByName.mockReturnValueOnce([]);
    bulkData.getCardByName.mockReturnValueOnce(null);
    bulkData.getCardByPartialName.mockReturnValueOnce(createCard('Lightning Bolt'));

    const response = await request(app).get('/card/bolt');

    expect(response.status).toBe(200);
    expect(response.body.name).toBe('Lightning Bolt');
    expect(scryfallLib.getCard).not.toHaveBeenCalled();
    expect(scryfallLib.autocompleteCardName).not.toHaveBeenCalled();
  });

  test('GET /card/:name should allow live API in strict bulk mode when forceApi=true', async () => {
    bulkData.getExactTokensByName.mockReturnValueOnce([]);
    bulkData.getCardByName.mockReturnValueOnce(null);
    scryfallLib.getCard.mockResolvedValueOnce(createCard('Missing Card'));

    const response = await request(app)
      .get('/card/Missing Card')
      .query({ forceApi: 'true' });

    expect(response.status).toBe(200);
    expect(scryfallLib.getCard).toHaveBeenCalledWith('Missing Card', undefined);
  });

  test('GET /related should not call live API in strict bulk mode without forceApi', async () => {
    bulkData.getCardByOracleId.mockReturnValueOnce(null);
    bulkData.getCardByName.mockReturnValueOnce(null);

    const response = await request(app)
      .get('/related')
      .query({ name: 'Missing Source' });

    expect(response.status).toBe(404);
    expect(String(response.body.details || '')).toContain('Source card not found');
    expect(response.headers['x-bulk-strict']).toBe('true');
    expect(scryfallLib.searchCards).not.toHaveBeenCalled();
    expect(scryfallLib.getCard).not.toHaveBeenCalled();
  });

  test('GET /related resolve=cards should skip unresolved proxy lookups in strict bulk mode without forceApi', async () => {
    const sourceCard = {
      ...createCard('Source Card'),
      id: 'source-id',
      layout: 'normal',
      all_parts: []
    };
    const relatedPart = {
      object: 'related_card',
      id: 'token-id',
      component: 'token',
      name: 'Token Part',
      type_line: 'Token Creature',
      uri: 'https://api.scryfall.com/cards/token-id'
    };

    bulkData.getCardByName.mockReturnValueOnce(sourceCard);
    bulkData.getAllPartsById.mockReturnValueOnce([relatedPart]);
    bulkData.getCardById.mockReturnValueOnce(null);

    const response = await request(app)
      .get('/related')
      .query({ name: 'Source Card', resolve: 'cards' });

    expect(response.status).toBe(200);
    expect(Array.isArray(response.body.data)).toBe(true);
    expect(response.body.data).toHaveLength(0);
    expect(scryfallLib.proxyUri).not.toHaveBeenCalled();
  });

  test('GET /related should allow live source lookup when forceApi=true', async () => {
    bulkData.getCardByOracleId.mockReturnValueOnce(null);
    bulkData.getCardByName.mockReturnValueOnce(null);
    scryfallLib.getCard.mockResolvedValueOnce({ ...createCard('API Source'), all_parts: [] });

    const response = await request(app)
      .get('/related')
      .query({ name: 'API Source', forceApi: 'true' });

    expect(response.status).toBe(200);
    expect(scryfallLib.getCard).toHaveBeenCalledWith('API Source', null);
  });
});
