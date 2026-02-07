/**
 * Integration tests for server endpoints
 * Tests API endpoints, error handling, and validation
 */

const request = require('supertest');

// Mock environment variables before requiring the server
process.env.NODE_ENV = 'test';
process.env.DEFAULT_CARD_BACK = 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';
process.env.USE_BULK_DATA = 'false';

const app = require('../server');

describe('Server Endpoints - Health Check', () => {
  test('GET / should return 200 status', async () => {
    const response = await request(app).get('/');
    expect(response.status).toBe(200);
  });

  test('GET / should return JSON', async () => {
    const response = await request(app).get('/');
    expect(response.type).toBe('application/json');
  });

  test('GET / should return service status', async () => {
    const response = await request(app).get('/');
    expect(response.body).toHaveProperty('service');
    expect(response.body.service).toBe('MTG Card Importer Backend');
  });

  test('GET / should include endpoints information', async () => {
    const response = await request(app).get('/');
    expect(response.body).toHaveProperty('endpoints');
    expect(Array.isArray(response.body.endpoints)).toBe(true);
  });

  test('GET / should include configuration', async () => {
    const response = await request(app).get('/');
    expect(response.body).toHaveProperty('config');
    expect(response.body.config).toHaveProperty('useBulkData');
  });
});

describe('Server Endpoints - Input Validation', () => {
  test('should reject card names that are too long', async () => {
    const longName = 'a'.repeat(201);
    const response = await request(app).get(`/card/${longName}`);
    expect(response.status).toBe(400);
  });

  test('should reject search queries that are too long', async () => {
    const longQuery = 'a'.repeat(1001);
    const response = await request(app).get('/search').query({ q: longQuery });
    expect(response.status).toBe(400);
  });

  test('should reject invalid card back URLs', async () => {
    const response = await request(app)
      .post('/deck')
      .send({
        decklist: '1 Mountain',
        back: 'http://malicious-site.com/image.jpg'
      });
    expect(response.status).toBe(400);
    expect(response.body.details).toContain('Invalid card back URL');
  });

  test('should accept valid Steam CDN card back URLs', async () => {
    const response = await request(app)
      .post('/deck')
      .send({
        decklist: '1 Mountain',
        back: 'https://steamusercontent-a.akamaihd.net/ugc/123/image.jpg'
      });
    // May return 404 or other error from API, but not 400 validation error
    expect(response.status).not.toBe(400);
  });

  test('should accept valid Imgur card back URLs', async () => {
    const response = await request(app)
      .post('/deck')
      .send({
        decklist: '1 Mountain',
        back: 'https://i.imgur.com/abc123.jpg'
      });
    // May return 404 or other error from API, but not 400 validation error
    expect(response.status).not.toBe(400);
  });
});

describe('Server Endpoints - Error Responses', () => {
  test('should return 404 for unknown endpoint', async () => {
    const response = await request(app).get('/nonexistent-endpoint');
    expect(response.status).toBe(404);
  });

  test('should return JSON error format', async () => {
    const response = await request(app).get('/nonexistent-endpoint');
    expect(response.type).toBe('application/json');
    expect(response.body).toHaveProperty('error');
  });
});

describe('Server Endpoints - CORS', () => {
  test('should include CORS headers', async () => {
    const response = await request(app).get('/');
    expect(response.headers).toHaveProperty('access-control-allow-origin');
  });
});

describe('Server Endpoints - Deck Building', () => {
  test('POST /deck should require decklist', async () => {
    const response = await request(app)
      .post('/deck')
      .send({});
    expect(response.status).toBe(400);
  });

  test('POST /deck should accept valid decklist', async () => {
    const response = await request(app)
      .post('/deck')
      .send({
        decklist: '1 Mountain\n1 Forest'
      });
    // Should not be a validation error (400)
    // May be 404 or other errors from API
    expect(response.status).not.toBe(400);
  });

  test('POST /deck/parse should parse decklist format', async () => {
    const response = await request(app)
      .post('/deck/parse')
      .send({
        decklist: '4 Lightning Bolt\n2 Mountain'
      });
    // Should not be a validation error
    expect(response.status).not.toBe(400);
    expect(response.body.detected_format).toBe('decklist_json');
    expect(response.body.mainboard_count).toBeGreaterThan(0);
  });
});

describe('Server Endpoints - Random Card', () => {
  test('GET /random should accept count parameter', async () => {
    const response = await request(app)
      .get('/random')
      .query({ count: 3 });
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /random should accept query parameter', async () => {
    const response = await request(app)
      .get('/random')
      .query({ q: 't:creature' });
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /random should reject count over limit', async () => {
    const response = await request(app)
      .get('/random')
      .query({ count: 101 });
    expect(response.status).toBe(400);
  });

  test('GET /random should reject negative count', async () => {
    const response = await request(app)
      .get('/random')
      .query({ count: -1 });
    expect(response.status).toBe(400);
  });
});

describe('Server Endpoints - Search', () => {
  test('GET /search should require query parameter', async () => {
    const response = await request(app).get('/search');
    expect(response.status).toBe(400);
  });

  test('GET /search should accept valid query', async () => {
    const response = await request(app)
      .get('/search')
      .query({ q: 't:creature' });
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /search should accept limit parameter', async () => {
    const response = await request(app)
      .get('/search')
      .query({ q: 't:creature', limit: 10 });
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /search should reject limit over 175', async () => {
    const response = await request(app)
      .get('/search')
      .query({ q: 't:creature', limit: 200 });
    expect(response.status).toBe(400);
  });
});

describe('Server Endpoints - Card Lookup', () => {
  test('GET /card/:name should accept card name', async () => {
    const response = await request(app).get('/card/Mountain');
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /card/:name should accept set parameter', async () => {
    const response = await request(app)
      .get('/card/Mountain')
      .query({ set: 'dom' });
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /cards/:id should accept card ID', async () => {
    const response = await request(app).get('/cards/some-scryfall-id');
    // Should not be a validation error (may be 404 from API)
    expect(response.status).not.toBe(400);
  });

  test('GET /cards/:set/:number should accept set and number', async () => {
    const response = await request(app).get('/cards/dom/123');
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /cards/:set/:number/:lang should accept language', async () => {
    const response = await request(app).get('/cards/dom/123/en');
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });
});

describe('Server Endpoints - Rulings and Tokens', () => {
  test('GET /rulings/:name should accept card name', async () => {
    const response = await request(app).get('/rulings/Mountain');
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /tokens/:name should accept card name', async () => {
    const response = await request(app).get('/tokens/treasure');
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /printings/:name should accept card name', async () => {
    const response = await request(app).get('/printings/Mountain');
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });
});

describe('Server Endpoints - Sets', () => {
  test('GET /sets/:code should accept set code', async () => {
    const response = await request(app).get('/sets/dom');
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /sets/:code should reject invalid set codes', async () => {
    const response = await request(app).get('/sets/invalid-set-code-12345');
    // Should be a validation error or 404
    expect([400, 404]).toContain(response.status);
  });
});

describe('Server Endpoints - Bulk Data', () => {
  test('GET /bulk/stats should return statistics', async () => {
    const response = await request(app).get('/bulk/stats');
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('loaded');
  });

  test('POST /bulk/reload should trigger reload', async () => {
    const response = await request(app).post('/bulk/reload');
    // Should accept the request (may succeed or fail based on config)
    expect([200, 400, 503]).toContain(response.status);
  });
});

describe('Server Endpoints - Proxy', () => {
  test('GET /proxy should require uri parameter', async () => {
    const response = await request(app).get('/proxy');
    expect(response.status).toBe(400);
  });

  test('GET /proxy should accept valid Scryfall URI', async () => {
    const uri = 'https://api.scryfall.com/cards/some-id';
    const response = await request(app)
      .get('/proxy')
      .query({ uri: uri });
    // Should not be a validation error
    expect(response.status).not.toBe(400);
  });

  test('GET /proxy should reject non-Scryfall URIs', async () => {
    const response = await request(app)
      .get('/proxy')
      .query({ uri: 'https://evil-site.com/api' });
    expect(response.status).toBe(400);
  });
});

describe('Server Endpoints - Security', () => {
  test('should reject potential XSS in card names', async () => {
    const response = await request(app).get('/card/<script>alert("xss")</script>');
    // Should either reject or safely handle
    expect(response.status).not.toBe(200);
  });

  test('should reject SQL injection attempts in search', async () => {
    const response = await request(app)
      .get('/search')
      .query({ q: "'; DROP TABLE cards; --" });
    // Should not cause server error
    expect(response.status).not.toBe(500);
  });

  test('should reject path traversal attempts', async () => {
    const response = await request(app).get('/card/../../../etc/passwd');
    // Should not expose file system
    expect(response.status).not.toBe(200);
  });
});

describe('Server Endpoints - Content Type', () => {
  test('POST endpoints should accept JSON', async () => {
    const response = await request(app)
      .post('/deck')
      .set('Content-Type', 'application/json')
      .send({
        decklist: '1 Mountain'
      });
    // Should not reject based on content type
    expect(response.status).not.toBe(415);
  });

  test('POST endpoints should reject invalid JSON', async () => {
    const response = await request(app)
      .post('/deck')
      .set('Content-Type', 'application/json')
      .send('{ invalid json }');
    expect(response.status).toBe(400);
  });
});
