import { notFound } from 'next/navigation';
import { Shell } from '@/components/shell';
import { isLocale, type Locale } from '@/lib/catalog-query';
import { firebaseSiteOrigin } from '@/lib/firebase-site';
import { membershipText } from '@/lib/membership-copy';
import { articleRows } from '@/lib/membership-types';

export const dynamic = 'force-dynamic';

async function loadNews(locale: Locale) {
  const origin = firebaseSiteOrigin();
  if (!origin) return null;
  try {
    const url = new URL(`/site_content/public/${locale}.json`, origin);
    url.searchParams.set('orderBy', JSON.stringify('updatedAt'));
    url.searchParams.set('limitToLast', '40');
    const response = await fetch(url, { cache: 'no-store', redirect: 'manual', signal: AbortSignal.timeout(5000) });
    if (!response.ok) return null;
    return articleRows(await response.json()).filter(([, item]) => item.published && item.locale === locale);
  } catch {
    return null;
  }
}

export default async function NewsPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const t = membershipText(locale);
  const rows = await loadNews(locale);
  return <Shell locale={locale} hrefFor={(value) => `/${value}/onsen/news`}>
    <div className="container member-page member-news">
      <h1>{t('articles')}</h1>
      {rows?.length ? rows.map(([id, item]) => <article className="member-card" key={id} id={id}>
        <h2>{item.title}</h2>
        <time dateTime={new Date(item.updatedAt).toISOString()}>{new Intl.DateTimeFormat(locale, { dateStyle: 'long' }).format(item.updatedAt)}</time>
        <p className="member-body">{item.body}</p>
      </article>) : <p role="status">{t(rows ? 'empty' : 'unavailable')}</p>}
    </div>
  </Shell>;
}
