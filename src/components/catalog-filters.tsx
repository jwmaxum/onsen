import Link from 'next/link';
import { SlidersHorizontal } from 'lucide-react';
import { qualities, queryParams, withQuery, type CatalogQuery, type Kind } from '@/lib/catalog-query';
import { qualityNames, regionName, text } from '@/lib/i18n';

export function CatalogFilters({ query }: { query: CatalogQuery }) {
  const { locale } = query;
  const t = text(locale);
  const base = `/${locale}/onsen`;
  const regions = [...new Set(['01', '02', '04', '44', ...(query.prefecture ? [query.prefecture] : [])])].sort();
  const options = { ...query, cursor: undefined };
  return <div className="filter-box">
    <div className="filter-top">
      <nav className="segmented" aria-label={t('northSouth')}>
        {(['journey', 'nationwide'] as const).map((scope) => <Link key={scope}
          href={withQuery(base, queryParams({ ...options, scope }))} aria-current={query.scope === scope ? 'page' : undefined}>{t(scope)}</Link>)}
      </nav>
      <nav className="segmented segmented-small" aria-label={t('results')}>
        {(['facility', 'area'] satisfies Kind[]).map((kind) => <Link key={kind}
          href={withQuery(base, queryParams({ ...options, kind }))} aria-current={query.kind === kind ? 'page' : undefined}>
          {t(kind === 'facility' ? 'facilities' : 'areas')}</Link>)}
      </nav>
    </div>
    <form method="get" action={base} className="filters">
      <input type="hidden" name="kind" value={query.kind} />
      <input type="hidden" name="scope" value={query.scope} />
      {query.limit !== 20 && <input type="hidden" name="limit" value={query.limit} />}
      <div className="filter-field">
        <label htmlFor="filter-prefecture">{t('region')}</label>
        <select id="filter-prefecture" name="prefecture" defaultValue={query.prefecture ?? ''}>
          <option value="">{t('allRegions')}</option>
          {regions.map((code) => <option key={code} value={code}>{regionName(code, locale)}</option>)}
        </select>
      </div>
      <div className="filter-field">
        <label htmlFor="filter-quality">{t('quality')}</label>
        <select id="filter-quality" name="quality" defaultValue={query.quality ?? ''}>
          <option value="">{t('allQualities')}</option>
          {qualities.map((quality, index) => <option key={quality} value={quality}>{qualityNames[locale][index]}</option>)}
        </select>
      </div>
      <div className="filter-field">
        <label htmlFor="filter-price">{t('price')}</label>
        <input id="filter-price" name="maxDayPriceJpy" type="number" min={0} max={999999} step={1} inputMode="numeric"
          placeholder="JPY" defaultValue={query.maxDayPriceJpy} aria-describedby="price-rule" />
      </div>
      <button className="button filter-submit" type="submit"><SlidersHorizontal size={17} aria-hidden="true" />{t('apply')}</button>
    </form>
    <div className="filter-foot"><p id="price-rule">{t('priceRule')}</p>
      <Link href={withQuery(base, queryParams({ ...options, prefecture: undefined, quality: undefined, maxDayPriceJpy: undefined }))}>{t('reset')}</Link>
    </div>
  </div>;
}
