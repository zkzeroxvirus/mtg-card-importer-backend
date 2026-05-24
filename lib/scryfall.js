const axios = require('axios');

const scryfallClient = axios.create({
  baseURL: 'https://api.scryfall.com',
  headers: {
    'User-Agent': 'MTG-Card-Importer/1.0',
    'Accept': 'application/json'
  }
});

const DEFAULT_REQUEST_TIMEOUT_MS = Math.max(parseInt(process.env.SCRYFALL_TIMEOUT_MS || '15000', 10) || 15000, 1000);
let requestSignalProvider = null;
let liveApiGuard = null;

function setRequestSignalProvider(provider) {
  requestSignalProvider = typeof provider === 'function' ? provider : null;
}

function setLiveApiGuard(guardFn) {
  liveApiGuard = typeof guardFn === 'function' ? guardFn : null;
}

function getActiveRequestSignal() {
  if (!requestSignalProvider) {
    return null;
  }
  try {
    return requestSignalProvider() || null;
  } catch {
    return null;
  }
}

function resolveRequestOptions(options = {}) {
  return {
    signal: options.signal || getActiveRequestSignal() || null,
    timeout: Number.isFinite(options.timeout) && options.timeout > 0 ? options.timeout : DEFAULT_REQUEST_TIMEOUT_MS
  };
}

function isAbortError(error) {
  if (!error) {
    return false;
  }
  if (error.name === 'AbortError') {
    return true;
  }
  if (error.code === 'ERR_CANCELED' || error.code === 'ECONNABORTED') {
    return true;
  }
  if (typeof error.message === 'string' && /aborted|canceled/i.test(error.message)) {
    return true;
  }
  return false;
}

function createAbortError() {
  const error = new Error('Request aborted');
  error.code = 'ERR_CANCELED';
  error.name = 'AbortError';
  return error;
}

function throwIfAborted(signal) {
  if (signal?.aborted) {
    throw createAbortError();
  }
}

function assertLiveApiAllowed(operation, options = {}) {
  if (!liveApiGuard) {
    return;
  }
  const allowed = liveApiGuard({ operation, ...options });
  if (!allowed) {
    const error = new Error('Live Scryfall API requests are disabled in strict bulk mode. Use forceApi=true to override.');
    error.code = 'LIVE_API_DISABLED';
    error.status = 503;
    throw error;
  }
}

async function sleep(ms, signal) {
  if (!Number.isFinite(ms) || ms <= 0) {
    return;
  }
  await new Promise((resolve, reject) => {
    let timeoutId;
    const onAbort = () => {
      if (timeoutId) {
        clearTimeout(timeoutId);
      }
      reject(createAbortError());
    };

    if (signal) {
      signal.addEventListener('abort', onAbort, { once: true });
    }

    timeoutId = setTimeout(() => {
      if (signal) {
        signal.removeEventListener('abort', onAbort);
      }
      resolve();
    }, ms);
  });
}

const globalQueue = {
  delay: parseInt(process.env.SCRYFALL_DELAY || '100', 10),
  lastRequest: 0,
  async wait(signal = null) {
    throwIfAborted(signal);
    const now = Date.now();
    const elapsed = now - this.lastRequest;
    if (elapsed < this.delay) {
      await sleep(this.delay - elapsed, signal);
    }
    throwIfAborted(signal);
    this.lastRequest = Date.now();
  }
};

async function withRetry(fn, maxRetries = 3, initialDelayMs = 1000, options = {}) {
  const signal = options.signal || null;

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    throwIfAborted(signal);
    try {
      return await fn();
    } catch (error) {
      if (isAbortError(error)) {
        throw error;
      }

      const isRateLimit = error.response?.status === 429;
      const isNetworkError = !error.response && error.code !== 'ECONNABORTED';
      const is5xx = error.response?.status >= 500;
      
      if (!isRateLimit && !isNetworkError && !is5xx) {
        throw error;
      }
      
      const delayMs = isRateLimit 
        ? (parseInt(error.response.headers['retry-after'], 10) * 1000 || initialDelayMs * Math.pow(2, attempt))
        : initialDelayMs * Math.pow(2, attempt);
        
      const errorDesc = isRateLimit ? 'HTTP 429' : (isNetworkError ? 'Network Error' : `HTTP ${error.response.status}`);
      
      console.warn(
        `Scryfall API error (${errorDesc}), retrying in ${delayMs}ms (attempt ${attempt + 1}/${maxRetries})`
      );
      await sleep(delayMs, signal);
    }
  }
  throwIfAborted(signal);
  return await fn();
}

async function getCard(name, set = null, options = {}) {
  const requestOptions = resolveRequestOptions(options);
  assertLiveApiAllowed('getCard', { cardName: name, set });
  let url = `/cards/named?fuzzy=${encodeURIComponent(name)}`;
  if (set) url += `&set=${encodeURIComponent(set)}`;
  await globalQueue.wait(requestOptions.signal);
  try {
    const response = await withRetry(
      () => scryfallClient.get(url, requestOptions),
      3,
      1000,
      { signal: requestOptions.signal }
    );
    return response.data;
  } catch (error) {
    if (error.response?.status === 404) {
      throw new Error(`Card not found: ${name}`);
    }
    throw error;
  }
}

async function autocompleteCardName(q, options = {}) {
  const requestOptions = resolveRequestOptions(options);
  assertLiveApiAllowed('autocompleteCardName', { query: q });
  try {
    await globalQueue.wait(requestOptions.signal);
    const response = await withRetry(
      () => scryfallClient.get(`/cards/autocomplete?q=${encodeURIComponent(q)}`, requestOptions),
      3,
      1000,
      { signal: requestOptions.signal }
    );
    return response.data.data;
  } catch (error) {
    if (isAbortError(error)) {
      throw error;
    }
    return [];
  }
}

async function getCardById(id, options = {}) {
  const requestOptions = resolveRequestOptions(options);
  assertLiveApiAllowed('getCardById', { id });
  await globalQueue.wait(requestOptions.signal);
  try {
    const response = await withRetry(
      () => scryfallClient.get(`/cards/${id}`, requestOptions),
      3,
      1000,
      { signal: requestOptions.signal }
    );
    return response.data;
  } catch (error) {
    if (error.response?.status === 404) {
      throw new Error(`Card not found with ID: ${id}`);
    }
    throw error;
  }
}

async function getCardBySetNumber(set, number, lang = null, options = {}) {
  const requestOptions = resolveRequestOptions(options);
  assertLiveApiAllowed('getCardBySetNumber', { set, number, lang });
  let url = `/cards/${set}/${number}`;
  if (lang) url += `/${lang}`;
  await globalQueue.wait(requestOptions.signal);
  const response = await withRetry(
    () => scryfallClient.get(url, requestOptions),
    3,
    1000,
    { signal: requestOptions.signal }
  );
  return response.data;
}

async function searchCards(q, limit = 1, unique = 'cards', order = null, options = {}) {
  const requestOptions = resolveRequestOptions(options);
  assertLiveApiAllowed('searchCards', { query: q, limit, unique, order });
  const results = [];
  const params = new URLSearchParams({ q, unique });
  if (order) params.set('order', order);
  let url = `/cards/search?${params.toString()}`;

  try {
    while (url && results.length < limit) {
      throwIfAborted(requestOptions.signal);
      await globalQueue.wait(requestOptions.signal);
      const response = await withRetry(
        () => scryfallClient.get(url, requestOptions),
        3,
        1000,
        { signal: requestOptions.signal }
      );
      const page = response.data;
      results.push(...page.data);

      if (page.has_more && page.next_page && results.length < limit) {
        const nextUrl = new URL(page.next_page);
        url = nextUrl.pathname + nextUrl.search;
      } else {
        url = null;
      }
    }
  } catch (error) {
    if (error.response?.status === 404) {
      return [];
    }
    throw error;
  }

  return results.slice(0, limit);
}

async function getRandomCard(q = '', options = {}) {
  const requestOptions = resolveRequestOptions(options);
  assertLiveApiAllowed('getRandomCard', { query: q });
  let url = '/cards/random';
  if (q) {
    url += `?q=${encodeURIComponent(q)}`;
  }
  await globalQueue.wait(requestOptions.signal);
  const response = await withRetry(
    () => scryfallClient.get(url, requestOptions),
    3,
    1000,
    { signal: requestOptions.signal }
  );
  return response.data;
}

async function getSet(setCode, options = {}) {
  const requestOptions = resolveRequestOptions(options);
  assertLiveApiAllowed('getSet', { setCode });
  await globalQueue.wait(requestOptions.signal);
  const response = await withRetry(
    () => scryfallClient.get(`/sets/${setCode}`, requestOptions),
    3,
    1000,
    { signal: requestOptions.signal }
  );
  return response.data;
}

async function getCardRulings(id, options = {}) {
  const requestOptions = resolveRequestOptions(options);
  assertLiveApiAllowed('getCardRulings', { id });
  await globalQueue.wait(requestOptions.signal);
  const response = await withRetry(
    () => scryfallClient.get(`/cards/${id}/rulings`, requestOptions),
    3,
    1000,
    { signal: requestOptions.signal }
  );
  return response.data.data;
}

async function getPrintings(name, options = {}) {
  const requestOptions = resolveRequestOptions(options);
  assertLiveApiAllowed('getPrintings', { cardName: name });
  await globalQueue.wait(requestOptions.signal);
  const cardResponse = await withRetry(
    () => scryfallClient.get(`/cards/named?fuzzy=${encodeURIComponent(name)}`, requestOptions),
    3,
    1000,
    { signal: requestOptions.signal }
  );
  const oracleId = cardResponse.data.oracle_id;

  await globalQueue.wait(requestOptions.signal);
  const printingsResponse = await withRetry(
    () => scryfallClient.get(`/cards/search?q=oracleid:${oracleId}&unique=prints`, requestOptions),
    3,
    1000,
    { signal: requestOptions.signal }
  );
  return printingsResponse.data.data;
}

function parseDecklist(decklist) {
  const lines = decklist.split('\n');
  const cards = [];
  const cardRegex = /^(\d+x?\s+)([^(\n]+)(\s+\([^)]+\)\s+\d+)?$/i;
  
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    
    // Skip comment lines
    if (trimmed.startsWith('//')) continue;
    
    const match = trimmed.match(cardRegex);
    if (match) {
      const count = parseInt(match[1].replace('x', ''), 10);
      const name = match[2].trim();
      cards.push({ count, name });
    }
  }
  
  return cards;
}

function convertToTTSCard(scryfallCard, backUrl, position = null) {
  const imageUrl = getCardImageUrl(scryfallCard);
  if (!imageUrl) {
    throw new Error(`No image available for ${scryfallCard.name}`);
  }

  const pos = position || {};
  const cmc = scryfallCard.cmc !== undefined ? scryfallCard.cmc : 0;
  const isDFC = scryfallCard.card_faces && scryfallCard.card_faces.length >= 2 && !scryfallCard.image_uris;
  const frontFace = isDFC ? scryfallCard.card_faces[0] : null;
  const faceCmc = frontFace && frontFace.cmc !== undefined ? frontFace.cmc : cmc;
  const nickname = isDFC
    ? `${frontFace.name}\n${frontFace.type_line || ''}\n${faceCmc}CMC DFC`
    : `${scryfallCard.name}\n${scryfallCard.type_line || ''}\n${cmc}CMC`;

  const customDeckEntry = {
    FaceURL: imageUrl,
    BackURL: backUrl,
    NumWidth: 1,
    NumHeight: 1,
    BackIsHidden: true,
    UniqueBack: false,
    Type: 0
  };

  const ttsCard = {
    Name: 'Card',
    Nickname: nickname,
    Description: getOracleText(isDFC ? frontFace : scryfallCard),
    Memo: scryfallCard.oracle_id || '',
    CardID: 100,
    CustomDeck: { '1': customDeckEntry },
    Transform: {
      posX: pos.x || 0,
      posY: pos.y || 0,
      posZ: pos.z || 0,
      rotX: 0,
      rotY: pos.rotY || 0,
      rotZ: 0,
      scaleX: 1,
      scaleY: 1,
      scaleZ: 1
    }
  };

  if (isDFC) {
    const backFace = scryfallCard.card_faces[1];
    const backFaceImageUrl = getCardImageUrl(backFace);
    if (backFaceImageUrl) {
      const backCmc = backFace.cmc !== undefined ? backFace.cmc : cmc;
      ttsCard.States = {
        2: {
          Name: 'Card',
          Nickname: `${backFace.name}\n${backFace.type_line || ''}\nCMC: ${backCmc} DFC`,
          Description: getOracleText(backFace),
          Memo: scryfallCard.oracle_id || '',
          CardID: 200,
          CustomDeck: {
            '2': {
              FaceURL: backFaceImageUrl,
              BackURL: backUrl,
              NumWidth: 1,
              NumHeight: 1,
              BackIsHidden: true,
              UniqueBack: false,
              Type: 0
            }
          },
          Transform: { ...ttsCard.Transform }
        }
      };
    }
  }

  return ttsCard;
}

function getCardImageUrl(card, version = 'normal') {
  if (card.image_uris && card.image_uris[version]) {
    return card.image_uris[version];
  }
  if (card.card_faces && card.card_faces[0] && card.card_faces[0].image_uris && card.card_faces[0].image_uris[version]) {
    return card.card_faces[0].image_uris[version];
  }
  return null;
}

const DEFAULT_CARD_BACK = 'https://gamepedia.cursecdn.com/mtgsalvation_gamepedia/f/f8/Magic_card_back.jpg';

function getCardBackUrl(card, defaultUrl = DEFAULT_CARD_BACK) {
  if (card.card_faces && card.card_faces[1] && card.card_faces[1].image_uris && card.card_faces[1].image_uris.normal) {
    return card.card_faces[1].image_uris.normal;
  }
  return defaultUrl;
}

function getOracleText(card) {
  const oracleText = (card.oracle_text || '').replace(/"/g, "'");
  if (card.power !== undefined && card.toughness !== undefined) {
    return oracleText + '\n[b]' + card.power + '/' + card.toughness + '[/b]';
  }
  if (card.loyalty) {
    return oracleText + '\n[b]' + card.loyalty + '[/b]';
  }
  return oracleText;
}

const ANTE_WORD_REGEX = /\bante\b/i;

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
    '-layout:emblem'
  ];

  return exclusions.join(' ');
}

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
  const legalities = card.legalities || {};
  if (['memorabilia', 'token', 'minigame', 'draft_innovation', 'funny'].includes(setType)) {
    if (setType === 'funny' && legalities.commander === 'legal') {
      // Allow funny cards that are commander legal
    } else {
      return true;
    }
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
    'stickers'
  ].includes(layout)) {
    return true;
  }

  if (layout === 'meld') {
    if (card.name && !card.mana_cost && !card.card_faces) {
      return true;
    }
  }

  const typeLine = (card.type_line || '').toLowerCase();
  if (typeLine.includes('basic land') || typeLine === 'basic') {
    return true;
  }

  const oracleText = getOracleText(card);
  if (ANTE_WORD_REGEX.test(oracleText)) {
    return true;
  }

  return false;
}

async function proxyUri(uri, options = {}) {
  const requestOptions = resolveRequestOptions(options);
  assertLiveApiAllowed('proxyUri', { uri });
  try {
    const urlObj = new URL(uri);
    if (urlObj.hostname !== 'api.scryfall.com') {
      throw new Error(`Forbidden hostname: ${urlObj.hostname}`);
    }
    const path = urlObj.pathname + urlObj.search;
    
    const response = await withRetry(() => 
      scryfallClient.get(path, requestOptions),
      3,
      1000,
      { signal: requestOptions.signal }
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
  globalQueue,
  setRequestSignalProvider,
  setLiveApiGuard,
  isAbortError
};
