# Custom Image Proxy Feature

## Overview

The MTG Card Importer now supports **custom image proxies** - you can fetch card data from Scryfall but use your own custom artwork!

## How It Works

### Syntax

```
scryfall <cardname> <image-url>
```

### Examples

1. **Basic Proxy:**
   ```
   scryfall island https://i.imgur.com/example.jpg
   ```

2. **With Multiple Words:**
   ```
   scryfall black lotus https://example.com/custom-art.png
   ```

3. **Placeholder Images for Testing:**
   ```
   scryfall mountain https://via.placeholder.com/300x200
   ```

## What Gets Fetched

### From Scryfall Backend:
- ✅ Card name
- ✅ Type line (e.g., "Basic Land — Island")
- ✅ Oracle text
- ✅ Mana cost
- ✅ Power/Toughness
- ✅ All card metadata

### From Custom URL:
- 🎨 **Card face image only**

## Use Cases

### 1. Custom Artwork
Create proxies with custom artwork while maintaining official card text:
```
scryfall "lightning bolt" https://myartwork.com/custom-bolt.jpg
```

### 2. Altered Cards
Use photos of your altered/customized physical cards:
```
scryfall "sol ring" https://imgur.com/my-altered-sol-ring.jpg
```

### 3. Placeholder Cards
Test deck layouts with placeholder images:
```
scryfall forest https://via.placeholder.com/300x420/green/white
```

### 4. Community Artwork
Use fan-made artwork while keeping official rules:
```
scryfall counterspell https://community-art.com/counterspell-v2.png
```

## Technical Details

### URL Requirements

**Supported Formats:**
- ✅ `http://` URLs
- ✅ `https://` URLs (recommended)
- ✅ Direct image links (.jpg, .png, .gif, etc.)
- ✅ URLs with query parameters

**Position:**
- ⚠️ URL **must be at the end** of the command
- ⚠️ Space required between card name and URL

### Image Requirements

For best results in Tabletop Simulator:
- **Format:** JPG or PNG
- **Size:** 300×420 pixels (standard MTG card ratio)
- **Aspect Ratio:** 5:7 (portrait)
- **File Size:** Under 5MB recommended

## Comparison: Regular vs Custom Proxy

### Regular Card Spawn
```
scryfall island
```
**Result:**
- Name: Island ✅ (from Scryfall)
- Text: Tap: Add U ✅ (from Scryfall)
- Image: Official Scryfall image ✅ (from Scryfall)

### Custom Proxy Spawn
```
scryfall island https://example.com/custom.jpg
```
**Result:**
- Name: Island ✅ (from Scryfall)
- Text: Tap: Add U ✅ (from Scryfall)
- Image: Your custom image 🎨 (from URL)

## Implementation Details

### How It Works Internally

1. **Parser detects URL at end:**
   ```lua
   local customImageUrl = a:match('(https?://[^%s]+)$')
   ```

2. **Card name extracted:**
   ```lua
   local nameWithoutUrl = a:gsub('https?://[^%s]+$', '')
   ```

3. **Backend fetches card data:**
   ```lua
   WebRequest.get(BACKEND_URL..'/card/'..encodedName, ...)
   ```

4. **Custom image applied:**
   ```lua
   Card.image = tbl.customImage
   ```

5. **Card spawned with mixed data**

### Data Flow

```
User Input: "scryfall island https://custom.jpg"
     ↓
Parser: name="island", customImage="https://custom.jpg"
     ↓
Backend API: /card/island → {card data}
     ↓
Card Spawner: data from backend + image from URL
     ↓
Result: Island card with custom artwork
```

## Troubleshooting

### Image Doesn't Load
- ✅ Check URL is accessible (open in browser)
- ✅ Ensure URL is direct image link
- ✅ Try HTTPS instead of HTTP
- ✅ Check image size (under 5MB)

### Card Data Wrong
- ✅ Check card name spelling
- ✅ Try exact card name from Scryfall
- ✅ Backend must be running and accessible

### Command Not Working
- ✅ Ensure URL is at the END
- ✅ Check for space between name and URL
- ✅ Try without special characters in name

## Examples by Card Type

### Basic Land
```
scryfall plains https://example.com/custom-plains.jpg
```

### Creature
```
scryfall "Serra Angel" https://example.com/angel.jpg
```

### Instant/Sorcery
```
scryfall counterspell https://example.com/counter.jpg
```

### Artifact
```
scryfall "mox sapphire" https://example.com/mox.jpg
```

### Planeswalker
```
scryfall "Jace, the Mind Sculptor" https://example.com/jace.jpg
```

## Limitations

### Not Supported
- ❌ Custom card text (must use Scryfall data)
- ❌ Custom card names (must be valid Scryfall card)
- ❌ Multiple faces with different custom images
- ❌ Custom back images (uses default card back)

### Supported
- ✅ Any card in Scryfall database
- ✅ Any accessible image URL
- ✅ Mix of regular and proxy cards in same deck
- ✅ All card types (creatures, lands, spells, etc.)

## Advanced Usage

### Batch Proxies
Spawn multiple custom proxies in sequence:
```
scryfall island https://art1.com/island.jpg
scryfall mountain https://art1.com/mountain.jpg
scryfall forest https://art1.com/forest.jpg
```

### Deck with Proxies
Use custom images in deck imports by adding `#URL` to card names in decklist:
```
1 Island #https://example.com/island.jpg
1 Mountain #https://example.com/mountain.jpg
```

## Best Practices

### Image Hosting
- ✅ Use reliable image hosts (Imgur, your own server)
- ✅ Use HTTPS for security
- ✅ Keep images permanently accessible
- ✅ Use direct links (not gallery pages)

### Card Names
- ✅ Use exact Scryfall names
- ✅ Use quotes for multi-word names if needed
- ✅ Check spelling before spawning

### Testing
- ✅ Test with placeholder images first
- ✅ Verify card data is correct
- ✅ Check image quality in TTS

## Version History

### v1.903 (Current)
- ✅ Added custom image proxy feature
- ✅ Syntax: `scryfall cardname url`
- ✅ Supports any image URL
- ✅ Maintains all card data from Scryfall

### v1.902
- Initial backend integration

## Credits

- **Feature Implemented By:** Custom backend development
- **Original Importer:** Amuzet
- **Modified By:** Sirin

## Support

For issues or questions:
1. Check this documentation
2. Test with simple examples
3. Verify backend is running
4. Check TTS console for errors

---

**Enjoy creating custom card proxies!** 🎨
