import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MediaCache } from '../src/lib/media-cache.ts';

test('media cache coalesces concurrent requests, enforces byte budget, and revokes on release/clear', async () => {
  let fetches = 0;
  let seq = 0;
  const revoked = [];
  const cache = new MediaCache({
    maxBytes: 10,
    origin: () => 'https://sync.example.com',
    fetcher: async (_token, path) => {
      fetches += 1;
      await new Promise((r) => setTimeout(r, 10));
      return new Blob([path.endsWith('/a') ? '123456' : '789012']);
    },
    createObjectURL: () => `blob:test-${++seq}`,
    revokeObjectURL: (url) => revoked.push(url),
  });

  const [h1, h2] = await Promise.all([
    cache.acquire('tok1', '/messages/1/a'),
    cache.acquire('tok1', '/messages/1/a'),
  ]);
  assert.equal(fetches, 1);
  assert.equal(h1.url, h2.url);
  assert.equal(cache.bytes, 6);

  // Acquiring /b (6 bytes) exceeds 10 byte budget and evicts /a, but /a stays unrevoked until refs hit 0!
  const hb = await cache.acquire('tok1', '/messages/2/b');
  assert.equal(cache.size, 1);
  assert.equal(cache.bytes, 6);
  assert.deepEqual(revoked, []);

  h1.release();
  assert.deepEqual(revoked, []);
  h2.release();
  assert.deepEqual(revoked, [h1.url]);

  // Token isolation: different token does not hit tok1's cache.
  const hb2 = await cache.acquire('tok2', '/messages/2/b');
  assert.notEqual(hb2.url, hb.url);
  assert.equal(fetches, 3);

  hb.release();
  hb2.release();
  cache.clear();
  assert.equal(cache.size, 0);
  assert.equal(cache.bytes, 0);
  assert.ok(revoked.includes(hb.url));
  assert.ok(revoked.includes(hb2.url));
});
