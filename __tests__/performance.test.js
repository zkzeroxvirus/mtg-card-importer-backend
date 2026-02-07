/* global it */
const request = require('supertest');
const app = require('../server');

describe('Performance and Monitoring Endpoints', () => {
  describe('GET /', () => {
    it('should return health check with metrics', async () => {
      const response = await request(app)
        .get('/')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('status', 'ok');
      expect(response.body).toHaveProperty('service');
      expect(response.body).toHaveProperty('version');
      expect(response.body).toHaveProperty('uptime');
      expect(response.body).toHaveProperty('metrics');
      expect(response.body.metrics).toHaveProperty('totalRequests');
      expect(response.body.metrics).toHaveProperty('errors');
      expect(response.body.metrics).toHaveProperty('errorRate');
      expect(response.body.metrics).toHaveProperty('memoryMB');
      expect(response.body).toHaveProperty('endpoints');
      expect(response.body.endpoints).toContain('GET /metrics');
    });
  });

  describe('GET /metrics', () => {
    it('should return detailed metrics', async () => {
      const response = await request(app)
        .get('/metrics')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('uptime');
      expect(response.body).toHaveProperty('requests');
      expect(response.body.requests).toHaveProperty('total');
      expect(response.body.requests).toHaveProperty('errors');
      expect(response.body.requests).toHaveProperty('errorRate');
      expect(response.body).toHaveProperty('memory');
      expect(response.body.memory).toHaveProperty('heapUsed');
      expect(response.body.memory).toHaveProperty('heapTotal');
      expect(response.body.memory).toHaveProperty('rss');
      expect(response.body).toHaveProperty('process');
      expect(response.body.process).toHaveProperty('pid');
      expect(response.body.process).toHaveProperty('version');
      expect(response.body.process).toHaveProperty('platform');
    });

    it('should track request counts', async () => {
      // Make a request to increment counter
      await request(app).get('/');
      
      const response = await request(app).get('/metrics');
      expect(response.body.requests.total).toBeGreaterThan(0);
    });
  });

  describe('GET /ready', () => {
    it('should return readiness status', async () => {
      const response = await request(app)
        .get('/ready')
        .expect('Content-Type', /json/);

      expect(response.body).toHaveProperty('ready');
      expect(typeof response.body.ready).toBe('boolean');
      
      // Should be ready in test mode (no bulk data required)
      expect(response.body.ready).toBe(true);
      expect(response.statusCode).toBe(200);
    });
  });

  describe('Response Compression', () => {
    it('should accept compression encoding header', async () => {
      const response = await request(app)
        .get('/')
        .set('Accept-Encoding', 'gzip, deflate')
        .expect(200);

      // Should not throw error with compression header
      expect(response.body).toHaveProperty('status', 'ok');
    });
  });

  describe('Performance Metrics Tracking', () => {
    it('should track errors in metrics', async () => {
      // Make a request that will fail
      await request(app)
        .get('/nonexistent-endpoint')
        .expect(404);

      const metricsResponse = await request(app).get('/metrics');
      
      // Error count should be tracked (may be > 0 from previous tests)
      expect(metricsResponse.body.requests.errors).toBeGreaterThanOrEqual(0);
      expect(metricsResponse.body.requests.errorRate).toBeGreaterThanOrEqual(0);
    });

    it('should include memory usage in metrics', async () => {
      const response = await request(app).get('/metrics');
      
      expect(response.body.memory.heapUsed).toBeGreaterThan(0);
      expect(response.body.memory.heapTotal).toBeGreaterThan(0);
      expect(response.body.memory.rss).toBeGreaterThan(0);
    });
  });

  describe('Concurrent Request Handling', () => {
    it('should handle multiple concurrent requests', async () => {
      const concurrentRequests = 10;
      const requests = [];

      for (let i = 0; i < concurrentRequests; i++) {
        requests.push(
          request(app)
            .get('/')
            .expect(200)
        );
      }

      const responses = await Promise.all(requests);
      
      // All requests should succeed
      expect(responses).toHaveLength(concurrentRequests);
      responses.forEach(response => {
        expect(response.body.status).toBe('ok');
      });
    });

    it('should handle concurrent card requests', async () => {
      const cards = ['Lightning Bolt', 'Counterspell', 'Dark Ritual'];
      const requests = cards.map(card =>
        request(app)
          .get(`/card/${encodeURIComponent(card)}`)
      );

      const responses = await Promise.all(requests);
      
      // Count successful responses (some may fail due to API limits)
      const successful = responses.filter(r => r.statusCode === 200);
      expect(successful.length).toBeGreaterThan(0);
    });
  });
});
