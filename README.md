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
npm start
```

### Deployment Options

**API Mode (No Bulk Data)**
- Best for quick cloud hosting (e.g., Render, Heroku)
- Uses Scryfall API directly with rate limiting
- Set `USE_BULK_DATA=false` in environment variables
- Lower memory usage
- Note: Render free tier may sleep after inactivity

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

**POST `/fetch-deck`** 🆕
- Fetch and import a deck from external platforms
- Consumes: `{ "url": "https://moxfield.com/decks/...", "back": "URL" }`
- Supported platforms:
  - **Moxfield**: `https://www.moxfield.com/decks/{deck-id}`
  - **Archidekt**: `https://archidekt.com/decks/{deck-id}`
  - **TappedOut**: `https://tappedout.net/mtg-decks/{deck-slug}/`
  - **Scryfall**: `https://scryfall.com/@{username}/decks/{deck-id}`
- Returns: NDJSON (one TTS card object per line)
- Note: Deck must be public to fetch

Example: `POST /fetch-deck` with body `{"url": "https://www.moxfield.com/decks/abc123"}`

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
- `BULK_DATA_PATH` — Filesystem path for the bulk file (default: ./data)

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
- **Deck URLs** (via `/fetch-deck` endpoint):
  - Moxfield: `https://www.moxfield.com/decks/{deck-id}`
  - Archidekt: `https://archidekt.com/decks/{deck-id}`
  - TappedOut: `https://tappedout.net/mtg-decks/{deck-slug}/`
  - Scryfall: `https://scryfall.com/@{username}/decks/{deck-id}`

## Using the Lua Importer

The included `EXAMPLE MTG Card Importer.lua` script provides an easy way to spawn cards in Tabletop Simulator:

### Basic Commands

```
sf <card name>              # Spawn a single card
sf black lotus              # Spawn Black Lotus

sf <multiline decklist>     # Spawn a deck from text
sf 4 Lightning Bolt
3 Mountain

sf <deck URL>               # Fetch and spawn deck from URL
sf https://www.moxfield.com/decks/abc123
sf deck https://archidekt.com/decks/12345

sf random [n] [?q=query]    # Spawn random cards
sf random 5                 # 5 random cards
sf random 3 ?q=t:creature   # 3 random creatures

sf search <query>           # Search and spawn up to 100 cards
sf search t:dragon pow>5    # All dragons with power > 5
```

### Installation

1. In Tabletop Simulator, create a new object (e.g., a tablet or notebook)
2. Right-click the object → Scripting
3. Copy the contents of `EXAMPLE MTG Card Importer.lua` into the script editor
4. Save
5. Use the chat commands with prefix `sf`

The script will auto-update from GitHub when new versions are available.

## License

Uses Scryfall's free API with rate limiting. See [Scryfall API documentation](https://scryfall.com/docs/api) for terms.
