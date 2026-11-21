import { writeFile } from 'node:fs/promises';
import {
  analysisColumns, coverageColumns, entryColumns, inventoryColumns, legColumns, maxCatalogBytes,
} from '../src/lib/catalog-projection.ts';

const views = {
  web_catalog_versions: { select: 'release_id,status,as_of', order: 'release_id.asc', status: 'in.(active,retained)' },
  web_catalog_entries: { select: entryColumns, order: 'release_id.asc,latitude.desc,longitude.desc,entity_id.asc' },
  published_spring_analyses: {
    select: `facility_slug,${analysisColumns}`, order: 'source_url.asc,analysis_id.asc,locale.asc',
  },
  web_pilot_route_legs: {
    select: `facility_slug,${legColumns}`, order: 'facility_slug.asc,travel_mode.desc,route_key.asc,seq.asc',
  },
  prefecture_coverage: { select: `kind,${coverageColumns}`, order: 'kind.asc,prefecture_code.asc' },
  area_inventory_progress: { select: inventoryColumns, order: 'prefecture_code.asc' },
};

async function readView(origin, name) {
  const rows = [];
  const pageSize = 500;
  const url = new URL(`${origin.pathname.replace(/\/$/, '')}/${name}`, origin);
  for (let offset = 0; offset < 20_000; offset += pageSize) {
    url.search = new URLSearchParams({ ...views[name], limit: String(pageSize), offset: String(offset) }).toString();
    const response = await fetch(url, {
      headers: { 'Accept-Profile': 'api' }, redirect: 'error', signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error(`${name} returned HTTP ${response.status}`);
    const page = await response.json();
    if (!Array.isArray(page)) throw new Error(`${name} did not return rows`);
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
  throw new Error(`${name} exceeded the export row limit`);
}

export async function exportCatalog(source) {
  const origin = new URL(source);
  if (origin.protocol !== 'http:' || !['127.0.0.1', '[::1]'].includes(origin.hostname)
    || origin.username || origin.password || origin.search || origin.hash) {
    throw new Error('The export source must be the local, anonymous PostgREST API');
  }
  const versions = await readView(origin, 'web_catalog_versions');
  const catalog = Object.fromEntries(await Promise.all(Object.keys(views)
    .filter((view) => view !== 'web_catalog_versions').map(async (view) => [view, await readView(origin, view)])));
  if (JSON.stringify(await readView(origin, 'web_catalog_versions')) !== JSON.stringify(versions)) {
    throw new Error('The catalog release changed during export. Run the export again.');
  }
  const [release, ...otherActive] = versions.filter(({ status }) => status === 'active');
  const knownReleases = new Set(versions.map(({ release_id }) => release_id));
  const entries = catalog.web_catalog_entries.filter((entry) => entry.release_id === release?.release_id);
  if (otherActive.length || (release && !Number.isFinite(Date.parse(release.as_of)))
    || catalog.web_catalog_entries.some((entry) => !knownReleases.has(entry.release_id))
    || !catalog.area_inventory_progress.length) {
    throw new Error('The public catalog is incomplete');
  }

  // RTDB otherwise drops null fields and empty arrays.
  const data = JSON.stringify({ schema_version: 1, web_catalog_versions: versions, ...catalog });
  const bytes = Buffer.byteLength(data);
  if (bytes > maxCatalogBytes) throw new Error('The public catalog exceeded the Firebase snapshot limit');
  return { data, release, summary: { release: release?.release_id ?? null,
    facilities: entries.filter((entry) => entry.kind === 'facility').length,
    areas: entries.filter((entry) => entry.kind === 'area').length,
    views: Object.fromEntries(Object.entries(catalog).map(([view, rows]) => [view, rows.length])), bytes } };
}

if (import.meta.main) {
  const [source, output] = process.argv.slice(2);
  if (!source || !output) throw new Error('Usage: node scripts/export-firebase-catalog.mjs <local-api-origin> <output.json>');
  const { data, summary } = await exportCatalog(source);
  await writeFile(output, JSON.stringify({ onsen_public: { v1: data } }), { flag: 'wx' });
  console.log(JSON.stringify(summary));
}
