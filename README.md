# MTG Card Importer Backend

A Node.js backend that proxies the Scryfall API to provide Magic: The Gathering card data in Tabletop Simulator-compatible formats.

**✅ Fully compliant with [Scryfall API guidelines](https://scryfall.com/docs/api)** - See [SCRYFALL_API_COMPLIANCE.md](SCRYFALL_API_COMPLIANCE.md) for details.

**⚡ Optimized for high concurrency** - Supports 500+ concurrent users with clustering and compression. See [PERFORMANCE_GUIDE.md](PERFORMANCE_GUIDE.md) for details.

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
- **Supports 500+ concurrent users with clustering and performance optimizations**

## Performance

**Single Process:**
- 100-200 concurrent users
- 50-100 requests/second

**Clustered (4 cores):**
- 500-1000 concurrent users  
- 200-400 requests/second

**Clustered (8 cores):**
- 1000-2000 concurrent users
- 400-800 requests/second

See [PERFORMANCE_GUIDE.md](PERFORMANCE_GUIDE.md) for detailed benchmarks, tuning, and horizontal scaling strategies.

## Deployment

### Quick Start

1. Copy the environment template:
```bash
cp .env.example .env
```

2. Customize settings in `.env` as needed (see Configuration section below)

3. Install dependencies and start the server:
```bash
npm install

# Single process (for development or low traffic)
npm start

# Clustered mode (for production with high traffic)
npm run start:cluster
```

### Development

The project includes scripts for development, testing, and linting:

```bash
# Run the server in development mode with auto-reload
npm run dev

# Run tests
npm test
npm run test:watch      # Run tests in watch mode
npm run test:coverage   # Run tests with coverage report

# Lint code
npm run lint            # Check for linting errors
npm run lint:fix        # Fix linting errors automatically

# Build (validates that the project can be built)
npm run build
```

### Docker (Recommended for Unraid/Self-Hosted)

The Docker image is optimized for production use with clustering enabled by default.

**Build the image:**
```bash
docker build -t mtg-card-importer-backend .
```

**Run the container:**
```bash
docker run -d \
  --name mtg-card-importer-backend \
  -p 3000:3000 \
  -e NODE_ENV=production \
  -e USE_BULK_DATA=true \
  -e BULK_DATA_PATH=/app/data \
  -e WORKERS=auto \
  -e MAX_CACHE_SIZE=5000 \
  -e SCRYFALL_DELAY=100 \
  -e DEFAULT_CARD_BACK=https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/ \
  -v /mnt/user/appdata/mtg-card-importer-backend:/app/data \
  --restart unless-stopped \
  mtg-card-importer-backend
```

**Unraid Template Configuration:**
- **Container port:** `3000` → Host port: `3000` (or your preferred port)
- **Volume mapping:** `/mnt/user/appdata/mtg-card-importer-backend` → `/app/data`
- **Key environment variables:**
  - `NODE_ENV=production` (required for optimal performance)
  - `USE_BULK_DATA=true` (recommended for self-hosted - loads card data into memory)
  - `BULK_DATA_PATH=/app/data` (where bulk data is cached)
  - `WORKERS=auto` (uses CPU cores for clustering, capped by container memory)
  - `PORT=3000` (default)
  - `MAX_CACHE_SIZE=5000` (optional - default is 5000)
  - `SCRYFALL_DELAY=100` (optional - default is 100ms)
  - `DEFAULT_CARD_BACK=<URL>` (optional - custom card back image)

**Notes:**
- The Dockerfile uses clustering mode (`npm run start:cluster`) by default for better performance
- Auto worker count is capped by container memory (~700MB per worker in bulk data mode)
- Bulk data file (~161MB compressed, ~500MB in memory) is downloaded on first start and cached
- Set `WORKERS=1` to disable clustering if running on a single-core system
- Restart policy `unless-stopped` ensures the container restarts automatically

### Deployment Options

**API Mode (No Bulk Data)**
- Best for quick cloud hosting (e.g., Heroku, Railway, Fly.io)
- Uses Scryfall API directly with rate limiting
- Set `USE_BULK_DATA=false` in environment variables
- Lower memory usage
- Note: Some free tier services may sleep after inactivity

**Bulk Data Mode**
- Best for heavy usage or local hosting
- Loads Scryfall Oracle bulk (~161MB compressed) into memory (~500MB)
- Set `USE_BULK_DATA=true` in environment variables
- Faster response times
- First start downloads the bulk file once (1-2 minutes); subsequent restarts reuse the cached file

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
- Note: Automatically excludes non-playable cards (basic lands, tokens, emblems, art cards, test cards, digital-only cards, meld results, etc.) to match paper Magic gameplay
- Note: Automatically filters to unique cards (by oracle_id) to prevent skewing results with heavily reprinted cards or alternative arts

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

**POST `/build`**
- Build deck with optional hand position (TTS spawning)
- Consumes: `{ "data": "DECKLIST", "back": "URL", "hand": {...} }`
- Returns: NDJSON (one TTS card object per line)

**POST `/deck/parse`**
- Parse and validate decklist text without building TTS objects
- Consumes: Raw text body (decklist in any supported format)
- Returns: `{ format: "FORMAT_NAME", cards: [...], sideboard: [...] }`
- Supports all decklist formats (see Decklist Format section below)
- Useful for validation and format detection before building

### System

**GET `/`**
- Health check endpoint
- Returns: Service status, metrics, and available endpoints
- Includes: uptime, request counts, error rate, memory usage

**GET `/metrics`**
- Detailed performance metrics
- Returns: Request stats, memory usage, bulk data status, process info
- Use for monitoring and alerting

**GET `/ready`**
- Readiness probe for load balancers
- Returns: `{"ready": true}` when server is ready to accept traffic
- Returns HTTP 503 if server is not ready (bulk data loading, high memory)

**GET `/bulk/stats`**
- Get bulk data statistics
- Returns: File size, card count, memory usage, last update time, and enabled status
- Works regardless of `USE_BULK_DATA` setting (returns empty stats when disabled)

**POST `/bulk/reload`**
- Manually trigger bulk data reload (when bulk mode is enabled)
- No request body required
- Returns: Success status and updated statistics
- Useful for forcing updates without restarting the server

**GET `/rulings/:name`**
- Fetch card rulings by card name
- Returns: Scryfall rulings list

**GET `/tokens/:name`**
- Fetch tokens created by a card
- Returns: Array of Scryfall token cards

**GET `/printings/:name`**
- Fetch all printings of a card
- Returns: Scryfall list object with all printings

**GET `/proxy`**
- Proxy Scryfall API requests with rate limiting
- Query parameters: `?uri=SCRYFALL_API_URL` (must be a valid Scryfall API URL)
- Returns: Proxied Scryfall API response
- Note: Returns HTTP 400 error if request includes blocked parameters:
  - `include_extras=true` (increases result set size)
  - `include_multilingual=true` (increases result set size)
  - `order=released` or `order=added` (can return thousands of results)

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

### Core Settings
- `NODE_ENV` — `development` or `production` (default: development)
- `PORT` — Server port (default: 3000)

### Performance Settings
- `WORKERS` — Number of worker processes for clustering (default: auto = CPU cores, capped by memory)
  - Set to `1` to disable clustering
  - Set to `auto` to use all CPU cores when memory allows (recommended for production)
- `MAX_CACHE_SIZE` — Maximum entries in caches (default: 5000)
  - Higher values = more memory, fewer cache misses
  - Lower values = less memory, more cache misses

### Scryfall API Settings
- `SCRYFALL_DELAY` — Rate limit delay in ms for API mode (default: 100)
- `DEFAULT_CARD_BACK` — Optional default card back image URL (Steam CDN/Imgur recommended)

### Bulk Data Settings
- `USE_BULK_DATA` — `true` enables bulk mode (fast, higher RAM); `false` uses Scryfall API
- `BULK_DATA_PATH` — Filesystem path for the bulk file (default: ./data, Docker/Unraid: /app/data)

See [PERFORMANCE_GUIDE.md](PERFORMANCE_GUIDE.md) for detailed tuning recommendations.

## Configuration

Copy `.env.example` to `.env` and customize values:

```env
NODE_ENV=production
PORT=3000

# Performance (for 500+ concurrent users)
WORKERS=auto
MAX_CACHE_SIZE=5000

# Scryfall API
SCRYFALL_DELAY=100
DEFAULT_CARD_BACK=https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/

# Bulk Data (recommended for production)
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
- **Simple text**: `2 Black Lotus`
- **With set code**: `2 Black Lotus (LEA) 1`
- **Arena format**: `2 Black Lotus (LEA)`
- **Moxfield JSON**: `{ "main": [...], "sideboard": [...] }`
- **Archidekt JSON**: `{ "cards": [...] }`
- **Deckstats format**: With brackets `[2x] Black Lotus`
- **TappedOut CSV**: Comma-separated format
- **Scryfall deck exports**: Official Scryfall export format

All formats can be parsed and validated using the `/deck/parse` endpoint.

## Troubleshooting

### System Crashes or High Memory Usage (Unraid/Docker)

If you're experiencing system crashes or high memory usage, especially after recent updates:

**Root Cause**: Memory leaks from duplicate bulk data update timers in cluster mode (fixed in latest version)

**Solution**: Update to the latest version and restart:
```bash
# Pull latest image
docker pull your-registry/mtg-card-importer-backend:latest

# Or rebuild if using local image
docker build --no-cache -t mtg-card-importer-backend .

# Restart container
docker restart mtg-card-importer-backend
```

### Docker Container Won't Start - "Cannot find module 'express'"

If your Docker container crashes immediately with errors like:
```
Error: Cannot find module 'express'
Require stack:
- /app/server.js
```

**Root Cause**: Docker is using a stale cached build layer where dependencies weren't properly installed.

**Solution**: Rebuild the Docker image without cache:
```bash
docker build --no-cache -t mtg-card-importer-backend .
```

Then run your container as normal:
```bash
docker run -d \
  --name mtg-card-importer \
  --network mtg-net \
  -p 3000:3000 \
  -e NODE_ENV=production \
  -e USE_BULK_DATA=true \
  -e BULK_DATA_PATH=/app/data \
  -e WORKERS=auto \
  -v /mnt/user/appdata/mtg-card-importer-backend:/app/data \
  --restart unless-stopped \
  mtg-card-importer-backend
```

**Prevention**: Always rebuild the image after:
- Pulling updates from git
- Changing `package.json` or `package-lock.json`
- Experiencing any module-not-found errors

### Container Keeps Restarting

Check the logs to see the specific error:
```bash
docker logs mtg-card-importer
```

Common issues:
- **Port already in use**: Change the host port in the `-p` flag (e.g., `-p 3001:3000`)
- **Network doesn't exist**: Create the network first or remove `--network mtg-net`
- **Volume mount issues**: Ensure the host directory exists and has proper permissions

### Performance Issues

See [PERFORMANCE_GUIDE.md](PERFORMANCE_GUIDE.md) for detailed tuning recommendations, including:
- Worker count optimization
- Cache size tuning
- Bulk data vs API mode comparison
- Clustering best practices

## License

Uses Scryfall's free API with rate limiting. See [Scryfall API documentation](https://scryfall.com/docs/api) for terms.
