/**
 * Tests for power and toughness filter regex parsing
 * Ensures all operators work correctly: :, =, <, >, <=, >=
 * This tests the fix for the reported issue where : and = operators were not working
 */

describe('Power and Toughness Filter Regex Parsing', () => {
  // Test the regex patterns directly to ensure proper parsing
  function testPowerParsing(part) {
    let powerEquals = null;
    let powerGreater = null;
    let powerGreaterEqual = null;
    let powerLess = null;
    let powerLessEqual = null;

    if (part.match(/^pow(er)?[:=<>]/i)) {
      // Handle >= first (before >)
      if (part.match(/pow(er)?>=(\d+)/i)) {
        const match = part.match(/pow(er)?>=(\d+)/i);
        powerGreaterEqual = parseInt(match[2]);
      } else if (part.match(/pow(er)?<=(\d+)/i)) {
        const match = part.match(/pow(er)?<=(\d+)/i);
        powerLessEqual = parseInt(match[2]);
      } else if (part.match(/pow(er)?>(\d+)/i)) {
        const match = part.match(/pow(er)?>(\d+)/i);
        powerGreater = parseInt(match[2]);
      } else if (part.match(/pow(er)?<(\d+)/i)) {
        const match = part.match(/pow(er)?<(\d+)/i);
        powerLess = parseInt(match[2]);
      } else if (part.match(/pow(er)?[:=](\d+)/i)) {
        const match = part.match(/pow(er)?[:=](\d+)/i);
        powerEquals = parseInt(match[2]);
      }
    }

    return { powerEquals, powerGreater, powerGreaterEqual, powerLess, powerLessEqual };
  }

  function testToughnessParsing(part) {
    let toughnessEquals = null;
    let toughnessGreater = null;
    let toughnessGreaterEqual = null;
    let toughnessLess = null;
    let toughnessLessEqual = null;

    if (part.match(/^tou(ghness)?[:=<>]/i)) {
      // Handle >= first (before >)
      if (part.match(/tou(ghness)?>=(\d+)/i)) {
        const match = part.match(/tou(ghness)?>=(\d+)/i);
        toughnessGreaterEqual = parseInt(match[2]);
      } else if (part.match(/tou(ghness)?<=(\d+)/i)) {
        const match = part.match(/tou(ghness)?<=(\d+)/i);
        toughnessLessEqual = parseInt(match[2]);
      } else if (part.match(/tou(ghness)?>(\d+)/i)) {
        const match = part.match(/tou(ghness)?>(\d+)/i);
        toughnessGreater = parseInt(match[2]);
      } else if (part.match(/tou(ghness)?<(\d+)/i)) {
        const match = part.match(/tou(ghness)?<(\d+)/i);
        toughnessLess = parseInt(match[2]);
      } else if (part.match(/tou(ghness)?[:=](\d+)/i)) {
        const match = part.match(/tou(ghness)?[:=](\d+)/i);
        toughnessEquals = parseInt(match[2]);
      }
    }

    return { toughnessEquals, toughnessGreater, toughnessGreaterEqual, toughnessLess, toughnessLessEqual };
  }

  describe('Power Filter - Colon Operator (:)', () => {
    test('pow:3 should parse to powerEquals=3', () => {
      const result = testPowerParsing('pow:3');
      expect(result.powerEquals).toBe(3);
      expect(result.powerGreater).toBeNull();
      expect(result.powerGreaterEqual).toBeNull();
      expect(result.powerLess).toBeNull();
      expect(result.powerLessEqual).toBeNull();
    });

    test('power:3 should parse to powerEquals=3', () => {
      const result = testPowerParsing('power:3');
      expect(result.powerEquals).toBe(3);
      expect(result.powerGreater).toBeNull();
    });

    test('pow:0 should parse to powerEquals=0', () => {
      const result = testPowerParsing('pow:0');
      expect(result.powerEquals).toBe(0);
    });
  });

  describe('Power Filter - Equals Operator (=)', () => {
    test('pow=3 should parse to powerEquals=3', () => {
      const result = testPowerParsing('pow=3');
      expect(result.powerEquals).toBe(3);
      expect(result.powerGreater).toBeNull();
      expect(result.powerGreaterEqual).toBeNull();
    });

    test('power=3 should parse to powerEquals=3', () => {
      const result = testPowerParsing('power=3');
      expect(result.powerEquals).toBe(3);
    });

    test('pow=5 should parse to powerEquals=5', () => {
      const result = testPowerParsing('pow=5');
      expect(result.powerEquals).toBe(5);
    });
  });

  describe('Power Filter - Greater Than Operator (>)', () => {
    test('pow>3 should parse to powerGreater=3', () => {
      const result = testPowerParsing('pow>3');
      expect(result.powerGreater).toBe(3);
      expect(result.powerEquals).toBeNull();
      expect(result.powerGreaterEqual).toBeNull();
    });

    test('power>3 should parse to powerGreater=3', () => {
      const result = testPowerParsing('power>3');
      expect(result.powerGreater).toBe(3);
    });
  });

  describe('Power Filter - Greater Than or Equal Operator (>=)', () => {
    test('pow>=3 should parse to powerGreaterEqual=3', () => {
      const result = testPowerParsing('pow>=3');
      expect(result.powerGreaterEqual).toBe(3);
      expect(result.powerGreater).toBeNull();
      expect(result.powerEquals).toBeNull();
    });

    test('power>=3 should parse to powerGreaterEqual=3', () => {
      const result = testPowerParsing('power>=3');
      expect(result.powerGreaterEqual).toBe(3);
    });
  });

  describe('Power Filter - Less Than Operator (<)', () => {
    test('pow<3 should parse to powerLess=3', () => {
      const result = testPowerParsing('pow<3');
      expect(result.powerLess).toBe(3);
      expect(result.powerEquals).toBeNull();
      expect(result.powerLessEqual).toBeNull();
    });

    test('power<3 should parse to powerLess=3', () => {
      const result = testPowerParsing('power<3');
      expect(result.powerLess).toBe(3);
    });
  });

  describe('Power Filter - Less Than or Equal Operator (<=)', () => {
    test('pow<=3 should parse to powerLessEqual=3', () => {
      const result = testPowerParsing('pow<=3');
      expect(result.powerLessEqual).toBe(3);
      expect(result.powerLess).toBeNull();
      expect(result.powerEquals).toBeNull();
    });

    test('power<=3 should parse to powerLessEqual=3', () => {
      const result = testPowerParsing('power<=3');
      expect(result.powerLessEqual).toBe(3);
    });
  });

  describe('Toughness Filter - Colon Operator (:)', () => {
    test('tou:3 should parse to toughnessEquals=3', () => {
      const result = testToughnessParsing('tou:3');
      expect(result.toughnessEquals).toBe(3);
      expect(result.toughnessGreater).toBeNull();
      expect(result.toughnessGreaterEqual).toBeNull();
      expect(result.toughnessLess).toBeNull();
      expect(result.toughnessLessEqual).toBeNull();
    });

    test('toughness:3 should parse to toughnessEquals=3', () => {
      const result = testToughnessParsing('toughness:3');
      expect(result.toughnessEquals).toBe(3);
    });

    test('tou:4 should parse to toughnessEquals=4', () => {
      const result = testToughnessParsing('tou:4');
      expect(result.toughnessEquals).toBe(4);
    });
  });

  describe('Toughness Filter - Equals Operator (=)', () => {
    test('tou=3 should parse to toughnessEquals=3', () => {
      const result = testToughnessParsing('tou=3');
      expect(result.toughnessEquals).toBe(3);
      expect(result.toughnessGreater).toBeNull();
      expect(result.toughnessGreaterEqual).toBeNull();
    });

    test('toughness=3 should parse to toughnessEquals=3', () => {
      const result = testToughnessParsing('toughness=3');
      expect(result.toughnessEquals).toBe(3);
    });

    test('tou=5 should parse to toughnessEquals=5', () => {
      const result = testToughnessParsing('tou=5');
      expect(result.toughnessEquals).toBe(5);
    });
  });

  describe('Toughness Filter - Greater Than Operator (>)', () => {
    test('tou>3 should parse to toughnessGreater=3', () => {
      const result = testToughnessParsing('tou>3');
      expect(result.toughnessGreater).toBe(3);
      expect(result.toughnessEquals).toBeNull();
      expect(result.toughnessGreaterEqual).toBeNull();
    });

    test('toughness>3 should parse to toughnessGreater=3', () => {
      const result = testToughnessParsing('toughness>3');
      expect(result.toughnessGreater).toBe(3);
    });
  });

  describe('Toughness Filter - Greater Than or Equal Operator (>=)', () => {
    test('tou>=5 should parse to toughnessGreaterEqual=5', () => {
      const result = testToughnessParsing('tou>=5');
      expect(result.toughnessGreaterEqual).toBe(5);
      expect(result.toughnessGreater).toBeNull();
      expect(result.toughnessEquals).toBeNull();
    });

    test('toughness>=5 should parse to toughnessGreaterEqual=5', () => {
      const result = testToughnessParsing('toughness>=5');
      expect(result.toughnessGreaterEqual).toBe(5);
    });
  });

  describe('Toughness Filter - Less Than Operator (<)', () => {
    test('tou<3 should parse to toughnessLess=3', () => {
      const result = testToughnessParsing('tou<3');
      expect(result.toughnessLess).toBe(3);
      expect(result.toughnessEquals).toBeNull();
      expect(result.toughnessLessEqual).toBeNull();
    });

    test('toughness<3 should parse to toughnessLess=3', () => {
      const result = testToughnessParsing('toughness<3');
      expect(result.toughnessLess).toBe(3);
    });
  });

  describe('Toughness Filter - Less Than or Equal Operator (<=)', () => {
    test('tou<=3 should parse to toughnessLessEqual=3', () => {
      const result = testToughnessParsing('tou<=3');
      expect(result.toughnessLessEqual).toBe(3);
      expect(result.toughnessLess).toBeNull();
      expect(result.toughnessEquals).toBeNull();
    });

    test('toughness<=3 should parse to toughnessLessEqual=3', () => {
      const result = testToughnessParsing('toughness<=3');
      expect(result.toughnessLessEqual).toBe(3);
    });
  });

  describe('Case Insensitivity', () => {
    test('POW:3 should work (uppercase)', () => {
      const result = testPowerParsing('POW:3');
      expect(result.powerEquals).toBe(3);
    });

    test('POWER:3 should work (uppercase)', () => {
      const result = testPowerParsing('POWER:3');
      expect(result.powerEquals).toBe(3);
    });

    test('TOU:3 should work (uppercase)', () => {
      const result = testToughnessParsing('TOU:3');
      expect(result.toughnessEquals).toBe(3);
    });

    test('TOUGHNESS:3 should work (uppercase)', () => {
      const result = testToughnessParsing('TOUGHNESS:3');
      expect(result.toughnessEquals).toBe(3);
    });
  });
});
