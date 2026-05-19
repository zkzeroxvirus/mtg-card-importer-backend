const axios = require('axios');
const fs = require('fs');
const path = require('path');

const scryfallClient = axios.create({
  baseURL: 'https://api.scryfall.com',
  headers: {
    'User-Agent': 'MTG-Card-Importer/1.0',
    'Accept': 'application/json'
  }
});

const globalQueue = {
  active: 0,
  max: 10
};

async function withRetry(fn, maxRetries = 3, initialDelayMs = 1000) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
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
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
  return await fn();
}

function getCard(name) {
  return withRetry(() => scryfallClient.get(`/cards/named?fuzzy=${encodeURIComponent(name)}`))
    .then(response => response.data);
}

function autocompleteCardName(q) {
  return withRetry(() => scryfallClient.get(`/cards/autocomplete?q=${encodeURIComponent(q)}`))
    .then(response => response.data.data);
}

function getCardById(id) {
  return withRetry(() => scryfallClient.get(`/cards/${id}`))
    .then(response => response.data);
}

function getCardBySetNumber(set, number) {
  return withRetry(() => scryfallClient.get(`/cards/${set}/${number}`))
    .then(response => response.data);
}

function searchCards(q, page = 1) {
  return withRetry(() => scryfallClient.get(`/cards/search?q=${encodeURIComponent(q)}&page=${page}`))
    .then(response => response.data);
}

function getRandomCard(q = '') {
  let url = '/cards/random';
  if (q) {
    url += `?q=${encodeURIComponent(q)}`;
  }
  return withRetry(() => scryfallClient.get(url))
    .then(response => response.data);
}

function getSet(setCode) {
  return withRetry(() => scryfallClient.get(`/sets/${setCode}`))
    .then(response => response.data);
}

function getCardRulings(id) {
  return withRetry(() => scryfallClient.get(`/cards/${id}/rulings`))
    .then(response => response.data.data);
}

function getPrintings(oracleId) {
  return withRetry(() => scryfallClient.get(`/cards/search?q=oracleid:${oracleId}&unique=prints`))
    .then(response => response.data.data);
}

function parseDecklist(decklist) {
  const lines = decklist.split('\n');
  const cards = [];
  const cardRegex = /^(\d+x?\s+)?([^(\n]+)(\s+\([^)]+\)\s+\d+)?$/i;
  
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    
    // Skip comment lines
    if (trimmed.startsWith('//')) continue;
    
    const match = trimmed.match(cardRegex);
    if (match) {
      const count = match[1] ? parseInt(match[1].replace('x', ''), 10) : 1;
      const name = match[2].trim();
      cards.push({ count, name });
    }
  }
  
  return cards;
}

function convertToTTSCard(scryfallCard, count = 1) {
  const imageUrl = getCardImageUrl(scryfallCard);
  const backUrl = getCardBackUrl(scryfallCard);
  
  return {
    Nickname: scryfallCard.name,
    CardID: 100,
    Quantity: count,
    CustomDeck: {
      "1": {
        FaceURL: imageUrl,
        BackURL: backUrl,
        NumWidth: 1,
        NumHeight: 1,
        BackIsHidden: true,
        UniqueBack: false,
        Type: 0
      }
    }
  };
}

function getCardImageUrl(card, version = 'normal') {
  if (card.image_uris && card.image_uris[version]) {
    return card.image_uris[version];
  }
  if (card.card_faces && card.card_faces[0].image_uris && card.card_faces[0].image_uris[version]) {
    return card.card_faces[0].image_uris[version];
  }
  return '';
}

function getCardBackUrl(card) {
  if (card.layout === 'transform' || card.layout === 'modal_dfc' || card.layout === 'double_faced_token') {
    if (card.card_faces && card.card_faces[1].image_uris && card.card_faces[1].image_uris.normal) {
      return card.card_faces[1].image_uris.normal;
    }
  }
  return 'https://gamepedia.cursecdn.com/mtgsalvation_gamepedia/f/f8/Magic_card_back.jpg';
}

function getOracleText(card) {
  if (card.oracle_text) {
    return card.oracle_text;
  }
  if (card.card_faces) {
    return card.card_faces.map(face => `${face.name}: ${face.oracle_text}`).join('\n---\n');
  }
  return '';
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

async function proxyUri(uri) {
  try {
    const urlObj = new URL(uri);
    if (urlObj.hostname !== 'api.scryfall.com') {
      throw new Error(`Forbidden hostname: ${urlObj.hostname}`);
    }
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
