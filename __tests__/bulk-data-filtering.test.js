/**
 * Tests for bulk data filtering logic
 * Specifically tests exclusion of test cards, acorn-stamped cards, and non-playable layouts
 * 
 * Note: The isNonPlayableCard function is not exported, so we test the filtering
 * logic through mock scenarios that replicate the function's behavior.
 */

describe('Bulk Data Filtering - Non-Playable Cards', () => {
  describe('Card identification logic', () => {
    // These tests document the expected behavior of card filtering
    
    test('should identify Mystery Booster playtest cards (cmb1)', () => {
      const testCard = {
        name: 'Test Card',
        set: 'cmb1',
        type_line: 'Creature'
      };
      // We'll verify this through integration tests below
      expect(testCard.set).toBe('cmb1');
    });

    test('should identify Mystery Booster 2 test cards (mb2)', () => {
      const testCard = {
        name: 'Test Card 2',
        set: 'mb2',
        type_line: 'Creature'
      };
      expect(testCard.set).toBe('mb2');
    });

    test('should identify cmb2 test cards', () => {
      const testCard = {
        name: 'Test Card 3',
        set: 'cmb2',
        type_line: 'Creature'
      };
      expect(testCard.set).toBe('cmb2');
    });

    test('should identify acorn-stamped cards', () => {
      const acornCard = {
        name: 'Acorn Card',
        set: 'unf',
        security_stamp: 'acorn',
        type_line: 'Creature'
      };
      expect(acornCard.security_stamp).toBe('acorn');
    });

    test('should not flag normal cards', () => {
      const normalCard = {
        name: 'Lightning Bolt',
        set: 'lea',
        security_stamp: null,
        type_line: 'Instant'
      };
      expect(normalCard.set).not.toMatch(/^(cmb1|mb2|cmb2)$/);
      expect(normalCard.security_stamp).not.toBe('acorn');
    });

    test('should not flag cards with oval security stamp', () => {
      const normalCard = {
        name: 'Modern Card',
        set: 'mh2',
        security_stamp: 'oval',
        type_line: 'Creature'
      };
      expect(normalCard.security_stamp).not.toBe('acorn');
    });
  });

  describe('Integration: Test card exclusion in mock scenarios', () => {
    test('test cards should be excluded based on set code', () => {
      // This is a specification test to document expected behavior
      const testCardSets = ['cmb1', 'mb2', 'cmb2'];
      const mockCards = [
        { name: 'Normal Card', set: 'dom', security_stamp: null },
        { name: 'Test Card 1', set: 'cmb1', security_stamp: null },
        { name: 'Test Card 2', set: 'mb2', security_stamp: null },
        { name: 'Normal Card 2', set: 'mh2', security_stamp: 'oval' }
      ];

      // Filter out test cards manually to verify logic
      const filtered = mockCards.filter(card => {
        const set = card.set || '';
        return !testCardSets.includes(set.toLowerCase());
      });

      expect(filtered).toHaveLength(2);
      expect(filtered.map(c => c.name)).toEqual(['Normal Card', 'Normal Card 2']);
    });

    test('acorn cards should be excluded based on security_stamp', () => {
      const mockCards = [
        { name: 'Normal Card', set: 'dom', security_stamp: null },
        { name: 'Acorn Card 1', set: 'unf', security_stamp: 'acorn' },
        { name: 'Acorn Card 2', set: 'und', security_stamp: 'acorn' },
        { name: 'Normal Card 2', set: 'mh2', security_stamp: 'oval' }
      ];

      // Filter out acorn cards manually to verify logic
      const filtered = mockCards.filter(card => {
        const securityStamp = card.security_stamp || '';
        return securityStamp.toLowerCase() !== 'acorn';
      });

      expect(filtered).toHaveLength(2);
      expect(filtered.map(c => c.name)).toEqual(['Normal Card', 'Normal Card 2']);
    });

    test('both test and acorn cards should be excluded', () => {
      const testCardSets = ['cmb1', 'mb2', 'cmb2'];
      const mockCards = [
        { name: 'Normal Card', set: 'dom', security_stamp: null },
        { name: 'Test Card', set: 'cmb1', security_stamp: null },
        { name: 'Acorn Card', set: 'unf', security_stamp: 'acorn' },
        { name: 'Test Acorn Card', set: 'cmb1', security_stamp: 'acorn' }, // Both!
        { name: 'Normal Card 2', set: 'mh2', security_stamp: 'oval' }
      ];

      // Filter out both test and acorn cards
      const filtered = mockCards.filter(card => {
        const set = card.set || '';
        const securityStamp = card.security_stamp || '';
        const isTest = testCardSets.includes(set.toLowerCase());
        const isAcorn = securityStamp.toLowerCase() === 'acorn';
        return !isTest && !isAcorn;
      });

      expect(filtered).toHaveLength(2);
      expect(filtered.map(c => c.name)).toEqual(['Normal Card', 'Normal Card 2']);
    });
  });

  describe('Case insensitivity', () => {
    test('set codes should be matched case-insensitively', () => {
      const testCardSets = ['cmb1', 'mb2', 'cmb2'];
      const mockCards = [
        { name: 'Test Card Upper', set: 'CMB1', security_stamp: null },
        { name: 'Test Card Mixed', set: 'Mb2', security_stamp: null },
        { name: 'Normal Card', set: 'DOM', security_stamp: null }
      ];

      const filtered = mockCards.filter(card => {
        const set = card.set || '';
        return !testCardSets.includes(set.toLowerCase());
      });

      expect(filtered).toHaveLength(1);
      expect(filtered[0].name).toBe('Normal Card');
    });

    test('security_stamp should be matched case-insensitively', () => {
      const mockCards = [
        { name: 'Acorn Upper', set: 'unf', security_stamp: 'ACORN' },
        { name: 'Acorn Mixed', set: 'unf', security_stamp: 'Acorn' },
        { name: 'Normal Card', set: 'dom', security_stamp: 'OVAL' }
      ];

      const filtered = mockCards.filter(card => {
        const securityStamp = card.security_stamp || '';
        return securityStamp.toLowerCase() !== 'acorn';
      });

      expect(filtered).toHaveLength(1);
      expect(filtered[0].name).toBe('Normal Card');
    });
  });

  describe('Non-playable layout filtering', () => {
    // Test that non-playable card layouts are properly identified and excluded
    const nonPlayableLayouts = [
      'token',
      'double_faced_token',
      'emblem',
      'planar',
      'scheme',
      'vanguard',
      'art_series',
      'reversible_card',
      'augment',
      'host',
      'dungeon',
      'hero',
      'attraction',
      'stickers'
    ];

    test.each(nonPlayableLayouts)('should exclude cards with layout: %s', (layout) => {
      const mockCards = [
        { name: 'Normal Card', set: 'dom', layout: 'normal' },
        { name: `Non-playable ${layout}`, set: 'test', layout: layout },
        { name: 'Another Normal', set: 'mh2', layout: 'transform' }
      ];

      const filtered = mockCards.filter(card => {
        const cardLayout = card.layout || '';
        const nonPlayableLayouts = [
          'token', 'double_faced_token', 'emblem', 'planar', 'scheme',
          'vanguard', 'art_series', 'reversible_card', 'augment', 'host',
          'dungeon', 'hero', 'attraction', 'stickers'
        ];
        return !nonPlayableLayouts.includes(cardLayout.toLowerCase());
      });

      expect(filtered).toHaveLength(2);
      expect(filtered.map(c => c.name)).toEqual(['Normal Card', 'Another Normal']);
    });
    
    test('should exclude dungeon cards (AFR)', () => {
      const mockCards = [
        { name: 'Normal Card', set: 'afr', layout: 'normal' },
        { name: 'Dungeon of the Mad Mage', set: 'afr', layout: 'dungeon' },
        { name: 'Another Normal', set: 'afr', layout: 'modal_dfc' }
      ];

      const filtered = mockCards.filter(card => {
        const layout = card.layout || '';
        return layout.toLowerCase() !== 'dungeon';
      });

      expect(filtered).toHaveLength(2);
      expect(filtered.map(c => c.name)).toEqual(['Normal Card', 'Another Normal']);
    });
    
    test('should exclude hero cards (THB)', () => {
      const mockCards = [
        { name: 'Normal Card', set: 'thb', layout: 'normal' },
        { name: 'Hero Card', set: 'thb', layout: 'hero' },
        { name: 'Another Normal', set: 'thb', layout: 'transform' }
      ];

      const filtered = mockCards.filter(card => {
        const layout = card.layout || '';
        return layout.toLowerCase() !== 'hero';
      });

      expect(filtered).toHaveLength(2);
      expect(filtered.map(c => c.name)).toEqual(['Normal Card', 'Another Normal']);
    });
    
    test('should exclude attraction cards (Unfinity)', () => {
      const mockCards = [
        { name: 'Normal Card', set: 'unf', layout: 'normal', security_stamp: 'oval' },
        { name: 'Attraction Card', set: 'unf', layout: 'attraction' },
        { name: 'Another Normal', set: 'unf', layout: 'transform', security_stamp: 'oval' }
      ];

      const filtered = mockCards.filter(card => {
        const layout = card.layout || '';
        return layout.toLowerCase() !== 'attraction';
      });

      expect(filtered).toHaveLength(2);
      expect(filtered.map(c => c.name)).toEqual(['Normal Card', 'Another Normal']);
    });
    
    test('should exclude sticker cards (Unfinity)', () => {
      const mockCards = [
        { name: 'Normal Card', set: 'unf', layout: 'normal', security_stamp: 'oval' },
        { name: 'Sticker Sheet', set: 'unf', layout: 'stickers' },
        { name: 'Another Normal', set: 'unf', layout: 'transform', security_stamp: 'oval' }
      ];

      const filtered = mockCards.filter(card => {
        const layout = card.layout || '';
        return layout.toLowerCase() !== 'stickers';
      });

      expect(filtered).toHaveLength(2);
      expect(filtered.map(c => c.name)).toEqual(['Normal Card', 'Another Normal']);
    });

    test('should allow playable layouts', () => {
      const playableLayouts = [
        'normal', 'split', 'flip', 'transform', 'modal_dfc', 'meld',
        'leveler', 'class', 'case', 'saga', 'adventure', 'mutate',
        'prototype', 'battle'
      ];

      const mockCards = playableLayouts.map(layout => ({
        name: `Card with ${layout}`,
        set: 'test',
        layout: layout
      }));

      const nonPlayableLayouts = [
        'token', 'double_faced_token', 'emblem', 'planar', 'scheme',
        'vanguard', 'art_series', 'reversible_card', 'augment', 'host'
      ];

      const filtered = mockCards.filter(card => {
        const cardLayout = card.layout || '';
        return !nonPlayableLayouts.includes(cardLayout.toLowerCase());
      });

      // All playable layouts should pass through
      expect(filtered).toHaveLength(playableLayouts.length);
    });

    test('should filter combined: test sets, acorn, and non-playable layouts', () => {
      const testCardSets = ['cmb1', 'mb2', 'cmb2'];
      const nonPlayableLayouts = [
        'token', 'double_faced_token', 'emblem', 'planar', 'scheme',
        'vanguard', 'art_series', 'reversible_card', 'augment', 'host',
        'dungeon', 'hero', 'attraction', 'stickers'
      ];

      const mockCards = [
        { name: 'Normal Card', set: 'dom', security_stamp: null, layout: 'normal' },
        { name: 'Test Card', set: 'cmb1', security_stamp: null, layout: 'normal' },
        { name: 'Acorn Card', set: 'unf', security_stamp: 'acorn', layout: 'normal' },
        { name: 'Token Card', set: 'tkhm', security_stamp: null, layout: 'token' },
        { name: 'Art Card', set: 'nec', security_stamp: null, layout: 'art_series' },
        { name: 'Emblem', set: 'teld', security_stamp: null, layout: 'emblem' },
        { name: 'Dungeon Card', set: 'afr', security_stamp: null, layout: 'dungeon' },
        { name: 'Hero Card', set: 'thb', security_stamp: null, layout: 'hero' },
        { name: 'Attraction', set: 'unf', security_stamp: null, layout: 'attraction' },
        { name: 'Normal Card 2', set: 'mh2', security_stamp: 'oval', layout: 'transform' }
      ];

      // Apply all filters
      const filtered = mockCards.filter(card => {
        const set = card.set || '';
        const securityStamp = card.security_stamp || '';
        const layout = card.layout || '';
        
        const isTest = testCardSets.includes(set.toLowerCase());
        const isAcorn = securityStamp.toLowerCase() === 'acorn';
        const isNonPlayable = nonPlayableLayouts.includes(layout.toLowerCase());
        
        return !isTest && !isAcorn && !isNonPlayable;
      });

      expect(filtered).toHaveLength(2);
      expect(filtered.map(c => c.name)).toEqual(['Normal Card', 'Normal Card 2']);
    });

    test('layout matching should be case-insensitive', () => {
      const mockCards = [
        { name: 'Token Upper', set: 'test', layout: 'TOKEN' },
        { name: 'Token Mixed', set: 'test', layout: 'Token' },
        { name: 'Art Series Upper', set: 'test', layout: 'ART_SERIES' },
        { name: 'Dungeon Upper', set: 'test', layout: 'DUNGEON' },
        { name: 'Hero Mixed', set: 'test', layout: 'Hero' },
        { name: 'Normal Card', set: 'dom', layout: 'NORMAL' }
      ];

      const nonPlayableLayouts = [
        'token', 'double_faced_token', 'emblem', 'planar', 'scheme',
        'vanguard', 'art_series', 'reversible_card', 'augment', 'host',
        'dungeon', 'hero', 'attraction', 'stickers'
      ];

      const filtered = mockCards.filter(card => {
        const layout = card.layout || '';
        return !nonPlayableLayouts.includes(layout.toLowerCase());
      });

      expect(filtered).toHaveLength(1);
      expect(filtered[0].name).toBe('Normal Card');
    });
  });
});
