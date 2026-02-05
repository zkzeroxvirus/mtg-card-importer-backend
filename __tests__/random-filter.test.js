/**
 * Tests for filtering non-playable cards (test cards, tokens, etc.) from random endpoint
 * Verifies that test card sets like cmb2 are excluded from random results
 */

const scryfall = require('../lib/scryfall');

describe('Non-Playable Card Filtering', () => {
  describe('buildNonPlayableFilter', () => {
    test('should build filter query with all non-playable exclusions', () => {
      const filter = scryfall.buildNonPlayableFilter();
      
      // Check for unique cards filter (to avoid reprints and alternative arts)
      expect(filter).toContain('is:unique');
      
      // Check for test set exclusions
      expect(filter).toContain('-set:cmb1');
      expect(filter).toContain('-set:cmb2');
      expect(filter).toContain('-set:mb2');
      
      // Check for other exclusions
      expect(filter).toContain('game:paper');
      expect(filter).toContain('-is:oversized');
      expect(filter).toContain('-stamp:acorn');
      expect(filter).toContain('-t:basic');
      expect(filter).toContain('-layout:token');
      expect(filter).toContain('-layout:emblem');
      expect(filter).toContain('-set_type:funny');
    });
  });

  describe('isNonPlayableCard', () => {
    test('should identify cmb2 test cards as non-playable', () => {
      const testCard = {
        name: 'Bombardment',
        set: 'cmb2',
        games: ['paper'],
        layout: 'normal',
        type_line: 'Instant'
      };
      
      expect(scryfall.isNonPlayableCard(testCard)).toBe(true);
    });

    test('should identify cmb1 test cards as non-playable', () => {
      const testCard = {
        name: 'Test Card',
        set: 'cmb1',
        games: ['paper'],
        layout: 'normal',
        type_line: 'Creature'
      };
      
      expect(scryfall.isNonPlayableCard(testCard)).toBe(true);
    });

    test('should identify mb2 test cards as non-playable', () => {
      const testCard = {
        name: 'Test Card',
        set: 'mb2',
        games: ['paper'],
        layout: 'normal',
        type_line: 'Sorcery'
      };
      
      expect(scryfall.isNonPlayableCard(testCard)).toBe(true);
    });

    test('should identify token cards as non-playable', () => {
      const tokenCard = {
        name: 'Goblin Token',
        set: 'afr',
        games: ['paper'],
        layout: 'token',
        type_line: 'Token Creature — Goblin'
      };
      
      expect(scryfall.isNonPlayableCard(tokenCard)).toBe(true);
    });

    test('should identify emblem cards as non-playable', () => {
      const emblemCard = {
        name: 'Elspeth Emblem',
        set: 'thb',
        games: ['paper'],
        layout: 'emblem',
        type_line: 'Emblem'
      };
      
      expect(scryfall.isNonPlayableCard(emblemCard)).toBe(true);
    });

    test('should identify basic lands as non-playable', () => {
      const basicLand = {
        name: 'Island',
        set: 'neo',
        games: ['paper'],
        layout: 'normal',
        type_line: 'Basic Land — Island'
      };
      
      expect(scryfall.isNonPlayableCard(basicLand)).toBe(true);
    });

    test('should identify acorn stamped cards as non-playable', () => {
      const acornCard = {
        name: 'Funny Card',
        set: 'unf',
        games: ['paper'],
        layout: 'normal',
        type_line: 'Creature — Squirrel',
        security_stamp: 'acorn'
      };
      
      expect(scryfall.isNonPlayableCard(acornCard)).toBe(true);
    });

    test('should identify digital-only cards as non-playable', () => {
      const digitalCard = {
        name: 'Digital Only Card',
        set: 'aneo',
        games: ['arena'],
        layout: 'normal',
        type_line: 'Creature — Human'
      };
      
      expect(scryfall.isNonPlayableCard(digitalCard)).toBe(true);
    });

    test('should identify oversized cards as non-playable', () => {
      const oversizedCard = {
        name: 'Oversized Card',
        set: 'pc2',
        games: ['paper'],
        layout: 'planar',
        type_line: 'Plane',
        oversized: true
      };
      
      expect(scryfall.isNonPlayableCard(oversizedCard)).toBe(true);
    });

    test('should identify funny set type cards as non-playable', () => {
      const funnyCard = {
        name: 'Unstable Card',
        set: 'ust',
        games: ['paper'],
        layout: 'normal',
        type_line: 'Creature — Contraption',
        set_type: 'funny'
      };
      
      expect(scryfall.isNonPlayableCard(funnyCard)).toBe(true);
    });

    test('should identify meld result cards (ending in b) as non-playable', () => {
      const meldResult = {
        name: 'Chittering Host',
        set: 'emn',
        games: ['paper'],
        layout: 'meld',
        type_line: 'Creature — Eldrazi Horror',
        collector_number: '96b'
      };
      
      expect(scryfall.isNonPlayableCard(meldResult)).toBe(true);
    });

    test('should allow normal playable cards', () => {
      const normalCard = {
        name: 'Lightning Bolt',
        set: 'lea',
        games: ['paper'],
        layout: 'normal',
        type_line: 'Instant'
      };
      
      expect(scryfall.isNonPlayableCard(normalCard)).toBe(false);
    });

    test('should allow non-basic lands', () => {
      const nonBasicLand = {
        name: 'Tropical Island',
        set: 'lea',
        games: ['paper'],
        layout: 'normal',
        type_line: 'Land — Forest Island'
      };
      
      expect(scryfall.isNonPlayableCard(nonBasicLand)).toBe(false);
    });

    test('should allow meld cards that are not results (ending in a)', () => {
      const meldCard = {
        name: 'Midnight Scavengers',
        set: 'emn',
        games: ['paper'],
        layout: 'meld',
        type_line: 'Creature — Human Rogue',
        collector_number: '96a'
      };
      
      expect(scryfall.isNonPlayableCard(meldCard)).toBe(false);
    });
  });

  describe('Consistency between bulk-data and scryfall', () => {
    test('should filter test cards using isNonPlayableCard', () => {
      const testCards = [
        { name: 'Test 1', set: 'cmb1', games: ['paper'], layout: 'normal', type_line: 'Creature' },
        { name: 'Test 2', set: 'cmb2', games: ['paper'], layout: 'normal', type_line: 'Instant' },
        { name: 'Test 3', set: 'mb2', games: ['paper'], layout: 'normal', type_line: 'Sorcery' }
      ];

      testCards.forEach(card => {
        // All test cards should be identified as non-playable
        expect(scryfall.isNonPlayableCard(card)).toBe(true);
      });
    });

    test('should filter tokens using isNonPlayableCard', () => {
      const tokenCard = {
        name: 'Token',
        set: 'afr',
        games: ['paper'],
        layout: 'token',
        type_line: 'Token Creature'
      };

      expect(scryfall.isNonPlayableCard(tokenCard)).toBe(true);
    });

    test('should allow normal cards using isNonPlayableCard', () => {
      const normalCard = {
        name: 'Normal Card',
        set: 'neo',
        games: ['paper'],
        layout: 'normal',
        type_line: 'Creature — Human'
      };

      expect(scryfall.isNonPlayableCard(normalCard)).toBe(false);
    });
  });
});
