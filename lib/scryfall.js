import axios from 'axios';

const SCRYFALL_BASE = 'https://api.scryfall.com';
const DELAY_MS = parseInt(process.env.SCRYFALL_DELAY || '100', 10);

class RateLimiter {
  constructor(ms) { this.ms = ms; this.last = 0; }
  async wait() {
    const now = Date.now();
    const next = Math.max(this.last + this.ms, now);
    const sleep = next - now;
    if (sleep > 0) await new Promise(r => setTimeout(r, sleep));
    this.last = next;
  }
}

const limiter = new RateLimiter(DELAY_MS);

function getFaceImage(card) {
  if (Array.isArray(card.card_faces) && card.card_faces.length) {
    const front = card.card_faces[0];
    if (front.image_uris) {
      return front.image_uris.png || front.image_uris.normal || front.image_uris.large || front.image_uris.small;
    }
  }
  if (card.image_uris) {
    return card.image_uris.png || card.image_uris.normal || card.image_uris.large || card.image_uris.small;
  }
  return null;
}

function getOracleText(card) {
  if (Array.isArray(card.card_faces) && card.card_faces.length) {
    return card.card_faces.map(f => f.oracle_text || '').filter(Boolean).join('\n');
  }
  return card.oracle_text || '';
}

export async function getCard(name, set) {
  // Prefer exact search by set when provided
  try {
    await limiter.wait();
    if (set) {
      const { data } = await axios.get(`${SCRYFALL_BASE}/cards/search`, {
        params: { q: `!\"${name}\" e:${set}` }
      });
      if (data.total_cards > 0) return data.data[0];
    } else {
      const { data } = await axios.get(`${SCRYFALL_BASE}/cards/named`, {
        params: { exact: name }
      });
      if (data) return data;
    }
  } catch (_) { /* fall through to fuzzy */ }

  // Fuzzy fallback
  await limiter.wait();
  const { data } = await axios.get(`${SCRYFALL_BASE}/cards/named`, {
    params: { fuzzy: name }
  });
  return data;
}

export async function searchCards(q) {
  await limiter.wait();
  const { data } = await axios.get(`${SCRYFALL_BASE}/cards/search`, { params: { q } });
  return data.data || [];
}

export async function randomCards(count = 1, q) {
  const out = [];
  for (let i = 0; i < count; i++) {
    await limiter.wait();
    const { data } = await axios.get(`${SCRYFALL_BASE}/cards/random`, { params: q ? { q } : {} });
    out.push(data);
  }
  return out;
}

export function parseDecklist(text) {
  const lines = String(text).split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  const items = [];
  for (const line of lines) {
    const m = line.match(/^(\d+)\s+(.+)$/);
    if (m) {
      items.push({ count: parseInt(m[1], 10), name: m[2] });
    } else {
      items.push({ count: 1, name: line });
    }
  }
  return items;
}

export function convertToTTSCard(card, cardBackUrl) {
  const face = getFaceImage(card);
  const desc = getOracleText(card);
  const key = 1;
  const id = key * 100;
  return {
    name: card.name,
    set: card.set,
    collector_number: card.collector_number,
    image_url: face,
    scryfall_id: card.id,
    tts: {
      Name: "CardCustom",
      Nickname: card.name,
      Description: desc,
      GMNotes: JSON.stringify({ set: card.set, collector_number: card.collector_number, id: card.id }),
      Tags: ['MTG'],
      CustomDeck: {
        [key]: {
          FaceURL: face || '',
          BackURL: cardBackUrl || '',
          NumWidth: 10,
          NumHeight: 7,
          BackIsHidden: true
        }
      },
      DeckIDs: [id]
    }
  };
}

export function convertToSpawnObject(card, cardBackUrl, hand) {
  const face = getFaceImage(card);
  const desc = getOracleText(card);
  const key = 1;
  const id = key * 100;
  const pos = (hand && hand.position) ? hand.position : { x: 0, y: 1, z: 0 };
  const rot = (hand && hand.rotation) ? hand.rotation : { x: 0, y: 180, z: 0 };
  return {
    Name: "CardCustom",
    Transform: {
      posX: pos.x || 0,
      posY: pos.y || 1,
      posZ: pos.z || 0,
      rotX: rot.x || 0,
      rotY: rot.y || 0,
      rotZ: rot.z || 0,
      scaleX: 1,
      scaleY: 1,
      scaleZ: 1
    },
    Nickname: card.name,
    Description: desc,
    GMNotes: JSON.stringify({ set: card.set, collector_number: card.collector_number, id: card.id }),
    Tags: ['MTG'],
    CustomDeck: {
      [key]: {
        FaceURL: face || '',
        BackURL: cardBackUrl || '',
        NumWidth: 10,
        NumHeight: 7,
        BackIsHidden: true
      }
    },
    DeckIDs: [id]
  };
}
