# Lua Files for Tabletop Simulator

This directory contains Lua scripts for use with Tabletop Simulator to import Magic: The Gathering cards using the backend API.

## 🎨 NEW: Custom Image Proxy Feature (v1.903)

You can now spawn cards with custom artwork while keeping official card data from Scryfall!

**Usage:**
```
scryfall <cardname> <image-url>
```

**Examples:**
```
scryfall island https://i.imgur.com/custom-island.jpg
scryfall "black lotus" https://example.com/art.png
```

**What you get:**
- ✅ Card data (name, text, mana cost) from Scryfall
- 🎨 Custom image from your URL

See [CUSTOM_IMAGE_PROXY_GUIDE.md](CUSTOM_IMAGE_PROXY_GUIDE.md) for complete documentation.

---

## Files Overview

### 1. MTG Card Importer.lua
**Main production script** - Full-featured card importer with advanced functionality.

**Features:**
- ✅ Auto-update from GitHub on load
- ✅ Manual update check button (🔄)
- ✅ **Custom image proxies** - Use any artwork with official card data
- ✅ Custom card backs per player
- ✅ Deck import from multiple sources (Moxfield, Scryfall, etc.)
- ✅ Random card generation with Scryfall queries
- ✅ Booster pack generation
- ✅ Token spawning
- ✅ Oracle text lookup

**Configuration:**
```lua
-- Change backend URL (line 22)
BACKEND_URL = 'https://mtg-card-importer-backend.onrender.com'

-- Enable/disable auto-update (line 25)
AUTO_UPDATE_ENABLED = true

-- GitHub URL for updates (line 12)
GITURL = 'https://raw.githubusercontent.com/zkzeroxvirus/mtg-card-importer-backend/main/MTG%20Card%20Importer.lua'
```

**Usage:**
```
Scryfall <card name>                    - Spawn single card
Scryfall <card name> <image-url>        - Spawn card with custom image (NEW!)
Scryfall <URL>                          - Import deck from URL
Scryfall random <query>                 - Spawn random card(s)
Scryfall help                           - Show help
```

---

### 2. EXAMPLE MTG Card Importer.lua
**Simplified example script** - Minimal implementation showing core functionality.

**Features:**
- ✅ Auto-update from GitHub
- ✅ Basic card spawning
- ✅ Deck import
- ✅ Random cards
- ✅ Search functionality
- ✅ Clean, readable code for learning

**Configuration:**
```lua
-- Change backend URL (line 21)
local BaseURL = 'https://mtg-card-importer-backend.onrender.com'

-- Enable/disable auto-update (line 13)
AUTO_UPDATE_ENABLED = true
```

**Usage:**
```
sf <card name>              - Spawn single card
sf <decklist>               - Spawn deck from text
sf random [n] [query]       - Spawn random cards
sf search <query>           - Search and spawn cards
```

---

### 3. Mystery Pack Generator.lua
**Booster pack generator** - Creates randomized booster packs.

**Features:**
- ✅ Configurable set codes
- ✅ Rarity distribution (mythic/rare/uncommon/common)
- ✅ Special set handling (Mystery Booster, etc.)
- ✅ Custom pack contents

**Configuration:**
```lua
-- Change backend URL (line 15)
backendURL = 'https://mtg-card-importer-backend.onrender.com/'

-- Set the booster pack set (line 18)
setCode = 'Mystery'  -- or 'ZNR', 'STX', etc.
```

---

### 4. Essence Counter.lua
Counter management tool for tracking life, tokens, etc.

### 5. START TOKEN.lua
Token spawning utility.

---

## Self-Updating System

All main Lua files now include self-updating functionality that:

1. **Checks GitHub on Load** - Automatically checks for new versions when the object loads
2. **Manual Update Button** - Click the 🔄 button to check for updates anytime
3. **Auto-Downloads** - If a newer version is found, it downloads and applies automatically
4. **Version Display** - Shows current version in object name

### How It Works

```lua
-- 1. Script checks GitHub for latest version
function checkForUpdates()
  WebRequest.get(GITURL, ...)
end

-- 2. Compares versions
if newVersion > currentVersion then
  -- 3. Downloads new script
  self.setLuaScript(newScript)
  
  -- 4. Reloads object with new code
  self.reload()
end
```

### Disabling Auto-Update

If you want to disable automatic updates on load:

```lua
-- Set to false in the configuration section
AUTO_UPDATE_ENABLED = false
```

You can still manually check for updates using the 🔄 button.

---

## Backend Integration

All scripts connect to the backend API for card data. The backend URL can be configured at the top of each file.

### Supported Endpoints

The Lua scripts use these backend endpoints:

1. **`GET /card/:name`** - Fetch single card by name
2. **`GET /cards/:id`** - Fetch card by Scryfall ID
3. **`GET /cards/:set/:number`** - Fetch by set and collector number
4. **`GET /random`** - Get random card(s) with optional query
5. **`GET /search`** - Search cards with Scryfall syntax
6. **`POST /deck`** - Build deck from decklist
7. **`POST /build`** - Build deck with hand position

### Local Testing

For local development, change the backend URL to your local server:

```lua
BACKEND_URL = 'http://localhost:3000'
-- or
local BaseURL = 'http://localhost:3000'
```

---

## Installation

### In Tabletop Simulator:

1. **Create an Empty Object** - Right-click on table, select "Objects" > "Components" > "Custom" > "Custom Model"

2. **Open Scripting Window** - Right-click the object, select "Scripting"

3. **Copy Script** - Copy the contents of one of the Lua files

4. **Paste and Save** - Paste into the scripting window and click "Save & Play"

5. **Object Loads** - The script will:
   - Check for updates (if enabled)
   - Create UI buttons
   - Display usage information
   - Connect to backend

### From GitHub (Recommended):

The auto-update feature allows you to always have the latest version:

1. Create object with any version of the script
2. Script automatically checks GitHub
3. Downloads and applies updates
4. Or manually click 🔄 to update

---

## Code Formatting Standards

All Lua files now follow consistent formatting:

- ✅ **Clear section headers** with comment blocks
- ✅ **Consistent indentation** (2 spaces)
- ✅ **Descriptive comments** explaining functionality
- ✅ **Organized code structure** with logical grouping
- ✅ **Readable variable names**
- ✅ **Configuration at top** of file

Example:
```lua
-- ============================================================================
-- Section Name
-- ============================================================================
-- Description of what this section does

function myFunction()
  -- Clear comments
  local variable = "value"
  
  -- Grouped logic
  if condition then
    doSomething()
  end
end
```

---

## Troubleshooting

### "Could not connect to backend"
- Check that `BACKEND_URL` points to a running backend
- Verify the backend is accessible from your network
- Try the health check: `GET https://your-backend.com/`

### "Update failed"
- Check your internet connection
- Verify `GITURL` points to a valid GitHub raw file
- Try disabling auto-update and updating manually

### "Cards not spawning"
- Check backend logs for errors
- Verify card names are spelled correctly
- Try simpler queries first (e.g., "Black Lotus")

### "Button not working"
- Reload the script (right-click object > Scripting > Save & Play)
- Check for Lua errors in the game console (~ key)

---

## Contributing

When modifying Lua files:

1. **Update Version Number** - Increment version in file header
2. **Test Thoroughly** - Verify all features work
3. **Maintain Formatting** - Follow the established style
4. **Update GitHub** - Push changes so auto-update works
5. **Document Changes** - Add to this README

---

## Credits

- **Original Author**: Amuzet
- **Modified By**: Sirin (backend integration)
- **Current Maintainer**: zkzeroxvirus

---

## License

These scripts are provided as-is for use with Tabletop Simulator and the MTG Card Importer Backend.
