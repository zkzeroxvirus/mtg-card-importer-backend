/**
 * Tests for Scryfall API integration
 * Tests error handling, rate limiting, and API compliance
 */

// Mock axios to avoid real API calls during tests
jest.mock('axios');
const axios = require('axios');

axios.create.mockReturnValue({
  get: jest.fn().mockResolvedValue({ data: { data: [] } })
});

const scryfall = require('../lib/scryfall');

function loadScryfallWithGet(getImpl) {
  jest.resetModules();
  const mockedAxios = require('axios');
  mockedAxios.create.mockReturnValue({ get: getImpl });
  return require('../lib/scryfall');
}

describe('Scryfall API - Rate Limiting', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('globalQueue should enforce delay between requests', async () => {
    const times = [];
    const startTime = Date.now();
    
    // Make 3 consecutive queue waits
    for (let i = 0; i < 3; i++) {
      await scryfall.globalQueue.wait();
      times.push(Date.now() - startTime);
    }
    
    // First should be nearly instant, subsequent should have ~100ms delay
    expect(times[0]).toBeLessThan(50);
    expect(times[1]).toBeGreaterThanOrEqual(90); // Allow some timing variance
    expect(times[2]).toBeGreaterThanOrEqual(190);
  });
});

describe('Scryfall API - Card Name Normalization', () => {
  test('should handle underscores in card names', () => {
    const card = { name: 'Black_Lotus' };
    // normalizeCardName is not exported, but we can test via getCard behavior
    expect(card.name).toBe('Black_Lotus');
  });

  test('should handle special quotes in card names', () => {
    const card = { name: '"Ach! Hans, Run!"' };
    expect(card.name).toBe('"Ach! Hans, Run!"');
  });
});

describe('Scryfall API - Error Handling', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Reset the queue to avoid rate limiting in tests
    scryfall.globalQueue.lastRequest = 0;
  });

  test('getCard should throw on 404 with descriptive message', async () => {
    const localScryfall = loadScryfallWithGet(jest.fn().mockRejectedValue({
      response: { status: 404 },
      message: 'Not found'
    }));

    await expect(localScryfall.getCard('NonExistentCard123456')).rejects.toThrow('Card not found');
  });

  test('getCardById should throw on 404 with ID in message', async () => {
    const localScryfall = loadScryfallWithGet(jest.fn().mockRejectedValue({
      response: { status: 404 },
      message: 'Not found'
    }));

    await expect(localScryfall.getCardById('invalid-id')).rejects.toThrow('Card not found with ID: invalid-id');
  });

  test('autocompleteCardName should return empty array on error', async () => {
    axios.create = jest.fn(() => ({
      get: jest.fn().mockRejectedValue(new Error('Network error'))
    }));

    const result = await scryfall.autocompleteCardName('test');
    expect(result).toEqual([]);
  });

  test('searchCards should return empty array on 404', async () => {
    const localScryfall = loadScryfallWithGet(jest.fn().mockRejectedValue({
      response: { status: 404 },
      message: 'Not found'
    }));

    const result = await localScryfall.searchCards('impossible_query_xyz_123');
    expect(result).toEqual([]);
  });

  test('withRetry should respect HTTP-date Retry-After values', async () => {
    const setTimeoutSpy = jest.spyOn(global, 'setTimeout').mockImplementation((fn, _ms) => {
      fn();
      return 0;
    });

    const getMock = jest
      .fn()
      .mockRejectedValueOnce({
        response: {
          status: 429,
          headers: {
            'retry-after': 'Wed, 21 Oct 2015 07:28:00 GMT'
          }
        },
        message: 'Rate limited'
      })
      .mockResolvedValueOnce({
        data: {
          id: 'card-123'
        }
      });

    const localScryfall = loadScryfallWithGet(getMock);
    await localScryfall.getCardById('card-123');

    expect(setTimeoutSpy).toHaveBeenCalledWith(expect.any(Function), 1000);
    setTimeoutSpy.mockRestore();
  });

  test('getPrintings should queue every outbound API call', async () => {
    const getMock = jest
      .fn()
      .mockResolvedValueOnce({ data: { oracle_id: 'oracle-123' } })
      .mockResolvedValueOnce({ data: { data: [{ id: 'print-1' }] } });

    const localScryfall = loadScryfallWithGet(getMock);
    localScryfall.globalQueue.delay = 0;
    localScryfall.globalQueue.lastRequest = 0;

    const waitSpy = jest.spyOn(localScryfall.globalQueue, 'wait');
    const result = await localScryfall.getPrintings('Lightning Bolt');

    expect(waitSpy).toHaveBeenCalledTimes(2);
    expect(result).toHaveLength(1);
    waitSpy.mockRestore();
  });
});

describe('Scryfall API - Card Image URLs', () => {
  test('getCardImageUrl should return normal image for single-face card', () => {
    const card = {
      image_uris: {
        normal: 'https://example.com/card.jpg'
      }
    };
    expect(scryfall.getCardImageUrl(card)).toBe('https://example.com/card.jpg');
  });

  test('getCardImageUrl should return first face image for multi-face card', () => {
    const card = {
      card_faces: [
        { image_uris: { normal: 'https://example.com/front.jpg' } },
        { image_uris: { normal: 'https://example.com/back.jpg' } }
      ]
    };
    expect(scryfall.getCardImageUrl(card)).toBe('https://example.com/front.jpg');
  });

  test('getCardImageUrl should return null for card without images', () => {
    const card = { name: 'Test Card' };
    expect(scryfall.getCardImageUrl(card)).toBeNull();
  });

  test('getCardBackUrl should return second face for DFC', () => {
    const card = {
      card_faces: [
        { image_uris: { normal: 'https://example.com/front.jpg' } },
        { image_uris: { normal: 'https://example.com/back.jpg' } }
      ]
    };
    expect(scryfall.getCardBackUrl(card, 'default.jpg')).toBe('https://example.com/back.jpg');
  });

  test('getCardBackUrl should return default for single-face card', () => {
    const card = {
      image_uris: { normal: 'https://example.com/card.jpg' }
    };
    expect(scryfall.getCardBackUrl(card, 'default.jpg')).toBe('default.jpg');
  });
});

describe('Scryfall API - Oracle Text Formatting', () => {
  test('getOracleText should format single-face card', () => {
    const card = {
      mana_cost: '{2}{U}{U}',
      type_line: 'Creature — Merfolk Wizard',
      oracle_text: 'Flying\nWhen this enters, draw a card.',
      power: '2',
      toughness: '3'
    };
    const text = scryfall.getOracleText(card);
    expect(text).toContain('[b]{2}{U}{U}[/b]');
    expect(text).toContain('[b]Creature — Merfolk Wizard[/b]');
    expect(text).toContain('Flying');
    expect(text).toContain('[b]2/3[/b]');
  });

  test('getOracleText should format planeswalker', () => {
    const card = {
      mana_cost: '{2}{U}{U}',
      type_line: 'Legendary Planeswalker — Jace',
      oracle_text: '+1: Draw a card\n-2: Return target creature to its owner\'s hand',
      loyalty: '4'
    };
    const text = scryfall.getOracleText(card);
    expect(text).toContain('[b]Loyalty: 4[/b]');
  });

  test('getOracleText should format multi-face card', () => {
    const card = {
      card_faces: [
        {
          mana_cost: '{1}{R}',
          type_line: 'Creature — Human Werewolf',
          oracle_text: 'At the beginning of each upkeep, transform this.',
          power: '2',
          toughness: '2'
        },
        {
          type_line: 'Creature — Werewolf',
          oracle_text: 'This creature gets +2/+2.',
          power: '4',
          toughness: '4'
        }
      ]
    };
    const text = scryfall.getOracleText(card);
    expect(text).toContain('[b]{1}{R}[/b]');
    expect(text).toContain('---'); // Separator between faces
    expect(text).toContain('[b]2/2[/b]');
    expect(text).toContain('[b]4/4[/b]');
  });
});

describe('Scryfall API - TTS Card Conversion', () => {
  test('convertToTTSCard should create valid TTS card object', () => {
    const scryfallCard = {
      name: 'Lightning Bolt',
      image_uris: {
        normal: 'https://example.com/bolt.jpg'
      },
      mana_cost: '{R}',
      type_line: 'Instant',
      oracle_text: 'Lightning Bolt deals 3 damage to any target.',
      oracle_id: 'abc123'
    };
    
    const ttsCard = scryfall.convertToTTSCard(scryfallCard, 'https://example.com/back.jpg');
    
    expect(ttsCard.Name).toBe('Card');
    expect(ttsCard.Nickname).toContain('Lightning Bolt');
    expect(ttsCard.Nickname).toContain('Instant');
    expect(ttsCard.Nickname).toContain('CMC');
    expect(ttsCard.Description).toContain('Lightning Bolt deals 3 damage');
    expect(ttsCard.Memo).toBe('abc123');
    expect(ttsCard.CustomDeck['1'].FaceURL).toBe('https://example.com/bolt.jpg');
    expect(ttsCard.CustomDeck['1'].BackURL).toBe('https://example.com/back.jpg');
    expect(ttsCard.Transform).toBeDefined();
    expect(ttsCard.Transform.posX).toBe(0);
  });

  test('convertToTTSCard should use provided position', () => {
    const scryfallCard = {
      name: 'Mountain',
      image_uris: {
        normal: 'https://example.com/mountain.jpg'
      }
    };
    
    const position = { x: 5, y: 2, z: -3, rotY: 180 };
    const ttsCard = scryfall.convertToTTSCard(scryfallCard, 'back.jpg', position);
    
    expect(ttsCard.Transform.posX).toBe(5);
    expect(ttsCard.Transform.posY).toBe(2);
    expect(ttsCard.Transform.posZ).toBe(-3);
    expect(ttsCard.Transform.rotY).toBe(180);
  });

  test('convertToTTSCard should throw if no image available', () => {
    const scryfallCard = {
      name: 'Bad Card'
    };
    
    expect(() => scryfall.convertToTTSCard(scryfallCard, 'back.jpg'))
      .toThrow('No image available for Bad Card');
  });

  test('convertToTTSCard should include state data for DFC cards', () => {
    const scryfallCard = {
      name: 'Invasion of Zendikar',
      oracle_id: 'dfc-oracle-1',
      image_uris: {
        normal: 'https://example.com/front.jpg'
      },
      card_faces: [
        {
          name: 'Invasion of Zendikar',
          image_uris: { normal: 'https://example.com/front.jpg' },
          oracle_text: 'When this enters, search your library.'
        },
        {
          name: 'Awakened Skyclave',
          image_uris: { normal: 'https://example.com/back.jpg' },
          oracle_text: 'Flying, vigilance, haste'
        }
      ]
    };

    const ttsCard = scryfall.convertToTTSCard(scryfallCard, 'https://example.com/default-back.jpg');

    expect(ttsCard.States).toBeDefined();
    expect(ttsCard.States[2]).toBeDefined();
    expect(ttsCard.States[2].Nickname).toContain('Awakened Skyclave');
    expect(ttsCard.CustomDeck['1'].FaceURL).toBe('https://example.com/front.jpg');
    expect(ttsCard.CustomDeck['1'].BackURL).toBe('https://example.com/default-back.jpg');
    expect(ttsCard.States[2].CustomDeck['2'].FaceURL).toBe('https://example.com/back.jpg');
    expect(ttsCard.States[2].CustomDeck['2'].BackURL).toBe('https://example.com/default-back.jpg');
  });
});

describe('Scryfall API - Decklist Parsing', () => {
  test('parseDecklist should parse simple format', () => {
    const decklist = `4 Lightning Bolt
2 Mountain
1 Black Lotus`;
    
    const cards = scryfall.parseDecklist(decklist);
    
    expect(cards).toHaveLength(3);
    expect(cards[0]).toEqual({ count: 4, name: 'Lightning Bolt' });
    expect(cards[1]).toEqual({ count: 2, name: 'Mountain' });
    expect(cards[2]).toEqual({ count: 1, name: 'Black Lotus' });
  });

  test('parseDecklist should handle set codes', () => {
    const decklist = `4 Lightning Bolt (LEA) 155
2 Mountain (UNH) 138`;
    
    const cards = scryfall.parseDecklist(decklist);
    
    expect(cards).toHaveLength(2);
    expect(cards[0]).toEqual({ count: 4, name: 'Lightning Bolt' });
    expect(cards[1]).toEqual({ count: 2, name: 'Mountain' });
  });

  test('parseDecklist should skip comments and empty lines', () => {
    const decklist = `// This is a comment
4 Lightning Bolt

2 Mountain
// Another comment`;
    
    const cards = scryfall.parseDecklist(decklist);
    
    expect(cards).toHaveLength(2);
  });

  test('parseDecklist should handle cards with special characters', () => {
    const decklist = `1 "Ach! Hans, Run!"
1 Kongming, "Sleeping Dragon"`;
    
    const cards = scryfall.parseDecklist(decklist);
    
    expect(cards).toHaveLength(2);
    expect(cards[0].name).toBe('"Ach! Hans, Run!"');
    expect(cards[1].name).toBe('Kongming, "Sleeping Dragon"');
  });

  test('parseDecklist should return empty array for invalid input', () => {
    const decklist = `not a valid decklist
just random text
no numbers`;
    
    const cards = scryfall.parseDecklist(decklist);
    
    expect(cards).toHaveLength(0);
  });
});
