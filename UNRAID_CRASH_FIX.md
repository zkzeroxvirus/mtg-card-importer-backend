# Unraid Crash Fix - Memory Leak Resolution

## Issue Description

Unraid systems running the MTG Card Importer Backend in Docker were experiencing crashes after recent updates. The root cause was identified as memory leaks caused by improper timer management in bulk data update scheduling.

## Root Causes

### 1. Missing Timer Rescheduling
The `scheduleUpdateCheck()` function in `lib/bulk-data.js` failed to reschedule the next update after a successful update completed. This broke the 24-hour update cycle and could leave the system in an inconsistent state.

### 2. Multiple Concurrent Timers in Cluster Mode
When running in cluster mode (the default for Docker deployments), each worker process was creating its own 24-hour update timer. This resulted in:
- Multiple concurrent bulk data downloads (one per worker)
- Memory exhaustion from duplicate operations
- Increased disk I/O and network usage
- System instability and crashes

### 3. No Timer Cleanup on Shutdown
Update timers were not properly cleaned up during graceful shutdowns, leaving orphaned timers that could persist and cause issues on restart.

## Solution

### Changes Made

#### 1. `lib/bulk-data.js`
- **Added `scheduleUpdates` parameter** to `loadBulkData()` function
  - Controls whether automatic updates should be scheduled
  - Defaults to `true` for backward compatibility
  - Set to `false` in cluster workers to prevent duplicate timers

- **Fixed missing timer rescheduling**
  - Added `scheduleUpdateCheck()` calls after successful updates (lines 1915, 1924)
  - Added `scheduleUpdateCheck(RETRY_INTERVAL)` call after failed updates (line 1929)

- **Added `stopUpdateCheck()` function**
  - Cleanly stops automatic update checks
  - Clears the update timeout
  - Logs cleanup action for debugging

- **Improved timer scheduling logic**
  - Added `delay` parameter to `scheduleUpdateCheck()` for flexible retry intervals
  - Passes `false` to `loadBulkData()` within scheduled updates to prevent nested timers
  - Uses `RETRY_INTERVAL` (1 hour) for failed updates instead of `UPDATE_INTERVAL` (24 hours)

#### 2. `server.js`
- **Added cluster detection**
  - Imported `cluster` module
  - Added `SHOULD_SCHEDULE_UPDATES` constant
  - Only worker 1 schedules updates in cluster mode

- **Modified bulk data initialization**
  - Passes `SHOULD_SCHEDULE_UPDATES` to `loadBulkData()`
  - Logs which worker is responsible for scheduling updates

- **Added timer cleanup in shutdown handler**
  - Calls `bulkData.stopUpdateCheck()` during graceful shutdown
  - Only calls cleanup if this worker was responsible for scheduling

## Technical Details

### Cluster Mode Behavior

| Mode | Worker ID | Schedules Updates | Loads Data |
|------|-----------|-------------------|------------|
| Standalone | N/A | ✅ Yes | ✅ Yes |
| Cluster | Worker 1 | ✅ Yes | ✅ Yes |
| Cluster | Worker 2+ | ❌ No | ✅ Yes |

**Key Points:**
- All workers load bulk data into their own memory (required for serving requests)
- Only worker 1 schedules and performs automatic updates
- All workers share the same bulk data files on disk
- When worker 1 updates the files, other workers continue using their in-memory data until they restart or manually reload

### Timer Lifecycle

1. **Initial Load**
   - Server starts
   - Bulk data is loaded if enabled
   - Timer is scheduled (if `scheduleUpdates=true`)

2. **Scheduled Update (24 hours later)**
   - Download new bulk data from Scryfall
   - Load new data into memory
   - Reschedule next update for 24 hours
   - If download fails, retry in 1 hour

3. **Graceful Shutdown**
   - Receive SIGTERM or SIGINT
   - Stop update timer
   - Close server
   - Exit cleanly

## Testing

The fix has been validated through:

1. **Logic Testing**
   - Verified standalone mode schedules updates
   - Verified only worker 1 schedules in cluster mode
   - Verified workers 2+ do not schedule in cluster mode

2. **Integration Testing**
   - Server starts correctly in standalone mode
   - Cluster starts correctly with 2-3 workers
   - No duplicate timers are created
   - Graceful shutdown works properly

3. **Security Testing**
   - CodeQL analysis found no security issues
   - No new vulnerabilities introduced

## Deployment Recommendations

### For Unraid Users

1. **Update the container:**
   ```bash
   docker pull your-registry/mtg-card-importer-backend:latest
   ```

2. **Rebuild if using local image:**
   ```bash
   docker build --no-cache -t mtg-card-importer-backend .
   ```

3. **Restart the container:**
   ```bash
   docker restart mtg-card-importer-backend
   ```

4. **Verify the fix:**
   Check logs for proper worker behavior:
   ```bash
   docker logs mtg-card-importer-backend | grep -E "(Worker|automatic|update)"
   ```

   Expected output for cluster mode:
   ```
   [Cluster] Starting N worker processes...
   [Cluster] Worker 1 (PID: XXXX) is online
   [Init] Worker 1 - will handle automatic bulk data updates
   [Cluster] Worker 2 (PID: XXXX) is online
   [Init] Worker 2 - automatic updates disabled (handled by worker 1)
   ```

### Environment Variables

No changes to environment variables are required. The fix works with existing configurations:

```env
NODE_ENV=production
USE_BULK_DATA=true
BULK_DATA_PATH=/app/data
WORKERS=auto  # or set to 1 for single-process mode
```

## Monitoring

### Signs of Healthy Operation

- ✅ Only one "will handle automatic bulk data updates" message in logs
- ✅ Worker 2+ logs show "automatic updates disabled"
- ✅ Memory usage remains stable over time
- ✅ No "too many open files" or similar errors

### Signs of Issues (Pre-Fix Behavior)

- ❌ Multiple workers logging "will handle automatic bulk data updates"
- ❌ Memory usage growing over time
- ❌ Multiple concurrent bulk data downloads
- ❌ System crashes or OOM (out of memory) errors

## Additional Notes

### For Single-Process Deployments

If you're running with `WORKERS=1` or using `npm start` (non-clustered):
- The fix still applies and improves timer management
- All updates will be handled by the single process
- Memory usage should be lower and more stable

### For High-Availability Deployments

If you're running multiple instances behind a load balancer:
- Each instance is independent
- Each instance will have one timer (on worker 1)
- This is expected and correct behavior
- Consider using a shared volume for bulk data files to reduce downloads

## References

- Original Issue: "Not really sure but my unraid keeps crashing now since we updated a short while ago"
- Related Files:
  - `lib/bulk-data.js` - Bulk data management and timer scheduling
  - `server.js` - Server initialization and cluster mode detection
  - `cluster.js` - Cluster mode worker management

## Changelog

**v0.1.1** (This Fix)
- Fixed memory leak from duplicate update timers in cluster mode
- Added proper timer cleanup on shutdown
- Fixed missing timer rescheduling after updates
- Improved error handling and retry logic

**v0.1.0** (Previous Version)
- Initial cluster mode support
- Bulk data auto-update feature
- Issue: Multiple timers per cluster caused memory leaks
