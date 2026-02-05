const cluster = require('cluster');
const { calculateWorkerCount } = require('./lib/cluster-config');

/**
 * Cluster management for horizontal scaling across CPU cores
 * Supports high concurrency by running multiple worker processes
 */

// Configuration: Use environment variable or default to CPU count
const workersEnv = process.env.WORKERS || 'auto';
const {
  workers: WORKERS,
  cpuCount,
  memoryLimitMB,
  memoryPerWorkerMB,
  maxWorkersByMemory,
  useBulkData
} = calculateWorkerCount({ workersEnv });
// Stagger worker startup to prevent simultaneous JSON parsing (configurable via env var)
// Reduced to 500ms since decompression is now cached - only JSON.parse() is CPU intensive
const STARTUP_STAGGER_MS = parseInt(process.env.STARTUP_STAGGER_MS || '500', 10);

if (cluster.isPrimary) {
  console.log(`[Cluster] Primary process ${process.pid} is running`);
  if (workersEnv === 'auto') {
    const memoryNote = `${memoryLimitMB}MB limit, ${memoryPerWorkerMB}MB per worker estimate`;
    if (maxWorkersByMemory < cpuCount) {
      console.log(`[Cluster] Auto worker count limited by memory: ${WORKERS}/${cpuCount} (${memoryNote})`);
    } else {
      console.log(`[Cluster] Auto worker count using CPU cores: ${WORKERS}/${cpuCount} (${memoryNote})`);
    }

    if (useBulkData && memoryLimitMB < memoryPerWorkerMB) {
      console.warn('[Cluster] Memory limit is lower than bulk data recommendations. Consider setting USE_BULK_DATA=false.');
    }
  }
  console.log(`[Cluster] Starting ${WORKERS} worker processes with ${STARTUP_STAGGER_MS}ms stagger delay...`);

  // Track worker status
  const workerStats = new Map();

  // Fork workers with staggered startup to prevent simultaneous JSON parsing
  // First worker decompresses and caches data, subsequent workers use cached uncompressed JSON
  // This prevents 100% CPU usage when all workers try to JSON.parse() simultaneously
  // Delay can be configured via STARTUP_STAGGER_MS environment variable
  for (let i = 0; i < WORKERS; i++) {
    setTimeout(() => {
      const worker = cluster.fork();
      workerStats.set(worker.id, {
        startTime: Date.now(),
        restarts: 0
      });
    }, i * STARTUP_STAGGER_MS);
  }

  // Monitor worker health
  cluster.on('online', (worker) => {
    console.log(`[Cluster] Worker ${worker.id} (PID: ${worker.process.pid}) is online`);
  });

  // Handle worker exits and automatic restart
  cluster.on('exit', (worker, code, signal) => {
    const stats = workerStats.get(worker.id);
    const uptime = Math.floor((Date.now() - stats.startTime) / 1000);
    
    if (signal) {
      console.log(`[Cluster] Worker ${worker.id} was killed by signal: ${signal} (uptime: ${uptime}s)`);
    } else if (code !== 0) {
      console.log(`[Cluster] Worker ${worker.id} exited with error code: ${code} (uptime: ${uptime}s)`);
    } else {
      console.log(`[Cluster] Worker ${worker.id} exited cleanly (uptime: ${uptime}s)`);
    }

    // Restart worker with exponential backoff to prevent crash loops
    stats.restarts++;
    const delay = Math.min(stats.restarts * 1000, 10000); // Max 10s delay
    
    if (stats.restarts > 10) {
      console.error(`[Cluster] Worker ${worker.id} has restarted too many times (${stats.restarts}), not restarting`);
      return;
    }

    console.log(`[Cluster] Restarting worker ${worker.id} in ${delay}ms...`);
    setTimeout(() => {
      const newWorker = cluster.fork();
      workerStats.set(newWorker.id, {
        startTime: Date.now(),
        restarts: stats.restarts
      });
    }, delay);
  });

  // Graceful shutdown handler
  process.on('SIGTERM', () => {
    console.log('[Cluster] Primary received SIGTERM, shutting down workers...');
    for (const id in cluster.workers) {
      cluster.workers[id].process.kill('SIGTERM');
    }
  });

  process.on('SIGINT', () => {
    console.log('[Cluster] Primary received SIGINT, shutting down workers...');
    for (const id in cluster.workers) {
      cluster.workers[id].process.kill('SIGINT');
    }
  });

} else {
  // Worker process - load the actual server
  require('./server.js');
}
