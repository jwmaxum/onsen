import { ArrowLeft, ArrowRight, MapPin, MountainSnow } from 'lucide-react';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { CopyAddress } from '@/components/copy-address';
import { AnalysisCards, RouteCards } from '@/components/onsen-detail';
import { Shell } from '@/components/shell';
import { getDetail, getEntry, isSlug } from '@/lib/catalog';
import { CatalogError, detailPath, fromSearchRecord, isLocale, parseCatalogQuery, queryParams, withQuery, type Kind } from '@/lib/catalog-query';
import { entryIntroduction, entryLanguage, entryName, hasLocalizedEntry, localDate, regionName, text, yen } from '@/lib/i18n';
import { pageMetadata } from '@/lib/metadata';

type Props = { params: Promise<{ locale: string; category: string; slug: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };
function kindFor(category: string): Kind | undefined {
  if (category === 'facilities') return 'facility';
  if (category === 'areas') return 'area';
}

export async function generateMetadata({ params }: Props) {
  const { locale, category, slug } = await params;
  const kind = kindFor(category);
  if (!kind || !isLocale(locale)) return {};
  try {
    const entry = await getEntry(kind, slug);
    if (!entry) return {};
    const t = text(locale);
    return pageMetadata(locale, (value) => detailPath(value, kind, slug), `${entryName(entry, locale)} · ${t('brand')}`,
      `${entryName(entry, locale)} · ${regionName(entry.prefecture_code, locale)}`, hasLocalizedEntry(entry));
  } catch { return { robots: { index: false } }; }
}

export default async function OnsenDetail({ params, searchParams }: Props) {
  const [{ locale, category, slug }, raw] = await Promise.all([params, searchParams]);
  const kind = kindFor(category);
  if (!isLocale(locale) || !kind || !isSlug(slug)) notFound();
  const t = text(locale);
  const input = fromSearchRecord(raw);
  const release = input.get('release') || undefined;
  input.delete('release');
  input.delete('locale');
  input.set('kind', kind);
  let entry;
  let detail;
  let query;
  try {
    query = parseCatalogQuery(input, locale);
    entry = await getEntry(kind, slug, release);
    if (entry) detail = await getDetail(entry, query);
  } catch (error) {
    const message = error instanceof CatalogError && error.status === 409 ? t('expired')
      : error instanceof CatalogError && error.status === 400 ? t('badQuery') : t('unavailable');
    return <Shell locale={locale} hrefFor={(value) => detailPath(value, kind, slug)}>
      <div className="container detail-wrap"><div className="empty-panel" role="alert"><p>{message}</p>
        <Link href={`/${locale}/onsen`}>{t('retry')}</Link></div></div>
    </Shell>;
  }
  if (!entry || !detail || !query) notFound();
  const current = entry;
  const navigation = queryParams({ ...query, cursor: undefined }, { release: current.release_id });
  const back = `${withQuery(`/${locale}/onsen`, queryParams(query, { release: current.release_id }))}#entry-${slug}`;
  const name = entryName(current, locale);
  const introduction = entryIntroduction(current, locale);
  const ministrySource = current.public_source_url.startsWith('https://www.hkd.mlit.go.jp/');
  return <Shell locale={locale} hrefFor={(value) => withQuery(detailPath(value, kind, slug), navigation)}>
    <div className="container detail-wrap">
      <Link className="back-link" href={back}><ArrowLeft size={17} aria-hidden="true" />{t('back')}</Link>
      <header className="detail-hero">
        <div className="detail-intro">
          <span className="eyebrow"><MapPin size={16} aria-hidden="true" />{regionName(current.prefecture_code, locale)}</span>
          <h1 lang={entryLanguage(current, locale)}>{name}</h1>
          {name !== current.name_ja && <p className="detail-original" lang="ja">{current.name_ja}</p>}
          <p className="detail-coordinate" dir="ltr">{current.latitude.toFixed(4)}° N &nbsp; {current.longitude.toFixed(4)}° E</p>
        </div>
        <div className="detail-address">
          <span className="eyebrow">{t('address')}</span><p lang="ja">{current.location_ja}</p>
          <CopyAddress address={current.location_ja} label={t('copy')} copied={t('copied')} failed={t('copyFail')} />
          <p className="position-note">{t('representative')}</p>
        </div>
      </header>
      <section className="detail-section" aria-labelledby="overview-heading">
        <div className="section-heading"><div><span className="eyebrow"><MountainSnow size={16} aria-hidden="true" />{t('verified')}</span>
          <h2 id="overview-heading">{kind === 'facility' ? t('overview') : t('areas')}</h2>
          {introduction && <p>{introduction}</p>}</div></div>
        {kind === 'facility' ? <>
          <dl className="facility-facts">
            <div><dt>{t('rooms')}</dt><dd>{t('pending')}</dd></div><div><dt>{t('baths')}</dt><dd>{t('pending')}</dd></div>
            <div><dt>{t('admission')}</dt><dd>{current.day_admission_jpy === null ? t('pending') : yen(current.day_admission_jpy, locale)}</dd></div>
          </dl><p className="photo-note">{t('noPhoto')}</p>
        </> : <p>{t('noAreas')}</p>}
        <div className="source-links"><a href={current.public_source_url}
          target={ministrySource ? '_blank' : undefined} rel={ministrySource ? 'noopener noreferrer' : undefined}>
          {ministrySource ? '国土交通省 北海道開発局' : t('source')}
        </a>
          {current.coordinate_source_url && current.coordinate_attribution &&
            <a href={current.coordinate_source_url} target="_blank" rel="noopener noreferrer">{current.coordinate_attribution}</a>}
          <span>{t('verified')} <time dateTime={current.verified_at}>{localDate(current.verified_at, locale)}</time></span></div>
      </section>
      {kind === 'facility' && <><AnalysisCards locale={locale} rows={detail.analyses} /><RouteCards locale={locale} legs={detail.legs} /></>}
      <nav className="neighbor-nav" aria-label={t('northSouth')}>
        {detail.previous && <Link className="neighbor" href={withQuery(detailPath(locale, kind, detail.previous.slug), navigation)}>
          <ArrowLeft size={20} aria-hidden="true" /><span><small>{t('prev')}</small>
            <strong lang={entryLanguage(detail.previous, locale)}>{entryName(detail.previous, locale)}</strong></span></Link>}
        {detail.next && <Link className="neighbor neighbor-next" href={withQuery(detailPath(locale, kind, detail.next.slug), navigation)}>
          <span><small>{t('next')}</small><strong lang={entryLanguage(detail.next, locale)}>{entryName(detail.next, locale)}</strong></span>
          <ArrowRight size={20} aria-hidden="true" /></Link>}
      </nav>
    </div>
  </Shell>;
}
