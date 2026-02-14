# Scryfall Filter Implementation Status

This document provides a comprehensive overview of which Scryfall API filters are implemented in the bulk data query parser.

## ✅ Fully Implemented Filters (75+ total)

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
  - Operators: `:`, `=`, `<`, `>`, `<=`, `>=`
  - **NEW:** Supports `mv:odd` and `mv:even` for odd/even CMC
- `power:` / `pow:` - Creature power
  - Operators: `:`, `=`, `<`, `>`, `<=`, `>=`
  - **FIXED:** All operators now work correctly (previously `:` and `=` were not parsing)
- `toughness:` / `tou:` - Creature toughness
  - Operators: `:`, `=`, `<`, `>`, `<=`, `>=`
  - **FIXED:** All operators now work correctly (previously `:` and `=` were not parsing)
- `loyalty:` / `loy:` - Planeswalker loyalty
  - Operators: `:`, `=`, `<`, `>`, `<=`, `>=`
  - **FIXED:** All operators now work correctly (previously `:` and `=` were not parsing)

### Text & Abilities
- `oracle:` / `o:` - Search oracle text
- `keyword:` - Search for specific keywords (also supports `-keyword:` for exclusion)
- `flavor:` / `ft:` - Search flavor text
- `name:` - Search card name (supports quoted strings)
- `artist:` / `a:` - Search artist name (supports quoted strings)
- **NEW:** `fo:` / `fulloracle:` - Full oracle text including reminder text

### Mana & Symbols (NEW)
- `m:` / `mana:` - Mana symbol search
  - Examples: `m:{2}{U}{U}`, `m:{R}{R}`
  - Search for specific mana costs

### Feature Detection (NEW)
- `has:watermark` - Cards with watermarks
- `has:partner` - Cards with Partner ability
- `has:companion` - Cards with Companion ability

### Card Properties
- `watermark:` / `wm:` - Filter by watermark (also supports `-wm:` for exclusion)
- `frame:` - Filter by frame year (also supports `-frame:` for exclusion)
- `year:` - Filter by release year
  - Operators: `=`, `<`, `>`, `>=`
- **NEW:** `stamp:` - Security stamp type (oval, acorn, triangle)
- **NEW:** `frameeffect:` - Frame effects (showcase, extendedart, etc.)
- **NEW:** `block:` - Block name search (searches in set_name field)

### Format Legality
- `legal:` - Filter cards legal in a format
  - Examples: `legal:commander`, `legal:modern`, `legal:standard`
- `banned:` - Filter cards banned in a format
  - Examples: `banned:modern`, `banned:legacy`
- `restricted:` - Filter cards restricted in a format
  - Examples: `restricted:vintage`

### Layout
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
- **Requires** `BULK_DATA_TYPE=default_cards` (price fields are not present in `oracle_cards`) or API mode.

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
- **NEW:** `is:reserved` - Reserved list cards
- **NEW:** `is:spotlight` - Story spotlight cards
- **NEW:** `is:fetchland` - Fetchland cards (searches library for lands)
- **NEW:** `is:shockland` - Shockland cards (2 life payment on ETB)
- **NEW:** `is:modal` - Modal cards (choose one or more)

## ⚠️ Partially Implemented

### Printings Filter
- `prints:` - Number of printings
  - **LIMITED:** Only approximates based on reprint status
  - Note: Bulk data doesn't include full printing count
  - Treats reprints as 2+ and new cards as 1

### Format Filter
- `format:standard` - Only standard format is implemented
- Missing: Other format shorthands

## ❌ Not Yet Implemented

### Low Priority (Edge Cases)
- `power:*` / `toughness:*` - Variable stats (cards with * in power/toughness)
- `tagged:` - User tags (Scryfall-specific, not available in bulk data)
- `cube:` - Cube availability (Scryfall-specific)
- `date:` - Specific date filters (more granular than year:)
- `firstprint:` - First printing date
- `is:permanent` subtypes (is:land, is:enchantment, etc.)
- `unique:` - Uniqueness parameter (not a filter, sorting parameter)
- `prefer:` - Preference parameter (not a filter, sorting parameter)

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

# Mana symbol search (NEW)
m:{2}{U}{U}
m:{R}{R}

# Feature detection (NEW)
has:watermark t:artifact
has:partner
has:companion

# Land type shortcuts (NEW)
is:fetchland
is:shockland

# Security and frame effects (NEW)
stamp:oval
frameeffect:showcase

# Odd/even CMC (NEW)
mv:odd t:creature
mv:even t:instant

# Combined filters
legal:commander id<=rug mv<=3 t:creature
layout:normal usd<5 legal:pauper
is:reserved usd>=100
```

## Testing Coverage

All implemented filters have comprehensive test coverage:
- Unit tests for parsing logic
- Integration tests for filtering behavior
- Edge case handling
- Case insensitivity verification
- New filters tested in `__tests__/new-filters.test.js`

## Future Enhancements

Priority order for remaining implementations:
1. **Variable stats** (`power:*`, `toughness:*`) - Edge case for special cards
2. **More granular date filters** (`date:`, `firstprint:`) - Advanced historical queries
3. **Permanent subtypes** (`is:land`, `is:enchantment`, etc.) - Type shortcuts

Note: Many high-priority filters have been implemented in this update.

## Performance Considerations

- All filters work with local bulk data (fast)
- Fallback to Scryfall API when bulk data unavailable
- Price filters require cards with price data
- Format legality requires `legalities` field in card data
- Layout filter requires `layout` field in card data
- Mana symbol search performs substring matching on mana_cost field
- Feature detection (has:) checks keywords and oracle text
- Land type shortcuts (fetchland/shockland) use heuristics for identification

## Compliance

This implementation follows Scryfall API syntax where possible:
- Case-insensitive matching
- Multiple aliases for filters (e.g., `t:` vs `type:`, `m:` vs `mana:`)
- Operator consistency
- Error handling for malformed queries

## Implementation Notes

### Prints Filter Limitation
The `prints:` filter is partially implemented due to bulk data limitations. The oracle_cards bulk data doesn't include the full printing count for each card. The current implementation:
- Treats `reprint: true` cards as having 2+ printings
- Treats `reprint: false` cards as having 1 printing
- This is a rough approximation and may not be accurate for all queries

For accurate printing counts, consider using the Scryfall API's /cards/search endpoint directly.

### Block Filter
The `block:` filter searches the `set_name` field since block information isn't explicitly provided in bulk data. This works for most cases but may not be as precise as Scryfall's native block data.

### Land Type Shortcuts
The `is:fetchland` and `is:shockland` filters use heuristics based on:
- Card type line (must be Land)
- Oracle text patterns (e.g., "search your library" for fetchlands, "2 life" for shocklands)
- Known card names from popular cycles

This approach captures most common cases but may miss edge cases or non-standard lands.

## Recent Fixes

### Power/Toughness/Loyalty Filter Operators (2026-02-14)
Fixed a bug where the `:` and `=` operators were not working for power, toughness, and loyalty filters. The issue was in the regex patterns which used incorrect optional quantifiers:
- **Problem**: `/pow(er)?>=?(\d+)/i` only matched when `>` was present
- **Impact**: Queries like `pow:3`, `power=4`, `tou:5`, `loyalty:3` were not parsing correctly
- **Solution**: Restructured regex patterns to check each operator separately in priority order
- **Status**: All operators (`:`, `=`, `<`, `>`, `<=`, `>=`) now work correctly for power, toughness, and loyalty filters

Last Updated: 2026-02-14
