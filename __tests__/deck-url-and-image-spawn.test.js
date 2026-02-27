const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.USE_BULK_DATA = 'false';
process.env.DEFAULT_CARD_BACK = 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';

jest.mock('axios', () => ({
  get: jest.fn()
}));

jest.mock('../lib/bulk-data', () => ({
  isLoaded: jest.fn(() => false),
  getCardByName: jest.fn(),
  getCardById: jest.fn(),
  getCardBySetNumber: jest.fn(),
  getStats: jest.fn(() => ({ loaded: false, cardCount: 0 }))
}));

jest.mock('../lib/scryfall', () => ({
  getCard: jest.fn(),
  autocompleteCardName: jest.fn(() => []),
  getCardById: jest.fn(),
  getCardBySetNumber: jest.fn(),
  searchCards: jest.fn(),
  getRandomCard: jest.fn(),
  getSet: jest.fn(),
  getCardRulings: jest.fn(),
  getPrintings: jest.fn(),
  proxyUri: jest.fn(),
  parseDecklist: jest.fn(),
  convertToTTSCard: jest.fn()
}));

const axios = require('axios');
const scryfallLib = require('../lib/scryfall');
const app = require('../server');

describe('Deck URL imports removal and image spawning', () => {
  beforeEach(() => {
    jest.clearAllMocks();

    scryfallLib.getCard.mockResolvedValue({
      name: 'Island',
      image_uris: { normal: 'https://cards.scryfall.io/normal/front/1/1/test.jpg' }
    });
    scryfallLib.parseDecklist.mockReturnValue([{ count: 1, name: 'Island' }]);
    scryfallLib.convertToTTSCard.mockReturnValue({ Name: 'Card', Nickname: 'Island' });
  });

  test('GET /card/:name supports direct image URL spawning', async () => {
    const imageUrl = 'https://cards.scryfall.io/large/front/0/0/0058be07-a8a1-448e-8c3d-61718cb384ec.jpg?1562875117';
    const response = await request(app).get(`/card/${encodeURIComponent(imageUrl)}`);

    expect(response.status).toBe(200);
    expect(response.body.name).toBe('Custom Image');
    expect(response.body.image_uris.normal).toBe(imageUrl);
    expect(scryfallLib.getCard).not.toHaveBeenCalled();
  });

  test('GET /card/:name supports non-Scryfall image URL spawning', async () => {
    const imageUrl = 'https://i.imgur.com/abc123.png';
    const response = await request(app).get(`/card/${encodeURIComponent(imageUrl)}`);

    expect(response.status).toBe(200);
    expect(response.body.name).toBe('Custom Image');
    expect(response.body.image_uris.normal).toBe(imageUrl);
    expect(scryfallLib.getCard).not.toHaveBeenCalled();
  });

  test('POST /deck rejects removed deck import endpoint', async () => {
    const response = await request(app)
      .post('/deck')
      .set('Content-Type', 'application/octet-stream')
      .send(Buffer.from('https://moxfield.com/decks/mouJgxThWEeaMJnWDczbWw'));

    expect(response.status).toBe(410);
    expect(response.body.details).toContain('removed');
    expect(axios.get).not.toHaveBeenCalled();
  });

  test('POST /build rejects removed deck build endpoint', async () => {
    const response = await request(app)
      .post('/build')
      .set('Content-Type', 'application/octet-stream')
      .send(Buffer.from('https://tappedout.net/mtg-decks/mf-doomhive/'));

    expect(response.status).toBe(410);
    expect(response.body.details).toContain('removed');
    expect(axios.get).not.toHaveBeenCalled();
  });

  test('POST /deck rejects unsupported deck URL hosts via removed endpoint', async () => {
    const response = await request(app)
      .post('/deck')
      .set('Content-Type', 'application/octet-stream')
      .send(Buffer.from('https://example.com/my-deck'));

    expect(response.status).toBe(410);
    expect(response.body.details).toContain('removed');
  });
});
