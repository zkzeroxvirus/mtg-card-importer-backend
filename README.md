# MTG Card Importer Backend

A Node.js backend that proxies the Scryfall API to provide Magic: The Gathering card data in Tabletop Simulator-compatible formats.

## Overview

This backend acts as a middleware between the Amuzet Card Importer (Tabletop Simulator Lua script) and Scryfall's API. It:
- Fetches card data from Scryfall
- Applies rate limiting to respect Scryfall's API guidelines
- Converts card data to Tabletop Simulator object formats
- Provides convenient endpoints for deck building and card searching

## Quick Start

### Local Development (Windows PowerShell)

```powershell
# Copy environment template
Copy-Item .env.example .env

# Install dependencies
npm install

# Run development server
npm run dev

# Or run production
npm start
```

Server runs on `http://localhost:3000` by default.

### Cloud Deployment (Render)

This project is configured for easy deployment to [Render.com](https://render.com):

1. Fork/push this repo to GitHub
2. Create new Web Service on Render
3. Connect your GitHub repository
4. Set environment variables in Render dashboard:
   - `NODE_ENV` = `production`
   - `SCRYFALL_DELAY` = `100` (or adjust for rate limiting)
   - `DEFAULT_CARD_BACK` = Your default card back image URL (optional)
5. Render automatically deploys on git push

**Note:** Render's free tier will sleep after 15 minutes of inactivity. Upgrade to paid plan for always-on service.

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

1. **Rate Limiting**: All Scryfall requests are rate-limited to respect their API guidelines (default 100ms between requests)
2. **Caching**: Individual requests are not cached, but response handling is optimized
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
- `SCRYFALL_DELAY` — Rate limit delay in ms (default: 100)
- `DEFAULT_CARD_BACK` — Default card back URL when not specified in requests

## Configuration

Copy `.env.example` to `.env` and customize values:

```env
NODE_ENV=development
PORT=3000
SCRYFALL_DELAY=100
DEFAULT_CARD_BACK=https://gamepedia.cursecdn.com/mtgsalvation_gamepedia/f/f8/Magic_card_back.jpg
```

## Decklist Format

Supported formats:
- Simple: `2 Black Lotus`
- With set: `2 Black Lotus (LEA) 1`
- Deckstats format with brackets
- TappedOut CSV format
- Scryfall deck exports

## License

Uses Scryfall's free API with rate limiting. See [Scryfall API documentation](https://scryfall.com/docs/api) for terms.
