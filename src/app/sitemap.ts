import type { MetadataRoute } from 'next';
import { getCatalogPage } from '@/lib/catalog';
import { detailPath, locales } from '@/lib/catalog-query';
import { hasLocalizedEntry } from '@/lib/i18n';
import { siteOrigin } from '@/lib/metadata';

export const dynamic = 'force-dynamic';

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const origin = siteOrigin();
  if (!origin) return [];
  try {
    const pages = await Promise.all((['facility', 'area'] as const).map((kind) =>
      getCatalogPage({ locale: 'ja', scope: 'nationwide', kind, limit: 50 })));
    const url = (path: string) => new URL(path, origin).href;
    return [
      ...locales.flatMap((locale) => ['onsen', 'onsen/coverage'].map((path) => ({ url: url(`/${locale}/${path}`) }))),
      ...pages.flatMap(({ items }) => items.flatMap((entry) =>
        (hasLocalizedEntry(entry) ? locales : ['ja'] as const).map((locale) => ({
          url: url(detailPath(locale, entry.kind, entry.slug)), lastModified: entry.verified_at,
        })))),
    ];
  } catch { return []; }
}
