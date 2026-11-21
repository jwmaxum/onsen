import { isLocale, type Locale } from './catalog-query';

export type Profile = { name: string; phone: string };
export type Article = {
  locale: Locale;
  title: string;
  body: string;
  published: boolean;
  updatedAt: number;
  revision: string;
};
export type ArticleInput = Pick<Article, 'locale' | 'title' | 'body' | 'published'>;
export type ArticleStore = { drafts?: Record<string, Article>; public?: Partial<Record<Locale, Record<string, Article>>> };

export function normalizeProfile(name: string, phone: string): Profile | null {
  const normalized = { name: name.trim(), phone: phone.trim().replace(/[\s().-]/g, '') };
  return normalized.name.length > 0 && normalized.name.length <= 80 && /^\+?[0-9]{7,15}$/.test(normalized.phone)
    ? normalized : null;
}

export function articleRows(value: unknown): [string, Article][] {
  if (!value || typeof value !== 'object') return [];
  const rows = Object.entries(value).filter((entry): entry is [string, Article] => {
    const [id, row] = entry;
    return /^[a-zA-Z0-9_-]{1,80}$/.test(id) && row && typeof row === 'object'
      && typeof row.locale === 'string' && isLocale(row.locale)
      && typeof row.title === 'string' && typeof row.body === 'string' && typeof row.published === 'boolean'
      && typeof row.updatedAt === 'number' && Number.isFinite(row.updatedAt) && typeof row.revision === 'string';
  });
  return rows.sort((left, right) => right[1].updatedAt - left[1].updatedAt);
}
