export const locales = ['ko', 'ja', 'en', 'zh-Hans'] as const;
export type Locale = (typeof locales)[number];
export const localeLabels = { ko: '한국어', ja: '日本語', en: 'English', 'zh-Hans': '简体中文' };
export const qualities = ['simple', 'chloride', 'bicarbonate', 'sulfate', 'carbon_dioxide', 'iron', 'acidic', 'iodine', 'sulfur', 'radioactive'] as const;
export type Quality = (typeof qualities)[number];
export type Kind = 'facility' | 'area';
export const DEFAULT_LIMIT = 20;

export type CatalogQuery = {
  locale: Locale;
  kind: Kind;
  scope: 'journey' | 'nationwide';
  prefecture?: string;
  quality?: Quality;
  maxDayPriceJpy?: number;
  cursor?: string;
  limit: number;
};

export function isLocale(locale: string): locale is Locale {
  return (locales as readonly string[]).includes(locale);
}

export function isQuality(quality: string): quality is Quality {
  return (qualities as readonly string[]).includes(quality);
}

export class CatalogError extends Error {
  constructor(public readonly code: string, public readonly status: number) {
    super(code);
  }
}

const fields = ['locale', 'kind', 'scope', 'prefecture', 'quality', 'maxDayPriceJpy', 'cursor', 'limit'];
const prefecturePattern = /^(0[1-9]|[1-3][0-9]|4[0-7])$/;

export function parseCatalogQuery(params: URLSearchParams, defaultLocale: Locale = 'ko'): CatalogQuery {
  for (const name of params.keys()) {
    if (!fields.includes(name) || params.getAll(name).length !== 1) throw new CatalogError('invalid_query', 400);
  }
  const locale = params.get('locale') ?? defaultLocale;
  const kind = params.get('kind') ?? 'facility';
  const scope = params.get('scope') ?? 'journey';
  const prefecture = params.get('prefecture') || undefined;
  const quality = params.get('quality') || undefined;
  const price = params.get('maxDayPriceJpy') || undefined;
  const limit = params.get('limit') ?? String(DEFAULT_LIMIT);
  const cursor = params.get('cursor') || undefined;
  if (!isLocale(locale) || (kind !== 'facility' && kind !== 'area') || (scope !== 'journey' && scope !== 'nationwide')
      || (prefecture && !prefecturePattern.test(prefecture)) || (quality !== undefined && !isQuality(quality))
      || (price && !/^\d{1,6}$/.test(price)) || !/^(?:[1-9]|[1-4][0-9]|50)$/.test(limit)
      || (cursor && !/^[A-Za-z0-9_-]{8,700}\.[A-Za-z0-9_-]{43}$/.test(cursor))) {
    throw new CatalogError('invalid_query', 400);
  }
  return { locale, kind, scope, prefecture, quality, maxDayPriceJpy: price === undefined ? undefined : Number(price),
    cursor, limit: Number(limit) };
}

export function fromSearchRecord(record: Record<string, string | string[] | undefined>) {
  const params = new URLSearchParams();
  for (const [name, value] of Object.entries(record)) {
    for (const part of typeof value === 'string' ? [value] : (value ?? [])) params.append(name, part);
  }
  return params;
}

export function queryParams(query: CatalogQuery, options: { api?: boolean; release?: string } = {}) {
  const params = new URLSearchParams();
  if (options.api) params.set('locale', query.locale);
  if (query.kind !== 'facility') params.set('kind', query.kind);
  if (query.scope !== 'journey') params.set('scope', query.scope);
  if (query.prefecture) params.set('prefecture', query.prefecture);
  if (query.quality) params.set('quality', query.quality);
  if (query.maxDayPriceJpy !== undefined) params.set('maxDayPriceJpy', String(query.maxDayPriceJpy));
  if (query.limit !== DEFAULT_LIMIT) params.set('limit', String(query.limit));
  if (query.cursor) params.set('cursor', query.cursor);
  if (options.release) params.set('release', options.release);
  return params;
}

export function withQuery(path: string, params: URLSearchParams) {
  const search = params.toString();
  return search ? `${path}?${search}` : path;
}

export function detailPath(locale: Locale, kind: Kind, slug: string) {
  return `/${locale}/onsen/${kind === 'facility' ? 'facilities' : 'areas'}/${slug}`;
}
