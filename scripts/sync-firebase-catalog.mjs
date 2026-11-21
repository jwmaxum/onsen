import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { exportCatalog } from './export-firebase-catalog.mjs';
import { firebaseCatalogPath } from '../src/lib/catalog-projection.ts';

const requestOptions = { cache: 'no-store', redirect: 'error' };
const verificationIntervalMs = 60 * 60 * 1000;

async function request(url, operation, options = {}) {
  try {
    return await fetch(url, { ...requestOptions, ...options, signal: AbortSignal.timeout(15_000) });
  } catch {
    throw new Error(`${operation} failed to reach Firebase`);
  }
}

function activeRelease(value) {
  if (value === null) return null;
  if (typeof value !== 'string') throw new Error('Firebase returned an invalid catalog');
  const catalog = JSON.parse(value);
  const versions = catalog.schema_version === 1 && catalog.web_catalog_versions;
  const [release, ...others] = Array.isArray(versions) ? versions.filter((row) => row.status === 'active') : [];
  if (!Array.isArray(versions) || others.length || (release && !Number.isFinite(Date.parse(release.as_of)))) {
    throw new Error('Firebase returned an invalid active release');
  }
  return release ?? null;
}

export async function syncCatalog({ source, database, getIdToken, state }) {
  const origin = new URL(database);
  if (origin.protocol !== 'https:' || origin.href !== `${origin.origin}/` || origin.port
    || !/^[a-z0-9-]+\.(?:firebaseio\.com|[a-z0-9-]+\.firebasedatabase\.app)$/.test(origin.hostname)) {
    throw new Error('Expected a Firebase Realtime Database HTTPS origin');
  }
  const endpoint = new URL(firebaseCatalogPath, origin);
  const { data, release, summary } = await exportCatalog(source);
  const digest = createHash('sha256').update(data).digest('hex');
  if (state?.target === endpoint.href && state.digest === digest
    && Date.now() - state.verifiedAt < verificationIntervalMs) return { status: 'unchanged', summary, state };
  const confirmed = { target: endpoint.href, digest, verifiedAt: Date.now() };

  const remote = await request(endpoint, 'Catalog read', { headers: { 'X-Firebase-ETag': 'true' } });
  if (!remote.ok) throw new Error(`Catalog read failed (HTTP ${remote.status})`);
  const stored = await remote.json();
  if (stored === data) return { status: 'unchanged', summary, state: confirmed };
  const existing = activeRelease(stored);
  if (existing && release && existing.release_id !== release.release_id
    && Date.parse(existing.as_of) > Date.parse(release.as_of)) {
    throw new Error('A newer release is already published');
  }
  const etag = remote.headers.get('etag');
  if (!etag) throw new Error('Firebase did not supply a catalog ETag');
  if ((await exportCatalog(source)).data !== data) throw new Error('The source catalog changed before publication');

  const authenticated = new URL(endpoint);
  authenticated.searchParams.set('auth', await getIdToken());
  const updated = await request(authenticated, 'Catalog write', { method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'If-Match': etag }, body: JSON.stringify(data) });
  if (updated.status === 412) throw new Error('The published catalog changed during this run. The next run will compare it again.');
  if (!updated.ok) throw new Error(`Catalog write failed (HTTP ${updated.status})`);
  const verified = await request(endpoint, 'Catalog verification');
  if (!verified.ok || await verified.json() !== data) throw new Error('Published catalog verification failed');
  return { status: 'published', summary, state: confirmed };
}

async function exchange(apiKey, credential) {
  const url = new URL('https://securetoken.googleapis.com/v1/token');
  url.searchParams.set('key', apiKey);
  const result = await request(url, 'Publisher authentication', { method: 'POST',
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: credential.refreshToken }) });
  if (!result.ok) throw new Error(`Publisher authentication failed (HTTP ${result.status})`);
  const payload = await result.json();
  if (payload.user_id !== credential.uid || typeof payload.id_token !== 'string'
    || typeof payload.refresh_token !== 'string') throw new Error('Unexpected Firebase publisher identity');
  credential.refreshToken = payload.refresh_token;
  return payload.id_token;
}

async function createPublisher(apiKey) {
  const url = new URL('https://identitytoolkit.googleapis.com/v1/accounts:signUp');
  url.searchParams.set('key', apiKey);
  const result = await request(url, 'Publisher creation', { method: 'POST',
    headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }) });
  if (!result.ok) throw new Error(`Publisher creation failed (HTTP ${result.status})`);
  const payload = await result.json();
  if (typeof payload.localId !== 'string' || typeof payload.refreshToken !== 'string') {
    throw new Error('Firebase did not return a publisher identity');
  }
  return { status: 'created', uid: payload.localId, refreshToken: payload.refreshToken };
}

if (import.meta.main) {
  // The PowerShell launcher captures this private pipe and protects rotated credentials with DPAPI.
  if (process.argv[2] !== '--windows-publisher-pipe' || process.stdin.isTTY) {
    throw new Error('Use scripts/sync-firebase-catalog.ps1 to run the Firebase publisher');
  }
  const { source, database, apiKey, credential, state, initialize } = JSON.parse(readFileSync(0, 'utf8'));
  const initialToken = credential?.refreshToken;
  let output;
  try {
    output = initialize ? await createPublisher(apiKey)
      : await syncCatalog({ source, database, state, getIdToken: () => exchange(apiKey, credential) });
  } catch (error) {
    // Never include URLs or remote response bodies in task logs.
    output = { status: 'error', error: error instanceof SyntaxError ? 'Invalid Firebase response' : error.message };
    process.exitCode = 1;
  }
  if (credential && initialToken !== credential.refreshToken) output.refreshToken = credential.refreshToken;
  process.stdout.write(JSON.stringify(output));
}
