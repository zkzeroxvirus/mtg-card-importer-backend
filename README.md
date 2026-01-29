# MTG Card Importer Backend

A Node.js backend that proxies the Scryfall API to provide Magic: The Gathering card data in Tabletop Simulator-compatible formats.

**✅ Fully compliant with [Scryfall API guidelines](https://scryfall.com/docs/api)** - See [SCRYFALL_API_COMPLIANCE.md](SCRYFALL_API_COMPLIANCE.md) for details.

## 🎨 New Feature: Custom Image Proxies!

You can now spawn cards with custom artwork while keeping official card data:

```
scryfall island https://your-custom-art.com/island.jpg
```

See [CUSTOM_IMAGE_PROXY_GUIDE.md](CUSTOM_IMAGE_PROXY_GUIDE.md) for full documentation.

## Overview

This backend acts as a middleware between the Amuzet Card Importer (Tabletop Simulator Lua script) and Scryfall's API. It:
- Fetches card data from Scryfall
- Applies rate limiting to respect Scryfall's API guidelines
- Converts card data to Tabletop Simulator object formats
- Provides convenient endpoints for deck building and card searching

## Deployment Options

Two ready-to-use setups:

### A) Render (API mode, no bulk data)
- Best for quick cloud hosting; uses Scryfall API directly with rate limiting.
- Steps (PowerShell on Windows):
```powershell
# Copy env template and set cloud-friendly defaults
Copy-Item .env.example .env

# For Render API mode, set USE_BULK_DATA=false
(Get-Content .env) -replace 'USE_BULK_DATA=true','USE_BULK_DATA=false' | Set-Content .env

# Commit and push; create a new Web Service on Render pointing at your repo
# Env vars to set in Render Dashboard:
# NODE_ENV=production
# SCRYFALL_DELAY=50
# USE_BULK_DATA=false
# DEFAULT_CARD_BACK=<optional image URL>
```
- Render free tier may sleep after inactivity; bulk data is disabled to keep memory low.

### B) Docker / Unraid (Bulk data mode)
- Best for LAN speed or heavy usage; loads Scryfall Oracle bulk (~161MB compressed) into memory (~500MB).
- Steps (PowerShell):
```powershell
# Copy env template
Copy-Item .env.example .env

# Ensure bulk data is enabled and stored in /app/data
(Get-Content .env) -replace 'USE_BULK_DATA=true','USE_BULK_DATA=true' | Set-Content .env

# Build and run with docker compose
docker compose up -d

# Watch logs for the first bulk download (1-2 minutes)
docker logs -f mtg-card-importer-backend
```
- For Unraid, place the repo in appdata, map ./data to /app/data, and expose port 3000 (or your chosen port).
- First start downloads the bulk file once; subsequent restarts reuse the cached file.

Minimal docker-compose.yml:
```yaml
services:
	mtg-card-importer-backend:
		build: .
		container_name: mtg-card-importer-backend
		ports:
			- "3000:3000"
		environment:
			- NODE_ENV=production
			- USE_BULK_DATA=true
			- BULK_DATA_PATH=/app/data
			- SCRYFALL_DELAY=50
		volumes:
			- ./data:/app/data
		restart: unless-stopped
```

## API Endpoints

### Card Lookup

**GET `/card/:name`**
- Fetch single card by name
- Query parameters: `?set=XYZ` (optional set code)
- Returns: Scryfall card object

Example: `GET /card/black%20lotus?set=lea`

**GET `/cards/:id`**
- Fetch card by Scryfall ID
- Returns: Scryfall card object

**GET `/cards/:set/:number/:lang`**
- Fetch card by set code and collector number
- `lang` parameter defaults to `en` if omitted
- Returns: Scryfall card object

### Card Search

**GET `/search`**
- Search cards using Scryfall query syntax
- Query parameters: `?q=QUERY&limit=100`
- Returns: Scryfall list object with card array

Example: `GET /search?q=type:creature%20power>5`

**GET `/random`**
- Fetch random card(s)
- Query parameters: `?count=5&q=FILTER` (both optional)
- Returns: Single card or list of cards depending on count

### Set Information

**GET `/sets/:code`**
- Fetch set information by set code
- Returns: Scryfall set object

Example: `GET /sets/dom`

### Deck Building

**POST `/deck`**
- Build deck from decklist text
- Consumes: `{ "decklist": "2 Black Lotus\n4 Mountain", "back": "URL" }`
- Returns: NDJSON (one TTS card object per line)

**POST /build`**
- Build deck with optional hand position (TTS spawning)
- Consumes: `{ "data": "DECKLIST", "back": "URL", "hand": {...} }`
- Returns: NDJSON (one TTS card object per line)

### System

**GET `/`**
- Health check endpoint
- Returns: Service status and available endpoints

**GET `/rulings/:name`**
- Fetch card rulings by card name
- Returns: Scryfall rulings list

**GET `/tokens/:name`**
- Fetch tokens created by a card
- Returns: Array of Scryfall token cards

**GET `/printings/:name`**
- Fetch all printings of a card
- Returns: Scryfall list object with all printings

## How It Works

### Scryfall API Integration

1. **Rate Limiting**: API mode is rate-limited to respect Scryfall guidelines (default 50ms between requests)
2. **Caching**: Bulk mode keeps the full Oracle bulk file in memory for instant responses; API mode streams results directly
3. **Error Handling**: Returns 404 when cards are not found, with descriptive error messages

### Tabletop Simulator Format

Card objects are converted to Tabletop Simulator's `CardCustom` format including:
- Front and back images
- Card name, description (oracle text), and metadata
- Multi-face card support (flip cards, double-faced cards)
- Proper deck object structure for spawning

## Environment Variables

- `NODE_ENV` — `development` or `production` (default: development)
- `PORT` — Server port (default: 3000)
- `SCRYFALL_DELAY` — Rate limit delay in ms for API mode (default: 50)
- `DEFAULT_CARD_BACK` — Default card back URL when not specified in requests
- `USE_BULK_DATA` — `true` enables bulk mode (fast, higher RAM); `false` uses Scryfall API
- `BULK_DATA_PATH` — Filesystem path for the bulk file (default: ./data; in Docker: /app/data)

## Configuration

Copy `.env.example` to `.env` and customize values:

```env
NODE_ENV=development
PORT=3000
SCRYFALL_DELAY=50
DEFAULT_CARD_BACK=https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/
USE_BULK_DATA=true
BULK_DATA_PATH=./data
```

## Scryfall API Compliance

This backend is fully compliant with [Scryfall's API guidelines](https://scryfall.com/docs/api):

- ✅ **Rate Limiting**: Enforces 50-100ms delay between requests (configurable via `SCRYFALL_DELAY`)
- ✅ **User-Agent Header**: Includes descriptive application name and version
- ✅ **Accept Header**: Properly set for all API requests
- ✅ **Retry Logic**: Respects `Retry-After` header for 429 responses
- ✅ **Bulk Data Mode**: Optional caching to minimize API calls (recommended for self-hosted)
- ✅ **Data Usage**: Creates additional value through TTS format conversion

See [SCRYFALL_API_COMPLIANCE.md](SCRYFALL_API_COMPLIANCE.md) for detailed technical documentation.

## Decklist Format

Supported formats:
- Simple: `2 Black Lotus`
- With set: `2 Black Lotus (LEA) 1`
- Deckstats format with brackets
- TappedOut CSV format
- Scryfall deck exports

## License

Uses Scryfall's free API with rate limiting. See [Scryfall API documentation](https://scryfall.com/docs/api) for terms.
