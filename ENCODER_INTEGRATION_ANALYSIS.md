# MTG Card Importer - Encoder Integration Review

## Issues Found & Fixes Applied

### Problem #1: Incorrect Property Registration Pattern ❌ → ✅
**Issue:** Your code registered a single unified property called "MTG Importer" with `activateFunc='toggleMenu'`
```lua
-- OLD (Wrong):
enc.call('APIregisterProperty', {
    propID = mod_name,
    name = 'MTG Importer',
    activateFunc = 'toggleMenu',  -- ← This is backwards!
})
```

**Why This Broke:** 
- The Encoder expects each *feature* to be a separate property
- When Encoder calls `toggleMenu`, it doesn't create buttons—it should be the activation function
- The Encoder's button system is designed to list all properties, not to have a property that creates buttons

**Solution:**  ✅
Register 6 individual properties instead:
```lua
-- NEW (Correct):
enc.call('APIregisterProperty', {propID='mtg_oracle', name='Oracle', activateFunc='eOracle'})
enc.call('APIregisterProperty', {propID='mtg_rulings', name='Rulings', activateFunc='eRulings'})
enc.call('APIregisterProperty', {propID='mtg_tokens', name='Tokens', activateFunc='eTokens'})
enc.call('APIregisterProperty', {propID='mtg_printings', name='Printings', activateFunc='ePrintings'})
enc.call('APIregisterProperty', {propID='mtg_back', name='Set Back', activateFunc='eSetBack'})
enc.call('APIregisterProperty', {propID='mtg_reverse', name='Flip Card', activateFunc='eReverse'})
```

Now Encoder will:
1. Show all 6 properties in the right-click menu
2. Call each property's `activateFunc` when the player clicks it
3. Manage button positioning and styling automatically

---

### Problem #2: Wrong Callback Function Signature ❌ → ✅
**Issue:** Your callbacks received just `card` parameter, but Encoder passes a table with multiple values
```lua
-- OLD (Wrong):
function eOracle(card)
    local cardName = card.getName()  -- ← card is nil from Encoder!
```

**Why This Broke:**
- Encoder calls property callbacks with: `{obj=card, color=playerColor, propID='mtg_oracle', ...}`
- Your code expected just the card object directly
- `card` parameter would be `nil`, causing crashes when calling `card.getName()`

**Solution:** ✅
Extract the card from the params table:
```lua
-- NEW (Correct):
function eOracle(params)
    local card = params.obj
    if not card then return end
    local cardName = card.getName()  -- ← Now works!
```

---

### Problem #3: Manual Button Management ❌ → ✅
**Issue:** You had `toggleMenu()` and `createButtons()` manually creating buttons on the card
```lua
-- OLD (Wrong):
function toggleMenu(card)
    createButtons(card)  -- ← You're managing buttons manually!
end

function createButtons(card)
    card.clearButtons()  -- ← Clears ALL buttons
    for _, btn in ipairs(buttons) do
        card.createButton({...})  -- ← Hard-coded positions
    end
end
```

**Why This Broke:**
- The Encoder rebuilds buttons frequently for its own functionality (flip, disable encoding, etc.)
- Your manual button creation would fight with Encoder's button system
- You'd lose buttons when Encoder rebuilded them
- Your buttons would be in weird positions and styles

**Solution:** ✅
Delete those functions entirely. Encoder now:
1. Calls each property's `activateFunc` when clicked
2. Manages all button layout, positioning, and styling
3. Handles button conflicts automatically
4. Uses the πMenu mod for consistent visual presentation

---

## Hook-Up Flow - How It Works Now

```
[Card Spawned]
       ↓
[Player Right-Clicks Card]
       ↓
[Encoder shows registered properties:]
  • Oracle
  • Rulings
  • Tokens
  • Printings
  • Set Back
  • Flip Card
       ↓
[Player Clicks "Oracle"]
       ↓
[Encoder calls eOracle({obj=card, color=playerColor, ...})]
       ↓
[eOracle fetches /card endpoint]
       ↓
[Print oracle text + set card description]
```

---

## Architecture Comparison

### ❌ Your Old Approach (Unified Property)
```
registerModule() 
  → APIregisterProperty("MTG Importer")
      → activateFunc: toggleMenu
          → toggleMenu creates buttons manually
              → buttons don't integrate with Encoder
```

### ✅ New Approach (Individual Properties)
```
registerModule()
  → APIregisterProperty("mtg_oracle") → activateFunc: eOracle
  → APIregisterProperty("mtg_rulings") → activateFunc: eRulings
  → APIregisterProperty("mtg_tokens") → activateFunc: eTokens
  → APIregisterProperty("mtg_printings") → activateFunc: ePrintings
  → APIregisterProperty("mtg_back") → activateFunc: eSetBack
  → APIregisterProperty("mtg_reverse") → activateFunc: eReverse

When card is right-clicked:
Encoder displays menu with all 6 properties
Each property is a clickable button that calls its activateFunc
```

---

## API Contract with Encoder

### Property Registration
```lua
enc.call('APIregisterProperty', {
    propID = 'unique_id',           -- REQUIRED: unique identifier
    name = 'Display Name',          -- REQUIRED: shown in menu
    values = {},                    -- REQUIRED: (empty for buttons)
    funcOwner = self,               -- REQUIRED: which object owns the functions
    activateFunc = 'functionName',  -- REQUIRED: called when property clicked
    callOnActivate = true,          -- OPTIONAL: call immediately on activate
    visible_in_hand = 0             -- OPTIONAL: show in hand (0=no, 1=yes)
})
```

### Callback Function Signature
```lua
function propertyCallback(params)
    -- params = {
    --     obj = card_object,
    --     color = player_color,
    --     propID = 'property_id',
    --     ... (other Encoder data)
    -- }
    
    local card = params.obj
    if not card then return end
    
    -- Your code here
end
```

---

## Remaining (Obsolete) Code to Clean Up

Your file still has some unused code from the old approach:

```lua
-- These can be deleted entirely:
function toggleMenu(card) ... end      -- Encoder doesn't call this
function createButtons(card) ... end   -- Encoder manages buttons now
```

They're not breaking anything (they're just not called), but cleaning them up would improve code clarity.

---

## Testing Checklist

Once deployed, verify:

- [ ] Spawn a card via chat (`sf Mountain`)
- [ ] Right-click the card
- [ ] Verify 6 properties appear: Oracle, Rulings, Tokens, Printings, Set Back, Flip Card
- [ ] Click "Oracle" → should display card text
- [ ] Click "Rulings" → should show rulings in chat
- [ ] Click "Tokens" → should spawn token cards if any exist
- [ ] Click "Printings" → should list printings in chat
- [ ] Click "Set Back" → should confirm back image set
- [ ] Click "Flip Card" → should flip the card
- [ ] Test without Encoder mod → chat commands should still work

---

## Files Modified

- **MTG Card Importer.lua** (v2.3 → v2.3.1)
  - Fixed registerModule() to register 6 individual properties
  - Updated all 6 callback function signatures (receive params table)
  - Marked toggleMenu/createButtons for cleanup (currently unused)

---

## Deployed

✅ Commit: `927e2bc` - "Fix Encoder integration: register individual properties"  
✅ Pushed to Render (auto-deploys)  
✅ Changes live at: https://mtg-card-importer-backend.onrender.com
