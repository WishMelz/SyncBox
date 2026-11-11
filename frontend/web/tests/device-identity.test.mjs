import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cachedDeviceId, cacheDeviceId, deviceFingerprint } from '../src/lib/device-identity.ts';

function environment(overrides = {}) {
  for (const [key, value] of Object.entries({
    navigator: {
      platform: 'MacIntel',
      userAgent: 'Mozilla/5.0 Chrome/142.0.0.0 Safari/537.36',
      languages: ['zh-CN', 'en'],
      maxTouchPoints: 0,
      hardwareConcurrency: 8,
    },
    screen: { width: 1920, height: 1080, colorDepth: 24 },
    document: { createElement: () => ({ getContext: () => null }) },
    localStorage: { getItem: () => null, setItem: () => {} },
    ...overrides,
  }))
    Object.defineProperty(globalThis, key, { configurable: true, value });
}

test('fingerprint survives empty/private storage, browser version, zoom and screen rotation', () => {
  environment();
  const first = deviceFingerprint();
  environment({
    navigator: {
      ...navigator,
      userAgent: 'Mozilla/5.0 Chrome/143.0.1.0 Safari/537.36',
      languages: ['zh-CN'],
    },
    screen: { width: 1080, height: 1920, colorDepth: 24 },
    localStorage: {
      getItem: () => {
        throw Error('blocked');
      },
      setItem: () => {
        throw Error('blocked');
      },
    },
    innerWidth: 800,
    devicePixelRatio: 2,
  });
  assert.equal(deviceFingerprint(), first);
  assert.equal(cachedDeviceId('owner'), undefined);
  assert.doesNotThrow(() => cacheDeviceId('owner', 'device-id'));
});

test('different browser families and observable hardware produce different fingerprints', () => {
  environment();
  const first = deviceFingerprint();
  environment({ navigator: { ...navigator, userAgent: 'Mozilla/5.0 Firefox/145.0' } });
  assert.notEqual(deviceFingerprint(), first);
  environment({ navigator: { ...navigator, hardwareConcurrency: 16 } });
  assert.notEqual(deviceFingerprint(), first);
});

test('WebGL renderer is included, bounded, and its context is released', () => {
  let released = false;
  environment({
    document: {
      createElement: () => ({
        getContext: () => ({
          getExtension: (name) =>
            name === 'WEBGL_debug_renderer_info'
              ? { UNMASKED_VENDOR_WEBGL: 1, UNMASKED_RENDERER_WEBGL: 2 }
              : {
                  loseContext: () => {
                    released = true;
                  },
                },
          getParameter: (key) => (key === 1 ? 'Vendor' : 'GPU'.repeat(300)),
        }),
      }),
    },
  });
  const fingerprint = deviceFingerprint();
  assert.ok(fingerprint.includes('Vendor|GPU'));
  assert.ok(fingerprint.length < 1024);
  assert.equal(released, true);
});

test('disabled WebGL has a deterministic fallback', () => {
  environment({
    document: {
      createElement: () => {
        throw Error('blocked');
      },
    },
  });
  assert.equal(JSON.parse(deviceFingerprint()).gpu, 'unavailable');
  assert.equal(deviceFingerprint(), deviceFingerprint());
});

test('device cache is an optional per-account migration hint', () => {
  const values = new Map();
  environment({
    localStorage: {
      getItem: (key) => values.get(key),
      setItem: (key, value) => values.set(key, value),
    },
  });
  const before = deviceFingerprint();
  cacheDeviceId('owner', 'server-id');
  assert.equal(cachedDeviceId('owner'), 'server-id');
  assert.equal(cachedDeviceId('other'), undefined);
  values.clear();
  assert.equal(deviceFingerprint(), before);
});
