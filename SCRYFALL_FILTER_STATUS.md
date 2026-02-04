# Scryfall Filter Implementation Status

This document provides a comprehensive overview of which Scryfall API filters are implemented in the bulk data query parser.

## ✅ Fully Implemented Filters (53 total)

### Basic Card Properties
- `set:` / `s:` / `se:` - Filter by set code
- `set:(...)` - OR syntax for multiple sets
- `rarity:` / `r:` - Filter by rarity (common, uncommon, rare, mythic)
  - Supports comparison: `r>=rare`, `r>common`, `r<rare`
- `type:` / `t:` - Filter by card type (also supports `-t:` for exclusion)
- `border:` - Filter by border color (black, white, borderless, silver, gold)

### Colors & Color Identity
- `color:` / `c:` - Filter by mana color
  - Operators: `:`, `=`, `<`, `>`, `<=`, `>=`, `!=`
  - Supports color count: `c=2`, `c>=3`
  - Supports color names: `white`, `blue`, `black`, `red`, `green`
  - Supports guild/shard names: `azorius`, `dimir`, `bant`, `esper`, etc.
- `identity:` / `id:` - Filter by color identity
  - Same operators as color
  - Useful for Commander deck building
- `produces:` - Filter by mana colors produced

### Numeric Properties
- `manavalue:` / `mv:` / `cmc:` - Converted mana cost
  - Operators: `=`, `<`, `>`, `<=`, `>=`
- `power:` / `pow:` - Creature power
  - Operators: `=`, `<`, `>`, `<=`, `>=`
- `toughness:` / `tou:` / `toughness:` - Creature toughness
  - Operators: `=`, `<`, `>`, `<=`, `>=`
- `loyalty:` / `loy:` / `loyalty:` - Planeswalker loyalty
  - Operators: `=`, `<`, `>`, `<=`, `>=`

### Text & Abilities
- `oracle:` / `o:` - Search oracle text
- `keyword:` - Search for specific keywords (also supports `-keyword:` for exclusion)
- `flavor:` / `ft:` - Search flavor text
- `name:` - Search card name (supports quoted strings)
- `artist:` / `a:` - Search artist name (supports quoted strings)

### Card Properties
- `watermark:` / `wm:` - Filter by watermark (also supports `-wm:` for exclusion)
- `frame:` - Filter by frame year (also supports `-frame:` for exclusion)
- `year:` - Filter by release year
  - Operators: `=`, `<`, `>`, `>=`

### Format Legality (NEW)
- `legal:` - Filter cards legal in a format
  - Examples: `legal:commander`, `legal:modern`, `legal:standard`
- `banned:` - Filter cards banned in a format
  - Examples: `banned:modern`, `banned:legacy`
- `restricted:` - Filter cards restricted in a format
  - Examples: `restricted:vintage`

### Layout (NEW)
- `layout:` - Filter by card layout type
  - Examples: `layout:normal`, `layout:transform`, `layout:split`
- `-layout:` - Exclude specific layout types

### Price Filters
- `usd:` - USD price filter
  - Operators: `=`, `<`, `>`, `<=`, `>=`
- `eur:` - EUR price filter
  - Operators: `=`, `<`, `>`, `<=`, `>=`
- `tix:` - MTGO ticket price filter
  - Operators: `=`, `<`, `>`, `<=`, `>=`

### Game & Availability
- `game:` - Filter by game availability (paper, arena, mtgo)
- `lang:` / `language:` - Filter by language (default: en)

### Card Status Filters (is:)
- `is:spell` - Instant or sorcery
- `is:permanent` - Non-instant/sorcery
- `is:transform` - Transform/DFC cards (also `-is:transform`)
- `is:booster` - Available in boosters
- `is:historic` - Historic (legendary, artifact, or saga)
- `is:commander` - Legal as commander
- `is:companion` - Has companion ability
- `is:reprint` - Reprinted card
- `is:new` - First printing
- `is:paper` - Available in paper
- `is:digital` - Digital-only
- `is:promo` - Promotional printing
- `is:funny` - Un-set or funny card
- `is:full-art` - Full-art card
- `is:extended-art` - Extended-art frame
- `is:vanilla` - No rules text

## ⚠️ Partially Implemented

### Format Filter
- `format:standard` - Only standard format is implemented
- Missing: Other format shorthands

## ❌ Not Yet Implemented

### High Priority (Common Queries)
- `m:` / `mana:` - Mana symbol search (e.g., `m:{2}{U}{U}`)
- `has:` - Feature detection
  - `has:watermark`, `has:partner`, `has:companion`, etc.
- `block:` - Block name search
- `fo:` / `fulloracle:` - Full oracle text including reminder text
- `prints:` - Number of printings
  - Examples: `prints>10`, `prints=1`

### Medium Priority (Less Common)
- `stamp:` - Security stamp type (oval, acorn, triangle)
- `frameeffect:` - Frame effects (showcase, extendedart, etc.)
- `is:reserved` - Reserved list cards
- `is:spotlight` - Story spotlight cards
- `is:fetchland`, `is:shockland` - Land type shortcuts
- `is:modal` - Modal cards
- `unique:` - Uniqueness parameter (not a filter)
- `prefer:` - Preference parameter (not a filter)

### Low Priority (Edge Cases)
- `manavalue:odd` / `manavalue:even` - Odd/even CMC
- `power:*` / `toughness:*` - Variable stats
- `tagged:` - User tags (Scryfall-specific)
- `cube:` - Cube availability
- `date:` - Specific date filters
- `firstprint:` - First printing date
- `is:permanent` subtypes (is:land, is:enchantment, etc.)

## Query Syntax Support

### ✅ Supported Operators
- Comparison: `=`, `<`, `>`, `<=`, `>=`, `!=`
- Negation: `-` prefix (e.g., `-t:creature`, `-layout:transform`)
- OR syntax: `(set:xxx or set:yyy)` for sets
- Quoted strings: `artist:"Rebecca Guay"`, `o:"draw a card"`
- Color operations: `contains`, `subset`, `exact`, `strict-subset`

### ❌ Not Supported
- `or` operator (except for set filters)
- Regular expressions
- Parenthetical grouping (except for OR sets)
- `AND` operator (implicit only)

## Usage Examples

### Working Queries
```
# Format legality
legal:commander t:creature
banned:modern
restricted:vintage

# Layout filters
layout:transform
-layout:normal

# Price filters
usd>=50 t:artifact
eur<10 r:rare

# Combined filters
legal:commander id<=rug mv<=3 t:creature
layout:normal usd<5 legal:pauper
```

## Testing Coverage

All implemented filters have comprehensive test coverage:
- Unit tests for parsing logic
- Integration tests for filtering behavior
- Edge case handling
- Case insensitivity verification

## Future Enhancements

Priority order for additional implementations:
1. **Mana symbol search** (`mana:`) - High user demand
2. **Feature detection** (`has:`) - Versatile filter
3. **Block filter** (`block:`) - Historical searches
4. **Full oracle search** (`fo:`) - Advanced text queries
5. **Frame effects** (`frameeffect:`) - Visual preferences

## Performance Considerations

- All filters work with local bulk data (fast)
- Fallback to Scryfall API when bulk data unavailable
- Price filters require cards with price data
- Format legality requires `legalities` field in card data
- Layout filter requires `layout` field in card data

## Compliance

This implementation follows Scryfall API syntax where possible:
- Case-insensitive matching
- Multiple aliases for filters (e.g., `t:` vs `type:`)
- Operator consistency
- Error handling for malformed queries

Last Updated: 2026-02-04
