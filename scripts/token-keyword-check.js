const axios = require('axios');

const baseUrl = 'http://localhost:3000';
const terms = ['fish', 'soldier', 'angel'];

(async () => {
  for (const term of terms) {
    const query = `t:token name:${term}`;
    const response = await axios.post(
      `${baseUrl}/random/build`,
      { q: query, count: 15, enforceCommander: true, explain: true },
      {
        validateStatus: () => true,
        headers: { Accept: 'application/x-ndjson' },
        timeout: 30000
      }
    );

    const text = typeof response.data === 'string'
      ? response.data
      : JSON.stringify(response.data || '');

    const firstLine = text.split(/\r?\n/).find(Boolean) || '';
    let deck = null;
    try {
      deck = JSON.parse(firstLine);
    } catch {
      deck = null;
    }

    const cards = Array.isArray(deck && deck.ContainedObjects) ? deck.ContainedObjects : [];
    const names = cards.map(card => String(card.Nickname || '').trim()).filter(Boolean);
    const memos = cards.map(card => String(card.Memo || '').trim()).filter(Boolean);

    const uniqueNames = new Set(names);
    const uniqueMemos = new Set(memos);

    console.log(JSON.stringify({
      term,
      query,
      status: response.status,
      plan: response.headers['x-query-plan'] || null,
      explain: response.headers['x-query-explain'] || null,
      returnedCards: cards.length,
      uniqueByName: uniqueNames.size,
      uniqueByMemo: uniqueMemos.size,
      names
    }));
  }
})().catch(error => {
  console.error(JSON.stringify({ error: error.message }));
  process.exit(1);
});
