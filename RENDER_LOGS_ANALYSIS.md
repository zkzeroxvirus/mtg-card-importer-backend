# Render Logs Analysis

## Summary

The render logs show the MTG Card Importer Backend handling various `/random` endpoint requests from users. The logs reveal both normal operation and some issues that have been addressed.

## What the Logs Show

### Normal Operation

The logs show the backend successfully handling:
- Single random card requests with various Scryfall search queries
- Bulk random card requests (e.g., count=22, count=11)
- Different search patterns:
  - Color filters: `c=colorless`, `c=blue`, `c=b`, `c=u`, `c=g`
  - Type filters: `t:artifact`, `t:token`, `t:creature`
  - Rarity filters: `rarity:u`, `rarity:c`
  - Color identity: `id:UR`
  - Commander cards: `is:commander game:paper`
  - Complex queries: `c=blue t:artifact CMC<=3`

### Issues Identified

#### 1. Rate Limiting / Timeouts (Most Critical)

**What happened:**
```
2026-01-29T05:10:47.57835136Z GET /random - count: 22, query: "id:UR game:paper"
...
2026-01-29T05:10:58.21727513Z Scryfall API error (undefined), retrying in 500ms (attempt 1/2)
...
2026-01-29T05:11:19.819694098Z Random card 5 failed: timeout of 10000ms exceeded
2026-01-29T05:11:20.472612456Z Random card 18 failed: timeout of 10000ms exceeded
2026-01-29T05:11:20.674619621Z Random card 22 failed: timeout of 10000ms exceeded
```

**Cause:**
When a user requests multiple random cards (count > 1), the backend makes that many sequential API calls to Scryfall's `/cards/random` endpoint. With count=22:
- 22 separate API calls are initiated with 15ms stagger between them
- Each call must wait in the global rate limiting queue (50ms delay between calls)
- Total time: ~22 * 50ms = 1.1 seconds minimum, plus network latency
- Some requests timeout after 10 seconds

**Impact:**
- Some cards fail to fetch within the 10-second timeout
- Users may receive incomplete results (19/22 cards instead of 22/22)

**Mitigation:**
The backend already has several protective measures:
- Request staggering (15ms between initiations)
- Global request queue ensuring Scryfall API compliance
- Retry logic with exponential backoff for transient errors
- Graceful degradation (returns partial results on failure)

#### 2. Error Message Quality (Fixed)

**Before:**
```
Scryfall API error (undefined), retrying in 500ms (attempt 1/2)
```

**Issue:**
When timeouts or network errors occurred, the error status was shown as "undefined" because these errors don't have HTTP status codes.

**After (Fixed):**
```
Scryfall API error (Timeout), retrying in 500ms (attempt 1/3)
```

Now shows:
- "Timeout" for ECONNABORTED errors
- "HTTP 429" or "HTTP 503" for rate limit/server errors
- "Network error" for other network issues
- More detailed error context in logs
- Correct retry attempt counter (1/3, 2/3, 3/3)

#### 3. Log Spam (Fixed)

**Before:**
When fetching 22 cards, you'd see 22 individual log lines:
```
Scryfall API call: https://api.scryfall.com/cards/random?q=id%3AUR%20game%3Apaper
Scryfall API call: https://api.scryfall.com/cards/random?q=id%3AUR%20game%3Apaper
Scryfall API call: https://api.scryfall.com/cards/random?q=id%3AUR%20game%3Apaper
...
```

**After (Fixed):**
```
GET /random - count: 22, query: "id:UR game:paper"
Scryfall API call: https://api.scryfall.com/cards/random?q=id%3AUR%20game%3Apaper
Fetching 21 additional random cards (logs suppressed)...
Bulk random completed: 19/22 cards fetched in 10523ms (3 failed)
```

Much cleaner and more informative!

## Improvements Made

### 1. Better Error Logging
- Error types are now clearly identified (Timeout, HTTP 429, HTTP 503, Network error)
- Timeout errors include the full error message
- Unexpected errors log full context (status, code, message)

### 2. Reduced Log Spam
- Bulk random card requests now suppress individual API call logs
- Summary log shows: total fetched, time taken, failures
- Much easier to diagnose issues without scrolling through hundreds of log lines

### 3. Enhanced Error Context
- All Scryfall errors now include the full URL being called
- Error objects logged with structured data for debugging
- Easier to identify which specific query is causing issues

## Recommendations

### For Users
1. **Limit bulk requests**: Use count <= 15 for best reliability
2. **Be patient**: Large requests (count > 10) may take 10+ seconds
3. **Check results**: Some cards may fail, check the returned count

### For Operators
1. **Monitor timeout patterns**: If timeouts are frequent, consider:
   - Increasing the timeout from 10s to 15s
   - Reducing the maximum allowed count
   - Adding request coalescing for identical queries
2. **Watch for rate limit errors**: If seeing HTTP 429, the 50ms delay may need adjustment
3. **Use bulk data mode**: Enable `USE_BULK_DATA=true` for instant local responses (no API calls)

## Understanding the Logs

### Normal Request Pattern
```
GET /random - count: 1, query: "t:token"
Scryfall API call: https://api.scryfall.com/cards/random?q=t%3Atoken
```
Single card request, completes in ~100-500ms

### Bulk Request Pattern (New)
```
GET /random - count: 22, query: "id:UR game:paper"
Scryfall API call: https://api.scryfall.com/cards/random?q=id%3AUR%20game%3Apaper
Fetching 21 additional random cards (logs suppressed)...
Bulk random completed: 22/22 cards fetched in 1256ms (0 failed)
```
Multiple cards, logs suppressed, summary provided

### Error Pattern
```
GET /random - count: 5, query: "invalid:syntax"
Scryfall API call: https://api.scryfall.com/cards/random?q=invalid%3Asyntax
Scryfall 404: https://api.scryfall.com/cards/random?q=invalid%3Asyntax
Error getting random cards: No random card found with query: invalid:syntax (Scryfall returned 404)
```
Invalid query, error cached to prevent repeated failed requests

### Timeout Pattern
```
Scryfall API error (Timeout), retrying in 500ms (attempt 1/3)
Scryfall API error (Timeout), retrying in 1000ms (attempt 2/3)
Scryfall timeout: https://api.scryfall.com/cards/random?q=... - timeout of 10000ms exceeded
Random card 5 failed: Request timeout (timeout of 10000ms exceeded)
```
Network slow or Scryfall overloaded, request failed after retries

## Deployment Notes

The application successfully deploys and starts:
```
==> Running 'npm start'
MTG Card Importer Backend running on port 3000
Health check: http://localhost:3000/
Bulk data enabled: false
[Init] Using Scryfall API mode
```

Port detection works automatically:
```
==> Detected service running on port 3000
```

The service is live and accessible at the Render URL.
