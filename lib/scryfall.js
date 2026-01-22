const axios = require('axios');

const SCRYFALL_API = 'https://api.scryfall.com';
const DELAY = parseInt(process.env.SCRYFALL_DELAY || '50');

// Rate limiter - ensures minimum 50ms between requests (Scryfall API requirement)
class RateLimiter {
  constructor(delay = DELAY) {
    this.delay = delay;
    this.lastRequest = 0;
  }

  async wait() {
    const now = Date.now();
    const timeSinceLastRequest = now - this.lastRequest;
    if (timeSinceLastRequest < this.delay) {
      await new Promise(resolve => setTimeout(resolve, this.delay - timeSinceLastRequest));
    }
    this.lastRequest = Date.now();
  }
}

const limiter = new RateLimiter();

// Axios instance with headers
const scryfallClient = axios.create({
  baseURL: SCRYFALL_API,
  headers: {
    'User-Agent': 'MTGCardImporterTTS/1.0',
    'Accept': 'application/json'
  }
});

/**
 * Fetch single card from Scryfall
 */
async function getCard(name, set = null) {
  await limiter.wait();

  try {
    let url = `/cards/named?fuzzy=${encodeURIComponent(name)}`;
    if (set) {
      url += `&set=${encodeURIComponent(set)}`;
    }

    const response = await scryfallClient.get(url);
    return response.data;
  } catch (error) {
    if (error.response?.status === 404) {
      throw new Error(`Card not found: ${name}`);
    }
    throw error;
  }
}

/**
 * Search for cards
 */
async function searchCards(query, limit = 10) {
  await limiter.wait();

  try {
    const response = await scryfallClient.get(`/cards/search?q=${encodeURIComponent(query)}&unique=prints`);
    const cards = response.data.data || [];
    return cards.slice(0, limit);
  } catch (error) {
    if (error.response?.status === 404) {
      return [];
    }
    throw error;
  }
}

/**
 * Get random card
 */
async function getRandomCard(query = '') {
  await limiter.wait();

  try {
    let url = '/cards/random';
    if (query) {
      url += `?q=${encodeURIComponent(query)}`;
    }
    const response = await scryfallClient.get(url);
    return response.data;
  } catch (error) {
    throw error;
  }
}

/**
 * Get card image URL (front face)
 */
function getCardImageUrl(card) {
  if (card.image_uris?.normal) {
    return card.image_uris.normal;
  }
  if (card.card_faces?.[0]?.image_uris?.normal) {
    return card.card_faces[0].image_uris.normal;
  }
  return null;
}

/**
 * Get card back image URL (for multi-face cards)
 */
function getCardBackUrl(card, defaultBack) {
  if (card.card_faces?.length > 1 && card.card_faces[1]?.image_uris?.normal) {
    return card.card_faces[1].image_uris.normal;
  }
  return defaultBack;
}

/**
 * Get oracle text
 */
function getOracleText(card) {
  if (card.oracle_text) {
    return card.oracle_text;
  }
  if (card.card_faces) {
    return card.card_faces.map(face => face.oracle_text || '').join('\n---\n');
  }
  return '';
}

/**
 * Convert Scryfall card to TTS card object
 */
function convertToTTSCard(scryfallCard, cardBack) {
  const faceUrl = getCardImageUrl(scryfallCard);
  
  if (!faceUrl) {
    throw new Error(`No image available for ${scryfallCard.name}`);
  }

  const backUrl = getCardBackUrl(scryfallCard, cardBack);
  const oracleText = getOracleText(scryfallCard);

  return {
    Name: 'Card',
    Nickname: scryfallCard.name || 'Unknown Card',
    Description: oracleText,
    Memo: scryfallCard.oracle_id || '',
    CardID: 100,
    Transform: {
      posX: 0,
      posY: 0,
      posZ: 0,
      rotX: 0,
      rotY: 0,
      rotZ: 0,
      scaleX: 1,
      scaleY: 1,
      scaleZ: 1
    },
    CustomDeck: {
      '1': {
        FaceURL: faceUrl,
        BackURL: backUrl,
        NumWidth: 1,
        NumHeight: 1,
        BackIsHidden: true,
        UniqueBack: false,
        Type: 0
      }
    },
    DeckIDs: [100]
  };
}

/**
 * Get card rulings
 */
async function getCardRulings(cardId) {
  await limiter.wait();

  try {
    const response = await scryfallClient.get(`/cards/${encodeURIComponent(cardId)}/rulings`);
    const rulings = response.data.data || [];
    return rulings;
  } catch (error) {
    if (error.response?.status === 404) {
      return [];
    }
    throw error;
  }
}

/**
 * Parse decklist string into array of {count, name} objects
 */
function parseDecklist(decklistText) {
  const cards = [];
  const lines = decklistText.split('\n');

  for (let line of lines) {
    line = line.trim();
    
    // Skip empty lines and comments
    if (!line || line.startsWith('//')) {
      continue;
    }

    // Parse "count cardname" or "count cardname (set) number"
    const match = line.match(/^(\d+)\s+(.+?)(?:\s*\([^)]+\))?(?:\s+\d+)?$/);
    if (match) {
      const count = parseInt(match[1]);
      let cardName = match[2].trim();
      
      // Remove set info in parentheses if present
      cardName = cardName.replace(/\s*\([^)]+\).*$/, '').trim();
      
      if (cardName) {
        cards.push({ count, name: cardName });
      }
    }
  }

  return cards;
}

/**
 * Get tokens associated with a card
 */
async function getTokens(cardName) {
  await limiter.wait();

  try {
    // Search for tokens created by this card
    const query = `o:"create${cardName}"`;
    const response = await scryfallClient.get(`/cards/search?q=${encodeURIComponent(query)}&unique=cards`);
    
    if (response.data && response.data.data) {
      // Filter to only actual tokens
      return response.data.data.filter(card => card.type_line && card.type_line.includes('Token'));
    }
    return [];
  } catch (error) {
    // If search fails, return empty array (card may not create tokens)
    return [];
  }
}

/**
 * Get all printings of a card
 */
async function getPrintings(cardName) {
  await limiter.wait();

  try {
    // Get the unique card first
    const cardResponse = await scryfallClient.get(`/cards/named?fuzzy=${encodeURIComponent(cardName)}`);
    if (!cardResponse.data || cardResponse.data.object === 'error') {
      throw new Error(`Card not found: ${cardName}`);
    }

    const oracleId = cardResponse.data.oracle_id;
    
    // Search for all printings by oracle_id
    const response = await scryfallClient.get(`/cards/search?q=oracleid:${encodeURIComponent(oracleId)}&unique=prints&order=released`);
    
    if (response.data && response.data.data) {
      return response.data.data;
    }
    return [];
  } catch (error) {
    throw new Error(`Failed to fetch printings: ${error.message}`);
  }
}

module.exports = {
  getCard,
  searchCards,
  getRandomCard,
  getCardRulings,
  getTokens,
  getPrintings,
  parseDecklist,
  convertToTTSCard,
  getCardImageUrl,
  getCardBackUrl,
  getOracleText,
  RateLimiter
};
