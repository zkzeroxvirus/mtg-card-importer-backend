const bulkData = require('../lib/bulk-data');

describe('Bulk Data - partial name matching', () => {
  const lightningBolt = {
    name: 'Lightning Bolt',
    set: 'm11',
    lang: 'en'
  };

  const ragavan = {
    name: 'Ragavan, Nimble Pilferer',
    set: 'mh2',
    lang: 'en'
  };

  const sampleEntries = [
    ['lightning bolt', [lightningBolt]],
    ['ragavan nimble pilferer', [ragavan]]
  ];

  test('matches small typos in card names', () => {
    const match = bulkData.findBestPartialNameMatch(sampleEntries, 'Ligntning Bolt');

    expect(match).toBe(lightningBolt);
  });

  test('matches loose shorthand when tokens are still close', () => {
    const match = bulkData.findBestPartialNameMatch(sampleEntries, 'ragavn nimble');

    expect(match).toBe(ragavan);
  });

  test('respects set filters while matching partially', () => {
    const match = bulkData.findBestPartialNameMatch(sampleEntries, 'light bolt', 'm11');

    expect(match).toBe(lightningBolt);
  });

  test('returns null for empty partial names', () => {
    expect(bulkData.findBestPartialNameMatch(sampleEntries, '   ')).toBeNull();
  });
});