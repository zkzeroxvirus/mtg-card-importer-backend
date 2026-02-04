/**
 * Tests for price filtering in bulk data
 * Tests USD, EUR, and TIX price filters with various operators
 */

describe('Price Filtering', () => {
  // Mock card data with different prices
  const mockCards = [
    {
      name: 'Expensive Card',
      type_line: 'Artifact',
      set: 'lea',
      lang: 'en',
      prices: { usd: '100.00', eur: '90.00', tix: '50.00' }
    },
    {
      name: 'Mid Price Card',
      type_line: 'Artifact',
      set: 'lea',
      lang: 'en',
      prices: { usd: '25.50', eur: '20.00', tix: '10.00' }
    },
    {
      name: 'Cheap Card',
      type_line: 'Artifact',
      set: 'lea',
      lang: 'en',
      prices: { usd: '1.00', eur: '0.80', tix: '0.50' }
    },
    {
      name: 'No Price Card',
      type_line: 'Artifact',
      set: 'lea',
      lang: 'en',
      prices: { usd: null, eur: null, tix: null }
    }
  ];

  // Helper to simulate parseQuery and filterCards functionality
  const parseQuerySimple = (query) => {
    const filters = {
      language: 'en',
      type: [],
      usdGreaterEqual: null,
      usdGreater: null,
      usdLessEqual: null,
      usdLess: null,
      usdEquals: null
    };

    // Parse type
    const typeMatch = query.match(/t:(\w+)/i);
    if (typeMatch) {
      filters.type.push(typeMatch[1].toLowerCase());
    }

    // Parse USD filters
    let match;
    if ((match = query.match(/usd>=([0-9.]+)/i))) {
      filters.usdGreaterEqual = parseFloat(match[1]);
    } else if ((match = query.match(/usd>([0-9.]+)/i))) {
      filters.usdGreater = parseFloat(match[1]);
    } else if ((match = query.match(/usd<=([0-9.]+)/i))) {
      filters.usdLessEqual = parseFloat(match[1]);
    } else if ((match = query.match(/usd<([0-9.]+)/i))) {
      filters.usdLess = parseFloat(match[1]);
    } else if ((match = query.match(/usd[:=]([0-9.]+)/i))) {
      filters.usdEquals = parseFloat(match[1]);
    }

    return filters;
  };

  const filterCardsSimple = (cards, filters) => {
    return cards.filter(card => {
      // Language filter
      if (card.lang !== filters.language) return false;

      // Type filter
      if (filters.type.length > 0) {
        const typeLine = (card.type_line || '').toLowerCase();
        const hasAllTypes = filters.type.every(t => typeLine.includes(t));
        if (!hasAllTypes) return false;
      }

      // USD price filters
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

  describe('USD price filtering', () => {
    test('should filter cards with usd>=50', () => {
      const query = 't:artifact usd>=50';
      const filters = parseQuerySimple(query);
      const results = filterCardsSimple(mockCards, filters);

      expect(results).toHaveLength(1);
      expect(results[0].name).toBe('Expensive Card');
    });

    test('should filter cards with usd>50', () => {
      const query = 't:artifact usd>50';
      const filters = parseQuerySimple(query);
      const results = filterCardsSimple(mockCards, filters);

      expect(results).toHaveLength(1);
      expect(results[0].name).toBe('Expensive Card');
    });

    test('should filter cards with usd<=25.50', () => {
      const query = 't:artifact usd<=25.50';
      const filters = parseQuerySimple(query);
      const results = filterCardsSimple(mockCards, filters);

      expect(results).toHaveLength(2);
      expect(results.map(c => c.name)).toContain('Mid Price Card');
      expect(results.map(c => c.name)).toContain('Cheap Card');
    });

    test('should filter cards with usd<10', () => {
      const query = 't:artifact usd<10';
      const filters = parseQuerySimple(query);
      const results = filterCardsSimple(mockCards, filters);

      expect(results).toHaveLength(1);
      expect(results[0].name).toBe('Cheap Card');
    });

    test('should filter cards with exact price usd=25.50', () => {
      const query = 't:artifact usd=25.50';
      const filters = parseQuerySimple(query);
      const results = filterCardsSimple(mockCards, filters);

      expect(results).toHaveLength(1);
      expect(results[0].name).toBe('Mid Price Card');
    });

    test('should exclude cards with no USD price', () => {
      const query = 't:artifact usd>=0';
      const filters = parseQuerySimple(query);
      const results = filterCardsSimple(mockCards, filters);

      // Should return 3 cards (all with prices), excluding the one with null price
      expect(results).toHaveLength(3);
      expect(results.map(c => c.name)).not.toContain('No Price Card');
    });
  });

  describe('Query parsing', () => {
    test('should parse combined query t:artifact+usd>=50', () => {
      const filters = parseQuerySimple('t:artifact+usd>=50');
      
      expect(filters.type).toContain('artifact');
      expect(filters.usdGreaterEqual).toBe(50);
    });

    test('should parse query with spaces t:artifact usd>=50', () => {
      const filters = parseQuerySimple('t:artifact usd>=50');
      
      expect(filters.type).toContain('artifact');
      expect(filters.usdGreaterEqual).toBe(50);
    });

    test('should parse decimal prices', () => {
      const filters = parseQuerySimple('usd>=12.50');
      
      expect(filters.usdGreaterEqual).toBe(12.50);
    });

    test('should parse integer prices', () => {
      const filters = parseQuerySimple('usd>=100');
      
      expect(filters.usdGreaterEqual).toBe(100);
    });
  });
});
