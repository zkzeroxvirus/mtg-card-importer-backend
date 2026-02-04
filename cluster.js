const cluster = require('cluster');
const os = require('os');

/**
 * Cluster management for horizontal scaling across CPU cores
 * Supports high concurrency by running multiple worker processes
 */

// Configuration: Use environment variable or default to CPU count
const workersEnv = process.env.WORKERS || 'auto';
const WORKERS = workersEnv === 'auto' ? os.cpus().length : parseInt(workersEnv, 10);

if (cluster.isPrimary) {
  console.log(`[Cluster] Primary process ${process.pid} is running`);
  console.log(`[Cluster] Starting ${WORKERS} worker processes...`);

  // Track worker status
  const workerStats = new Map();

  // Fork workers
  for (let i = 0; i < WORKERS; i++) {
    const worker = cluster.fork();
    workerStats.set(worker.id, {
      startTime: Date.now(),
      restarts: 0
    });
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
