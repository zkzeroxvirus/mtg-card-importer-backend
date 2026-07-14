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

  test('should cache upstream 404 image misses in memory', async () => {
    const missingImageUrl = 'https://cards.scryfall.io/normal/front/0/0/missing.jpg';
    axios.get.mockRejectedValueOnce({
      message: 'Request failed with status code 404',
      response: { status: 404 }
    });

    const app = require('../server');
    const firstResponse = await request(app)
      .get('/image-proxy')
      .query({ url: missingImageUrl });
    const secondResponse = await request(app)
      .get('/image-proxy')
      .query({ url: missingImageUrl });

    expect(firstResponse.status).toBe(404);
    expect(secondResponse.status).toBe(404);
    expect(axios.get).toHaveBeenCalledTimes(1);
  });

  test('should fetch the normal jpg variant for non-normal Scryfall image URLs', async () => {
    const pngImageUrl = 'https://cards.scryfall.io/png/back/4/a/4a1f905f-1d55-4d02-9d24-e58070793d3f.png?1782698306';
    const normalImageUrl = 'https://cards.scryfall.io/normal/back/4/a/4a1f905f-1d55-4d02-9d24-e58070793d3f.jpg?1782698306';

    axios.get.mockResolvedValueOnce({
      data: Buffer.from('normal-image-bytes'),
      headers: {
        'content-type': 'image/jpeg',
        'last-modified': 'Mon, 01 Jan 2024 00:00:00 GMT'
      }
    });

    const app = require('../server');
    const response = await request(app)
      .get('/image-proxy')
      .query({ url: pngImageUrl });

    expect(response.status).toBe(200);
    expect(response.body.toString('utf8')).toBe('normal-image-bytes');
    expect(axios.get).toHaveBeenCalledWith(normalImageUrl, expect.objectContaining({ responseType: 'arraybuffer' }));
  });

  test('should reuse one cache entry for versioned URLs of the same Scryfall image', async () => {
    const firstVersionUrl = 'https://cards.scryfall.io/normal/front/4/a/4a1f905f-1d55-4d02-9d24-e58070793d3f.jpg?111';
    const secondVersionUrl = 'https://cards.scryfall.io/large/front/4/a/4a1f905f-1d55-4d02-9d24-e58070793d3f.jpg?222';

    axios.get.mockResolvedValueOnce({
      data: Buffer.from('shared-image-bytes'),
      headers: {
        'content-type': 'image/jpeg',
        'last-modified': 'Mon, 01 Jan 2024 00:00:00 GMT'
      }
    });

    const app = require('../server');
    const firstResponse = await request(app)
      .get('/image-proxy')
      .query({ url: firstVersionUrl });
    const secondResponse = await request(app)
      .get('/image-proxy')
      .query({ url: secondVersionUrl });
    const cacheFiles = await fs.readdir(process.env.IMAGE_PROXY_CACHE_DIR);

    expect(firstResponse.status).toBe(200);
    expect(secondResponse.status).toBe(200);
    expect(secondResponse.body.toString('utf8')).toBe('shared-image-bytes');
    expect(axios.get).toHaveBeenCalledTimes(1);
    expect(cacheFiles.filter(file => file.endsWith('.bin'))).toHaveLength(1);
    expect(cacheFiles.filter(file => file.endsWith('.json'))).toHaveLength(1);
  });

  test('should add jpg when repairing extensionless Scryfall image URLs', async () => {
    const extensionlessImageUrl = 'https://cards.scryfall.io/png/front/8/7/878b0159-6917-45d3-b9ea-562ac49f0b8f';
    const normalImageUrl = 'https://cards.scryfall.io/normal/front/8/7/878b0159-6917-45d3-b9ea-562ac49f0b8f.jpg';

    axios.get.mockResolvedValueOnce({
      data: Buffer.from('repaired-image-bytes'),
      headers: {
        'content-type': 'image/jpeg',
        'last-modified': 'Mon, 01 Jan 2024 00:00:00 GMT'
      }
    });

    const app = require('../server');
    const response = await request(app)
      .get('/image-proxy')
      .query({ url: extensionlessImageUrl });

    expect(response.status).toBe(200);
    expect(response.body.toString('utf8')).toBe('repaired-image-bytes');
    expect(axios.get).toHaveBeenCalledWith(normalImageUrl, expect.objectContaining({ responseType: 'arraybuffer' }));
  });

  test('should proxy Scryfall-like image paths under the image proxy base', async () => {
    const normalImageUrl = 'https://cards.scryfall.io/normal/front/a/4/a4e86622-6f30-41b2-87d0-d345110e2387.jpg?12345';

    axios.get.mockResolvedValueOnce({
      data: Buffer.from('path-style-image-bytes'),
      headers: {
        'content-type': 'image/jpeg',
        'last-modified': 'Mon, 01 Jan 2024 00:00:00 GMT'
      }
    });

    const app = require('../server');
    const response = await request(app)
      .get('/image-proxy/normal/front/a/4/a4e86622-6f30-41b2-87d0-d345110e2387.jpg?12345');

    expect(response.status).toBe(200);
    expect(response.body.toString('utf8')).toBe('path-style-image-bytes');
    expect(axios.get).toHaveBeenCalledWith(normalImageUrl, expect.objectContaining({ responseType: 'arraybuffer' }));
  });

  test('should recover the current versioned Scryfall image URL when an unversioned image 404s', async () => {
    const unversionedImageUrl = 'https://cards.scryfall.io/normal/front/3/1/3199bea9-fef7-45fe-8777-2103d84a9347.jpg';
    const versionedImageUrl = 'https://cards.scryfall.io/normal/front/3/1/3199bea9-fef7-45fe-8777-2103d84a9347.jpg?1782683974';

    axios.get
      .mockRejectedValueOnce({
        message: 'Request failed with status code 404',
        response: { status: 404 }
      })
      .mockResolvedValueOnce({
        data: {
          image_uris: {
            normal: versionedImageUrl
          }
        },
        headers: {
          'content-type': 'application/json'
        }
      })
      .mockResolvedValueOnce({
        data: Buffer.from('versioned-image-bytes'),
        headers: {
          'content-type': 'image/jpeg',
          'last-modified': 'Mon, 01 Jan 2024 00:00:00 GMT'
        }
      });

    const app = require('../server');
    const response = await request(app)
      .get('/image-proxy/normal/front/3/1/3199bea9-fef7-45fe-8777-2103d84a9347.jpg');

    expect(response.status).toBe(200);
    expect(response.body.toString('utf8')).toBe('versioned-image-bytes');
    expect(axios.get).toHaveBeenNthCalledWith(1, unversionedImageUrl, expect.objectContaining({ responseType: 'arraybuffer' }));
    expect(axios.get).toHaveBeenNthCalledWith(2, 'https://api.scryfall.com/cards/3199bea9-fef7-45fe-8777-2103d84a9347', expect.objectContaining({
      headers: expect.objectContaining({ Accept: 'application/json' })
    }));
    expect(axios.get).toHaveBeenNthCalledWith(3, versionedImageUrl, expect.objectContaining({ responseType: 'arraybuffer' }));
  });
});
