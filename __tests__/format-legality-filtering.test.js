/**
 * Tests for format legality and layout filtering
 * Tests legal:, banned:, restricted:, and layout: filters
 */

describe('Format Legality and Layout Filtering', () => {
  // Mock card data with different legality statuses
  const mockCards = [
    {
      name: 'Lightning Bolt',
      type_line: 'Instant',
      set: 'lea',
      lang: 'en',
      layout: 'normal',
      legalities: {
        standard: 'not_legal',
        modern: 'legal',
        legacy: 'legal',
        vintage: 'legal',
        commander: 'legal',
        pauper: 'legal'
      }
    },
    {
      name: 'Black Lotus',
      type_line: 'Artifact',
      set: 'lea',
      lang: 'en',
      layout: 'normal',
      legalities: {
        standard: 'not_legal',
        modern: 'banned',
        legacy: 'banned',
        vintage: 'restricted',
        commander: 'banned',
        pauper: 'not_legal'
      }
    },
    {
      name: 'Delver of Secrets',
      type_line: 'Creature — Human Wizard',
      set: 'isd',
      lang: 'en',
      layout: 'transform',
      legalities: {
        standard: 'not_legal',
        modern: 'legal',
        legacy: 'legal',
        vintage: 'legal',
        commander: 'legal',
        pauper: 'legal'
      }
    },
    {
      name: 'Fire // Ice',
      type_line: 'Instant // Instant',
      set: 'mh2',
      lang: 'en',
      layout: 'split',
      legalities: {
        standard: 'not_legal',
        modern: 'legal',
        legacy: 'legal',
        vintage: 'legal',
        commander: 'legal',
        pauper: 'not_legal'
      }
    },
    {
      name: 'Sol Ring',
      type_line: 'Artifact',
      set: 'c21',
      lang: 'en',
      layout: 'normal',
      legalities: {
        standard: 'not_legal',
        modern: 'banned',
        legacy: 'legal',
        vintage: 'legal',
        commander: 'legal',
        pauper: 'not_legal'
      }
    }
  ];

  // Simplified parseQuery and filterCards for testing
  const parseQuery = (query) => {
    const filters = {
      language: 'en',
      legal: null,
      banned: null,
      restricted: null,
      layout: null,
      excludeLayout: null
    };

    const parts = query.match(/[^\s+]+/g) || [];
    
    parts.forEach(part => {
      // Format legality filters
      if (part.match(/^legal:/i)) {
        const match = part.match(/legal:(\w+)/i);
        if (match) filters.legal = match[1].toLowerCase();
      }
      
      if (part.match(/^banned:/i)) {
        const match = part.match(/banned:(\w+)/i);
        if (match) filters.banned = match[1].toLowerCase();
      }
      
      if (part.match(/^restricted:/i)) {
        const match = part.match(/restricted:(\w+)/i);
        if (match) filters.restricted = match[1].toLowerCase();
      }
      
      // Layout filter
      if (part.match(/^layout:/i)) {
        const match = part.match(/layout:(\w+)/i);
        if (match) filters.layout = match[1].toLowerCase();
      }
      
      if (part.match(/^-layout:/i)) {
        const match = part.match(/-layout:(\w+)/i);
        if (match) filters.excludeLayout = match[1].toLowerCase();
      }
    });

    return filters;
  };

  const filterCards = (cards, filters) => {
    return cards.filter(card => {
      if (card.lang !== filters.language) return false;
      
      // Format legality filters
      if (filters.legal) {
        const legalities = card.legalities || {};
        if (legalities[filters.legal] !== 'legal') return false;
      }
      
      if (filters.banned) {
        const legalities = card.legalities || {};
        if (legalities[filters.banned] !== 'banned') return false;
      }
      
      if (filters.restricted) {
        const legalities = card.legalities || {};
        if (legalities[filters.restricted] !== 'restricted') return false;
      }
      
      // Layout filter
      if (filters.layout && card.layout !== filters.layout) return false;
      if (filters.excludeLayout && card.layout === filters.excludeLayout) return false;
      
      return true;
    });
  };

  describe('Format legality filtering', () => {
    test('should filter cards legal in commander format', () => {
      const query = 'legal:commander';
      const filters = parseQuery(query);
      const results = filterCards(mockCards, filters);

      expect(results.length).toBeGreaterThan(0);
      expect(results.every(c => c.legalities.commander === 'legal')).toBe(true);
      
      const names = results.map(c => c.name);
      expect(names).toContain('Lightning Bolt');
      expect(names).toContain('Delver of Secrets');
      expect(names).not.toContain('Black Lotus'); // Banned in commander
    });

    test('should filter cards legal in modern format', () => {
      const query = 'legal:modern';
      const filters = parseQuery(query);
      const results = filterCards(mockCards, filters);

      expect(results.length).toBeGreaterThan(0);
      expect(results.every(c => c.legalities.modern === 'legal')).toBe(true);
      
      const names = results.map(c => c.name);
      expect(names).toContain('Lightning Bolt');
      expect(names).toContain('Delver of Secrets');
      expect(names).not.toContain('Black Lotus'); // Banned in modern
      expect(names).not.toContain('Sol Ring'); // Banned in modern
    });

    test('should filter cards legal in pauper format', () => {
      const query = 'legal:pauper';
      const filters = parseQuery(query);
      const results = filterCards(mockCards, filters);

      expect(results.length).toBeGreaterThan(0);
      expect(results.every(c => c.legalities.pauper === 'legal')).toBe(true);
      
      const names = results.map(c => c.name);
      expect(names).toContain('Lightning Bolt');
      expect(names).toContain('Delver of Secrets');
    });

    test('should filter cards banned in modern format', () => {
      const query = 'banned:modern';
      const filters = parseQuery(query);
      const results = filterCards(mockCards, filters);

      expect(results.length).toBeGreaterThan(0);
      expect(results.every(c => c.legalities.modern === 'banned')).toBe(true);
      
      const names = results.map(c => c.name);
      expect(names).toContain('Black Lotus');
      expect(names).toContain('Sol Ring');
      expect(names).not.toContain('Lightning Bolt');
    });

    test('should filter cards restricted in vintage format', () => {
      const query = 'restricted:vintage';
      const filters = parseQuery(query);
      const results = filterCards(mockCards, filters);

      expect(results).toHaveLength(1);
      expect(results[0].name).toBe('Black Lotus');
      expect(results[0].legalities.vintage).toBe('restricted');
    });
  });

  describe('Layout filtering', () => {
    test('should filter cards with normal layout', () => {
      const query = 'layout:normal';
      const filters = parseQuery(query);
      const results = filterCards(mockCards, filters);

      expect(results.length).toBeGreaterThan(0);
      expect(results.every(c => c.layout === 'normal')).toBe(true);
      
      const names = results.map(c => c.name);
      expect(names).toContain('Lightning Bolt');
      expect(names).toContain('Black Lotus');
      expect(names).not.toContain('Delver of Secrets'); // transform layout
      expect(names).not.toContain('Fire // Ice'); // split layout
    });

    test('should filter cards with transform layout', () => {
      const query = 'layout:transform';
      const filters = parseQuery(query);
      const results = filterCards(mockCards, filters);

      expect(results).toHaveLength(1);
      expect(results[0].name).toBe('Delver of Secrets');
      expect(results[0].layout).toBe('transform');
    });

    test('should filter cards with split layout', () => {
      const query = 'layout:split';
      const filters = parseQuery(query);
      const results = filterCards(mockCards, filters);

      expect(results).toHaveLength(1);
      expect(results[0].name).toBe('Fire // Ice');
      expect(results[0].layout).toBe('split');
    });

    test('should exclude cards with specified layout', () => {
      const query = '-layout:normal';
      const filters = parseQuery(query);
      const results = filterCards(mockCards, filters);

      expect(results.length).toBeGreaterThan(0);
      expect(results.every(c => c.layout !== 'normal')).toBe(true);
      
      const names = results.map(c => c.name);
      expect(names).toContain('Delver of Secrets');
      expect(names).toContain('Fire // Ice');
      expect(names).not.toContain('Lightning Bolt');
      expect(names).not.toContain('Black Lotus');
    });
  });

  describe('Query parsing', () => {
    test('should parse legal:commander filter', () => {
      const filters = parseQuery('legal:commander');
      
      expect(filters.legal).toBe('commander');
    });

    test('should parse banned:modern filter', () => {
      const filters = parseQuery('banned:modern');
      
      expect(filters.banned).toBe('modern');
    });

    test('should parse restricted:vintage filter', () => {
      const filters = parseQuery('restricted:vintage');
      
      expect(filters.restricted).toBe('vintage');
    });

    test('should parse layout:transform filter', () => {
      const filters = parseQuery('layout:transform');
      
      expect(filters.layout).toBe('transform');
    });

    test('should parse -layout:normal filter', () => {
      const filters = parseQuery('-layout:normal');
      
      expect(filters.excludeLayout).toBe('normal');
    });

    test('should handle case insensitivity', () => {
      const filters1 = parseQuery('legal:COMMANDER');
      const filters2 = parseQuery('Legal:Commander');
      const filters3 = parseQuery('LEGAL:commander');
      
      expect(filters1.legal).toBe('commander');
      expect(filters2.legal).toBe('commander');
      expect(filters3.legal).toBe('commander');
    });
  });
});
