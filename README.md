# MTG Card Importer Backend

Node.js + Express backend that proxies Scryfall to produce Tabletop Simulator-compatible card objects.

## Endpoints
- `GET /` — Health check
- `GET /card/:name` — Fetch single card by name (optional `?set=ABC`)
- `POST /deck` — Build deck from text list (NDJSON output)
- `GET /random` — Fetch `count` random cards (optional `?q=` filter)
- `GET /search` — Search Scryfall with Scryfall query syntax (`?q=`)

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

## Body format for /deck

```json
{
  "decklist": "2 Black Lotus\n4 Mountain",
  "set": "LEA" // optional
}
```

## Render Deployment
- Uses `Procfile` and `render.yaml` for auto-deploy
- Free plan supported; expect cold starts after idle periods

## Notes
- Rate limiting respects Scryfall guidelines via `SCRYFALL_DELAY`
- `DEFAULT_CARD_BACK` should be a PNG URL (placeholder provided)
