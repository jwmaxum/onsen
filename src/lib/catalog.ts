import 'server-only';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { cache } from 'react';
import { CatalogError, queryParams, type CatalogQuery, type Kind, type Locale } from './catalog-query';
import type { Analysis, AreaInventoryProgress, CatalogPage, CoverageRow, Entry, RouteLeg } from './catalog-types';

type Release = { release_id: string; as_of: string };
type Position = Pick<Entry, 'latitude' | 'longitude' | 'entity_id'>;
type Cursor = Position & { release: string; query: string };

const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const slugPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const pilot = /^pilot-\d{4}-\d{2}-\d{2}(?:-r[1-9]\d*)?$/;
const columns = 'release_id,entity_id,kind,prefecture_code,slug,name_ja,location_ja,latitude,longitude,facility_type,in_journey,public_source_url,verified_at,coordinate_accuracy,quality_codes,day_admission_jpy,coordinate_source_url,coordinate_attribution';
const analysisColumns = 'analysis_id,locale,sample_name,quality_name,sample_note,sampled_on,analyzed_on,source_temp_celsius,ph_onsite,ph_laboratory,source_publisher,source_url,source_terms_url,source_license,source_accessed_on,source_modified,source_attribution,source_transformation';
const legColumns = 'route_key,travel_mode,verified_at,valid_until,duration_minutes,fare_jpy,transfers,route_source_url,seq,mode,from_code,from_name_ja,to_code,to_name_ja,operator_name,service_name,leg_duration_minutes,leg_fare_jpy,reservation_required,leg_source_url';

export function isReleaseId(value: string) {
  return uuid.test(value) || pilot.test(value);
}

export function isSlug(value: string) {
  return value.length <= 150 && slugPattern.test(value);
}

type View = 'web_catalog_versions' | 'web_catalog_entries' | 'published_spring_analyses' | 'web_pilot_route_legs'
  | 'prefecture_coverage' | 'area_inventory_progress';

async function read<T>(view: View, params: Record<string, string>): Promise<T[]> {
  let base: URL;
  try {
    base = new URL(process.env.ONSEN_POSTGREST_URL ?? '');
  } catch {
    throw new CatalogError('data_unavailable', 503);
  }
  const local = ['127.0.0.1', 'localhost', '[::1]'].includes(base.hostname);
  if ((!local && base.protocol !== 'https:') || !['http:', 'https:'].includes(base.protocol)
      || base.username || base.password || base.search || base.hash) throw new CatalogError('data_unavailable', 503);
  const url = new URL(`${base.toString().replace(/\/$/, '')}/${view}`);
  url.search = new URLSearchParams(params).toString();
  const headers: Record<string, string> = { Accept: 'application/json', 'Accept-Profile': 'api' };
  const key = process.env.ONSEN_SUPABASE_PUBLIC_KEY;
  if (key) {
    headers.apikey = key;
    if (key.startsWith('eyJ')) headers.Authorization = `Bearer ${key}`;
  }
  try {
    const response = await fetch(url, { headers, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new CatalogError('data_unavailable', 503);
    const payload: unknown = await response.json();
    if (!Array.isArray(payload)) throw new CatalogError('data_unavailable', 503);
    return payload as T[];
  } catch {
    throw new CatalogError('data_unavailable', 503);
  }
}

function signature(payload: string) {
  const secret = process.env.ONSEN_CURSOR_SECRET;
  if (!secret || secret.length < 32) throw new CatalogError('data_unavailable', 503);
  return createHmac('sha256', secret).update(payload).digest();
}

function queryId(query: CatalogQuery) {
  return queryParams({ ...query, cursor: undefined }, { api: true }).toString();
}

function decodeCursor(token: string, query: CatalogQuery): Cursor {
  const [payload, encodedSignature] = token.split('.');
  const actual = Buffer.from(encodedSignature, 'base64url');
  const expected = signature(payload);
  if (actual.toString('base64url') !== encodedSignature || actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    throw new CatalogError('invalid_cursor', 400);
  }
  let value: Cursor;
  try { value = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')); }
  catch { throw new CatalogError('invalid_cursor', 400); }
  if (!value || value.query !== queryId(query) || !isReleaseId(value.release) || !uuid.test(value.entity_id)
      || !Number.isFinite(value.latitude) || Math.abs(value.latitude) > 90
      || !Number.isFinite(value.longitude) || Math.abs(value.longitude) > 180) throw new CatalogError('invalid_cursor', 400);
  return value;
}

function encodeCursor(entry: Entry, query: CatalogQuery) {
  const value: Cursor = { release: entry.release_id, query: queryId(query), latitude: entry.latitude,
    longitude: entry.longitude, entity_id: entry.entity_id };
  const payload = Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${payload}.${signature(payload).toString('base64url')}`;
}

function positionFilter(position: Position, before = false) {
  const { latitude, longitude, entity_id: id } = position;
  const coordinate = before ? 'gt' : 'lt';
  const identity = before ? 'lt' : 'gt';
  return `(latitude.${coordinate}.${latitude},and(latitude.eq.${latitude},longitude.${coordinate}.${longitude}),and(latitude.eq.${latitude},longitude.eq.${longitude},entity_id.${identity}.${id}))`;
}

const order = 'latitude.desc,longitude.desc,entity_id.asc';

export function getCoverage(kind: Kind) {
  return read<CoverageRow>('prefecture_coverage', {
    select: 'prefecture_code,name_ja,name_en,status,registered_sources,candidates,reviewed,published,withdrawn,checked_on,gap_codes',
    kind: `eq.${kind}`, order: 'prefecture_code.asc', limit: '47',
  });
}

export function getAreaInventoryProgress() {
  return read<AreaInventoryProgress>('area_inventory_progress', { order: 'prefecture_code.asc', limit: '47' });
}

function selection(query: CatalogQuery, release: string) {
  const params: Record<string, string> = { select: columns, release_id: `eq.${release}`, kind: `eq.${query.kind}` };
  if (query.scope === 'journey') params.in_journey = 'eq.true';
  if (query.prefecture) params.prefecture_code = `eq.${query.prefecture}`;
  if (query.quality) params.quality_codes = `cs.{${query.quality}}`;
  if (query.maxDayPriceJpy !== undefined) params.day_admission_jpy = `lte.${query.maxDayPriceJpy}`;
  return params;
}

const getRelease = cache(async (id?: string) => {
  if (id && !isReleaseId(id)) throw new CatalogError('invalid_query', 400);
  const [release] = await read<Release>('web_catalog_versions', { select: 'release_id,as_of', limit: '1',
    ...(id ? { release_id: `eq.${id}` } : { status: 'eq.active' }) });
  if (!release && id) throw new CatalogError('release_expired', 409);
  return release;
});

export async function getCatalogPage(query: CatalogQuery, releaseHint?: string): Promise<CatalogPage> {
  const cursor = query.cursor ? decodeCursor(query.cursor, query) : undefined;
  if (cursor && releaseHint && cursor.release !== releaseHint) throw new CatalogError('invalid_cursor', 400);
  const release = await getRelease(cursor?.release ?? releaseHint);
  if (!release) return { items: [], nextCursor: null, releaseId: null, asOf: null };
  const rows = await read<Entry>('web_catalog_entries', { ...selection(query, release.release_id), order,
    limit: String(query.limit + 1), ...(cursor ? { or: positionFilter(cursor) } : {}) });
  const items = rows.slice(0, query.limit);
  return { items, nextCursor: rows.length > query.limit ? encodeCursor(items.at(-1)!, query) : null,
    releaseId: release.release_id, asOf: release.as_of };
}

export const getEntry = cache(async (kind: Kind, slug: string, releaseHint?: string) => {
  if (!isSlug(slug)) return undefined;
  const release = await getRelease(releaseHint);
  if (!release) return undefined;
  return (await read<Entry>('web_catalog_entries', { select: columns, release_id: `eq.${release.release_id}`,
    kind: `eq.${kind}`, slug: `eq.${slug}`, limit: '1' }))[0];
});

async function getAnalyses(slug: string, locale: Locale) {
  const rows = await read<Analysis>('published_spring_analyses', { select: analysisColumns, facility_slug: `eq.${slug}`,
    locale: locale === 'ja' ? 'eq.ja' : `in.(${locale},ja)`, order: 'source_url.asc', limit: '100' });
  const localized = new Map<string, Analysis>();
  for (const row of rows) {
    if (row.locale === locale || !localized.has(row.analysis_id)) localized.set(row.analysis_id, row);
  }
  return [...localized.values()];
}

export async function getDetail(entry: Entry, query: CatalogQuery) {
  const filters = selection(query, entry.release_id);
  const facility = entry.kind === 'facility';
  const [previous, next, analyses, legs] = await Promise.all([
    read<Entry>('web_catalog_entries', { ...filters, or: positionFilter(entry, true), order: 'latitude.asc,longitude.asc,entity_id.desc', limit: '1' }),
    read<Entry>('web_catalog_entries', { ...filters, or: positionFilter(entry), order, limit: '1' }),
    facility ? getAnalyses(entry.slug, query.locale) : [],
    facility ? read<RouteLeg>('web_pilot_route_legs', { select: legColumns, facility_slug: `eq.${entry.slug}`,
      order: 'travel_mode.desc,route_key.asc,seq.asc', limit: '30' }) : [],
  ]);
  return { previous: previous[0], next: next[0], analyses, legs };
}
