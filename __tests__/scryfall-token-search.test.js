jest.mock('axios');
const axios = require('axios');

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

    expect(getMock).toHaveBeenCalledWith(
      `/cards/search?q=${encodeURIComponent('fish is:token -is:dfc')}&unique=cards`
    );
  });
});
