import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syncCatalog } from '../../scripts/sync-firebase-catalog.mjs';

const source = 'http://127.0.0.1:55450';
const database = 'https://onsen-sync-test.firebaseio.com';
const catalogPath = '/onsen_public/v1.json';
const firstRelease = { release_id: 'first', status: 'active', as_of: '2026-11-21T00:00:00Z' };
const nextRelease = { release_id: 'next', status: 'active', as_of: '2026-11-22T00:00:00Z' };

function mockCatalog(t, remoteRelease = firstRelease) {
  const store = { writes: 0, reads: 0, tokenRequests: 0, conflict: false, release: nextRelease, withdrawn: false,
    remote: remoteRelease ? JSON.stringify({ schema_version: 1, web_catalog_versions: [remoteRelease] }) : null };
  t.mock.method(globalThis, 'fetch', async (address, options) => {
    const url = new URL(address);
    if (url.origin === source) {
      assert.equal(options.headers['Accept-Profile'], 'api');
      const kind = store.withdrawn ? [] : [{ release_id: store.release?.release_id, kind: 'facility' }];
      const views = { web_catalog_versions: store.release ? [store.release] : [],
        web_catalog_entries: kind, published_spring_analyses: [{ sample_note: 'reviewed' }],
        web_pilot_route_legs: [{ seq: 1 }], prefecture_coverage: [{ prefecture_code: '01' }],
        area_inventory_progress: [{ prefecture_code: '01' }] };
      assert.ok(Object.hasOwn(views, url.pathname.slice(1)));
      assert.ok(url.searchParams.get('select'));
      return Response.json(views[url.pathname.slice(1)]);
    }
    assert.equal(url.origin, database);
    assert.equal(url.pathname, catalogPath);
    if (options.method === 'PUT') {
      assert.equal(url.searchParams.get('auth'), 'test-id-token');
      assert.equal(options.headers['If-Match'], '"current-etag"');
      store.writes++;
      if (store.conflict) return new Response(null, { status: 412 });
      store.remote = JSON.parse(options.body);
    } else {
      assert.equal(url.search, '');
      store.reads++;
    }
    return Response.json(store.remote, { headers: { etag: '"current-etag"' } });
  });
  const run = (state) => syncCatalog({ source, database, state, getIdToken: async () => {
    store.tokenRequests++;
    return 'test-id-token';
  } });
  return { store, run };
}

test('publishes all public views atomically and skips identical data', async (t) => {
  const { store, run } = mockCatalog(t);
  const first = await run();
  assert.equal(first.status, 'published');
  const data = JSON.parse(store.remote);
  assert.deepEqual(data.web_catalog_versions, [nextRelease]);
  assert.equal(Object.keys(data).length, 7);
  assert.equal(store.writes, 1);
  assert.equal((await run(first.state)).status, 'unchanged');
  assert.equal((await run()).status, 'unchanged');
  assert.equal(store.writes, 1);
  assert.equal(store.tokenRequests, 1);
});

test('a conflict leaves the published catalog intact', async (t) => {
  const { store, run } = mockCatalog(t);
  const previous = store.remote;
  store.conflict = true;
  await assert.rejects(run(), /changed during this run/);
  assert.equal(store.remote, previous);
  store.conflict = false;
  assert.equal((await run()).status, 'published');
});

test('an older release never replaces a newer one', async (t) => {
  const { store, run } = mockCatalog(t, nextRelease);
  store.release = firstRelease;
  await assert.rejects(run(), /newer release is already published/);
  assert.equal(store.writes, 0);
  assert.equal(store.tokenRequests, 0);
});

test('withdrawal within the same release updates Firebase even if the as-of date declines', async (t) => {
  const { store, run } = mockCatalog(t, nextRelease);
  store.release = { ...nextRelease, as_of: firstRelease.as_of };
  store.withdrawn = true;
  assert.equal((await run()).status, 'published');
  assert.equal(JSON.parse(store.remote).web_catalog_entries.length, 0);
});
