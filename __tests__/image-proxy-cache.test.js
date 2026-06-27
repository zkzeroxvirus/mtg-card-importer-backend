const request = require('supertest');
const fs = require('fs/promises');
const path = require('path');

process.env.NODE_ENV = 'test';
process.env.USE_BULK_DATA = 'false';
process.env.IMAGE_PROXY_CACHE_DIR = path.join(__dirname, '..', 'data', 'image-cache-test');

jest.mock('axios', () => ({
  create: jest.fn(() => ({
    get: jest.fn()
  })),
  get: jest.fn()
}));

const axios = require('axios');

describe('Image Proxy Persistent Cache', () => {
  const imageUrl = 'https://cards.scryfall.io/normal/front/0/0/mock.jpg';

  beforeEach(async () => {
    axios.get.mockReset();
    await fs.rm(process.env.IMAGE_PROXY_CACHE_DIR, { recursive: true, force: true });
    delete require.cache[require.resolve('../server')];
  });

  afterAll(async () => {
    await fs.rm(process.env.IMAGE_PROXY_CACHE_DIR, { recursive: true, force: true });
  });

  test('should serve a cached image from disk after a reload', async () => {
    axios.get.mockResolvedValueOnce({
      data: Buffer.from('image-bytes'),
      headers: {
        'content-type': 'image/jpeg',
        'last-modified': 'Mon, 01 Jan 2024 00:00:00 GMT'
      }
    });

    const firstApp = require('../server');
    const firstResponse = await request(firstApp)
      .get('/image-proxy')
      .query({ url: imageUrl });

    expect(firstResponse.status).toBe(200);
    expect(firstResponse.body.toString('utf8')).toBe('image-bytes');
    expect(axios.get).toHaveBeenCalledTimes(1);

    axios.get.mockClear();
    delete require.cache[require.resolve('../server')];

    const secondApp = require('../server');
    const secondResponse = await request(secondApp)
      .get('/image-proxy')
      .query({ url: imageUrl });

    expect(secondResponse.status).toBe(200);
    expect(secondResponse.body.toString('utf8')).toBe('image-bytes');
    expect(axios.get).not.toHaveBeenCalled();
  });
});