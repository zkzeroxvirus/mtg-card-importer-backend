const axios = require('axios');
const { URLSearchParams } = require('url');

const SCRYFALL_API = 'https://api.scryfall.com';
const DELAY = parseInt(process.env.SCRYFALL_DELAY || '100');

function shouldUseRateLimitedQueue() {
  const mode = String(process.env.SCRYFALL_RATE_LIMIT_MODE || 'always').toLowerCase();
  if (mode === 'never') {
    return false;
  }
  return true;
}

function parseRetryAfterMs(retryAfterHeader) {
  if (!retryAfterHeader) {
    return null;
  }

  const retryAfterRaw = String(retryAfterHeader).trim();
  const retryAfterSeconds = Number.parseFloat(retryAfterRaw);
  if (Number.isFinite(retryAfterSeconds)) {
    return Math.max(Math.ceil(retryAfterSeconds * 1000), 0);
  }

  const retryAfterDateMs = Date.parse(retryAfterRaw);
  if (Number.isFinite(retryAfterDateMs)) {
    return Math.max(retryAfterDateMs - Date.now(), 0);
  }

  return null;
}

// Global request queue - ensures ALL requests (even parallel ones) stay compliant
class GlobalRequestQueue {
  constructor(delay = DELAY) {
    this.delay = delay;
    this.lastRequest = 0;
    this.queue = [];
    this.processing = false;
  }

  async wait() {
    if (!shouldUseRateLimitedQueue()) {
      return;
    }

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

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/**
 * Normalize a card name for better fuzzy matching
 */
function normalizeCardName(name) {
  if (!name || typeof name !== 'string') return '';
  return name
    .replace(/[_]+/g, ' ')
    .replace(/[“”]/g, '"')
    .replace(/[’]/g, "'")
    .replace(/[^\w\s'\-:,]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

  const ANTE_WORD_REGEX = /\bante\b/i;

/**
 * Build a Scryfall query fragment that excludes non-playable/random-noise cards.
 * Kept in sync with random filtering behavior and tests.
 */
function buildNonPlayableFilter() {
  const exclusions = [
    'is:unique',
    'game:paper',
    '-set:cmb1',
    '-set:cmb2',
    '-set:mb2',
    '-is:oversized',
    '-stamp:acorn',
    '-t:basic',
    '-o:"ante"',
    '-layout:token',
    '-layout:emblem',
    '-set_type:funny'
  ];

  return exclusions.join(' ');
}

/**
 * Check if a card should be excluded from random playable results.
 */
function isNonPlayableCard(card) {
  const set = (card.set || '').toLowerCase();
  if (['cmb1', 'mb2', 'cmb2'].includes(set)) {
    return true;
  }

  const securityStamp = (card.security_stamp || '').toLowerCase();
  if (securityStamp === 'acorn') {
    return true;
  }

  const games = card.games || [];
  if (!games.includes('paper')) {
    return true;
  }

  if (card.oversized === true) {
    return true;
  }

  const setType = (card.set_type || '').toLowerCase();
  if (['funny', 'memorabilia', 'token', 'minigame'].includes(setType)) {
    return true;
  }

  const layout = (card.layout || '').toLowerCase();
  if ([
    'token',
    'double_faced_token',
    'emblem',
    'planar',
    'scheme',
    'vanguard',
    'art_series',
    'reversible_card',
    'augment',
    'host',
    'dungeon',
    'hero',
    'attraction',
    'stickers'
  ].includes(layout)) {
    return true;
  }

  if (layout === 'meld') {
    const collectorNumber = (card.collector_number || '').toLowerCase();
    if (collectorNumber.endsWith('b')) {
      return true;
    }
  }

  const typeLine = (card.type_line || '').toLowerCase();
  if (typeLine.includes('basic')) {
    return true;
  }

  const oracleText = card.oracle_text || '';
  if (ANTE_WORD_REGEX.test(oracleText)) {
    return true;
  }

  return false;
}

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
          const retryAfterMs = parseRetryAfterMs(retryAfter);
          // Ensure minimum delay of 1 second even if Retry-After says 0
          delayMs = Math.max(retryAfterMs ?? 60000, 1000);
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
        `Scryfall API error (${errorDesc}), retrying in ${delayMs}ms (attempt ${attempt + 1}/${maxRetries})`
      );
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
}

/**
 * Fetch single card from Scryfall (simple fuzzy search like OLD importer)
 */
async function getCard(name, set = null) {
  await globalQueue.wait();

  try {
    const normalizedName = normalizeCardName(name);
    let url = `/cards/named?fuzzy=${encodeURIComponent(normalizedName || name)}`;
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
 * Autocomplete card names for better typo recovery
 */
async function autocompleteCardName(query) {
  await globalQueue.wait();

  try {
    const normalizedQuery = normalizeCardName(query);
    const response = await withRetry(() =>
      scryfallClient.get(`/cards/autocomplete?q=${encodeURIComponent(normalizedQuery || query)}`)
    );
    return response.data?.data || [];
  } catch (error) {
    // Autocomplete errors are non-critical, silently return empty array
    console.debug('Autocomplete failed:', error.message);
    return [];
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
 * @param {string} query Scryfall search query
 * @param {number} limit Maximum number of cards to return
 * @param {string} unique Scryfall unique mode (cards/prints)
 * @param {string|null} order Optional Scryfall order (e.g., 'random'); defaults to null
 * @returns {Promise<Array<object>>} Card list (ordering follows Scryfall; random order varies per call)
 */
async function searchCards(query, limit = 10, unique = 'cards', order = null) {
  await globalQueue.wait();

  try {
    const params = new URLSearchParams({
      q: query,
      unique
    });
    if (order) {
      params.set('order', order);
    }
    const response = await withRetry(() => 
      scryfallClient.get(`/cards/search?${params.toString()}`)
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
  const pickImage = (imageUris) => imageUris?.normal || imageUris?.large || imageUris?.png || imageUris?.small || null;

  const direct = pickImage(card.image_uris);
  if (direct) {
    return direct;
  }

  if (card.card_faces?.length > 0) {
    const frontFace = pickImage(card.card_faces[0]?.image_uris);
    if (frontFace) {
      return frontFace;
    }
  }

  return null;
}

/**
 * Get card back image URL (for multi-face cards)
 */
function getCardBackUrl(card, defaultBack) {
  const pickImage = (imageUris) => imageUris?.normal || imageUris?.large || imageUris?.png || imageUris?.small || null;
  if (card.card_faces?.length > 1) {
    const backFace = pickImage(card.card_faces[1]?.image_uris);
    if (backFace) {
      return backFace;
    }
  }
  return defaultBack;
}

function formatTtsNickname(card, fallbackName, cmcValue, isDoubleFaced = false) {
  const name = String(card?.name || fallbackName || 'Unknown Card').replace(/"/g, '');
  const typeLine = String(card?.type_line || '');
  const cmc = Number.isFinite(cmcValue) ? cmcValue : (Number.isFinite(card?.cmc) ? card.cmc : 0);
  return `${name}\n${typeLine}\n${cmc}CMC${isDoubleFaced ? ' DFC' : ''}`;
}

function formatTtsDescription(card) {
  const oracle = String(card?.oracle_text || '').replace(/"/g, "'");
  if (card?.power && card?.toughness) {
    return `${oracle}\n[b]${card.power}/${card.toughness}[/b]`;
  }
  if (card?.loyalty) {
    return `${oracle}\n[b]${card.loyalty}[/b]`;
  }
  return oracle;
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
    text = card.card_faces.map((face, _idx) => {
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

  const backUrl = cardBack;
  const hasDoubleFace = Array.isArray(scryfallCard.card_faces) && scryfallCard.card_faces.length > 1;
  const frontFace = hasDoubleFace ? scryfallCard.card_faces[0] : scryfallCard;
  const frontCmc = Number.isFinite(scryfallCard.cmc) ? scryfallCard.cmc : (Number.isFinite(frontFace?.cmc) ? frontFace.cmc : 0);

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

  const ttsCard = {
    Name: 'Card',
    Nickname: formatTtsNickname(frontFace, scryfallCard.name, frontCmc, hasDoubleFace),
    Description: formatTtsDescription(frontFace),
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
        UniqueBack: false
      }
    },
    DeckIDs: [100]
  };

  if (hasDoubleFace && getCardBackUrl(scryfallCard, null)) {
    const backFace = scryfallCard.card_faces[1];
    const backFaceImage = getCardBackUrl(scryfallCard, null);
    const backFaceCmc = Number.isFinite(scryfallCard.cmc) ? scryfallCard.cmc : (Number.isFinite(backFace?.cmc) ? backFace.cmc : 0);
    ttsCard.States = {
      2: {
        Name: 'Card',
        Nickname: formatTtsNickname(backFace, `${scryfallCard.name || 'Unknown Card'} (Back)`, backFaceCmc, hasDoubleFace),
        Description: formatTtsDescription(backFace),
        Memo: scryfallCard.oracle_id || '',
        CardID: 200,
        Transform: { ...transform },
        CustomDeck: {
          '2': {
            FaceURL: backFaceImage,
            BackURL: cardBack,
            NumWidth: 1,
            NumHeight: 1,
            BackIsHidden: true,
            UniqueBack: false
          }
        }
      }
    };
  }

  return ttsCard;
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

    // Important: Must wait for global queue before second API call
    await globalQueue.wait();
    
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
  autocompleteCardName,
  getCardById,
  getCardBySetNumber,
  searchCards,
  getRandomCard,
  getSet,
  getCardRulings,
  getPrintings,
  parseDecklist,
  convertToTTSCard,
  getCardImageUrl,
  getCardBackUrl,
  getOracleText,
  buildNonPlayableFilter,
  isNonPlayableCard,
  proxyUri,
  globalQueue
};
