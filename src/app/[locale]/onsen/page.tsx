import { ArrowDown, Compass } from 'lucide-react';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { CatalogFilters } from '@/components/catalog-filters';
import { CatalogList } from '@/components/catalog-list';
import { Shell } from '@/components/shell';
import { getCatalogPage } from '@/lib/catalog';
import { CatalogError, fromSearchRecord, isLocale, parseCatalogQuery, queryParams, withQuery } from '@/lib/catalog-query';
import { coverageText } from '@/lib/coverage-copy';
import { localDate, text } from '@/lib/i18n';
import { pageMetadata } from '@/lib/metadata';

type Props = { params: Promise<{ locale: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };

export async function generateMetadata({ params }: Props) {
  const { locale } = await params;
  if (!isLocale(locale)) return {};
  const t = text(locale);
  return pageMetadata(locale, (value) => `/${value}/onsen`, `${t('home')} · ${t('brand')}`, t('intro'));
}

export default async function OnsenPage({ params, searchParams }: Props) {
  const [{ locale }, raw] = await Promise.all([params, searchParams]);
  if (!isLocale(locale)) notFound();
  const t = text(locale);
  const input = fromSearchRecord(raw);
  const releaseHint = input.get('release') || undefined;
  input.delete('release');
  input.delete('locale');
  let query = parseCatalogQuery(new URLSearchParams(), locale);
  let result;
  let message;
  try {
    query = parseCatalogQuery(input, locale);
    result = await getCatalogPage(query, releaseHint);
  } catch (error) {
    message = error instanceof CatalogError && error.status === 400 ? t('badQuery')
      : error instanceof CatalogError && error.status === 409 ? t('expired') : t('unavailable');
  }
  const preserved = queryParams({ ...query, cursor: undefined });
  return <Shell locale={locale} hrefFor={(value) => withQuery(`/${value}/onsen`, preserved)}>
    <section className="hero">
      <div className="container hero-inner">
        <div className="hero-copy">
          <div className="eyebrow"><Compass size={16} aria-hidden="true" />{result?.releaseId?.startsWith('pilot-') ? t('sample') : t('catalog')}</div>
          <h1>{t('headline1')}<br /><em>{t('headline2')}</em></h1>
          <p>{t('intro')}</p>
        </div>
        <div className="hero-rail" aria-hidden="true"><span>N</span><div className="hero-rail-track" /><ArrowDown size={23} /><span>S</span></div>
      </div>
    </section>
    <div className="container browse-wrap">
      <CatalogFilters query={query} />
      <p className="coverage-link"><Link href={`/${locale}/onsen/coverage`}>{coverageText(locale).title}</Link></p>
      {message && <div role="alert" className="empty-panel"><p>{message}</p><Link href={`/${locale}/onsen`}>{t('retry')}</Link></div>}
      {result && <>
        <CatalogList key={`${result.releaseId}:${queryParams(query)}`} initial={result} query={query} />
        {result.asOf && <p className="catalog-date">{t('verified')} <time dateTime={result.asOf}>{localDate(result.asOf, locale)}</time></p>}
      </>}
    </div>
  </Shell>;
}
