# Spawning Indicator and Button Safety Implementation

## Overview
This document describes the implementation of the spawning indicator and button safety features for the START TOKEN script in Tabletop Simulator.

## Problem Statement
The START TOKEN had buttons numbered 1-22 that spawn random cards, but users could press them multiple times before cards were fully spawned, causing:
- Multiple concurrent spawn requests
- Potential confusion about spawn status
- No visual feedback during spawning

## Solution

### 1. Spawning State Tracking
Added global variables to track spawning state:
```lua
isSpawning = false           -- Prevents concurrent spawns
spawnIndicatorText = nil     -- Reference to the 3D text indicator
cardsSpawned = 0            -- Counter for processed cards
totalCardsToSpawn = 0       -- Total cards in current spawn request
```

### 2. Spawning Indicator (3D Text)
Implemented similar to MTG Importer's spawning indicator:

- **createSpawningIndicator(position)**: Creates a 3D text object above the spawn position
  - Displays: "Spawning...\n0 / N cards"
  - Font size: 60
  - Position: 3 units above spawn anchor

- **updateSpawningIndicator()**: Updates the counter as cards are processed
  - Shows progress: "Spawning...\nX / N cards"

- **destroySpawningIndicator()**: Removes the 3D text when spawning is complete

- **endSpawning()**: Resets all spawning state and removes indicator

### 3. Safety Mechanism
Modified `spawnRandomCardsByNumber(n)` function:

**Before spawning:**
1. Check if `isSpawning == true`
2. If yes, show "Cards are still spawning! Please wait..." and return
3. If no, set `isSpawning = true` and proceed

**During spawning:**
1. Create spawning indicator
2. Fetch cards from backend
3. Process each card and update indicator
4. Handle errors by calling `endSpawning()`

**After spawning:**
1. Spawn the deck object
2. Wait 1 second (so user sees completion)
3. Call `endSpawning()` to reset state and remove indicator

### 4. Error Handling
All error paths now call `endSpawning()` to ensure:
- Spawning state is reset
- Indicator is removed
- Buttons become clickable again

## Benefits

1. **No Concurrent Spawns**: Users cannot trigger multiple spawn requests simultaneously
2. **Visual Feedback**: 3D text shows spawning progress in real-time
3. **Better UX**: Clear indication when spawning is in progress
4. **Consistent with MTG Importer**: Uses same pattern as the main importer script
5. **Error Recovery**: Properly handles errors and resets state

## Testing Recommendations

To test in Tabletop Simulator:

1. **Single Click Test**: Click any numbered button (1-22) and verify:
   - Spawning indicator appears
   - Progress updates as cards are processed
   - Indicator disappears after completion

2. **Multiple Click Test**: Click a button multiple times quickly and verify:
   - Only one spawn request is processed
   - Red message appears: "Cards are still spawning! Please wait..."
   - No duplicate cards are spawned

3. **Error Handling Test**: Disconnect from network and click button, verify:
   - Error message appears
   - Spawning state resets
   - Buttons become clickable again

4. **Progress Display Test**: Click buttons for different counts (1, 5, 22) and verify:
   - Indicator shows correct total count
   - Progress updates correctly

## Code Changes Summary

- Added 4 global variables for spawning state
- Added 4 helper functions for indicator management
- Modified `spawnRandomCardsByNumber()` to include safety check and indicator
- Added indicator updates in the card processing loop
- Added `endSpawning()` calls on all error paths
- Added 1-second delay before removing indicator on success

## Files Modified

- `MTG-TOOLS/START TOKEN.lua` - All changes in this single file
