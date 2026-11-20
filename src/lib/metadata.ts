import type { Metadata } from 'next';
import { locales, type Locale } from './catalog-query';

export function siteOrigin(): URL | undefined {
  try {
    const value = new URL(process.env.ONSEN_SITE_URL ?? '');
    if (value.protocol === 'https:' && !value.username && !value.password && !value.search && !value.hash) return new URL(value.origin);
  } catch { /* Indexing is opt-in through the public site origin. */ }
  return undefined;
}

export function pageMetadata(locale: Locale, path: (value: Locale) => string, title: string, description: string,
  translated = true): Metadata {
  const origin = siteOrigin();
  if (!origin) return { title, description, robots: { index: false, follow: true } };
  return {
    title, description, metadataBase: origin, robots: { index: translated || locale === 'ja', follow: true },
    alternates: { canonical: path(locale), languages: Object.fromEntries(
      (translated ? locales : ['ja'] as const).map((value) => [value, path(value)])) },
  };
}
