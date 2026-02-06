# Bug Fix: Multiple Token Printings Spawn

## Issue
When users used the command `scryfall treasure` in Tabletop Simulator, multiple or all printings of Treasure tokens would spawn instead of a single token card.

## Root Cause
The MTG Card Importer Lua script (`MTG-TOOLS/MTG Card Importer.lua`) had special handling for token cards that would automatically search for and spawn ALL unique printings of a token whenever a token card was returned.

### Original Behavior (Lines 1050-1054)
```lua
if obj.object=='card' and obj.type_line and obj.type_line:match('Token') then
  -- Card is a token, find all unique tokens of this type (e.g., all Bird tokens)
  WebRequest.get(BACKEND_URL..'/search?unique=card&q=t:token+'..encodedName,function(wr)
      spawnList(wr,qTbl)end)
  return false
```

When the backend returned a valid token card (like "Dinosaur // Treasure"), the Lua script would:
1. Detect that the card's `type_line` contained "Token"
2. Make an additional search query for ALL unique tokens matching that name
3. Spawn all the results (multiple printings)

This behavior was likely intended for generic queries like "scryfall bird" where users might want to see different bird token variants. However, it was problematic for specific queries like "scryfall treasure" where users expected a single token.

## Fix
Removed the automatic "search for all token variants" behavior when a valid token card is successfully returned from the backend. 

### New Behavior
- When `/card/treasure` returns a valid token card, spawn that single card
- Only fall back to searching for token variants when the card is NOT found (error case)

This maintains the intended functionality for the error case (finding tokens when the exact card doesn't exist) while fixing the issue where valid token lookups would spawn all printings.

## Testing
The backend correctly returns a single token when queried:
```bash
curl "https://api.scryfall.com/cards/named?fuzzy=treasure"
# Returns: "Dinosaur // Treasure" (single double-faced token)
```

With the Lua fix, this single token will now be spawned instead of triggering a search for all Treasure token printings.

## Impact
- **Minimal change**: Removed 5 lines of code that caused unwanted behavior
- **No backend changes needed**: Fix is entirely in the Lua client script
- **Backwards compatible**: Error handling still searches for token variants when card not found
- **User-facing improvement**: Users get the expected single token when using commands like `scryfall treasure`, `scryfall clue`, etc.
