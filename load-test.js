#!/usr/bin/env node

/**
 * Load Testing Script for MTG Card Importer Backend
 * Tests server capacity for handling 500+ concurrent users
 */

const http = require('http');
const https = require('https');

const BASE_URL = process.env.TEST_URL || 'http://localhost:3000';
const CONCURRENT_USERS = parseInt(process.env.CONCURRENT_USERS || '500', 10);
const REQUESTS_PER_USER = parseInt(process.env.REQUESTS_PER_USER || '5', 10);
const RAMP_UP_TIME = parseInt(process.env.RAMP_UP_TIME || '10000', 10); // 10 seconds

// Test scenarios mimicking real user behavior
const TEST_SCENARIOS = [
  { name: 'Single Card Lookup', path: '/card/Lightning%20Bolt' },
  { name: 'Card by ID', path: '/cards/f7cbb6c3-c0a8-4fbf-8066-5dc8ef37e5b9' },
  { name: 'Random Card', path: '/random' },
  { name: 'Search Cards', path: '/search?q=t:creature+c:red' },
  { name: 'Card Rulings', path: '/rulings/Black%20Lotus' },
  { name: 'Card Printings', path: '/printings/Lightning%20Bolt' },
  { 
    name: 'Build Small Deck', 
    path: '/deck/parse',
    method: 'POST',
    body: '4 Lightning Bolt\n4 Counterspell\n4 Brainstorm\n'
  },
];

// Statistics tracking
const stats = {
  totalRequests: 0,
  successfulRequests: 0,
  failedRequests: 0,
  totalLatency: 0,
  minLatency: Infinity,
  maxLatency: 0,
  statusCodes: {},
  errors: {},
  startTime: 0,
  endTime: 0
};

function makeRequest(scenario) {
  return new Promise((resolve) => {
    const startTime = Date.now();
    const url = new URL(BASE_URL + scenario.path);
    const isHttps = url.protocol === 'https:';
    const client = isHttps ? https : http;

    const options = {
      hostname: url.hostname,
      port: url.port || (isHttps ? 443 : 80),
      path: url.pathname + url.search,
      method: scenario.method || 'GET',
      headers: {
        'User-Agent': 'LoadTest/1.0',
        'Accept': 'application/json'
      },
      timeout: 30000 // 30 second timeout
    };

    if (scenario.body) {
      options.headers['Content-Type'] = 'text/plain';
      options.headers['Content-Length'] = Buffer.byteLength(scenario.body);
    }

    const req = client.request(options, (res) => {
      res.on('data', () => {});

      res.on('end', () => {
        const latency = Date.now() - startTime;
        stats.totalRequests++;
        stats.totalLatency += latency;
        stats.minLatency = Math.min(stats.minLatency, latency);
        stats.maxLatency = Math.max(stats.maxLatency, latency);

        const statusCode = res.statusCode;
        stats.statusCodes[statusCode] = (stats.statusCodes[statusCode] || 0) + 1;

        if (statusCode >= 200 && statusCode < 400) {
          stats.successfulRequests++;
        } else {
          stats.failedRequests++;
        }

        resolve({ success: true, latency, statusCode });
      });
    });

    req.on('error', (error) => {
      const latency = Date.now() - startTime;
      stats.totalRequests++;
      stats.failedRequests++;
      stats.totalLatency += latency;
      
      const errorType = error.code || 'UNKNOWN_ERROR';
      stats.errors[errorType] = (stats.errors[errorType] || 0) + 1;

      resolve({ success: false, latency, error: errorType });
    });

    req.on('timeout', () => {
      req.destroy();
      const latency = Date.now() - startTime;
      stats.totalRequests++;
      stats.failedRequests++;
      stats.totalLatency += latency;
      stats.errors['TIMEOUT'] = (stats.errors['TIMEOUT'] || 0) + 1;
      
      resolve({ success: false, latency, error: 'TIMEOUT' });
    });

    if (scenario.body) {
      req.write(scenario.body);
    }

    req.end();
  });
}

async function simulateUser(userId, delayMs) {
  // Stagger user start times to simulate gradual ramp-up
  await new Promise(resolve => setTimeout(resolve, delayMs));

  const userRequests = [];
  
  for (let i = 0; i < REQUESTS_PER_USER; i++) {
    // Pick a random scenario
    const scenario = TEST_SCENARIOS[Math.floor(Math.random() * TEST_SCENARIOS.length)];
    userRequests.push(makeRequest(scenario));
    
    // Small delay between requests from same user (realistic behavior)
    if (i < REQUESTS_PER_USER - 1) {
      await new Promise(resolve => setTimeout(resolve, 100 + Math.random() * 200));
    }
  }

  return Promise.all(userRequests);
}

async function runLoadTest() {
  console.log('='.repeat(70));
  console.log('MTG Card Importer Backend - Load Test');
  console.log('='.repeat(70));
  console.log(`Target URL: ${BASE_URL}`);
  console.log(`Concurrent Users: ${CONCURRENT_USERS}`);
  console.log(`Requests per User: ${REQUESTS_PER_USER}`);
  console.log(`Total Expected Requests: ${CONCURRENT_USERS * REQUESTS_PER_USER}`);
  console.log(`Ramp-up Time: ${RAMP_UP_TIME}ms`);
  console.log('='.repeat(70));
  console.log('');

  // Check server health before starting
  console.log('Checking server health...');
  try {
    await makeRequest({ path: '/' });
    console.log('✓ Server is responding\n');
  } catch (error) {
    console.error('✗ Server is not responding. Please start the server first.', error.message);
    process.exit(1);
  }

  stats.startTime = Date.now();
  console.log('Starting load test...\n');

  // Create all user simulations with staggered start times
  const users = [];
  const delayPerUser = RAMP_UP_TIME / CONCURRENT_USERS;
  
  for (let i = 0; i < CONCURRENT_USERS; i++) {
    users.push(simulateUser(i + 1, i * delayPerUser));
    
    // Progress indicator every 100 users
    if ((i + 1) % 100 === 0) {
      console.log(`Started ${i + 1}/${CONCURRENT_USERS} users...`);
    }
  }

  // Wait for all users to complete
  await Promise.all(users);
  stats.endTime = Date.now();

  // Display results
  console.log('\n' + '='.repeat(70));
  console.log('Load Test Results');
  console.log('='.repeat(70));
  
  const duration = (stats.endTime - stats.startTime) / 1000;
  const avgLatency = stats.totalRequests > 0 ? stats.totalLatency / stats.totalRequests : 0;
  const successRate = stats.totalRequests > 0 ? (stats.successfulRequests / stats.totalRequests * 100) : 0;
  const throughput = stats.totalRequests / duration;

  console.log(`\nDuration: ${duration.toFixed(2)}s`);
  console.log(`Total Requests: ${stats.totalRequests}`);
  console.log(`Successful: ${stats.successfulRequests} (${successRate.toFixed(2)}%)`);
  console.log(`Failed: ${stats.failedRequests}`);
  console.log(`\nLatency:`);
  console.log(`  Average: ${avgLatency.toFixed(2)}ms`);
  console.log(`  Min: ${stats.minLatency === Infinity ? 'N/A' : stats.minLatency + 'ms'}`);
  console.log(`  Max: ${stats.maxLatency}ms`);
  console.log(`\nThroughput: ${throughput.toFixed(2)} req/s`);

  console.log(`\nStatus Codes:`);
  Object.keys(stats.statusCodes).sort().forEach(code => {
    console.log(`  ${code}: ${stats.statusCodes[code]}`);
  });

  if (Object.keys(stats.errors).length > 0) {
    console.log(`\nErrors:`);
    Object.keys(stats.errors).forEach(error => {
      console.log(`  ${error}: ${stats.errors[error]}`);
    });
  }

  console.log('\n' + '='.repeat(70));
  
  // Determine if test passed
  const PASS_THRESHOLD = 95; // 95% success rate
  const passed = successRate >= PASS_THRESHOLD;
  
  if (passed) {
    console.log(`✓ PASS - Success rate ${successRate.toFixed(2)}% meets threshold (${PASS_THRESHOLD}%)`);
    process.exit(0);
  } else {
    console.log(`✗ FAIL - Success rate ${successRate.toFixed(2)}% below threshold (${PASS_THRESHOLD}%)`);
    process.exit(1);
  }
}

// Run the load test
runLoadTest().catch(error => {
  console.error('Load test failed:', error);
  process.exit(1);
});
