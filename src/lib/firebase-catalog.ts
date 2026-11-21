import 'server-only';
import { cache } from 'react';
import { CatalogError, type CatalogQuery, type Kind } from './catalog-query';
import { firebaseCatalogPath, maxCatalogBytes } from './catalog-projection';
import type { Analysis, AreaInventoryProgress, CoverageRow, Entry, RouteLeg } from './catalog-types';

export type CatalogRelease = { release_id: string; as_of: string };
export type CatalogPosition = Pick<Entry, 'latitude' | 'longitude' | 'entity_id'>;

export type FirebaseCatalog = {
  schema_version: 1;
  web_catalog_versions: (CatalogRelease & { status: 'active' | 'retained' })[];
  web_catalog_entries: Entry[];
  published_spring_analyses: (Analysis & { facility_slug: string })[];
  web_pilot_route_legs: (RouteLeg & { facility_slug: string })[];
  prefecture_coverage: (CoverageRow & { kind: Kind })[];
  area_inventory_progress: AreaInventoryProgress[];
};

const tables = ['web_catalog_versions', 'web_catalog_entries', 'published_spring_analyses',
  'web_pilot_route_legs', 'prefecture_coverage', 'area_inventory_progress'] as const;
let cached: { origin: string; data: FirebaseCatalog; expires: number } | undefined;

export const loadFirebaseCatalog = cache(async (origin: string): Promise<FirebaseCatalog> => {
  if (cached?.origin === origin && cached.expires > Date.now()) return cached.data;
  try {
    const url = new URL(origin);
    const allowedHost = /^[a-z0-9-]+\.(?:firebaseio\.com|[a-z0-9-]+\.firebasedatabase\.app)$/;
    if (url.protocol !== 'https:' || !allowedHost.test(url.hostname) || url.href !== `${url.origin}/`
      || url.port) throw new Error('Invalid Firebase origin');
    const response = await fetch(new URL(firebaseCatalogPath, url), {
      cache: 'no-store', redirect: 'manual', signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error('Firebase request failed');
    const body: unknown = await response.json();
    if (typeof body !== 'string' || Buffer.byteLength(body) > maxCatalogBytes) throw new Error('Invalid catalog data');
    const data = JSON.parse(body) as FirebaseCatalog | null;
    if (data?.schema_version !== 1 || !tables.every((table) => Array.isArray(data[table]))) {
      throw new Error('Invalid catalog schema');
    }
    cached = { origin, data, expires: Date.now() + 60_000 };
    return data;
  } catch {
    throw new CatalogError('data_unavailable', 503);
  }
});

export function comparePosition(left: CatalogPosition, right: CatalogPosition) {
  return right.latitude - left.latitude || right.longitude - left.longitude || left.entity_id.localeCompare(right.entity_id);
}

export function firebaseEntries(data: FirebaseCatalog, query: CatalogQuery, release: string) {
  const { kind, scope, prefecture, quality, maxDayPriceJpy } = query;
  return data.web_catalog_entries.filter((entry) => entry.release_id === release && entry.kind === kind
    && (scope !== 'journey' || entry.in_journey)
    && (!prefecture || entry.prefecture_code === prefecture)
    && (!quality || entry.quality_codes.includes(quality))
    && (maxDayPriceJpy === undefined || (entry.day_admission_jpy !== null && entry.day_admission_jpy <= maxDayPriceJpy)))
    .sort(comparePosition);
}
