# MTG Card Importer Backend

Node.js + Express backend that proxies Scryfall to produce Tabletop Simulator-compatible card objects.

## Endpoints
- `GET /` — Health check
- `GET /card/:name` — Fetch single card by name (optional `?set=ABC`)
- `POST /deck` — Build deck from decklist text (NDJSON output)
- `POST /build` — Build deck from decklist text with hand position (NDJSON output) - **Use this for TTS spawning**
- `GET /random` — Fetch `count` random cards (optional `?q=` filter)
- `GET /search` — Search Scryfall with Scryfall query syntax (`?q=`)
- `GET /rulings/:cardId` — Get card rulings by card ID

## Quick Start (Windows PowerShell)

```powershell
# Set up env
Copy-Item .env.example .env

# Install deps
npm install

# Run dev
npm run dev

# Or run
npm start
```

## Request/Response Formats

### POST /build (for TTS spawning)
```json
{
  "data": "2 Black Lotus\n4 Mountain\n1 Sol Ring",
  "back": "https://...",  // optional card back URL
  "hand": {...}  // hand transform position (optional)
}
```

Response: NDJSON (one TTS card object per line)

### POST /deck
```json
{
  "decklist": "2 Black Lotus\n4 Mountain",
  "back": "https://...",  // optional card back URL
}
```

Response: NDJSON (one TTS card object per line)

## Render Deployment
- Uses `render.yaml` for auto-deploy to Render
- Free plan supported; expect cold starts after idle periods
- Set `DEFAULT_CARD_BACK` environment variable for card back URL

## Environment Variables
- `NODE_ENV` — `development` or `production`
- `PORT` — Server port (default: 3000)
- `SCRYFALL_DELAY` — Rate limit delay in ms (default: 100, respects Scryfall guidelines)
- `DEFAULT_CARD_BACK` — Default card back URL when not specified in request

## Notes
- Rate limiting respects Scryfall guidelines via `SCRYFALL_DELAY`
- Converts Scryfall JSON to Tabletop Simulator CardCustom format
- Handles multi-face cards automatically (e.g., Flip cards, Double-faced cards)
- Returns 404 when card not found on Scryfall
