# Deck URL Fetching Feature

## Overview

The MTG Card Importer Backend now supports fetching decks directly from popular deck-building platforms via the `/fetch-deck` endpoint. This feature allows users to import entire decklists by simply providing a URL, making it easier to quickly spawn decks in Tabletop Simulator.

## Architectural Decision

**Decision**: Implement deck URL fetching in the **backend** (not in the Lua importer script).

**Rationale**:
1. **Consistency**: Aligns with current architecture where the backend acts as middleware between Scryfall and TTS
2. **Maintainability**: Platform API changes only need fixing in one place (the backend)
3. **Performance**: Backend can cache fetched decks, implement rate limiting, and optimize for Scryfall compliance
4. **Simplicity**: Keeps the Lua script simple and focused on TTS integration
5. **Security**: Backend can validate and sanitize deck data before processing
6. **Reusability**: Multiple clients (current importer, future tools) can use the same endpoint

## Supported Platforms

### 1. Moxfield
- **URL Format**: `https://www.moxfield.com/decks/{deck-id}`
- **API Endpoint**: `https://api.moxfield.com/v2/decks/all/{deck-id}`
- **Format**: JSON with `mainboard`, `commanders`, and `companions` sections
- **Requirements**: Deck must be public
- **Example**: `https://www.moxfield.com/decks/vKTTXm_qPkyJ-JEdSDH_0g`

### 2. Archidekt
- **URL Format**: `https://archidekt.com/decks/{deck-id}`
- **API Endpoint**: `https://archidekt.com/api/decks/{deck-id}/`
- **Format**: JSON with `cards` array
- **Requirements**: Deck must be public
- **Example**: `https://archidekt.com/decks/12345`
- **Note**: Automatically excludes sideboard and maybeboard cards

### 3. TappedOut
- **URL Format**: `https://tappedout.net/mtg-decks/{deck-slug}/`
- **Export Format**: Plain text via `?fmt=txt` parameter
- **Requirements**: Deck must be public
- **Example**: `https://tappedout.net/mtg-decks/my-commander-deck/`
- **Note**: Uses text export, not JSON API

### 4. Scryfall
- **URL Format**: `https://scryfall.com/@{username}/decks/{deck-id}`
- **API Endpoint**: `https://api.scryfall.com/decks/{deck-id}/export/text`
- **Format**: Plain text decklist
- **Requirements**: Deck must be public
- **Example**: `https://scryfall.com/@username/decks/abc123`

## API Usage

### Endpoint: POST /fetch-deck

**Request Body (JSON)**:
```json
{
  "url": "https://www.moxfield.com/decks/{deck-id}",
  "back": "https://steamusercontent-a.akamaihd.net/ugc/.../card-back.jpg" // optional
}
```

**Request Body (Plain Text)**:
```
https://www.moxfield.com/decks/{deck-id}
```

**Response**: NDJSON (newline-delimited JSON) - one TTS card object per line

**Status Codes**:
- `200`: Success - returns NDJSON stream of cards
- `400`: Bad request (invalid URL, unsupported platform, etc.)
- `403`: Deck is private or access denied
- `404`: Deck not found
- `502`: Failed to fetch from external platform

**Example using curl**:
```bash
curl -X POST http://localhost:3000/fetch-deck \
  -H "Content-Type: application/json" \
  -d '{"url":"https://www.moxfield.com/decks/abc123"}'
```

## Lua Importer Integration

The `EXAMPLE MTG Card Importer.lua` script now supports deck URLs:

### Usage Examples

**Direct URL paste**:
```
sf https://www.moxfield.com/decks/abc123
sf https://archidekt.com/decks/12345
sf https://tappedout.net/mtg-decks/my-deck/
sf https://scryfall.com/@username/decks/xyz789
```

**Explicit deck command**:
```
sf deck https://www.moxfield.com/decks/abc123
sf url https://archidekt.com/decks/12345
```

**How it works**:
1. User types a command with a deck URL in TTS chat
2. Lua script detects the URL pattern (checks for supported platforms)
3. Lua script sends POST request to `/fetch-deck` endpoint with the URL
4. Backend fetches the decklist from the platform
5. Backend converts each card to TTS format via Scryfall API
6. Backend returns NDJSON stream of card objects
7. Lua script spawns each card in the player's hand zone

## Implementation Details

### Platform Detection
The backend automatically detects the platform based on the hostname in the URL:
- `moxfield.com` → Moxfield
- `archidekt.com` → Archidekt
- `tappedout.net` → TappedOut
- `scryfall.com` (with `/decks/` in path) → Scryfall

### Deck ID Extraction
Each platform has a different URL structure, so the backend extracts the deck ID accordingly:
- **Moxfield**: `/decks/([a-zA-Z0-9_-]+)`
- **Archidekt**: `/decks/(\d+)`
- **TappedOut**: `/mtg-decks/([a-zA-Z0-9_-]+)`
- **Scryfall**: `/@[^/]+/decks/([a-zA-Z0-9-]+)`

### Security Features
1. **URL Validation**: Ensures provided URL is valid and from a supported platform
2. **Card Back Validation**: Only allows card backs from trusted domains (Steam CDN, Imgur)
3. **Deck Size Limit**: Maximum 500 cards to prevent API abuse (configurable via `MAX_DECK_SIZE`)
4. **Request Size Limit**: Maximum 10KB request body
5. **Error Handling**: Gracefully handles private decks, network errors, and invalid data

## Error Handling

### Common Errors

**Invalid URL format**:
```json
{"error": "Invalid URL format"}
```

**Unsupported platform**:
```json
{"error": "Unsupported deck platform. Supported: Moxfield, Archidekt, TappedOut, Scryfall"}
```

**Deck not found or private**:
```json
{"error": "Deck not found or is private"}
```

**Failed to fetch**:
```json
{"error": "Failed to fetch deck from moxfield: <reason>"}
```

### Troubleshooting

1. **"Deck not found or is private"**: Ensure the deck is set to public on the platform
2. **"Invalid URL format"**: Check that the URL is complete and properly formatted
3. **"Unsupported deck platform"**: Verify the URL is from Moxfield, Archidekt, TappedOut, or Scryfall
4. **No cards spawned**: The deck might be empty or contain invalid card names

## Testing

### Manual Testing

Since the sandboxed environment doesn't have external network access, manual testing with real deck URLs requires a deployed instance:

1. **Deploy to Render/Heroku**: Follow deployment instructions in README.md
2. **Test with public decks**: Use known public decks from each platform
3. **Verify card counts**: Compare spawned cards against deck list on platform
4. **Test error cases**: Try private decks, invalid URLs, non-existent decks

### Example Test Cases

```bash
# Test Moxfield (replace with actual public deck)
curl -X POST https://your-backend.com/fetch-deck \
  -H "Content-Type: application/json" \
  -d '{"url":"https://www.moxfield.com/decks/vKTTXm_qPkyJ-JEdSDH_0g"}'

# Test Archidekt
curl -X POST https://your-backend.com/fetch-deck \
  -H "Content-Type: application/json" \
  -d '{"url":"https://archidekt.com/decks/12345"}'

# Test invalid URL
curl -X POST https://your-backend.com/fetch-deck \
  -H "Content-Type: application/json" \
  -d '{"url":"not-a-url"}'

# Test unsupported platform
curl -X POST https://your-backend.com/fetch-deck \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/decks/123"}'
```

## Performance Considerations

1. **Rate Limiting**: Each card in the deck requires a Scryfall API call
   - Respect Scryfall's rate limits (50-100ms between requests)
   - Large decks (100+ cards) may take 5-10 seconds to process
   
2. **Caching Opportunities** (Future Enhancement):
   - Cache fetched decklists for 5-10 minutes
   - Cache individual Scryfall card lookups (already implemented in bulk mode)
   
3. **Parallel Processing** (Future Enhancement):
   - Could batch Scryfall requests to speed up large decks
   - Must still respect rate limits

## Future Enhancements

1. **Additional Platforms**:
   - Deckbox
   - MTGGoldfish
   - TCGPlayer Deck Builder
   
2. **Sideboard Support**:
   - Optional parameter to include sideboard cards
   - Spawn sideboard in a separate zone
   
3. **Commander Zone**:
   - Detect commander cards and spawn in commander zone
   - Handle partner commanders
   
4. **Deck Caching**:
   - Cache fetched decklists to reduce external API calls
   - Invalidate cache after configurable TTL
   
5. **Batch Import**:
   - Support importing multiple decks at once
   - Queue system for large imports

## Compliance

This feature maintains full compliance with Scryfall's API guidelines:
- Rate limiting enforced (50-100ms between card fetches)
- Proper User-Agent headers
- Retry logic with backoff
- Creates additional value through TTS format conversion

External platforms (Moxfield, Archidekt, etc.) are accessed via their public endpoints:
- Respects platform-specific rate limits
- Only fetches public decks
- No authentication or private data access
- Minimal load (one request per deck import)
