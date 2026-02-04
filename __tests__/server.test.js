const request = require('supertest');

// Mock environment variables before requiring the server
process.env.NODE_ENV = 'test';
process.env.DEFAULT_CARD_BACK = 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/';
process.env.USE_BULK_DATA = 'false';

const app = require('../server');

describe('Server Health Check', () => {
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
});
