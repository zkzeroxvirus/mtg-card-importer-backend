jest.mock('axios');
const axios = require('axios');
const { URLSearchParams } = require('url');

describe('Scryfall API - Token Search Query', () => {
  test('searchCards should append -is:dfc for is:token queries', async () => {
    const getMock = jest.fn().mockResolvedValue({ data: { data: [] } });
    axios.create.mockReturnValue({ get: getMock });

    let scryfall;
    jest.isolateModules(() => {
      scryfall = require('../lib/scryfall');
    });

    scryfall.globalQueue.delay = 0;
    scryfall.globalQueue.lastRequest = 0;

    await scryfall.searchCards('fish is:token', 5);

    const expectedParams = new URLSearchParams({
      q: 'fish is:token -is:dfc',
      unique: 'cards'
    });

    expect(getMock).toHaveBeenCalledWith(`/cards/search?${expectedParams.toString()}`);
  });
});
