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
 * Fetch card by Scryfall ID
 */
async function getCardById(id) {
  await limiter.wait();

  try {
    const response = await scryfallClient.get(`/cards/${id}`);
    return response.data;
  } catch (error) {
    if (error.response?.status === 404) {
      throw new Error(`Card not found with ID: ${id}`);
    }
    throw error;
  }
}

/**
 * Fetch card by set code and collector number
 */
async function getCardBySetNumber(set, number, lang = 'en') {
  await limiter.wait();

  try {
    const response = await scryfallClient.get(`/cards/${set}/${number}/${lang}`);
    return response.data;
  } catch (error) {
    if (error.response?.status === 404) {
      throw new Error(`Card not found: ${set} #${number} (${lang})`);
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
 * Get set information by code
 */
async function getSet(setCode) {
  await limiter.wait();

  try {
    const response = await scryfallClient.get(`/sets/${setCode}`);
    return response.data;
  } catch (error) {
    if (error.response?.status === 404) {
      throw new Error(`Set not found: ${setCode}`);
    }
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
 * Get full formatted card text with all details (Amuzet-style++)
 */
function getOracleText(card) {
  let parts = [];
  
  // Mana cost
  if (card.mana_cost) {
    parts.push(`[b]${card.mana_cost}[/b]`);
  }
  
  // Type line
  if (card.type_line) {
    parts.push(`[b]${card.type_line}[/b]`);
  }
  
  // Oracle text
  let text = '';
  if (card.oracle_text) {
    text = card.oracle_text;
  } else if (card.card_faces) {
    // For DFC/MDFC, show both faces
    text = card.card_faces.map((face, idx) => {
      let faceText = [];
      if (face.mana_cost) faceText.push(`[b]${face.mana_cost}[/b]`);
      if (face.type_line) faceText.push(`[b]${face.type_line}[/b]`);
      if (face.oracle_text) faceText.push(face.oracle_text);
      if (face.power && face.toughness) faceText.push(`[b]${face.power}/${face.toughness}[/b]`);
      if (face.loyalty) faceText.push(`[b]Loyalty: ${face.loyalty}[/b]`);
      return faceText.join('\n');
    }).join('\n---\n');
    parts.push(text);
    
    // Early return for multi-face cards since we already formatted everything
    return parts.join('\n');
  }
  
  if (text) {
    parts.push(text);
  }
  
  // P/T or Loyalty
  if (card.power && card.toughness) {
    parts.push(`[b]${card.power}/${card.toughness}[/b]`);
  } else if (card.loyalty) {
    parts.push(`[b]Loyalty: ${card.loyalty}[/b]`);
  }
  
  // Additional info
  const extras = [];
  if (card.keywords && card.keywords.length > 0) {
    extras.push(`Keywords: ${card.keywords.join(', ')}`);
  }
  if (card.produced_mana && card.produced_mana.length > 0) {
    extras.push(`Produces: ${card.produced_mana.join('')}`);
  }
  
  if (extras.length > 0) {
    parts.push(`[i]${extras.join(' • ')}[/i]`);
  }
  
  return parts.join('\n');
}

/**
 * Convert Scryfall card to TTS card object
 */
function convertToTTSCard(scryfallCard, cardBack, position = null) {
  const faceUrl = getCardImageUrl(scryfallCard);
  
  if (!faceUrl) {
    throw new Error(`No image available for ${scryfallCard.name}`);
  }

  const backUrl = getCardBackUrl(scryfallCard, cardBack);
  const oracleText = getOracleText(scryfallCard);

  // Always include Transform with default values
  let transform = {
    posX: 0,
    posY: 0,
    posZ: 0,
    rotX: 0,
    rotY: 0,
    rotZ: 0,
    scaleX: 1,
    scaleY: 1,
    scaleZ: 1
  };

  // Override with position if provided
  if (position && position.x !== undefined) {
    transform.posX = position.x;
    transform.posY = position.y || 0;
    transform.posZ = position.z;
    transform.rotX = position.rotX || 0;
    transform.rotY = position.rotY || 0;
    transform.rotZ = position.rotZ || 0;
  }

  return {
    Name: 'Card',
    Nickname: scryfallCard.name || 'Unknown Card',
    Description: oracleText,
    Memo: scryfallCard.oracle_id || '',
    CardID: 100,
    Transform: transform,
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
 * Get card rulings by card name
 */
async function getCardRulings(cardName) {
  await limiter.wait();

  try {
    // First get the card to get its ID
    const card = await getCard(cardName);
    
    await limiter.wait();
    const response = await scryfallClient.get(`/cards/${card.id}/rulings`);
    return response.data.data || [];
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

/**
 * Proxy a Scryfall API URI
 * Used for fetching cards via their API URIs (e.g., from all_parts array)
 */
async function proxyUri(uri) {
  await limiter.wait();

  try {
    // Extract the path from the full URI
    const urlObj = new URL(uri);
    const path = urlObj.pathname + urlObj.search;
    
    const response = await scryfallClient.get(path);
    return response.data;
  } catch (error) {
    if (error.response?.status === 404) {
      throw new Error(`Resource not found: ${uri}`);
    }
    throw new Error(`Failed to proxy URI: ${error.message}`);
  }
}

module.exports = {
  getCard,
  getCardById,
  getCardBySetNumber,
  searchCards,
  getRandomCard,
  getSet,
  getCardRulings,
  getTokens,
  getPrintings,
  parseDecklist,
  convertToTTSCard,
  getCardImageUrl,
  getCardBackUrl,
  getOracleText,
  proxyUri,
  RateLimiter
};
