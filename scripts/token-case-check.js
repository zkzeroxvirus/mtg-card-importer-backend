const axios = require('axios');

const baseUrl = 'http://localhost:3000';
const cases = [
  ['Soldier', 1, false],
  ['Soldier', 15, false],
  ['Fish', 1, false],
  ['Fish', 15, false],
  ['Soldier', 1, true],
  ['Soldier', 15, true],
  ['Fish', 1, true],
  ['Fish', 15, true]
];

(async () => {
  for (const [name, count, enforceCommander] of cases) {
    const query = `t:token name:"${name}"`;
    const response = await axios.post(
      `${baseUrl}/random/build`,
      { q: query, count, enforceCommander, explain: true },
      {
        validateStatus: () => true,
        headers: { Accept: 'application/x-ndjson' },
        timeout: 15000
      }
    );

    const text = typeof response.data === 'string'
      ? response.data
      : JSON.stringify(response.data || '');

    const hasDeckPayload = text.includes('DeckCustom') || text.includes('ContainedObjects');

    console.log(JSON.stringify({
      name,
      count,
      enforceCommander,
      status: response.status,
      hasDeckPayload,
      plan: response.headers['x-query-plan'] || null,
      explain: response.headers['x-query-explain'] || null,
      fallback: response.headers['x-bulk-fallback'] || null,
      bodySample: text.slice(0, 140)
    }));
  }
})().catch(error => {
  console.error(error);
  process.exit(1);
});
