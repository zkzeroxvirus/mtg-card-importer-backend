const { calculateWorkerCount } = require('../lib/cluster-config');

describe('calculateWorkerCount', () => {
  test('respects explicit worker overrides', () => {
    const result = calculateWorkerCount({
      workersEnv: '3',
      cpuCount: 8,
      memoryLimitMB: 512
    });

    expect(result.workers).toBe(3);
    expect(result.workersEnv).toBe('3');
  });

  test('defaults invalid worker values to one', () => {
    const result = calculateWorkerCount({
      workersEnv: '0',
      cpuCount: 4,
      memoryLimitMB: 2048
    });

    expect(result.workers).toBe(1);
  });

  test('caps auto workers by memory in bulk data mode', () => {
    const result = calculateWorkerCount({
      workersEnv: 'auto',
      useBulkData: 'true',
      cpuCount: 6,
      memoryLimitMB: 1600
    });

    expect(result.memoryPerWorkerMB).toBe(700);
    expect(result.maxWorkersByMemory).toBe(2);
    expect(result.workers).toBe(2);
  });

  test('caps auto workers by memory in API mode', () => {
    const result = calculateWorkerCount({
      workersEnv: 'auto',
      useBulkData: 'false',
      cpuCount: 6,
      memoryLimitMB: 450
    });

    expect(result.memoryPerWorkerMB).toBe(200);
    expect(result.maxWorkersByMemory).toBe(2);
    expect(result.workers).toBe(2);
  });
});
