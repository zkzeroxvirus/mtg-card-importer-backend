const fs = require('fs');
const os = require('os');

const DEFAULT_BULK_WORKER_MEMORY_MB = 700;
const DEFAULT_API_WORKER_MEMORY_MB = 200;
const UNLIMITED_MEMORY_THRESHOLD_BYTES = 1e15;

function getCgroupMemoryLimitBytes() {
  const cgroupV2Path = '/sys/fs/cgroup/memory.max';
  const cgroupV1Path = '/sys/fs/cgroup/memory/memory.limit_in_bytes';

  try {
    if (fs.existsSync(cgroupV2Path)) {
      const value = fs.readFileSync(cgroupV2Path, 'utf8').trim();
      if (value && value !== 'max') {
        const parsed = parseInt(value, 10);
        if (Number.isFinite(parsed) && parsed > 0 && parsed < UNLIMITED_MEMORY_THRESHOLD_BYTES) {
          return parsed;
        }
      }
    }

    if (fs.existsSync(cgroupV1Path)) {
      const value = fs.readFileSync(cgroupV1Path, 'utf8').trim();
      const parsed = parseInt(value, 10);
      if (Number.isFinite(parsed) && parsed > 0 && parsed < UNLIMITED_MEMORY_THRESHOLD_BYTES) {
        return parsed;
      }
    }
  } catch (error) {
    console.warn('[Cluster] Failed to read cgroup memory limits:', error.message);
  }

  return null;
}

function getMemoryLimitMB() {
  const limitBytes = getCgroupMemoryLimitBytes();
  const totalBytes = limitBytes || os.totalmem();
  return Math.max(1, Math.floor(totalBytes / 1024 / 1024));
}

function calculateWorkerCount(options = {}) {
  const workersEnv = options.workersEnv ?? process.env.WORKERS ?? 'auto';
  const useBulkData = options.useBulkData ?? process.env.USE_BULK_DATA ?? 'false';
  const cpuCountRaw = options.cpuCount ?? os.cpus().length;
  const cpuCount = cpuCountRaw > 0 ? cpuCountRaw : 1;
  const memoryLimitMB = options.memoryLimitMB ?? getMemoryLimitMB();

  if (workersEnv !== 'auto') {
    const parsed = parseInt(workersEnv, 10);
    const workers = Number.isFinite(parsed) && parsed > 0 ? parsed : 1;
    return {
      workers,
      cpuCount,
      memoryLimitMB,
      memoryPerWorkerMB: null,
      maxWorkersByMemory: null,
      workersEnv,
      useBulkData
    };
  }

  const memoryPerWorkerMB = useBulkData === 'true'
    ? DEFAULT_BULK_WORKER_MEMORY_MB
    : DEFAULT_API_WORKER_MEMORY_MB;
  const maxWorkersByMemory = Math.max(1, Math.floor(memoryLimitMB / memoryPerWorkerMB));
  const workers = Math.max(1, Math.min(cpuCount, maxWorkersByMemory));

  return {
    workers,
    cpuCount,
    memoryLimitMB,
    memoryPerWorkerMB,
    maxWorkersByMemory,
    workersEnv,
    useBulkData
  };
}

module.exports = {
  calculateWorkerCount,
  getMemoryLimitMB
};
