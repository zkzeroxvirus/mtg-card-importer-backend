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

async function listCacheFiles(directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const entryPath = path.join(directory, entry.name);
    return entry.isDirectory() ? listCacheFiles(entryPath) : [entryPath];
  }));
  return nested.flat();
}

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

  test('should write new cache entries into two-level shard directories', async () => {
    const shardedImageUrl = 'https://cards.scryfall.io/normal/front/1/1/sharded.jpg';
    axios.get.mockResolvedValueOnce({
      data: Buffer.from('sharded-image-bytes'),
      headers: { 'content-type': 'image/jpeg' }
    });

    const app = require('../server');
    const response = await request(app).get('/image-proxy').query({ url: shardedImageUrl });
    const cacheFiles = await listCacheFiles(process.env.IMAGE_PROXY_CACHE_DIR);
    const relativeFiles = cacheFiles.map(file => path.relative(process.env.IMAGE_PROXY_CACHE_DIR, file));

    expect(response.status).toBe(200);
    expect(relativeFiles).toHaveLength(2);
    expect(relativeFiles.every(file => /^[0-9a-f]{2}[\\/][0-9a-f]{2}[\\/][0-9a-f]{64}\.(bin|json)$/i.test(file))).toBe(true);
  });

  test('should collect and normalize unique front and back image URLs from bulk cards', () => {
    const app = require('../server');
    const frontNormal = 'https://cards.scryfall.io/normal/front/4/a/4a1f905f-1d55-4d02-9d24-e58070793d3f.jpg?111';
    const frontLarge = 'https://cards.scryfall.io/large/front/4/a/4a1f905f-1d55-4d02-9d24-e58070793d3f.jpg?111';
    const backPng = 'https://cards.scryfall.io/png/back/8/7/878b0159-6917-45d3-b9ea-562ac49f0b8f.png?222';

    const urls = app.locals.imageCacheWarmer.collectBulkImageUrls([
      { image_uris: { normal: frontNormal } },
      {
        card_faces: [
          { image_uris: { large: frontLarge } },
          { image_uris: { png: backPng } }
        ]
      },
      { image_uris: { normal: 'https://example.com/not-scryfall.jpg' } }
    ]);

    expect(urls).toEqual([
      frontNormal,
      'https://cards.scryfall.io/normal/back/8/7/878b0159-6917-45d3-b9ea-562ac49f0b8f.jpg?222'
    ]);
  });

  test('should serve and lazily migrate legacy flat cache entries', async () => {
    const crypto = require('crypto');
    const legacyImageUrl = 'https://cards.scryfall.io/normal/front/2/2/legacy.jpg';
    const cacheIdentity = legacyImageUrl;
    const cacheKey = crypto.createHash('sha256').update(cacheIdentity).digest('hex');
    await fs.mkdir(process.env.IMAGE_PROXY_CACHE_DIR, { recursive: true });
    await Promise.all([
      fs.writeFile(path.join(process.env.IMAGE_PROXY_CACHE_DIR, `${cacheKey}.bin`), Buffer.from('legacy-image-bytes')),
      fs.writeFile(path.join(process.env.IMAGE_PROXY_CACHE_DIR, `${cacheKey}.json`), JSON.stringify({
        contentType: 'image/jpeg',
        sourceUrl: legacyImageUrl
      }))
    ]);

    const app = require('../server');
    const response = await request(app).get('/image-proxy').query({ url: legacyImageUrl });

    expect(response.status).toBe(200);
    expect(response.body.toString('utf8')).toBe('legacy-image-bytes');
    expect(axios.get).not.toHaveBeenCalled();

    const shardedBin = path.join(process.env.IMAGE_PROXY_CACHE_DIR, cacheKey.slice(0, 2), cacheKey.slice(2, 4), `${cacheKey}.bin`);
    let migratedBuffer = null;
    for (let attempt = 0; attempt < 50; attempt += 1) {
      try {
        migratedBuffer = await fs.readFile(shardedBin);
        break;
      } catch {
        await new Promise(resolve => setTimeout(resolve, 10));
      }
    }
    expect(migratedBuffer?.toString('utf8')).toBe('legacy-image-bytes');
    await expect(fs.access(path.join(process.env.IMAGE_PROXY_CACHE_DIR, `${cacheKey}.bin`))).rejects.toThrow();
  });

  test('should deduplicate concurrent legacy migrations for the same cache key', async () => {
    const concurrentUrl = 'https://cards.scryfall.io/normal/front/3/3/concurrent-legacy.jpg';
    const app = require('../server');
    const paths = app.locals.imageProxyCache.getPaths(concurrentUrl);
    const legacyBuffer = Buffer.from('concurrent-legacy-bytes');
    await fs.mkdir(process.env.IMAGE_PROXY_CACHE_DIR, { recursive: true });
    await Promise.all([
      fs.writeFile(paths.legacyFilePath, legacyBuffer),
      fs.writeFile(paths.legacyMetaPath, JSON.stringify({ contentType: 'image/jpeg' }))
    ]);

    const entry = {
      buffer: legacyBuffer,
      contentType: 'image/jpeg',
      etag: 'legacy-etag',
      lastModified: 'Mon, 01 Jan 2024 00:00:00 GMT'
    };
    await Promise.all([
      app.locals.imageProxyCache.migrateLegacyEntry(concurrentUrl, entry, {
        filePath: paths.legacyFilePath,
        metaPath: paths.legacyMetaPath
      }),
      app.locals.imageProxyCache.migrateLegacyEntry(concurrentUrl, entry, {
        filePath: paths.legacyFilePath,
        metaPath: paths.legacyMetaPath
      })
    ]);

    await expect(fs.readFile(paths.filePath)).resolves.toEqual(legacyBuffer);
    await expect(fs.access(paths.legacyFilePath)).rejects.toThrow();
    const cacheFiles = await listCacheFiles(process.env.IMAGE_PROXY_CACHE_DIR);
    expect(cacheFiles.filter(file => file.endsWith('.tmp'))).toHaveLength(0);
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
    const cacheFiles = await listCacheFiles(process.env.IMAGE_PROXY_CACHE_DIR);

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
