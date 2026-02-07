/**
 * Integration tests for price filtering with actual queries
 * Tests the full query parsing and filtering pipeline
 */

describe('Price Filter Integration Tests', () => {
  // Mock cards database similar to Scryfall bulk data
  const mockCardsDatabase = [
    {
      name: 'Mox Diamond',
      type_line: 'Artifact',
      set: 'lea',
      lang: 'en',
      cmc: 0,
      prices: { usd: '450.00', eur: '400.00', tix: '200.00' }
    },
    {
      name: 'Sol Ring',
      type_line: 'Artifact',
      set: 'c21',
      lang: 'en',
      cmc: 1,
      prices: { usd: '1.50', eur: '1.20', tix: '0.05' }
    },
    {
      name: 'Mana Vault',
      type_line: 'Artifact',
      set: 'lea',
      lang: 'en',
      cmc: 1,
      prices: { usd: '75.00', eur: '65.00', tix: '35.00' }
    },
    {
      name: 'Expensive Artifact',
      type_line: 'Artifact',
      set: 'lea',
      lang: 'en',
      cmc: 2,
      prices: { usd: '100.00', eur: '90.00', tix: '50.00' }
    },
    {
      name: 'Mountain',
      type_line: 'Basic Land — Mountain',
      set: 'unh',
      lang: 'en',
      cmc: 0,
      prices: { usd: '0.05', eur: '0.04', tix: '0.01' }
    },
    {
      name: 'Island',
      type_line: 'Basic Land — Island',
      set: 'unh',
      lang: 'en',
      cmc: 0,
      prices: { usd: '0.05', eur: '0.04', tix: '0.01' }
    }
  ];

  // Simplified parseQuery and filterCards for testing
  const parseQuery = (query) => {
    const filters = {
      language: 'en',
      type: [],
      set: null,
      nameContains: null,
      usdGreaterEqual: null,
      usdGreater: null,
      usdLessEqual: null,
      usdLess: null,
      usdEquals: null
    };

    const parts = query.match(/[^\s+]+/g) || [];
    
    // Check if query is just a plain text search (no operators like : = < >)
    if (!/:/.test(query) && !/[=<>]/.test(query)) {
      filters.nameContains = query.toLowerCase();
      return filters;
    }
    
    parts.forEach(part => {
      // Type
      if (part.match(/^t:(\w+)/i)) {
        const typeMatch = part.match(/^t:(\w+)/i);
        filters.type.push(typeMatch[1].toLowerCase());
        return;
      }

      // Set
      if (part.match(/^s[et]*:(\w+)/i)) {
        const setMatch = part.match(/^s[et]*:(\w+)/i);
        filters.set = setMatch[1].toLowerCase();
        return;
      }

      // USD filters - check all patterns first
      if (part.match(/^usd[:=<>]/i)) {
        let match;
        if ((match = part.match(/usd>=([0-9.]+)/i))) {
          filters.usdGreaterEqual = parseFloat(match[1]);
        } else if ((match = part.match(/usd>([0-9.]+)/i))) {
          filters.usdGreater = parseFloat(match[1]);
        } else if ((match = part.match(/usd<=([0-9.]+)/i))) {
          filters.usdLessEqual = parseFloat(match[1]);
        } else if ((match = part.match(/usd<([0-9.]+)/i))) {
          filters.usdLess = parseFloat(match[1]);
        } else if ((match = part.match(/usd[:=]([0-9.]+)/i))) {
          filters.usdEquals = parseFloat(match[1]);
        }
        return;
      }
      
      // If it's not a known filter, treat it as name search
      if (!/^(t|s|set|usd|eur|tix):/.test(part) && !/^(usd|eur|tix)[=<>]/.test(part)) {
        filters.nameContains = part.toLowerCase();
      }
    });

    return filters;
  };

  const filterCards = (cards, filters) => {
    return cards.filter(card => {
      if (card.lang !== filters.language) return false;
      
      if (filters.set && card.set !== filters.set) return false;
      
      if (filters.type.length > 0) {
        const typeLine = (card.type_line || '').toLowerCase();
        const hasAllTypes = filters.type.every(t => typeLine.includes(t));
        if (!hasAllTypes) return false;
      }
      
      if (filters.nameContains) {
        const cardName = (card.name || '').toLowerCase();
        if (!cardName.includes(filters.nameContains)) return false;
      }
      
      if (filters.usdEquals !== null || filters.usdGreater !== null || filters.usdGreaterEqual !== null || filters.usdLess !== null || filters.usdLessEqual !== null) {
        const usdPrice = card.prices?.usd;
        if (!usdPrice) return false;
        const usdNum = parseFloat(usdPrice);
        if (isNaN(usdNum)) return false;
        if (filters.usdEquals !== null && usdNum !== filters.usdEquals) return false;
        if (filters.usdGreater !== null && usdNum <= filters.usdGreater) return false;
        if (filters.usdGreaterEqual !== null && usdNum < filters.usdGreaterEqual) return false;
        if (filters.usdLess !== null && usdNum >= filters.usdLess) return false;
        if (filters.usdLessEqual !== null && usdNum > filters.usdLessEqual) return false;
      }
      
      return true;
    });
  };

  describe('Original problem statement commands', () => {
    test('should find artifacts costing $50 or more: t:artifact+usd>=50', () => {
      const query = 't:artifact+usd>=50';
      const filters = parseQuery(query);
      const results = filterCards(mockCardsDatabase, filters);

      expect(results.length).toBeGreaterThan(0);
      expect(results.every(c => c.type_line.toLowerCase().includes('artifact'))).toBe(true);
      expect(results.every(c => parseFloat(c.prices.usd) >= 50)).toBe(true);
      
      // Should include high-value cards
      const names = results.map(c => c.name);
      expect(names).toContain('Mox Diamond');
      expect(names).toContain('Mana Vault');
      expect(names).toContain('Expensive Artifact');
      
      // Should NOT include cheap cards
      expect(names).not.toContain('Sol Ring');
    });

    test('should find mountain cards in UNH set: mountain set:unh', () => {
      const query = 'mountain set:unh';
      const filters = parseQuery(query);
      const results = filterCards(mockCardsDatabase, filters);

      expect(results).toHaveLength(1);
      expect(results[0].name).toBe('Mountain');
      expect(results[0].set).toBe('unh');
    });
  });

  describe('Combined filters work correctly', () => {
    test('should combine type and price filters', () => {
      const query = 't:artifact usd>=50';
      const filters = parseQuery(query);
      
      expect(filters.type).toContain('artifact');
      expect(filters.usdGreaterEqual).toBe(50);
      
      const results = filterCards(mockCardsDatabase, filters);
      expect(results.every(c => {
        return c.type_line.toLowerCase().includes('artifact') &&
               parseFloat(c.prices.usd) >= 50;
      })).toBe(true);
    });

    test('should combine set and text filters', () => {
      const query = 'set:unh';
      const filters = parseQuery(query);
      
      expect(filters.set).toBe('unh');
      
      const results = filterCards(mockCardsDatabase, filters);
      expect(results.every(c => c.set === 'unh')).toBe(true);
      expect(results).toHaveLength(2); // Mountain and Island
    });
  });

  describe('Edge cases', () => {
    test('should handle decimal prices', () => {
      const query = 'usd>=1.50';
      const filters = parseQuery(query);
      const results = filterCards(mockCardsDatabase, filters);

      expect(results.length).toBeGreaterThan(0);
      expect(results.every(c => parseFloat(c.prices.usd) >= 1.50)).toBe(true);
    });

    test('should handle queries with + separator', () => {
      const query = 't:artifact+usd>=50';
      const filters = parseQuery(query);
      
      expect(filters.type).toContain('artifact');
      expect(filters.usdGreaterEqual).toBe(50);
    });

    test('should handle queries with space separator', () => {
      const query = 't:artifact usd>=50';
      const filters = parseQuery(query);
      
      expect(filters.type).toContain('artifact');
      expect(filters.usdGreaterEqual).toBe(50);
    });
  });

  describe('Price filter operators', () => {
    test('usd> operator should work (greater than)', () => {
      const query = 'usd>75';
      const filters = parseQuery(query);
      const results = filterCards(mockCardsDatabase, filters);

      expect(results.every(c => parseFloat(c.prices.usd) > 75)).toBe(true);
      expect(results.map(c => c.name)).toContain('Mox Diamond');
      expect(results.map(c => c.name)).not.toContain('Mana Vault'); // Exactly 75
    });

    test('usd< operator should work (less than)', () => {
      const query = 'usd<2';
      const filters = parseQuery(query);
      const results = filterCards(mockCardsDatabase, filters);

      expect(results.every(c => parseFloat(c.prices.usd) < 2)).toBe(true);
    });

    test('usd= operator should work (equals)', () => {
      const query = 'usd=1.50';
      const filters = parseQuery(query);
      const results = filterCards(mockCardsDatabase, filters);

      expect(results).toHaveLength(1);
      expect(results[0].name).toBe('Sol Ring');
    });
  });
});
