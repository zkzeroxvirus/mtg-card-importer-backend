const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const compression = require('compression');
require('dotenv').config();

const scryfallLib = require('./lib/scryfall');
const bulkData = require('./lib/bulk-data');

const app = express();

// Runtime config
const PORT = process.env.PORT || 3000;
const DEFAULT_BACK = process.env.DEFAULT_CARD_BACK || 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';
const USE_BULK_DATA = process.env.USE_BULK_DATA === 'true';
const VERBOSE_REQUEST_LOGS = process.env.VERBOSE_REQUEST_LOGS === 'true';

function debugLog(...args) {
  if (VERBOSE_REQUEST_LOGS) {
    console.log(...args);
  }
}

// Security and limits
const MAX_INPUT_LENGTH = 10000; // 10KB max for card names, queries, etc.
const MAX_SEARCH_LIMIT = 1000; // Maximum cards to return in search
const MAX_CACHE_SIZE = parseInt(process.env.MAX_CACHE_SIZE || '5000', 10); // Maximum size for failed query and error caches
// Bulk data URI guardrails
const BULK_URI_BLOCKED_IDENTIFIERS = new Set([
  'named',
  'search',
  'random',
  'collection',
  'autocomplete',
  'multiverse',
  'arena',
  'mtgo',
  'tcgplayer'
]);

// Random card deduplication constants
// When fetching multiple random cards, request extra to account for duplicates
// A 1.5x multiplier balances between API efficiency and getting enough unique cards
const DUPLICATE_BUFFER_MULTIPLIER = 1.5;
const MAX_RETRY_ATTEMPTS_MULTIPLIER = 3; // Retry up to 3x the requested count for bulk data
const RANDOM_SEARCH_UNIQUE = 'prints';
const RANDOM_SEARCH_ORDER = 'random';

function parseBooleanLike(value) {
  if (typeof value === 'boolean') {
    return value;
  }

  if (typeof value === 'number') {
    if (value === 1) return true;
    if (value === 0) return false;
    return null;
  }

  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim().toLowerCase();
  if (['true', '1', 'on', 'enable', 'enabled', 'yes'].includes(normalized)) {
    return true;
  }
  if (['false', '0', 'off', 'disable', 'disabled', 'no'].includes(normalized)) {
    return false;
  }

  return null;
}

function extractTrailingCount(rawQuery) {
  const query = String(rawQuery || '');
  const match = query.match(/(?:^|[\s+])(\d+)\s*$/);
  if (!match) {
    return { query, count: null };
  }

  // Do not treat the trailing number as count when it belongs to an operator
  // expression, e.g. "power = 3", "tou >= 5", or "mv: 3".
  const prefix = query.slice(0, match.index);
  if (/(?:[:=<>!]=?)\s*$/i.test(prefix)) {
    return { query, count: null };
  }

  const count = Number.parseInt(match[1], 10);
  if (!Number.isFinite(count)) {
    return { query, count: null };
  }

  const trimmedQuery = query.slice(0, match.index).trim();
  return { query: trimmedQuery, count };
}

function hasStructuredFilters(query) {
  if (!query) {
    return false;
  }
  const filterRegex = /(?:^|[\s+(])(?:t|type|s|set|r|rarity|c|color|id|identity|o|oracle|name|cmc|mv|pow|power|tou|toughness|loy|loyalty|is|f|format|legal|banned|restricted|layout|wm|watermark|lang|language|game|frame|border|stamp|has|kw|keyword|a|artist|ft|flavor|block|prints|usd|eur|tix|produces|m|mana|year|date):/i;
  return filterRegex.test(String(query));
}
function getRandomUniqKey(card) {
  if (!card || typeof card !== 'object') {
    return null;
  }

  if (card.oracle_id && typeof card.oracle_id === 'string') {
    return `oracle:${card.oracle_id}`;
  }

  if (card.id && typeof card.id === 'string') {
    return `id:${card.id}`;
  }

  if (card.name && typeof card.name === 'string') {
    return `name:${card.name.trim().toLowerCase()}`;
  }

  return null;
}

function ensureCommanderLegalityQuery(rawQuery) {
  let query = String(rawQuery || '').trim();
  if (!query) {
    return 'f:commander';
  }

  // Normalize common commander format aliases to canonical format name.
  query = query
    .replace(/\b(f|format|legal):c\b/ig, '$1:commander')
    .replace(/\b(f|format|legal):edh\b/ig, '$1:commander');

  if (/\b(?:f|format|legal):commander\b/i.test(query)) {
    return query;
  }

  return `${query} f:commander`;
}

function hasExplicitFormatLegalityFilter(rawQuery) {
  const query = String(rawQuery || '');
  return /\b(?:f|format|legal):/i.test(query);
}

function shouldBypassCommanderForTypeQuery(rawQuery) {
  const query = String(rawQuery || '');
  if (!query) {
    return false;
  }

  if (hasExplicitFormatLegalityFilter(query)) {
    return false;
  }

  return /\b(?:t|type):\s*"?(?:token|emblem|vanguard|conspiracy)\b/i.test(query);
}

function normalizeCommanderFormatAliases(rawQuery) {
  const query = String(rawQuery || '').trim();
  if (!query) {
    return query;
  }

  return query
    .replace(/\b(f|format|legal):c\b/ig, '$1:commander')
    .replace(/\b(f|format|legal):edh\b/ig, '$1:commander');
}

function escapeScryfallQuotedValue(value) {
  return String(value || '')
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"');
}

function buildExactTokenLookupQuery(name, set) {
  const escapedName = escapeScryfallQuotedValue(name);
  const baseQuery = `!"${escapedName}" t:token -is:dfc`;
  if (!set) {
    return baseQuery;
  }

  return `${baseQuery} set:${String(set).toLowerCase()}`;
}

function isTokenCard(card) {
  if (!card || typeof card !== 'object') {
    return false;
  }

  const layout = typeof card.layout === 'string' ? card.layout.toLowerCase() : '';
  if (layout === 'token') {
    return true;
  }

  if (typeof card.type_line === 'string' && /\btoken\b/i.test(card.type_line)) {
    return true;
  }

  if (Array.isArray(card.card_faces)) {
    return card.card_faces.some((face) => typeof face?.type_line === 'string' && /\btoken\b/i.test(face.type_line));
  }

  return false;
}

function shouldBypassCommanderForCard(card) {
  if (!card || typeof card !== 'object') {
    return false;
  }

  if (isTokenCard(card)) {
    return true;
  }

  const layout = String(card.layout || '').toLowerCase();
  if (layout === 'emblem' || layout === 'vanguard' || layout === 'conspiracy') {
    return true;
  }

  const typeLine = String(card.type_line || '').toLowerCase();
  return typeLine.includes('emblem') || typeLine.includes('vanguard') || typeLine.includes('conspiracy');
}

function buildDeckCustomObject(ttsCards, hand) {
  const deckTransform = {
    posX: hand?.position?.x || 0,
    posY: hand?.position?.y || 0,
    posZ: hand?.position?.z || 0,
    rotX: hand?.rotation?.x || 0,
    rotY: hand?.rotation?.y || 0,
    rotZ: hand?.rotation?.z || 180,
    scaleX: 1,
    scaleY: 1,
    scaleZ: 1
  };

  const deckObject = {
    CardID: 0,
    Name: 'DeckCustom',
    Nickname: 'Deck',
    Description: '',
    Transform: deckTransform,
    HideWhenFaceDown: false,
    AltLookAngle: { x: 0, y: 0, z: 0 },
    DeckIDs: [],
    CustomDeck: {},
    ContainedObjects: []
  };

  ttsCards.forEach((ttsCard, index) => {
    const deckNum = index + 1;
    const cardId = deckNum * 100;
    const customDeckEntry = ttsCard?.CustomDeck?.['1'] || ttsCard?.CustomDeck?.[1] || {};
    const stateTwo = ttsCard?.States?.[2];

    deckObject.DeckIDs.push(cardId);
    deckObject.CustomDeck[String(deckNum)] = {
      FaceURL: customDeckEntry.FaceURL,
      BackURL: customDeckEntry.BackURL,
      NumWidth: customDeckEntry.NumWidth || 1,
      NumHeight: customDeckEntry.NumHeight || 1,
      BackIsHidden: customDeckEntry.BackIsHidden !== false,
      UniqueBack: customDeckEntry.UniqueBack === true
    };

    const containedCard = {
      CardID: cardId,
      Name: 'Card',
      Nickname: ttsCard?.Nickname || 'Unknown Card',
      Description: ttsCard?.Description || '',
      Memo: ttsCard?.Memo || '',
      Transform: {
        posX: 0,
        posY: 1,
        posZ: 0,
        rotX: 0,
        rotY: 180,
        rotZ: 0,
        scaleX: 1,
        scaleY: 1,
        scaleZ: 1
      },
      HideWhenFaceDown: true,
      AltLookAngle: { x: 0, y: 0, z: 0 }
    };

    if (stateTwo?.CustomDeck) {
      const stateDeckNum = ttsCards.length + deckNum;
      const stateCardId = stateDeckNum * 100;
      const stateCustomDeckEntry = stateTwo.CustomDeck['2'] || stateTwo.CustomDeck[2] || stateTwo.CustomDeck[String(stateDeckNum)] || {};

      deckObject.CustomDeck[String(stateDeckNum)] = {
        FaceURL: stateCustomDeckEntry.FaceURL,
        BackURL: stateCustomDeckEntry.BackURL,
        NumWidth: stateCustomDeckEntry.NumWidth || 1,
        NumHeight: stateCustomDeckEntry.NumHeight || 1,
        BackIsHidden: stateCustomDeckEntry.BackIsHidden !== false,
        UniqueBack: stateCustomDeckEntry.UniqueBack === true
      };

      containedCard.States = {
        2: {
          CardID: stateCardId,
          Name: 'Card',
          Nickname: stateTwo.Nickname || `${ttsCard?.Nickname || 'Unknown Card'} (Back)`,
          Description: stateTwo.Description || '',
          Memo: stateTwo.Memo || ttsCard?.Memo || '',
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
            [String(stateDeckNum)]: {
              FaceURL: stateCustomDeckEntry.FaceURL,
              BackURL: stateCustomDeckEntry.BackURL,
              NumWidth: stateCustomDeckEntry.NumWidth || 1,
              NumHeight: stateCustomDeckEntry.NumHeight || 1,
              BackIsHidden: stateCustomDeckEntry.BackIsHidden !== false,
              UniqueBack: stateCustomDeckEntry.UniqueBack === true
            }
          },
          AltLookAngle: stateTwo.AltLookAngle || { x: 0, y: 0, z: 0 },
          HideWhenFaceDown: stateTwo.HideWhenFaceDown === true
        }
      };
    }

    deckObject.ContainedObjects.push(containedCard);
  });

  return deckObject;
}

// Security: Validate card back URL is from allowed domains
function isValidCardBackURL(url) {
  if (!url || typeof url !== 'string') return false;
  try {
    const parsed = new URL(url);
    // Allow common image hosting domains used by TTS community
    const allowedDomains = [
      'steamusercontent-a.akamaihd.net',
      'steamusercontent.com',
      'steamuserimages-a.akamaihd.net',
      'i.imgur.com',
      'imgur.com'
    ];
    const hostname = String(parsed.hostname || '').toLowerCase();
    return allowedDomains.some(domain => hostname === domain || hostname.endsWith(`.${domain}`));
  } catch (e) {
    // Invalid URL format
    console.debug('Invalid card back URL:', e.message);
    return false;
  }
}

function parseRandomBuildPayload(req) {
  if (!req || !req.body) {
    return null;
  }

  const bodyText = req.body.toString('utf8');
  if (!bodyText || !bodyText.trim()) {
    return {};
  }

  try {
    const parsed = JSON.parse(bodyText);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return null;
  }
}

function shouldRateLimitRandomRequest(req) {
  const method = String(req?.method || 'GET').toUpperCase();
  let rawQueryInput = '';
  let enforceCommanderInput;
  let forceApiInput;

  if (method === 'POST') {
    const payload = parseRandomBuildPayload(req);
    // Invalid payloads are rejected before any API calls, so skip rate limiting here.
    if (payload === null) {
      return false;
    }
    rawQueryInput = String(payload.q || '');
    enforceCommanderInput = payload.enforceCommander;
    forceApiInput = payload.forceApi;
  } else {
    rawQueryInput = String(req?.query?.q || '');
    enforceCommanderInput = req?.query?.enforceCommander;
    forceApiInput = req?.query?.forceApi;
  }

  const { query: rawQuery } = extractTrailingCount(rawQueryInput);
  const { query: normalizedQuery } = normalizeQueryOperators(rawQuery);
  const languageEnforcedQuery = enforceDefaultQueryLanguage(normalizedQuery);
  const enforceCommander = enforceCommanderInput === undefined
    ? true
    : parseBooleanLike(String(enforceCommanderInput)) !== false;
  const bypassCommanderForTypeQuery = enforceCommander && shouldBypassCommanderForTypeQuery(languageEnforcedQuery);
  const randomQuery = (enforceCommander && !bypassCommanderForTypeQuery)
    ? ensureCommanderLegalityQuery(languageEnforcedQuery)
    : normalizeCommanderFormatAliases(languageEnforcedQuery);

  const priceFilterPresent = hasPriceFilter(randomQuery);
  const apiOnlyFilterPresent = hasApiOnlyFilter(randomQuery);
  const forceApi = parseBooleanLike(String(forceApiInput)) === true;
  const executionPlan = buildRandomExecutionPlan({
    useBulkLoaded: USE_BULK_DATA && bulkData.isLoaded(),
    hasPriceFilter: priceFilterPresent,
    hasApiOnlyFilter: apiOnlyFilterPresent,
    forceApi
  });
  return executionPlan.primary === 'api';
}

// Validate the default card back URL on startup
if (!isValidCardBackURL(DEFAULT_BACK)) {
  console.error('ERROR: DEFAULT_CARD_BACK URL is not from an allowed domain. Server will not start.');
  console.error('Allowed domains: Steam CDN, Imgur');
  process.exit(1);
}

// Rate limiters
const randomLimiter = rateLimit({
  windowMs: 60 * 1000,      // 1 minute
  max: 50,                  // 50 requests per minute per IP
  keyGenerator: (req) => req.ip,
  message: 'Too many random card requests from this IP, please try again later',
  // Only rate-limit requests that are expected to hit Scryfall API.
  skip: (req) => !shouldRateLimitRandomRequest(req)
});

// Middleware
app.use(cors());

// Enable compression for all responses (improves bandwidth efficiency)
app.use(compression({
  filter: (req, res) => {
    if (req.headers['x-no-compression']) {
      return false;
    }
    return compression.filter(req, res);
  },
  level: 6 // Balance between compression speed and ratio
}));

const rawBodyParser = express.raw({ type: '*/*', limit: '10mb' });
app.use((req, res, next) => {
  const method = String(req.method || '').toUpperCase();
  if (method === 'GET' || method === 'HEAD' || method === 'OPTIONS') {
    return next();
  }
  return rawBodyParser(req, res, next);
});  // Parse raw body only for methods that can carry payloads

// Performance metrics tracking
const metrics = {
  requests: 0,
  errors: 0,
  startTime: Date.now()
};

// Request counter middleware
app.use((req, res, next) => {
  metrics.requests++;
  
  // Track response time
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    if (res.statusCode >= 500) {
      metrics.errors++;
    }
    
    // Log slow requests (> 5 seconds)
    if (duration > 5000) {
      console.warn(`[Perf] Slow request: ${req.method} ${req.path} took ${duration}ms`);
    }
  });
  
  next();
});


// Normalize errors from Scryfall/API calls into consistent JSON for the importer
function normalizeError(error, defaultStatus = 502) {
  let status = error?.response?.status;
  if (!status) {
    if (error?.code === 'ECONNABORTED') {
      status = 504; // Gateway Timeout
    } else if (error?.message && /not found/i.test(error.message)) {
      status = 404;
    } else {
      status = defaultStatus;
    }
  }

  const details =
    error?.response?.data?.details ||
    error?.response?.data?.error ||
    error?.message ||
    'Request failed';

  return { status, details };
}

function sanitizeCardForResponse(card) {
  if (!card || typeof card !== 'object') {
    return card;
  }

  const clone = { ...card };
  for (const key of Object.keys(clone)) {
    if (key.startsWith('_')) {
      delete clone[key];
    }
  }

  if (Array.isArray(clone.all_parts)) {
    clone.all_parts = clone.all_parts.map(part => {
      if (!part || typeof part !== 'object') {
        return part;
      }
      const partClone = { ...part };
      delete partClone.card;
      for (const key of Object.keys(partClone)) {
        if (key.startsWith('_')) {
          delete partClone[key];
        }
      }
      return partClone;
    });
  }

  if (Array.isArray(clone.card_faces)) {
    clone.card_faces = clone.card_faces.map(face => {
      if (!face || typeof face !== 'object') {
        return face;
      }
      const faceClone = { ...face };
      for (const key of Object.keys(faceClone)) {
        if (key.startsWith('_')) {
          delete faceClone[key];
        }
      }
      return faceClone;
    });
  }

  return clone;
}

function sanitizeCardsForResponse(cards) {
  if (!Array.isArray(cards)) {
    return cards;
  }
  return cards.map(sanitizeCardForResponse);
}

function sanitizeCardForSpawn(card) {
  const normalized = sanitizeCardForResponse(card);
  if (!normalized || typeof normalized !== 'object') {
    return normalized;
  }

  const spawnCard = {
    object: normalized.object,
    id: normalized.id,
    oracle_id: normalized.oracle_id,
    name: normalized.name,
    lang: normalized.lang,
    set: normalized.set,
    collector_number: normalized.collector_number,
    layout: normalized.layout,
    image_status: normalized.image_status,
    image_uris: normalized.image_uris,
    card_faces: normalized.card_faces,
    type_line: normalized.type_line,
    cmc: normalized.cmc,
    oracle_text: normalized.oracle_text,
    power: normalized.power,
    toughness: normalized.toughness,
    loyalty: normalized.loyalty
  };

  return spawnCard;
}

function sanitizeCardsForSpawn(cards) {
  if (!Array.isArray(cards)) {
    return cards;
  }
  return cards.map(sanitizeCardForSpawn);
}

function getRelatedSourceKind(card) {
  if (!card || typeof card !== 'object') {
    return 'other';
  }

  const layout = String(card.layout || '').toLowerCase();
  if (layout === 'emblem') {
    return 'emblem';
  }
  if (layout === 'token' || layout === 'double_faced_token') {
    return 'token';
  }

  const typeLine = String(card.type_line || '').toLowerCase();
  if (typeLine.includes('emblem')) {
    return 'emblem';
  }
  if (typeLine.includes('token')) {
    return 'token';
  }

  return 'other';
}

function shouldIncludeRelatedPart(sourceCard, part) {
  if (!part || typeof part !== 'object') {
    return false;
  }

  const sourceKind = getRelatedSourceKind(sourceCard);
  const component = String(part.component || '').toLowerCase();
  const partTypeLine = String(part.type_line || part.card?.type_line || '').toLowerCase();
  const isTokenType = partTypeLine.includes('token');
  const isEmblemType = partTypeLine.includes('emblem');

  if (sourceKind === 'token') {
    // Token cards may spawn other token cards, but not emblem/creator combo pieces.
    return component === 'token' || isTokenType;
  }

  if (sourceKind === 'emblem') {
    // Emblems may spawn token cards, but should not chain into other emblem parts.
    return component === 'token' || isTokenType;
  }

  return isTokenType || isEmblemType;
}

function isSameCardReference(sourceCard, part) {
  if (!sourceCard || !part) {
    return false;
  }

  const sourceId = String(sourceCard.id || '').trim();
  const partId = String(part.id || part.card?.id || '').trim();
  if (sourceId && partId && sourceId === partId) {
    return true;
  }

  const sourceOracleId = String(sourceCard.oracle_id || '').trim();
  const partOracleId = String(part.oracle_id || part.card?.oracle_id || '').trim();
  if (sourceOracleId && partOracleId && sourceOracleId === partOracleId) {
    return true;
  }

  const sourceName = String(sourceCard.name || '').trim().toLowerCase();
  const partName = String(part.name || part.card?.name || '').trim().toLowerCase();
  return Boolean(sourceName && partName && sourceName === partName);
}

function buildRelatedPartPayload(part) {
  return {
    id: part.id,
    component: part.component,
    name: part.name,
    type_line: part.type_line || part.card?.type_line,
    uri: part.uri
  };
}

function isDirectImageUrl(urlString) {
  if (typeof urlString !== 'string') {
    return false;
  }

  let urlObj;
  try {
    urlObj = new URL(urlString.trim());
  } catch {
    return false;
  }

  if (!/^https?:$/i.test(urlObj.protocol)) {
    return false;
  }

  return true;
}

function createSingleImageSpawnCard(imageUrl) {
  const normalized = imageUrl.trim();
  return {
    object: 'card',
    id: `image-spawn-${Buffer.from(normalized).toString('base64').slice(0, 24)}`,
    oracle_id: '',
    name: 'Custom Image',
    lang: 'en',
    released_at: null,
    uri: null,
    scryfall_uri: null,
    layout: 'normal',
    highres_image: true,
    image_status: 'highres_scan',
    image_uris: {
      small: normalized,
      normal: normalized,
      large: normalized,
      png: normalized,
      art_crop: normalized,
      border_crop: normalized
    },
    mana_cost: '',
    cmc: 0,
    type_line: 'Custom Image',
    oracle_text: '',
    power: null,
    toughness: null
  };
}

function cardHasUsableImage(card) {
  if (!card || typeof card !== 'object') {
    return false;
  }

  const hasFaceImage = (imageUris) => Boolean(
    imageUris && (imageUris.normal || imageUris.large || imageUris.png || imageUris.small)
  );

  if (hasFaceImage(card.image_uris)) {
    return true;
  }

  if (Array.isArray(card.card_faces) && card.card_faces.length > 0) {
    return card.card_faces.some(face => hasFaceImage(face?.image_uris));
  }

  return false;
}

async function hydrateCardForTts(card) {
  if (!card || typeof card !== 'object') {
    return card;
  }

  if (cardHasUsableImage(card)) {
    return card;
  }

  try {
    if (card.id) {
      return await scryfallLib.getCardById(card.id);
    }
    if (card.name) {
      return await scryfallLib.getCard(card.name, card.set || null);
    }
  } catch (error) {
    console.warn(`[Hydrate] Failed to enrich card images for ${card.name || card.id || 'unknown'}: ${error.message}`);
  }

  return card;
}

const COLON_ONLY_PREFIXES = [
  'is', 't', 'type', 's', 'set', 'r', 'rarity', 'o', 'oracle', 'name',
  'a', 'artist', 'ft', 'flavor', 'k', 'kw', 'keyword', 'layout', 'wm', 'watermark',
  'lang', 'language', 'game', 'format', 'f', 'legal', 'banned', 'restricted',
  'block', 'stamp', 'frame', 'border', 'has'
];
const COLON_ONLY_PREFIX_PATTERN = COLON_ONLY_PREFIXES.join('|');
const COLON_ONLY_PREFIX_REPLACE = new RegExp(`(^|[\\s+\\(])(-?(?:${COLON_ONLY_PREFIX_PATTERN}))=`, 'gi');
const POWER_TOUGHNESS_OPERATOR_WITH_SPACED_EQUAL_REPLACE = new RegExp(
  '(^|[\\s+\\(])(-?(?:pow|power|tou|toughness))\\s*([<>])\\s*=\\s*(-?\\d+)\\b',
  'gi'
);
const POWER_TOUGHNESS_OPERATOR_SPACING_REPLACE = new RegExp(
  '(^|[\\s+\\(])(-?(?:pow|power|tou|toughness))\\s*([=<>])\\s*(-?\\d+)\\b',
  'gi'
);
const RARITY_COMPARISON_REPLACE = new RegExp(
  '(^|[\\s+\\(])(-?(?:r|rarity))(<=|>=|!=|=|:|<|>)(mythic_rare|mythicrare|mythic|rare|uncommon|common)\\b',
  'gi'
);
const COLORLESS_COLOR_FILTER_REPLACE = new RegExp(
  '(^|[\\s+\\(])(-?(?:c|color))\\s*([:=])\\s*(c|colorless)\\b',
  'gi'
);

function normalizeRarityValue(rawValue) {
  const rarityValue = String(rawValue || '').toLowerCase();
  if (rarityValue === 'mythicrare' || rarityValue === 'mythic_rare') {
    return 'mythic';
  }
  return rarityValue;
}

const DEFAULT_QUERY_LANG = String(process.env.DEFAULT_QUERY_LANG || 'en').toLowerCase();
const LANG_FILTER_REGEX = /(?:^|[\s+(])(?:-?(?:lang|language):[a-z0-9_-]+)/i;
const PRICE_FILTER_REGEX = /\b(usd|eur|tix)[:=<>]/i;
const API_ONLY_FILTER_REGEX = /\b(?:otag)[:=]/i;

function hasPriceFilter(query) {
  return PRICE_FILTER_REGEX.test(String(query || ''));
}

function hasApiOnlyFilter(query) {
  return API_ONLY_FILTER_REGEX.test(String(query || ''));
}

function enforceDefaultQueryLanguage(query, defaultLang = DEFAULT_QUERY_LANG) {
  const normalizedQuery = String(query || '').trim();
  if (!defaultLang || defaultLang === '' || LANG_FILTER_REGEX.test(normalizedQuery)) {
    return normalizedQuery;
  }
  if (!normalizedQuery) {
    return `lang:${defaultLang}`;
  }
  return `${normalizedQuery} lang:${defaultLang}`;
}

function normalizeQueryOperators(rawQuery) {
  if (!rawQuery || typeof rawQuery !== 'string') {
    return { query: rawQuery || '', warning: null };
  }

  let normalized = rawQuery.replace(COLON_ONLY_PREFIX_REPLACE, '$1$2:');
  normalized = normalized.replace(/(^|[\s+(])(-?(?:k|kw)):/gi, (_full, boundary, prefix) => {
    const normalizedPrefix = String(prefix || '');
    if (normalizedPrefix.startsWith('-')) {
      return `${boundary}-keyword:`;
    }
    return `${boundary}keyword:`;
  });
  normalized = normalized.replace(POWER_TOUGHNESS_OPERATOR_WITH_SPACED_EQUAL_REPLACE, '$1$2$3=$4');
  normalized = normalized.replace(POWER_TOUGHNESS_OPERATOR_SPACING_REPLACE, '$1$2$3$4');
  normalized = normalized.replace(RARITY_COMPARISON_REPLACE, (fullMatch, prefixBoundary, prefix, operator, value) => {
    if (String(prefix || '').startsWith('-')) {
      return fullMatch;
    }

    const normalizedRarity = normalizeRarityValue(value);
    if (operator === '>' && normalizedRarity === 'rare') {
      return `${prefixBoundary}r:mythic`;
    }
    return fullMatch;
  });
  normalized = normalized.replace(COLORLESS_COLOR_FILTER_REPLACE, (_fullMatch, prefixBoundary, prefix) => {
    const normalizedPrefix = String(prefix || '').toLowerCase();
    const isNegated = normalizedPrefix.startsWith('-');
    return `${prefixBoundary}${isNegated ? '-' : ''}id=c`;
  });
  if (normalized !== rawQuery) {
    return {
      query: normalized,
      warning: `Normalized query operators: "${rawQuery}" -> "${normalized}" (use ":" for keyword filters).`
    };
  }

  return { query: rawQuery, warning: null };
}

function buildRandomExecutionPlan({
  useBulkLoaded,
  hasPriceFilter,
  hasApiOnlyFilter,
  forceApi
}) {
  if (forceApi) {
    return { primary: 'api', reason: 'forced_api' };
  }
  if (hasPriceFilter) {
    return { primary: 'api', reason: 'price_filter' };
  }
  if (hasApiOnlyFilter) {
    return { primary: 'api', reason: 'api_only_filter' };
  }
  if (useBulkLoaded) {
    return { primary: 'bulk', reason: 'bulk_loaded' };
  }
  return { primary: 'api', reason: 'bulk_unavailable' };
}

function setQueryPlanHeader(res, plan) {
  if (!res || !plan) {
    return;
  }
  const value = `${plan.primary}:${plan.reason}`;
  res.setHeader('X-Query-Plan', value);
}

function setExplainHeader(res, explainData) {
  if (!res || !explainData || typeof explainData !== 'object') {
    return;
  }
  const total = explainData.totalCards ?? 0;
  const pre = explainData.prefilteredCount ?? 0;
  const fin = explainData.finalCount ?? 0;
  const mode = explainData.mode || 'unknown';
  const value = `mode=${mode};total=${total};prefiltered=${pre};final=${fin}`;
  res.setHeader('X-Query-Explain', value);
}

/**
 * Resolve a Scryfall card URI against bulk data when possible.
 * Returns null for unsupported endpoints or when bulk data isn't available.
 */
function getBulkCardFromUri(uri) {
  if (!USE_BULK_DATA || !bulkData.isLoaded()) {
    return null;
  }
  try {
    const urlObj = new URL(uri);
    const pathSegments = urlObj.pathname.split('/').filter(Boolean);
    if (pathSegments[0] !== 'cards') {
      return null;
    }

    if (pathSegments.length === 2) {
      const cardId = pathSegments[1];
      if (BULK_URI_BLOCKED_IDENTIFIERS.has(cardId)) {
        return null;
      }
      return bulkData.getCardById(cardId);
    }

    if (pathSegments.length >= 3) {
      if (BULK_URI_BLOCKED_IDENTIFIERS.has(pathSegments[1]) || pathSegments[2] === 'rulings') {
        return null;
      }
      return bulkData.getCardBySetNumber(pathSegments[1], pathSegments[2], pathSegments[3] || 'en');
    }
  } catch {
    return null;
  }
  return null;
}


/**
 * Analyzes a Scryfall query and provides helpful hints for common syntax errors
 */
function getQueryHint(query) {
  const q = query.toLowerCase();

  // Non-numeric keyword filters require a colon operator
  if (/\b(is|t|type|s|set|r|rarity|o|oracle|name|a|artist|ft|flavor|kw|keyword|layout|wm|watermark|lang|language|game|format|f|legal|banned|restricted|block|stamp|frame|border|has)=/i.test(q)) {
    return ' (Use ":" for keyword filters, e.g., is:funny or t:token)';
  }
  
  // Check for common typos in color identity
  // Match "idXX" where XX are 2-3 lowercase letters (like "idgu" or "idub")
  // But only in search context - check if query has other search operators
  if (/\bid[a-z]{2,3}\b/.test(q) && (q.includes('t:') || q.includes('c:') || q.includes('s:') || q.includes('r:'))) {
    return ' (Did you mean "id:" or "identity:" for color identity? Example: id:gu for Simic)';
  }
  
  // Common keyword mistakes - missing colons or comparison operators
  const keywordPatterns = [
    { pattern: /\bcmc\d/, correct: 'cmc:', example: 'cmc:3 or cmc>=3', desc: 'mana value' },
    { pattern: /\bmv\d/, correct: 'mv:', example: 'mv:3 or mv<=3', desc: 'mana value' },
    { pattern: /\bpow(er)?\d/, correct: 'power:', example: 'power>=5', desc: 'power' },
    { pattern: /\btou(ghness)?\d/, correct: 'toughness:', example: 'toughness<=2', desc: 'toughness' },
    { pattern: /\bloy(alty)?\d/, correct: 'loyalty:', example: 'loyalty:3', desc: 'loyalty' },
    { pattern: /\brarity[a-z]/, correct: 'rarity:', example: 'rarity:mythic', desc: 'rarity' },
    { pattern: /\bcolor[wubrg]/, correct: 'color:', example: 'color:red', desc: 'color' },
    { pattern: /\btype[a-z]/, correct: 'type:', example: 'type:creature', desc: 'type' },
  ];
  
  for (const { pattern, correct, example, desc } of keywordPatterns) {
    if (pattern.test(q)) {
      return ` (Did you mean "${correct}" for ${desc}? Example: ${example})`;
    }
  }
  
  // Check for comparison operators written incorrectly (e.g., "mv=0=type" instead of "mv=0 type")
  if (/\b(cmc|mv|pow|power|tou|toughness|loy|loyalty)=\d+=[a-z]/.test(q)) {
    const match = q.match(/\b(cmc|mv|pow|power|tou|toughness|loy|loyalty)=(\d+)=/);
    if (match) {
      // "mv=0=type" should use space or + to separate: "mv=0 type:artifact" or "mv=0+type:artifact"
      return ` (Use spaces or "+" to separate conditions: "${match[1]}=${match[2]} type:..." not "${match[1]}=${match[2]}=type")`;
    }
  }
  
  // Common misspellings
  const misspellings = {
    'legnedary': 'legendary',
    'legndary': 'legendary',
    'planeswaker': 'planeswalker',
    'planeswalke': 'planeswalker',
    'insant': 'instant',
    'sorcry': 'sorcery',
    'creautre': 'creature',
    'enchantmnet': 'enchantment',
    'artifcat': 'artifact',
  };
  
  for (const [wrong, right] of Object.entries(misspellings)) {
    if (q.includes(wrong)) {
      return ` (Did you mean "${right}"?)`;
    }
  }
  
  // Check for invalid color abbreviations
  if (/\bc:[^wubrgcm\s<>=]/.test(q)) {
    return ' (Color codes are: w=white, u=blue, b=black, r=red, g=green, c=colorless, m=multicolor)';
  }
  
  // Check for mana symbols without braces for complex symbols
  if (/\b(m|mana):.*\d\/[wubrg]/i.test(q)) {
    return ' (Hybrid mana symbols need braces: {2/G} not 2/G)';
  }
  
  // Check for set code format errors
  if (/\b(s|set|e|edition):[A-Z]{4,}/.test(q)) {
    return ' (Set codes are usually 3 characters: "s:war" not "s:warof")';
  }
  
  // Check for rarity abbreviations
  if (/\br:(c|u|r|m)\b/.test(q)) {
    return ' (Use full rarity names: rarity:common, rarity:uncommon, rarity:rare, rarity:mythic)';
  }
  
  // Check for format names
  const invalidFormats = ['edh', 'cedh', 'canlander'];
  for (const fmt of invalidFormats) {
    if (new RegExp(`\\bf:${fmt}\\b`).test(q)) {
      const corrections = {
        'edh': 'commander',
        'cedh': 'commander',
        'canlander': 'duel'
      };
      return ` (Use "f:${corrections[fmt]}" for ${fmt.toUpperCase()})`;
    }
  }
  
  // Check for missing quotes around multi-word phrases
  if (/\bo:[a-z]+\s+[a-z]+(?!\s*\+)/.test(q) && !/"/.test(q)) {
    return ' (Use quotes for multi-word oracle text: o:"card name" or use + between words: o:card+name)';
  }
  
  return '';
}

// Cache for failed queries to prevent repeated API calls for same bad query
const failedQueryCache = new Map();
const FAILED_QUERY_CACHE_TTL = 60000; // 1 minute

// Track when we last showed detailed error for a query (to avoid spamming TTS chat)
const lastDetailedErrorTime = new Map();
const DETAILED_ERROR_COOLDOWN = 5000; // 5 seconds

// Helper: Evict oldest entries from a Map (LRU-style)
function evictOldestEntries(map, maxSize) {
  if (map.size <= maxSize) return;
  const entriesToRemove = map.size - maxSize;
  let removed = 0;
  for (const key of map.keys()) {
    map.delete(key);
    removed++;
    if (removed >= entriesToRemove) break;
  }
}

function isQueryCachedAsFailed(query) {
  const cached = failedQueryCache.get(query);
  if (cached && Date.now() - cached.timestamp < FAILED_QUERY_CACHE_TTL) {
    return cached.error;
  }
  return null;
}

function cacheFailedQuery(query, errorMessage) {
  failedQueryCache.set(query, {
    error: errorMessage,
    timestamp: Date.now()
  });
  
  // Enforce maximum cache size to prevent unbounded memory growth
  if (failedQueryCache.size > MAX_CACHE_SIZE) {
    const now = Date.now();
    // First try to clean up expired entries
    for (const [key, value] of failedQueryCache.entries()) {
      if (now - value.timestamp > FAILED_QUERY_CACHE_TTL) {
        failedQueryCache.delete(key);
      }
    }
    // If still over limit, evict oldest entries
    if (failedQueryCache.size > MAX_CACHE_SIZE) {
      evictOldestEntries(failedQueryCache, MAX_CACHE_SIZE);
    }
  }
}

function shouldShowDetailedError(query) {
  const lastShown = lastDetailedErrorTime.get(query);
  const now = Date.now();
  
  if (!lastShown || now - lastShown > DETAILED_ERROR_COOLDOWN) {
    lastDetailedErrorTime.set(query, now);
    
    // Enforce maximum cache size to prevent unbounded memory growth
    if (lastDetailedErrorTime.size > MAX_CACHE_SIZE) {
      // First try to clean up expired entries
      for (const [key, time] of lastDetailedErrorTime.entries()) {
        if (now - time > DETAILED_ERROR_COOLDOWN) {
          lastDetailedErrorTime.delete(key);
        }
      }
      // If still over limit, evict oldest entries
      if (lastDetailedErrorTime.size > MAX_CACHE_SIZE) {
        evictOldestEntries(lastDetailedErrorTime, MAX_CACHE_SIZE);
      }
    }
    
    return true;
  }
  
  return false;
}

// Health check with metrics
app.get('/', (req, res) => {
  const bulkStats = bulkData.getStats();
  const uptime = Math.floor((Date.now() - metrics.startTime) / 1000);
  const memUsage = process.memoryUsage();
  
  res.json({
    status: 'ok',
    service: 'MTG Card Importer Backend',
    version: '1.0.0',
    uptime: `${uptime}s`,
    metrics: {
      totalRequests: metrics.requests,
      errors: metrics.errors,
      errorRate: metrics.requests > 0 ? (metrics.errors / metrics.requests * 100).toFixed(2) + '%' : '0%',
      memoryMB: Math.round(memUsage.heapUsed / 1024 / 1024)
    },
    bulkData: {
      enabled: USE_BULK_DATA,
      loaded: bulkStats.loaded,
      cardCount: bulkStats.cardCount
    },
    endpoints: {
      card: 'GET /card/:name',
      deck: 'POST /deck',
      random: 'GET /random',
      search: 'GET /search',
      bulkStats: 'GET /bulk/stats',
      metrics: 'GET /metrics'
    }
  });
});

// Dedicated metrics endpoint for monitoring
app.get('/metrics', (req, res) => {
  const uptime = Math.floor((Date.now() - metrics.startTime) / 1000);
  const memUsage = process.memoryUsage();
  const bulkStats = bulkData.getStats();
  
  res.json({
    uptime: uptime,
    requests: {
      total: metrics.requests,
      errors: metrics.errors,
      errorRate: metrics.requests > 0 ? metrics.errors / metrics.requests : 0
    },
    memory: {
      heapUsed: memUsage.heapUsed,
      heapTotal: memUsage.heapTotal,
      external: memUsage.external,
      rss: memUsage.rss
    },
    bulkData: {
      enabled: USE_BULK_DATA,
      loaded: bulkStats.loaded,
      cardCount: bulkStats.cardCount,
      lastUpdate: bulkStats.lastUpdate
    },
    process: {
      pid: process.pid,
      version: process.version,
      platform: process.platform
    }
  });
});

// Readiness probe for load balancers
app.get('/ready', (req, res) => {
  const bulkStats = bulkData.getStats();
  
  // Server is ready if:
  // 1. Either bulk data is disabled OR bulk data is loaded
  // 2. Memory usage is reasonable (< 1GB heap)
  const memUsage = process.memoryUsage();
  const heapUsedMB = memUsage.heapUsed / 1024 / 1024;
  
  const isReady = (!USE_BULK_DATA || bulkStats.loaded) && heapUsedMB < 1024;
  
  if (isReady) {
    res.json({ ready: true });
  } else {
    res.status(503).json({ 
      ready: false,
      reason: USE_BULK_DATA && !bulkStats.loaded ? 'bulk data loading' : 'high memory usage'
    });
  }
});

/**
 * GET /card/:name
 * Get a single card - returns raw Scryfall JSON
 * Uses bulk data if available (exact name match only), falls back to API for fuzzy search
 */
app.get('/card/:name', async (req, res) => {
  const { name } = req.params;
  const { set } = req.query;
  const compactMode = String(req.query.compact || '').toLowerCase();
  const useSpawnCompact = compactMode === 'spawn';
  const requestEnforceCommander = req.query.enforceCommander === undefined
    ? null
    : parseBooleanLike(String(req.query.enforceCommander)) !== false;
  
  try {

    if (!name) {
      return res.status(400).json({ object: 'error', details: 'Card name required' });
    }

    if (isDirectImageUrl(name)) {
      return res.json(createSingleImageSpawnCard(name));
    }

    // Security: Validate input length to prevent DoS
    if (name.length > MAX_INPUT_LENGTH) {
      return res.status(400).json({ 
        object: 'error', 
        details: `Card name too long (max ${MAX_INPUT_LENGTH} characters)` 
      });
    }

    if (set && set.length > 10) {
      return res.status(400).json({ 
        object: 'error', 
        details: 'Set code too long (max 10 characters)' 
      });
    }

    // Validate input: detect if query string is being passed as card name
    if (name.includes('?q=')) {
      return res.status(400).json({ 
        object: 'error',
        details: 'Invalid card name. Did you mean to use /search or /random endpoint? Card name should not contain query parameters.'
      });
    }

    // Detect common search syntax in card name (indicates wrong endpoint usage)
    // Check for known search operators at word boundaries (colon, equals, comparison)
    // Valid Scryfall syntax uses these operators, so we detect them in card names
    const hasSearchOperator = /\b(id|c|t|type|s|set|r|rarity|cmc|mv|pow|power|tou|toughness)[:=<>]/i.test(name);
    if (hasSearchOperator) {
      return res.status(400).json({ 
        object: 'error',
        details: 'Invalid card name. This looks like a search query. Use /search or /random endpoint for queries.'
      });
    }

    let scryfallCard;
    const tokenLookupQuery = buildExactTokenLookupQuery(name, set || null);
    let bulkSingleTokenCandidate = false;

    if (!scryfallCard && USE_BULK_DATA && bulkData.isLoaded()) {
      const tokenMatches = bulkData.getExactTokensByName(name, set || null);
      if (tokenMatches.length > 1) {
        return res.json({
          object: 'list',
          total_cards: tokenMatches.length,
          has_more: false,
          data: useSpawnCompact ? sanitizeCardsForSpawn(tokenMatches) : sanitizeCardsForResponse(tokenMatches)
        });
      }
      if (tokenMatches.length === 1) {
        scryfallCard = tokenMatches[0];
        bulkSingleTokenCandidate = true;
      }
    }

    if (!scryfallCard || bulkSingleTokenCandidate) {
      const tokenMatches = await scryfallLib.searchCards(tokenLookupQuery, 25, 'cards');
      if (tokenMatches.length > 1) {
        return res.json({
          object: 'list',
          total_cards: tokenMatches.length,
          has_more: false,
          data: useSpawnCompact ? sanitizeCardsForSpawn(tokenMatches) : sanitizeCardsForResponse(tokenMatches)
        });
      }
      if (!scryfallCard && tokenMatches.length === 1) {
        scryfallCard = tokenMatches[0];
      }
    }
    
    // Bulk data only supports exact name matching, API supports fuzzy matching
    if (!scryfallCard && USE_BULK_DATA && bulkData.isLoaded()) {
      scryfallCard = bulkData.getCardByName(name, set || null);
    }

    if (!scryfallCard) {
      // Fall back to API for fuzzy matching
      scryfallCard = await scryfallLib.getCard(name, set);
    }

    // Preserve full all_parts to match Scryfall API behavior
    
    if (requestEnforceCommander && scryfallCard && !shouldBypassCommanderForCard(scryfallCard)) {
      const commanderLegality = scryfallCard.legalities && scryfallCard.legalities.commander;
      if (commanderLegality && commanderLegality !== 'legal') {
        return res.status(400).json({
          object: 'error',
          details: `Card is not legal in Commander: ${scryfallCard.name || name}`
        });
      }
    }

    // Return raw Scryfall format - Lua code will convert to TTS
    res.json(useSpawnCompact ? sanitizeCardForSpawn(scryfallCard) : sanitizeCardForResponse(scryfallCard));
  } catch (error) {
    console.error('Error fetching card:', error.message);
    const { status, details } = normalizeError(error, 502);

    // Fuzzy recovery: if card not found, try autocomplete and fetch best suggestion
    if (status === 404) {
      try {
        const suggestions = await scryfallLib.autocompleteCardName(name);
        if (suggestions && suggestions.length > 0) {
          const suggestion = suggestions[0];
          try {
            const corrected = await scryfallLib.getCard(suggestion, set || null);
            corrected._corrected_name = suggestion;
            corrected._original_name = name;
            return res.json(useSpawnCompact ? sanitizeCardForSpawn(corrected) : sanitizeCardForResponse(corrected));
          } catch (fallbackError) {
            // If set-specific lookup failed, try without set
            console.debug('Set-specific fallback failed:', fallbackError.message);
            if (set) {
              try {
                const corrected = await scryfallLib.getCard(suggestion, null);
                corrected._corrected_name = suggestion;
                corrected._original_name = name;
                return res.json(useSpawnCompact ? sanitizeCardForSpawn(corrected) : sanitizeCardForResponse(corrected));
              } catch (e) {
                // fall through to error response
                console.debug('Fallback without set also failed:', e.message);
              }
            }
          }

          const suggestionList = suggestions.slice(0, 5).join(', ');
          return res.status(404).json({
            object: 'error',
            details: `Card not found: ${name}. Did you mean: ${suggestionList}?`
          });
        }
      } catch (e) {
        // Ignore autocomplete failures and return original error
        console.debug('Autocomplete suggestion failed:', e.message);
      }
    }

    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /cards/:id
 * Get a card by Scryfall ID - returns raw Scryfall JSON
 */
app.get('/cards/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (!id) {
      return res.status(400).json({ error: 'Card ID required' });
    }

    let scryfallCard = null;
    if (USE_BULK_DATA && bulkData.isLoaded()) {
      scryfallCard = bulkData.getCardById(id);
    }
    if (!scryfallCard) {
      scryfallCard = await scryfallLib.getCardById(id);
    }
    
    // Return raw Scryfall format
    res.json(sanitizeCardForResponse(scryfallCard));
  } catch (error) {
    console.error('Error fetching card by ID:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /cards/:set/:number
 * GET /cards/:set/:number/:lang
 * Get a card by set code and collector number - returns raw Scryfall JSON
 */
app.get('/cards/:set/:number/:lang?', async (req, res) => {
  try {
    const { set, number, lang } = req.params;

    if (!set || !number) {
      return res.status(400).json({ error: 'Set code and collector number required' });
    }

    // Security: Validate input lengths
    if (set.length > 10) {
      return res.status(400).json({ error: 'Set code too long' });
    }
    if (number.length > 10) {
      return res.status(400).json({ error: 'Collector number too long' });
    }

    // Security: Validate language code format (2-3 letters)
    const langCode = lang || 'en';
    if (langCode && !/^[a-z]{2,3}$/i.test(langCode)) {
      return res.status(400).json({ error: 'Invalid language code format' });
    }

    let scryfallCard = null;
    if (USE_BULK_DATA && bulkData.isLoaded()) {
      scryfallCard = bulkData.getCardBySetNumber(set, number, langCode);
    }
    if (!scryfallCard) {
      scryfallCard = await scryfallLib.getCardBySetNumber(set, number, langCode);
    }
    
    // Return raw Scryfall format
    res.json(sanitizeCardForResponse(scryfallCard));
  } catch (error) {
    console.error('Error fetching card by set/number:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * POST /deck
 * Build a deck from decklist
 * Accepts either:
 *   - JSON body: { "decklist": "...", "back": "..." }
 *   - Plain text body: decklist lines (back uses default)
 * Returns NDJSON (newline-delimited JSON)
 */
app.post('/deck', async (req, res) => {
  return res.status(410).json({
    object: 'error',
    details: 'Deck import endpoint has been removed.'
  });
});

/**
 * POST /build
 * Alias for /deck endpoint (for compatibility with bundled importer)
 * Build a deck from decklist with hand position
 * Returns NDJSON (newline-delimited JSON)
 */
app.post('/build', async (req, res) => {
  return res.status(410).json({
    object: 'error',
    details: 'Deck build endpoint has been removed.'
  });
});

/**
 * POST /random/build
 * Build a random deck object in one request for TTS spawning.
 * Accepts JSON: { q, count, back, hand }
 * Returns NDJSON: single DeckCustom object
 */
app.post('/deck/parse', async (req, res) => {
  return res.status(410).json({
    object: 'error',
    details: 'Deck parse endpoint has been removed.'
  });
});

app.post('/random/build', randomLimiter, async (req, res) => {
  try {
    const bodyText = req.body ? req.body.toString('utf8') : '';
    let payload = {};

    if (bodyText && bodyText.trim()) {
      try {
        payload = JSON.parse(bodyText);
      } catch {
        return res.status(400).json({ error: 'Invalid JSON payload' });
      }
    }

    const rawQueryInput = String(payload.q || '');
    const { query: rawQuery, count: trailingCount } = extractTrailingCount(rawQueryInput);
    if (rawQuery.length > MAX_INPUT_LENGTH) {
      return res.status(400).json({
        object: 'error',
        details: `Query too long (max ${MAX_INPUT_LENGTH} characters)`
      });
    }

    const { query: normalizedQuery, warning: queryWarning } = normalizeQueryOperators(rawQuery);
    const languageEnforcedQuery = enforceDefaultQueryLanguage(normalizedQuery);
    const enforceCommander = payload.enforceCommander === undefined
      ? true
      : parseBooleanLike(String(payload.enforceCommander)) !== false;
    const bypassCommanderForTypeQuery = enforceCommander && shouldBypassCommanderForTypeQuery(languageEnforcedQuery);
    const applyCommanderLegality = enforceCommander && !bypassCommanderForTypeQuery;
    const explainRequested = payload.explain === true || String(payload.explain || '').toLowerCase() === 'true';
    const randomQuery = applyCommanderLegality
      ? ensureCommanderLegalityQuery(languageEnforcedQuery)
      : normalizeCommanderFormatAliases(languageEnforcedQuery);
    if (queryWarning) {
      res.setHeader('X-Query-Warning', queryWarning);
    }

    const countValue = Number.parseInt(payload.count, 10);
    const resolvedCount = Number.isFinite(countValue)
      ? countValue
      : (Number.isFinite(trailingCount) ? trailingCount : 1);
    const count = Math.min(Math.max(resolvedCount, 1), 100);

    const allowDupes = parseBooleanLike(String(payload.allowDupes)) === true;

    const cardBack = payload.back || DEFAULT_BACK;
    if (!isValidCardBackURL(cardBack)) {
      return res.status(400).json({
        error: 'Invalid card back URL. Only Steam CDN and Imgur URLs are allowed.'
      });
    }

    if (normalizedQuery) {
      const cachedError = isQueryCachedAsFailed(normalizedQuery);
      if (cachedError) {
        const showDetails = shouldShowDetailedError(normalizedQuery);
        if (showDetails) {
          return res.status(400).json({ object: 'error', details: cachedError });
        }
        return res.status(204).send();
      }
    }

    const priceFilterPresent = hasPriceFilter(randomQuery);
    const apiOnlyFilterPresent = hasApiOnlyFilter(randomQuery);
    const forceApi = parseBooleanLike(String(payload.forceApi)) === true;
    const executionPlan = buildRandomExecutionPlan({
      useBulkLoaded: USE_BULK_DATA && bulkData.isLoaded(),
      hasPriceFilter: priceFilterPresent,
      hasApiOnlyFilter: apiOnlyFilterPresent,
      forceApi
    });
    setQueryPlanHeader(res, executionPlan);
    if (explainRequested && executionPlan.primary === 'bulk') {
      setExplainHeader(res, bulkData.getQueryExplain(randomQuery, 'random'));
    }

    const randomCards = [];
    const seenCardKeys = new Set();
    let warningMessage = null;

    const addRandomCard = (card) => {
      if (!card) {
        return;
      }
      if (allowDupes) {
        randomCards.push(card);
        return;
      }
      const cardKey = getRandomUniqKey(card);
      if (cardKey && !seenCardKeys.has(cardKey)) {
        seenCardKeys.add(cardKey);
        randomCards.push(card);
      }
    };

    const fillWithDupes = (targetCount) => {
      if (!allowDupes || randomCards.length === 0) {
        return false;
      }
      while (randomCards.length < targetCount) {
        const pick = Math.floor(Math.random() * randomCards.length);
        randomCards.push(randomCards[pick]);
      }
      return true;
    };

    if (count === 1) {
      let scryfallCard = null;

      if (executionPlan.primary === 'bulk') {
        scryfallCard = await bulkData.getRandomCard(randomQuery, false, false);
        if (!scryfallCard && hasStructuredFilters(randomQuery)) {
          return res.status(404).json({
            object: 'error',
            details: `No eligible random cards found for the given query: "${normalizedQuery}"`
          });
        }
      }

      if (!scryfallCard) {
        const maxAttempts = MAX_RETRY_ATTEMPTS_MULTIPLIER;
        for (let attempt = 0; attempt < maxAttempts; attempt++) {
          try {
            const candidateCard = await scryfallLib.getRandomCard(randomQuery);
            scryfallCard = candidateCard;
            break;
          } catch (error) {
            if (error.message && error.message.includes('Scryfall returned 404')) {
              const hint = getQueryHint(normalizedQuery);
              const enhancedError = `Invalid search query: "${normalizedQuery}"${hint}. No cards match this query.`;
              cacheFailedQuery(normalizedQuery, enhancedError);
              throw new Error(enhancedError);
            }
            throw error;
          }
        }
      }

      if (!scryfallCard) {
        return res.status(404).json({
          object: 'error',
          details: 'No eligible random cards found for the given query'
        });
      }

      addRandomCard(scryfallCard);
    } else if (executionPlan.primary === 'bulk') {
      try {
        if (typeof bulkData.getRandomCards === 'function') {
          const bulkCards = await bulkData.getRandomCards(randomQuery, count, true, false);
          if (Array.isArray(bulkCards)) {
            for (const card of bulkCards) {
              addRandomCard(card);
            }
          }
        } else {
          const maxAttempts = count * MAX_RETRY_ATTEMPTS_MULTIPLIER;
          let attempts = 0;

          while (randomCards.length < count && attempts < maxAttempts) {
            attempts++;
            const card = await bulkData.getRandomCard(randomQuery, true, false);
            addRandomCard(card);
          }
        }
      } catch (error) {
        debugLog(`Skipped: ${error.message}`);
      }

      if (randomCards.length < count) {
        const availableCount = randomCards.length;
        if (availableCount === 0 && hasStructuredFilters(randomQuery)) {
          warningMessage = `No cards matched this query; returning empty results.`;
        }
        if (fillWithDupes(count)) {
          warningMessage = `Only ${availableCount} unique card(s) matched; filled ${count} cards with duplicates.`;
        } else {
          warningMessage = `Only ${availableCount} card(s) matched; returning partial results.`;
        }
      }
    } else {
      const hasRandomQuery = typeof normalizedQuery === 'string' && normalizedQuery.trim() !== '';
      if (count > 1 && hasRandomQuery) {
        if (priceFilterPresent || apiOnlyFilterPresent) {
          let apiAttempts = 0;
          const maxApiAttempts = count;
          while (randomCards.length < count && apiAttempts < maxApiAttempts) {
            apiAttempts++;
            const card = await scryfallLib.getRandomCard(randomQuery, true);
            addRandomCard(card);
          }
        } else {
          const cards = await scryfallLib.searchCards(randomQuery, count, RANDOM_SEARCH_UNIQUE, RANDOM_SEARCH_ORDER);

          if (!cards || cards.length === 0) {
            const hint = getQueryHint(normalizedQuery);
            const enhancedError = `Invalid search query: "${normalizedQuery}"${hint}. No cards match this query.`;
            cacheFailedQuery(normalizedQuery, enhancedError);
            throw new Error(enhancedError);
          }

          for (const card of cards) {
            addRandomCard(card);
          }
        }

        if (randomCards.length < count) {
          const availableCount = randomCards.length;
          if (fillWithDupes(count)) {
            warningMessage = `Only ${availableCount} unique card(s) matched; filled ${count} cards with duplicates.`;
          } else {
            warningMessage = `Only ${availableCount} card(s) matched; returning partial results.`;
          }
        }
      } else {
        let firstCard;
        try {
          firstCard = await scryfallLib.getRandomCard(randomQuery);

          if (!firstCard) {
            throw new Error('No eligible random cards found for the given query');
          }

          addRandomCard(firstCard);
        } catch (error) {
          if (error.response?.status === 404) {
            const hint = getQueryHint(normalizedQuery);
            const enhancedError = `Invalid search query: "${normalizedQuery}"${hint}. No cards match this query.`;
            cacheFailedQuery(normalizedQuery, enhancedError);
            throw new Error(enhancedError);
          }
          throw error;
        }

        if (count > 1) {
          const hasRandomQuery = typeof normalizedQuery === 'string' && normalizedQuery.trim() !== '';
          if (hasRandomQuery) {
            const remaining = count - randomCards.length;
            const searchLimit = Math.max(remaining, Math.ceil(remaining * DUPLICATE_BUFFER_MULTIPLIER));
            const apiCards = await scryfallLib.searchCards(randomQuery, searchLimit, RANDOM_SEARCH_UNIQUE, RANDOM_SEARCH_ORDER);
            for (const card of apiCards) {
              addRandomCard(card);
            }
          } else {
            let apiAttempts = 0;
            const maxApiAttempts = count * MAX_RETRY_ATTEMPTS_MULTIPLIER;
            while (randomCards.length < count && apiAttempts < maxApiAttempts) {
              apiAttempts++;
              const card = await scryfallLib.getRandomCard(randomQuery, true);
              addRandomCard(card);
            }
          }

          if (randomCards.length < count) {
            const availableCount = randomCards.length;
            if (fillWithDupes(count)) {
              warningMessage = `Only ${availableCount} unique card(s) matched; filled ${count} cards with duplicates.`;
            } else {
              warningMessage = `Only ${availableCount} card(s) matched; returning partial results.`;
            }
          }
        }
      }
    }

    if (randomCards.length === 0) {
      return res.status(404).json({
        object: 'error',
        details: 'No eligible random cards found for the given query'
      });
    }

    const hydratedCards = await Promise.all(randomCards.map(card => hydrateCardForTts(card)));
    const ttsCards = [];

    for (const card of hydratedCards) {
      try {
        ttsCards.push(scryfallLib.convertToTTSCard(card, cardBack));
      } catch (error) {
        console.warn(`[RandomBuild] Skipping card with missing TTS image data (${card?.name || card?.id || 'unknown'}): ${error.message}`);
      }
    }

    if (ttsCards.length < count && !warningMessage) {
      warningMessage = `Only ${ttsCards.length} card(s) had usable images; returning partial results.`;
    }

    if (ttsCards.length === 0) {
      return res.status(404).json({
        object: 'error',
        details: 'No eligible random cards with image data found for the given query'
      });
    }

    const deckObject = buildDeckCustomObject(ttsCards, payload.hand || null);

    res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
    if (warningMessage) {
      const warningLine = JSON.stringify({ object: 'warning', warning: warningMessage });
      res.send(`${warningLine}\n${JSON.stringify(deckObject)}\n`);
    } else {
      res.send(`${JSON.stringify(deckObject)}\n`);
    }
  } catch (error) {
    console.error('Error building random deck:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /random
 * Get random card(s) - returns raw Scryfall card or list
 * Uses bulk data if available, falls back to API
 * Rate limited: 50 bulk requests per minute per IP
 */
app.get('/random', randomLimiter, async (req, res) => {
  try {
    const { count } = req.query;
    const compactMode = String(req.query.compact || '').toLowerCase();
    const useSpawnCompact = compactMode === 'spawn';
    const rawQueryInput = String(req.query.q || '');
    const { query: rawQuery, count: trailingCount } = extractTrailingCount(rawQueryInput);
    const { query: q, warning: queryWarning } = normalizeQueryOperators(rawQuery);
    const languageEnforcedQuery = enforceDefaultQueryLanguage(q);
    const explainRequested = req.query.explain === 'true' || req.query.explain === true;
    const requestEnforceCommander = req.query.enforceCommander === undefined
      ? true
      : parseBooleanLike(String(req.query.enforceCommander)) !== false;
    const bypassCommanderForTypeQuery = requestEnforceCommander && shouldBypassCommanderForTypeQuery(languageEnforcedQuery);
    const enforceCommander = requestEnforceCommander && !bypassCommanderForTypeQuery;
    const randomQuery = enforceCommander ? ensureCommanderLegalityQuery(languageEnforcedQuery) : normalizeCommanderFormatAliases(languageEnforcedQuery);
    const allowDupes = parseBooleanLike(String(req.query.allowDupes)) === true;
    const forceApi = parseBooleanLike(String(req.query.forceApi)) === true;
    if (queryWarning) {
      res.setHeader('X-Query-Warning', queryWarning);
    }
    // Security: Enforce maximum count to prevent resource exhaustion
    const explicitCount = Number.parseInt(count, 10);
    const resolvedCount = Number.isFinite(explicitCount)
      ? explicitCount
      : (Number.isFinite(trailingCount) ? trailingCount : 1);
    const numCards = Math.min(Math.max(resolvedCount, 1), 100);
    
    debugLog(`GET /random - count: ${numCards}, query: "${randomQuery}"`);

    // Security: Validate query length
    if (q && q.length > MAX_INPUT_LENGTH) {
      return res.status(400).json({ 
        object: 'error', 
        details: `Query too long (max ${MAX_INPUT_LENGTH} characters)` 
      });
    }

    // Check if this query recently failed
    if (q) {
      const cachedError = isQueryCachedAsFailed(q);
      if (cachedError) {
        debugLog(`Returning cached error for query: "${q}"`);
        
        // Only show detailed error once per cooldown period to avoid spamming TTS chat
        // When users spawn a 15-card booster with invalid query, show error on first request only
        // Subsequent requests within cooldown get silently suppressed (204 No Content)
        const showDetails = shouldShowDetailedError(q);
        
        if (showDetails) {
          return res.status(400).json({ object: 'error', details: cachedError });
        } else {
          // Silently suppress subsequent failed requests to prevent chat spam
          return res.status(204).send();
        }
      }
    }

    const priceFilterPresent = hasPriceFilter(randomQuery);
    const apiOnlyFilterPresent = hasApiOnlyFilter(randomQuery);
    const executionPlan = buildRandomExecutionPlan({
      useBulkLoaded: USE_BULK_DATA && bulkData.isLoaded(),
      hasPriceFilter: priceFilterPresent,
      hasApiOnlyFilter: apiOnlyFilterPresent,
      forceApi
    });
    setQueryPlanHeader(res, executionPlan);
    if (explainRequested && executionPlan.primary === 'bulk') {
      setExplainHeader(res, bulkData.getQueryExplain(randomQuery, 'random'));
    }
    
    if (numCards === 1) {
      // Single random card
      let scryfallCard = null;
      
      // Skip bulk mode for price/funny filters to ensure accurate data
      if (executionPlan.primary === 'bulk') {
        scryfallCard = await bulkData.getRandomCard(randomQuery);
        if (!scryfallCard && hasStructuredFilters(randomQuery)) {
          return res.status(404).json({
            object: 'error',
            details: `No eligible random cards found for the given query: "${q}"`
          });
        }
      }
      
      // Fallback to API if bulk data not loaded or returned null
      if (!scryfallCard) {
        const maxAttempts = MAX_RETRY_ATTEMPTS_MULTIPLIER;
        for (let attempt = 0; attempt < maxAttempts; attempt++) {
          try {
            const candidateCard = await scryfallLib.getRandomCard(randomQuery);
            scryfallCard = candidateCard;
            break;
          } catch (error) {
            // Single card request failed - add helpful hint if it's a 404
            if (error.message && error.message.includes('Scryfall returned 404')) {
              const hint = getQueryHint(q);
              const enhancedError = `Invalid search query: "${q}"${hint}. No cards match this query.`;
              cacheFailedQuery(q, enhancedError);
              throw new Error(enhancedError);
            }
            throw error;
          }
        }
      }

      if (!scryfallCard) {
        return res.status(404).json({
          object: 'error',
          details: 'No eligible random cards found for the given query'
        });
      }
      
      res.json(useSpawnCompact ? sanitizeCardForSpawn(scryfallCard) : sanitizeCardForResponse(scryfallCard));
    } else {
      // Multiple random cards - return as list
      const cards = [];
      const seenCardKeys = new Set(); // Track oracle/card identity to avoid duplicates
      let warningMessage = null;

      const addCard = (card) => {
        if (!card) {
          return;
        }
        if (allowDupes) {
          cards.push(card);
          return;
        }
        const cardKey = getRandomUniqKey(card);
        if (cardKey && !seenCardKeys.has(cardKey)) {
          seenCardKeys.add(cardKey);
          cards.push(card);
        }
      };

      const fillWithDupes = (targetCount) => {
        if (!allowDupes || cards.length === 0) {
          return false;
        }
        while (cards.length < targetCount) {
          const pick = Math.floor(Math.random() * cards.length);
          cards.push(cards[pick]);
        }
        return true;
      };
      
      // Skip bulk mode for price/funny filters to ensure accurate data
      if (executionPlan.primary === 'bulk') {
        try {
          if (typeof bulkData.getRandomCards === 'function') {
            const bulkCards = await bulkData.getRandomCards(randomQuery, numCards, true);
            if (Array.isArray(bulkCards)) {
              for (const card of bulkCards) {
                addCard(card);
              }
            }
          } else {
            const maxAttempts = numCards * MAX_RETRY_ATTEMPTS_MULTIPLIER;
            let attempts = 0;

            while (cards.length < numCards && attempts < maxAttempts) {
              attempts++;
              const card = await bulkData.getRandomCard(randomQuery, true);
              addCard(card);
            }
          }
        } catch (error) {
          debugLog(`Skipped: ${error.message}`);
        }

        if (cards.length < numCards) {
          const availableCount = cards.length;
          if (availableCount === 0 && hasStructuredFilters(randomQuery)) {
            warningMessage = `No cards matched this query; returning empty results.`;
          }
          if (fillWithDupes(numCards)) {
            warningMessage = `Only ${availableCount} unique card(s) matched; filled ${numCards} cards with duplicates.`;
          } else {
            warningMessage = `Only ${availableCount} card(s) matched; returning partial results.`;
          }
        }
      } else {
        const hasRandomQuery = typeof q === 'string' && q.trim() !== '';
        if (numCards > 1 && hasRandomQuery) {
          if (priceFilterPresent || apiOnlyFilterPresent) {
            let apiAttempts = 0;
            const maxApiAttempts = numCards;

            while (cards.length < numCards && apiAttempts < maxApiAttempts) {
              apiAttempts++;
              const card = await scryfallLib.getRandomCard(randomQuery, true);
              addCard(card);
            }
          } else {
            const randomCards = await scryfallLib.searchCards(randomQuery, numCards, RANDOM_SEARCH_UNIQUE, RANDOM_SEARCH_ORDER);

            if (!randomCards || randomCards.length === 0) {
              const hint = getQueryHint(q);
              const enhancedError = `Invalid search query: "${q}"${hint}. No cards match this query.`;
              cacheFailedQuery(q, enhancedError);
              throw new Error(enhancedError);
            }

            for (const card of randomCards) {
              addCard(card);
            }
          }

          if (cards.length < numCards) {
            const availableCount = cards.length;
            if (fillWithDupes(numCards)) {
              warningMessage = `Only ${availableCount} unique card(s) matched; filled ${numCards} cards with duplicates.`;
            } else {
              warningMessage = `Only ${availableCount} card(s) matched; returning partial results.`;
            }
          }
        } else {
          // Single-card requests and query-less random requests keep /cards/random semantics.
          // API - Test first request to validate query before fetching all cards
          // If query is malformed, this fails fast instead of wasting API calls
          let firstCard;
          try {
            const candidateCard = await scryfallLib.getRandomCard(randomQuery);
            firstCard = candidateCard;

            if (!firstCard) {
              throw new Error('No eligible random cards found for the given query');
            }

            addCard(firstCard);
          } catch (error) {
            // First request failed - likely invalid query
            if (error.response?.status === 404) {
              const hint = getQueryHint(q);

              const enhancedError = `Invalid search query: "${q}"${hint}. No cards match this query.`;
              cacheFailedQuery(q, enhancedError);
              throw new Error(enhancedError);
            }
            throw error;
          }
          
          if (numCards > 1) {
            const hasRandomQuery = typeof q === 'string' && q.trim() !== '';
            if (hasRandomQuery) {
              const remaining = numCards - cards.length;
              const searchLimit = Math.max(remaining, Math.ceil(remaining * DUPLICATE_BUFFER_MULTIPLIER));
              const randomCards = await scryfallLib.searchCards(randomQuery, searchLimit, RANDOM_SEARCH_UNIQUE, RANDOM_SEARCH_ORDER);
              for (const card of randomCards) {
                if (cards.length >= numCards) {
                  break;
                }
                addCard(card);
              }
            } else {
              let apiAttempts = 0;
              const maxApiAttempts = numCards * MAX_RETRY_ATTEMPTS_MULTIPLIER;
              while (cards.length < numCards && apiAttempts < maxApiAttempts) {
                apiAttempts++;
                const card = await scryfallLib.getRandomCard(randomQuery, true);
                addCard(card);
              }
            }

            if (cards.length < numCards) {
              const availableCount = cards.length;
              if (fillWithDupes(numCards)) {
                warningMessage = `Only ${availableCount} unique card(s) matched; filled ${numCards} cards with duplicates.`;
              } else {
                warningMessage = `Only ${availableCount} card(s) matched; returning partial results.`;
              }
            }
          }
        }
      }
      
      const responseBody = {
        object: 'list',
        total_cards: cards.length,
        data: useSpawnCompact ? sanitizeCardsForSpawn(cards) : sanitizeCardsForResponse(cards)
      };
      if (warningMessage) {
        responseBody.warning = warningMessage;
      }
      res.json(responseBody);
    }
  } catch (error) {
    console.error('Error getting random cards:', error.message);
    console.error('Error details:', {
      status: error.response?.status,
      statusText: error.response?.statusText,
      data: error.response?.data,
      query: req.query
    });
    
    // Note: Failed queries are now cached at the point of failure (single card or bulk)
    // This ensures the enhanced error message is what gets cached
    
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /search
 * Search for cards - returns Scryfall list format
 * Uses bulk data if available, falls back to API
 */
app.get('/search', async (req, res) => {
  try {
    const { limit = 100, unique } = req.query;
    const compactMode = String(req.query.compact || '').toLowerCase();
    const useSpawnCompact = compactMode === 'spawn';
    const { query: q, warning: queryWarning } = normalizeQueryOperators(String(req.query.q || ''));
    const explainRequested = req.query.explain === 'true' || req.query.explain === true;
    const requestEnforceCommander = req.query.enforceCommander === undefined
      ? null
      : parseBooleanLike(String(req.query.enforceCommander)) !== false;
    const applyCommanderLegality = requestEnforceCommander === null
      ? null
      : (requestEnforceCommander && !shouldBypassCommanderForTypeQuery(q));
    const searchQuery = applyCommanderLegality === null
      ? q
      : (applyCommanderLegality ? ensureCommanderLegalityQuery(q) : normalizeCommanderFormatAliases(q));
    if (queryWarning) {
      res.setHeader('X-Query-Warning', queryWarning);
    }

    if (!q) {
      return res.status(400).json({ error: 'Query required' });
    }

    // Security: Validate input length
    if (q.length > MAX_INPUT_LENGTH) {
      return res.status(400).json({ 
        error: `Query too long (max ${MAX_INPUT_LENGTH} characters)` 
      });
    }

    const requestedUnique = unique || (q && q.toLowerCase().includes('oracleid:') ? 'prints' : 'cards');
    // Security: Enforce maximum limit to prevent memory exhaustion
    const limitNum = Math.min(parseInt(limit) || 100, MAX_SEARCH_LIMIT);
    
    let scryfallCards = null;
    
    const priceFilterPresent = hasPriceFilter(searchQuery);
    const apiOnlyFilterPresent = hasApiOnlyFilter(searchQuery);
    const canUseBulkSearch = USE_BULK_DATA && bulkData.isLoaded();
    const searchPlan = priceFilterPresent
      ? { primary: 'api', reason: 'price_filter' }
      : (apiOnlyFilterPresent
        ? { primary: 'api', reason: 'api_only_filter' }
        : (canUseBulkSearch ? { primary: 'bulk', reason: 'bulk_loaded' } : { primary: 'api', reason: 'bulk_unavailable' }));
    setQueryPlanHeader(res, searchPlan);
    if (explainRequested && searchPlan.primary === 'bulk') {
      setExplainHeader(res, bulkData.getQueryExplain(searchQuery, 'search'));
    }
    
    if (searchPlan.primary === 'bulk') {
      scryfallCards = await bulkData.searchCards(searchQuery, limitNum);
      
      // Fallback to API if bulk data returned null (no matches)
      if (!scryfallCards) {
        debugLog(`[Fallback] Bulk data returned no results for "${searchQuery}", using API`);
        res.setHeader('X-Bulk-Fallback', 'bulk_no_results');
        scryfallCards = await scryfallLib.searchCards(searchQuery, limitNum, requestedUnique);
      }
    } else {
      scryfallCards = await scryfallLib.searchCards(searchQuery, limitNum, requestedUnique);
    }
    
    // Ensure scryfallCards is an array
    if (!scryfallCards) {
      scryfallCards = [];
    }
    
    if (scryfallCards.length === 0) {
      return res.json({ 
        object: 'list',
        total_cards: 0,
        data: []
      });
    }

    // Return Scryfall list format
    res.json({
      object: 'list',
      total_cards: scryfallCards.length,
      has_more: false,
      data: useSpawnCompact ? sanitizeCardsForSpawn(scryfallCards) : sanitizeCardsForResponse(scryfallCards)
    });
  } catch (error) {
    console.error('Error searching cards:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /rulings/:name
 * Get card rulings from Scryfall - returns Scryfall list format
 */
app.get('/rulings/:name', async (req, res) => {
  try {
    const { name } = req.params;

    if (!name) {
      return res.status(400).json({ error: 'Card name required' });
    }

    const rulings = await scryfallLib.getCardRulings(name);
    
    // Return Scryfall rulings format
    res.json({
      object: 'list',
      has_more: false,
      data: rulings
    });
  } catch (error) {
    console.error('Error fetching rulings:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /tokens/:name
 * Removed endpoint
 */
app.get('/tokens/:name', async (req, res) => {
  return res.status(410).json({
    object: 'error',
    details: 'Token lookup endpoint has been removed.'
  });
});

/**
 * GET /related?name=...&oracleId=...&set=...
 * Returns related token/emblem parts for a source card.
 */
app.get('/related', async (req, res) => {
  try {
    const rawName = typeof req.query.name === 'string' ? req.query.name.trim() : '';
    const rawOracleId = typeof req.query.oracleId === 'string' ? req.query.oracleId.trim() : '';
    const set = typeof req.query.set === 'string' ? req.query.set.trim().toLowerCase() : '';
    const resolveMode = String(req.query.resolve || '').trim().toLowerCase();
    const resolveCards = resolveMode === 'cards';
    const compactMode = String(req.query.compact || '').toLowerCase();
    const useSpawnCompact = compactMode === 'spawn';

    if (!rawName && !rawOracleId) {
      return res.status(400).json({ object: 'error', details: 'name or oracleId is required' });
    }

    if (rawName.length > MAX_INPUT_LENGTH || rawOracleId.length > 128 || set.length > 10) {
      return res.status(400).json({ object: 'error', details: 'Invalid related lookup parameters' });
    }

    const normalizedOracleId = rawOracleId.replace(/^oracleid:/i, '');
    let sourceCard = null;

    if (USE_BULK_DATA && bulkData.isLoaded()) {
      if (normalizedOracleId) {
        sourceCard = bulkData.getCardByOracleId(normalizedOracleId);
      }
      if (!sourceCard && rawName) {
        sourceCard = bulkData.getCardByName(rawName, set || null);
      }
    }

    if (!sourceCard) {
      if (normalizedOracleId) {
        const oracleMatches = await scryfallLib.searchCards(`oracleid:${normalizedOracleId}`, 1, 'prints');
        sourceCard = oracleMatches[0] || null;
      }
      if (!sourceCard && rawName) {
        sourceCard = await scryfallLib.getCard(rawName, set || null);
      }
    }

    if (!sourceCard) {
      return res.status(404).json({ object: 'error', details: 'Source card not found' });
    }

    let rawParts = [];
    if (USE_BULK_DATA && bulkData.isLoaded() && sourceCard.id) {
      rawParts = bulkData.getAllPartsById(sourceCard.id) || [];
    }
    if ((!Array.isArray(rawParts) || rawParts.length === 0) && Array.isArray(sourceCard.all_parts)) {
      rawParts = sourceCard.all_parts;
    }

    const seenUris = new Set();
    const related = [];
    for (const part of rawParts || []) {
      if (
        !part ||
        !part.uri ||
        isSameCardReference(sourceCard, part) ||
        !shouldIncludeRelatedPart(sourceCard, part)
      ) {
        continue;
      }
      if (seenUris.has(part.uri)) {
        continue;
      }
      seenUris.add(part.uri);

      if (!resolveCards) {
        related.push(buildRelatedPartPayload(part));
        continue;
      }

      let resolvedCard = part.card || null;
      if (!resolvedCard && part.id && USE_BULK_DATA && bulkData.isLoaded()) {
        resolvedCard = bulkData.getCardById(part.id);
      }
      if (!resolvedCard) {
        resolvedCard = getBulkCardFromUri(part.uri);
      }
      if (!resolvedCard) {
        try {
          resolvedCard = await scryfallLib.proxyUri(part.uri);
        } catch (resolveError) {
          console.warn(`[Related] Failed to resolve part URI ${part.uri}: ${resolveError.message}`);
          continue;
        }
      }

      related.push(useSpawnCompact ? sanitizeCardForSpawn(resolvedCard) : sanitizeCardForResponse(resolvedCard));
    }

    return res.json({
      object: 'list',
      total_cards: related.length,
      has_more: false,
      data: related
    });
  } catch (error) {
    console.error('Error fetching related token/emblem parts:', error.message);
    const { status, details } = normalizeError(error, 502);
    return res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /printings/:name
 * Get all printings of a card - returns Scryfall list format
 */
app.get('/printings/:name', async (req, res) => {
  try {
    const { name } = req.params;

    if (!name) {
      return res.status(400).json({ error: 'Card name required' });
    }

    const printings = await scryfallLib.getPrintings(name);
    
    // Return Scryfall list format with full card data
    res.json({
      object: 'list',
      total_cards: printings.length,
      has_more: false,
      data: printings
    });
  } catch (error) {
    console.error('Error fetching printings:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details });
  }
});

/**
 * GET /sets/:code
 * Get set information by set code - returns raw Scryfall set object
 */
app.get('/sets/:code', async (req, res) => {
  return res.status(410).json({
    object: 'error',
    details: 'Set lookup endpoint has been removed.'
  });
});

/**
 * GET /bulk/stats
 * Get bulk data statistics
 */
app.get('/bulk/stats', (req, res) => {
  const stats = bulkData.getStats();
  res.json({
    ...stats,
    enabled: USE_BULK_DATA,
    fileSizeMB: stats.fileSize ? (stats.fileSize / 1024 / 1024).toFixed(2) : 0
  });
});

/**
 * POST /bulk/reload
 * Manually trigger bulk data reload
 */
app.post('/bulk/reload', async (req, res) => {
  try {
    if (!USE_BULK_DATA) {
      return res.status(400).json({ error: 'Bulk data not enabled' });
    }
    
    console.log('[API] Manual bulk data reload requested');
    await bulkData.downloadBulkData();
    await bulkData.loadBulkData();
    
    res.json({
      success: true,
      message: 'Bulk data reloaded',
      stats: bulkData.getStats()
    });
  } catch (error) {
    console.error('Error reloading bulk data:', error.message);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /proxy?uri=...
 * Proxy a Scryfall API URI through the backend
 * Used for fetching related cards (tokens, etc.) via their API URIs
 */
app.get('/proxy', async (req, res) => {
  try {
    const { uri } = req.query;
    
    if (!uri) {
      return res.status(400).json({ 
        object: 'error', 
        details: 'Missing uri parameter' 
      });
    }
    
    let parsedUri;
    try {
      parsedUri = new URL(String(uri));
    } catch {
      return res.status(400).json({
        object: 'error',
        details: 'Invalid URI format'
      });
    }

    // Validate it's an exact Scryfall API URL
    if (parsedUri.protocol !== 'https:' || parsedUri.hostname !== 'api.scryfall.com') {
      return res.status(400).json({ 
        object: 'error', 
        details: 'Invalid URI - must be a Scryfall API URL' 
      });
    }

    // Block expensive/abuse parameters using normalized query params.
    const includeExtras = String(parsedUri.searchParams.get('include_extras') || '').toLowerCase();
    const includeMultilingual = String(parsedUri.searchParams.get('include_multilingual') || '').toLowerCase();
    const order = String(parsedUri.searchParams.get('order') || '').toLowerCase();
    const isBlocked =
      includeExtras === 'true' ||
      includeMultilingual === 'true' ||
      order === 'released' ||
      order === 'added';
    if (isBlocked) {
      return res.status(400).json({ 
        object: 'error', 
        details: 'Parameter not allowed in proxied requests' 
      });
    }

    const normalizedUri = parsedUri.toString();
    const bulkCard = getBulkCardFromUri(normalizedUri);
    if (bulkCard) {
      return res.json(sanitizeCardForResponse(bulkCard));
    }

    const cardData = await scryfallLib.proxyUri(normalizedUri);
    res.json(cardData);
    
  } catch (error) {
    console.error('[Proxy] Error:', error.message);
    const { status, details } = normalizeError(error, 502);
    res.status(status).json({ object: 'error', details, status });
  }
});

/**
 * Error handler
 */
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ 
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// Start server with bulk data initialization
// Only start the server if not in test environment
let server;
if (process.env.NODE_ENV !== 'test') {
  server = app.listen(PORT, '0.0.0.0', async () => {
    console.log(`MTG Card Importer Backend running on port ${PORT}`);
    console.log(`Worker PID: ${process.pid}`);
    console.log(`Health check: http://localhost:${PORT}/`);
    console.log(`Metrics: http://localhost:${PORT}/metrics`);
    console.log(`Readiness probe: http://localhost:${PORT}/ready`);
    console.log(`Bulk data enabled: ${USE_BULK_DATA}`);
    
    if (USE_BULK_DATA) {
      console.log('[Init] Loading bulk data in background...');
      bulkData.loadBulkData()
        .then(() => {
          console.log('[Init] Bulk data ready!');
        })
        .catch((error) => {
          console.error('[Init] Failed to load bulk data, falling back to API mode:', error.message);
          console.error('[Init] Server will continue using Scryfall API');
        });
    } else {
      console.log('[Init] Using Scryfall API mode');
    }
  });

  // Configure server timeouts for high concurrency
  server.keepAliveTimeout = 65000; // 65 seconds (higher than common LB timeout of 60s)
  server.headersTimeout = 66000; // Slightly higher than keepAliveTimeout
  server.requestTimeout = 120000; // 2 minutes for long-running deck builds

  // Graceful shutdown handler
  const gracefulShutdown = (signal) => {
    console.log(`\n[Shutdown] Received ${signal}, starting graceful shutdown...`);
    
    server.close(() => {
      console.log('[Shutdown] Server closed, no longer accepting connections');
      console.log('[Shutdown] Exiting process');
      process.exit(0);
    });

    // Force shutdown after 30 seconds if graceful shutdown hangs
    setTimeout(() => {
      console.error('[Shutdown] Graceful shutdown timeout, forcing exit');
      process.exit(1);
    }, 30000);
  };

  process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
  process.on('SIGINT', () => gracefulShutdown('SIGINT'));
}

// Export app for testing
module.exports = app;
