# Scryfall API Compliance

This document outlines how the MTG Card Importer Backend complies with [Scryfall's API guidelines](https://scryfall.com/docs/api).

## Required Headers

Per Scryfall's requirements (enforced since August 2024), all API requests must include:

### User-Agent Header
- **Requirement**: Must be descriptive and identify your application
- **Our Implementation**: `MTGCardImporterTTS/${version}` where version is dynamically loaded from package.json
- **Location**: 
  - `lib/scryfall.js` line 53-54
  - `lib/bulk-data.js` line 40-42 and 59-61

### Accept Header
- **Requirement**: Must be present
- **Our Implementation**: 
  - `application/json` for API calls
  - `*/*` for bulk data downloads
- **Location**: 
  - `lib/scryfall.js` line 55
  - `lib/bulk-data.js` line 42 and 61

## Rate Limiting

### Requirements
- **50-100ms delay between requests** (average 10 requests per second)
- Respect `Retry-After` header when receiving 429 responses
- Avoid excessive requests that could result in temporary or permanent bans

### Our Implementation

#### Global Request Queue
- **Location**: `lib/scryfall.js` lines 7-46
- All API requests go through a global queue that ensures sequential execution
- Default delay: 100ms (configurable via `SCRYFALL_DELAY` environment variable)
- Queue processes requests one at a time with enforced delays
- Recommended minimum: 100ms (Scryfall suggests 50-100ms between requests)
- Queue throttling is enabled by default regardless of bulk mode (`SCRYFALL_RATE_LIMIT_MODE=always`)
- Optional override: `SCRYFALL_RATE_LIMIT_MODE=never` (not recommended for compliance)

#### Retry Logic with Exponential Backoff
- **Location**: `lib/scryfall.js` lines 64-97
- Automatically retries transient errors (429, 503, timeouts)
- Respects `Retry-After` header from 429 responses
- Exponential backoff: 1s, 2s, 4s for 429 errors
- Maximum 3 retry attempts

#### Critical: All API Calls Must Use globalQueue.wait()

Every function that makes an API call MUST call `await globalQueue.wait()` before the request:

```javascript
async function example() {
  await globalQueue.wait();  // REQUIRED before each API call
  return await withRetry(() => scryfallClient.get('/endpoint'));
}
```

**Important locations where this is enforced:**
- `getCard()` - Line 118
- `getCardById()` - Line 139
- `getCardBySetNumber()` - Line 157
- `searchCards()` - Line 175
- `getRandomCard()` - Line 201
- `getSet()` - Line 228
- `getCardRulings()` - Lines 118 and 399 (two API calls!)
- `getPrintings()` - Line 520

#### Special Cases

**getCardRulings()**: Makes TWO API calls:
1. First call: `getCard()` (already has queue wait)
2. Second call: Fetch rulings (requires its own queue wait at line 399)

## Bulk Data Mode

To reduce API load, the backend supports bulk data mode:

- **Environment Variable**: `USE_BULK_DATA=true`
- **Benefit**: Eliminates most API calls by caching full card database in memory
- **Update Frequency**: Automatic updates every 24 hours
- **Compliance**: 
  - Initial download requests include proper User-Agent headers
  - Download URLs (*.scryfall.io) do not have rate limits per Scryfall docs
  - Still respects 24-hour caching as recommended by Scryfall

## Error Handling

### 404 Not Found
- Returns empty results or descriptive error messages
- Does not retry (not a transient error)

### 429 Too Many Requests
- Automatically retries with exponential backoff
- Respects `Retry-After` header if present
- Logs warnings for monitoring

### 503 Service Unavailable
- Automatically retries with exponential backoff (500ms, 1s, 2s)
- Shorter delays than 429 since it's typically temporary

### Timeouts
- 10-second timeout for regular API requests
- 5-minute timeout for bulk data downloads
- Treated as transient errors and retried

## Data and Image Usage Compliance

Our backend complies with Scryfall's data and image usage policies:

- ✅ Fetches data from Scryfall API with rate limiting
- ✅ Does not paywall Scryfall data
- ✅ Creates additional value (TTS format conversion)
- ✅ Does not repackage/republish raw data
- ✅ Preserves card image integrity (no cropping, distortion, watermarks)
- ✅ Proper attribution via source API

## Testing Rate Limiting

To verify rate limiting is working:

```javascript
const scryfall = require('./lib/scryfall');

async function test() {
  const times = [];
  for (let i = 0; i < 3; i++) {
    const start = Date.now();
    await scryfall.globalQueue.wait();
    times.push(Date.now() - start);
  }
  console.log('Delays (ms):', times);
  // First: ~0ms, subsequent: ~50ms
}
```

## Configuration

Environment variables for API compliance:

- `SCRYFALL_DELAY`: Milliseconds between requests (default: 100, recommended minimum: 100)
- `SCRYFALL_RATE_LIMIT_MODE`: Queue mode (`always` default; `never` disables queue and may violate Scryfall guidance)
- `USE_BULK_DATA`: Enable bulk data mode to reduce API calls (default: true)
- `BULK_DATA_PATH`: Where to store bulk data files (default: ./data)

## Monitoring

Watch for these log messages indicating rate limiting issues:

```
Scryfall API error (429), retrying in XXXms (attempt X/X)
```

If you see frequent 429 errors, consider:
1. Increasing `SCRYFALL_DELAY` to 150ms or higher
2. Enabling bulk data mode (`USE_BULK_DATA=true`)
3. Implementing additional caching at the application level
4. Reducing the number of parallel requests in bulk operations

## Version History

- **v0.1.0**: Initial implementation with rate limiting
  - Added global request queue
  - Implemented retry logic with exponential backoff
  - Added User-Agent and Accept headers
  - Fixed missing queue waits in getCardRulings()
  - Updated axios to 1.13.4 for security fixes
