const axios = require('axios');

const SCRYFALL_API = 'https://api.scryfall.com';
const DELAY = parseInt(process.env.SCRYFALL_DELAY || '50');

// Global request queue - ensures ALL requests (even parallel ones) stay compliant
class GlobalRequestQueue {
  constructor(delay = DELAY) {
    this.delay = delay;
    this.lastRequest = 0;
    this.queue = [];
    this.processing = false;
  }

  async wait() {
    return new Promise(resolve => {
      this.queue.push(resolve);
      this.processQueue();
    });
  }

  async processQueue() {
    if (this.processing || this.queue.length === 0) {
      return;
    }

    this.processing = true;

    while (this.queue.length > 0) {
      const now = Date.now();
      const timeSinceLastRequest = now - this.lastRequest;
      
      if (timeSinceLastRequest < this.delay) {
        await new Promise(resolve => 
          setTimeout(resolve, this.delay - timeSinceLastRequest)
        );
      }

      this.lastRequest = Date.now();
      const resolve = this.queue.shift();
      resolve();
    }

    this.processing = false;
  }
}

const globalQueue = new GlobalRequestQueue();

// Axios instance with headers
// Version should match package.json for compliance with Scryfall API requirements
const packageVersion = require('../package.json').version;
const scryfallClient = axios.create({
  baseURL: SCRYFALL_API,
  headers: {
    'User-Agent': `MTGCardImporterTTS/${packageVersion}`,
    'Accept': 'application/json'
  },
  timeout: 10000
});

/**
 * Retry wrapper with exponential backoff for transient errors (429, 503)
 * Respects Retry-After header if present
 */
async function withRetry(requestFn, maxRetries = 3) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await requestFn();
    } catch (error) {
      const status = error.response?.status;
      const isTransient = [429, 503].includes(status) || error.code === 'ECONNABORTED';
      const isLastAttempt = attempt === maxRetries - 1;
      
      if (!isTransient || isLastAttempt) {
        throw error;
      }
      
      // Calculate delay: respect Retry-After header, otherwise exponential backoff
      let delayMs;
      if (status === 429) {
        const retryAfter = error.response?.headers?.['retry-after'];
        if (retryAfter) {
          // Retry-After can be in seconds or HTTP-date format
          delayMs = isNaN(retryAfter) ? 60000 : parseInt(retryAfter) * 1000;
        } else {
          delayMs = Math.pow(2, attempt) * 1000; // 1s, 2s, 4s
        }
      } else {
        delayMs = Math.pow(2, attempt) * 500; // 500ms, 1s, 2s for 503
      }
      
      // Improved error logging with better context
      let errorDesc = status ? `HTTP ${status}` : error.code || 'Network error';
      if (error.code === 'ECONNABORTED') {
        errorDesc = 'Timeout';
      }
      
      console.warn(
        `Scryfall API error (${errorDesc}), retrying in ${delayMs}ms (attempt ${attempt + 1}/${maxRetries - 1})`
      );
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
}

/**
 * Helper: fetch a token card by its type/name (e.g., "treasure", "clue", "goblin")
 */
async function fetchTokenByType(name) {
  await globalQueue.wait();

  const query = `t:token name:${encodeURIComponent(name)}`;
  const response = await withRetry(() =>
    scryfallClient.get(`/cards/search?q=${query}&unique=cards`)
  );

  const cards = response.data?.data || [];
  return cards.find(card => card.type_line && card.type_line.includes('Token')) || null;
}

/**
 * Fetch single card from Scryfall (simple fuzzy search like OLD importer)
 */
async function getCard(name, set = null) {
  await globalQueue.wait();

  try {
    let url = `/cards/named?fuzzy=${encodeURIComponent(name)}`;
    if (set) {
      url += `&set=${encodeURIComponent(set)}`;
    }

    return await withRetry(() => scryfallClient.get(url).then(r => r.data));
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
  await globalQueue.wait();

  try {
    return await withRetry(() => 
      scryfallClient.get(`/cards/${id}`).then(r => r.data)
    );
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
  await globalQueue.wait();

  try {
    return await withRetry(() => 
      scryfallClient.get(`/cards/${set}/${number}/${lang}`).then(r => r.data)
    );
  } catch (error) {
    if (error.response?.status === 404) {
      throw new Error(`Card not found: ${set} #${number} (${lang})`);
    }
    throw error;
  }
}

/**
 * Search for cards - returns unique card designs (not all printings)
 */
async function searchCards(query, limit = 10, unique = 'cards') {
  await globalQueue.wait();

  try {
    // Automatically exclude DFCs when searching for tokens to avoid duplicate variant cards
    let finalQuery = query;
    if (query.toLowerCase().includes('t:token')) {
      finalQuery = query + ' -is:dfc';
    }

    const response = await withRetry(() => 
      scryfallClient.get(`/cards/search?q=${encodeURIComponent(finalQuery)}&unique=${encodeURIComponent(unique)}`)
    );
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
async function getRandomCard(query = '', suppressLog = false) {
  await globalQueue.wait();

  let url = '/cards/random';
  if (query) {
    url += `?q=${encodeURIComponent(query)}`;
  }
  
  // Allow suppressing logs for bulk operations to reduce spam
  if (!suppressLog) {
    console.log(`Scryfall API call: ${SCRYFALL_API}${url}`);
  }

  try {
    return await withRetry(() => 
      scryfallClient.get(url).then(r => r.data)
    );
  } catch (error) {
    // Provide better error context
    if (error.response?.status === 404) {
      const queryInfo = query ? ` with query: ${query}` : '';
      console.error(`Scryfall 404: ${SCRYFALL_API}${url}`);
      throw new Error(`No random card found${queryInfo} (Scryfall returned 404)`);
    }
    if (error.code === 'ECONNABORTED') {
      console.error(`Scryfall timeout: ${SCRYFALL_API}${url} - ${error.message}`);
      throw new Error(`Request timeout (${error.message})`);
    }
    // Log unexpected errors with more details
    console.error(`Scryfall API error: ${SCRYFALL_API}${url}`, {
      status: error.response?.status,
      code: error.code,
      message: error.message
    });
    throw error;
  }
}

/**
 * Get set information by code
 */
async function getSet(setCode) {
  await globalQueue.wait();

  try {
    return await withRetry(() => 
      scryfallClient.get(`/sets/${setCode}`).then(r => r.data)
    );
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
  if (card.card_faces?.length > 0 && card.card_faces[0]?.image_uris?.normal) {
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
 * Uses dedicated /cards/named/:name/rulings endpoint (1 request instead of 2)
 */
async function getCardRulings(cardName) {
  try {
    // Resolve the card first (handles fuzzy/locale) then fetch rulings by ID
    const card = await getCard(cardName);
    
    // Important: Must wait for global queue before making second API call
    await globalQueue.wait();
    
    const response = await withRetry(() => 
      scryfallClient.get(`/cards/${encodeURIComponent(card.id)}/rulings`)
    );
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
 * Get tokens associated with a card or by token type
 * Supports two modes:
 *   1. Cards that create tokens (e.g., "Doubling Season" -> tokens it creates)
 *   2. Token cards by name (e.g., "bird" -> Bird Token card)
 */
async function getTokens(cardName) {
  await globalQueue.wait();

  // Cap results to avoid client overload
  const MAX_TOKENS = 16;

  // Try to use the card's all_parts relationships first (best signal for tokens)
  try {
    const sourceCard = await getCard(cardName);
    if (sourceCard?.all_parts?.length) {
      const tokenParts = sourceCard.all_parts
        .filter(part => {
          const typeLine = (part.type_line || '').toLowerCase();
          return typeLine.includes('token') || typeLine.includes('emblem');
        })
        .slice(0, MAX_TOKENS);

      const tokensFromParts = [];
      for (const part of tokenParts) {
        try {
          // Important: Must wait for global queue before each API call in loop
          await globalQueue.wait();
          
          const tokenData = await withRetry(() => 
            scryfallClient.get(part.uri).then(r => r.data)
          );
          tokensFromParts.push(tokenData);
        } catch (err) {
          console.warn(`Failed to fetch token from all_parts: ${part.uri}`, err.message);
        }
      }

      if (tokensFromParts.length) {
        return tokensFromParts;
      }
    }
  } catch (err) {
    // Fall back to search if card lookup fails or has no token parts
  }

  try {
    // First, try to find tokens by type/name (ordered newest first)
    await globalQueue.wait();
    
    const typeQuery = `t:token name:"${cardName}"`;
    const typeResponse = await withRetry(() => 
      scryfallClient.get(`/cards/search?q=${encodeURIComponent(typeQuery)}&unique=cards&order=released&dir=desc`)
    );

    if (typeResponse.data && typeResponse.data.data && typeResponse.data.data.length > 0) {
      return typeResponse.data.data
        .filter(card => card.type_line && card.type_line.includes('Token'))
        .slice(0, MAX_TOKENS);
    }

    // Fallback: search for cards that create this token (oracle text search)
    await globalQueue.wait();
    
    const createQuery = `o:"create ${cardName}"`;
    const createResponse = await withRetry(() => 
      scryfallClient.get(`/cards/search?q=${encodeURIComponent(createQuery)}&unique=cards&order=released&dir=desc`)
    );
    
    if (createResponse.data && createResponse.data.data) {
      return createResponse.data.data
        .filter(card => card.type_line && card.type_line.includes('Token'))
        .slice(0, MAX_TOKENS);
    }

    return [];
  } catch (error) {
    // If search fails, return empty array (token may not exist or no cards create it)
    return [];
  }
}

/**
 * Get all printings of a card
 */
async function getPrintings(cardName) {
  await globalQueue.wait();

  try {
    // Get the unique card first
    const cardResponse = await withRetry(() => 
      scryfallClient.get(`/cards/named?fuzzy=${encodeURIComponent(cardName)}`)
    );
    if (!cardResponse.data || cardResponse.data.object === 'error') {
      throw new Error(`Card not found: ${cardName}`);
    }

    const oracleId = cardResponse.data.oracle_id;
    
    // Search for all printings by oracle_id
    const response = await withRetry(() => 
      scryfallClient.get(`/cards/search?q=oracleid:${encodeURIComponent(oracleId)}&unique=prints&order=released`)
    );
    
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
  await globalQueue.wait();

  try {
    // Extract the path from the full URI
    const urlObj = new URL(uri);
    const path = urlObj.pathname + urlObj.search;
    
    const response = await withRetry(() => 
      scryfallClient.get(path)
    );
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
  globalQueue
};
