const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DEFAULT_CARD_BACK = 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';
process.env.USE_BULK_DATA = 'false';

jest.mock('../lib/scryfall', () => ({
  getCard: jest.fn(),
  searchCards: jest.fn()
}));

const scryfallLib = require('../lib/scryfall');
const app = require('../server');

describe('Token card lookup', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('GET /card/:name prefers exact token match when fuzzy token name differs', async () => {
    scryfallLib.getCard.mockResolvedValue({
      object: 'card',
      name: 'Dinosaur // Treasure',
      type_line: 'Token Creature — Dinosaur // Token Artifact — Treasure',
      layout: 'double_faced_token'
    });

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
    expect(response.body.type_line).toContain('Token Artifact');
  });

  test('GET /card/:name falls back to fuzzy token when no exact match exists', async () => {
    scryfallLib.getCard.mockResolvedValue({
      object: 'card',
      name: 'Dinosaur // Treasure',
      type_line: 'Token Creature — Dinosaur // Token Artifact — Treasure',
      layout: 'double_faced_token'
    });

    scryfallLib.searchCards.mockResolvedValue([]);

    const response = await request(app).get('/card/treasure');

    expect(response.status).toBe(200);
    expect(response.body.name).toBe('Dinosaur // Treasure');
    expect(response.body.layout).toBe('double_faced_token');
  });
});
