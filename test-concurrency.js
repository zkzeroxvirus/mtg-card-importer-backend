#!/usr/bin/env node

/**
 * Simple concurrency test to demonstrate server capabilities
 */

const http = require('http');

const PORT = process.env.PORT || 3001;
const CONCURRENT_REQUESTS = 50;

function makeRequest(path) {
  return new Promise((resolve, reject) => {
    const startTime = Date.now();
    
    const req = http.get(`http://localhost:${PORT}${path}`, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const latency = Date.now() - startTime;
        resolve({ statusCode: res.statusCode, latency, success: res.statusCode === 200 });
      });
    });
    
    req.on('error', (error) => {
      reject(error);
    });
    
    req.setTimeout(5000, () => {
      req.destroy();
      reject(new Error('Timeout'));
    });
  });
}

async function runTest() {
  console.log('Testing concurrent request handling...');
  console.log(`Making ${CONCURRENT_REQUESTS} concurrent requests to health check endpoint`);
  
  const startTime = Date.now();
  const requests = [];
  
  for (let i = 0; i < CONCURRENT_REQUESTS; i++) {
    requests.push(
      makeRequest('/')
        .catch(error => ({ success: false, error: error.message, latency: 0 }))
    );
  }
  
  const results = await Promise.all(requests);
  const duration = (Date.now() - startTime) / 1000;
  
  const successful = results.filter(r => r.success).length;
  const failed = results.filter(r => !r.success).length;
  const avgLatency = results.reduce((sum, r) => sum + r.latency, 0) / results.length;
  const throughput = results.length / duration;
  
  console.log('\nResults:');
  console.log(`Duration: ${duration.toFixed(2)}s`);
  console.log(`Successful: ${successful}/${results.length}`);
  console.log(`Failed: ${failed}`);
  console.log(`Average Latency: ${avgLatency.toFixed(2)}ms`);
  console.log(`Throughput: ${throughput.toFixed(2)} req/s`);
  
  if (successful >= results.length * 0.95) {
    console.log('\n✓ Test passed (95%+ success rate)');
    process.exit(0);
  } else {
    console.log('\n✗ Test failed (below 95% success rate)');
    process.exit(1);
  }
}

runTest();
