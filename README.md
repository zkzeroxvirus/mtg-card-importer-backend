# MTG Card Importer Backend

A high-performance backend for importing Magic: The Gathering (MTG) cards directly into Tabletop Simulator (TTS). This backend proxies the Scryfall API, enables filtering, and serves MTG card data in bulk or API-based modes.

---

## Key Features

### 🎨 Custom Image Proxies
- Spawn MTG cards with user-provided artworks while maintaining official Scryfall card data.
- Example Command:
  ```
  scryfall island https://your-custom-art.com/island.jpg
  ```

### 🖼️ Single Image Spawning
- Use image URLs to create blank cards without any additional card data.
- Example Command:
  ```
  scryfall https://cards.scryfall.io/large/front/0/0/image.jpg
  ```

### High Performance
- **API Mode:** Quickly fetches live data from Scryfall with respect to API guidelines.
- **Bulk Mode:** Preloads, compresses, and serves Scryfall Oracle bulk files allowing near-instant response times.
- **Clustering:** Supports 500+ concurrent users with optimized multi-process startup.

## Public API
### Card APIs:
- **GET `/card/:name`**: Fetch a single card (e.g., `black lotus`). Supports optional parameters `set`, `forceApi`.
- **GET `/search`**: Perform flexible searches with Scryfall-like query syntax.
- **GET `/random`**: Retrieve random cards with optional filtering parameters (`count`, `q`, etc.).
- **GET `/card/:id`**: Retrieve by ID from memory or Scryfall fallback.

### Operations:
- **GET `/metrics`**: Returns operational performance and runtime data.
- **POST `/bulk/reload`**: Force-reload bulk cached data.

---

## Setup

Start developing or host via:
### Local Development
1. Clone Repository:
   ```bash
   git clone https://github.com/zkzeroxvirus/mtg-card-importer-backend
   ```
2. Install Dependencies:
   ```bash
   npm install
   ```
3. Start Dev Server:
   ```bash
   npm run dev
   ```


### Option: Docker Deployment
1. Build Docker Image
```bash
Docker Up does ```{}``` handle certain.
ehancements-` key ONLY
