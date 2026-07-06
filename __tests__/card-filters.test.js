const {
  hasMeaningfulRulesText,
  isStandaloneNonGameplayCard
} = require('../lib/card-filters');

describe('card-filters', () => {
  test('should reject standalone poster/accessory cards with no gameplay text or source links', () => {
    const stormCounter = {
      name: 'Storm Counter',
      type_line: 'Card',
      layout: 'normal',
      set_type: 'box',
      promo_types: ['poster'],
      oracle_text: '',
      legalities: {
        commander: 'not_legal',
        modern: 'not_legal'
      }
    };

    expect(isStandaloneNonGameplayCard(stormCounter)).toBe(true);
  });

  test('should reject theme-only front cards', () => {
    const jumpstartFrontCard = {
      name: 'Treasure',
      type_line: 'Card',
      layout: 'token',
      set_type: 'memorabilia',
      oracle_text: '(Theme color: {R})',
      legalities: {
        commander: 'not_legal'
      }
    };

    expect(hasMeaningfulRulesText(jumpstartFrontCard)).toBe(false);
    expect(isStandaloneNonGameplayCard(jumpstartFrontCard)).toBe(true);
  });

  test('should allow legal poster cards', () => {
    const aetherVialPoster = {
      name: 'Aether Vial',
      type_line: 'Artifact',
      layout: 'normal',
      set_type: 'box',
      promo_types: ['poster'],
      oracle_text: 'At the beginning of your upkeep, you may put a charge counter on this artifact.',
      legalities: {
        modern: 'legal',
        commander: 'legal'
      }
    };

    expect(isStandaloneNonGameplayCard(aetherVialPoster)).toBe(false);
  });

  test('should allow usable gameplay markers with source links or rules text', () => {
    const treasure = {
      name: 'Treasure',
      type_line: 'Token Artifact - Treasure',
      layout: 'token',
      oracle_text: '{T}, Sacrifice this token: Add one mana of any color.',
      legalities: {
        commander: 'not_legal'
      },
      all_parts: [{ component: 'combo_piece', name: 'Dockside Extortionist' }]
    };

    const maxSpeed = {
      name: 'Start Your Engines! // Max Speed',
      type_line: 'Card // Card',
      layout: 'double_faced_token',
      legalities: {
        commander: 'not_legal'
      },
      card_faces: [
        {
          name: 'Start Your Engines!',
          oracle_text: 'Whenever an opponent loses life during your turn, if your speed is 1 or greater, increase your speed by 1.'
        },
        {
          name: 'Max Speed',
          oracle_text: ''
        }
      ],
      all_parts: [{ component: 'combo_piece', name: 'The Speed Demon' }]
    };

    expect(isStandaloneNonGameplayCard(treasure)).toBe(false);
    expect(isStandaloneNonGameplayCard(maxSpeed)).toBe(false);
  });
});
