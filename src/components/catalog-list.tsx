'use client';

import Link from 'next/link';
import { useState } from 'react';
import { ArrowDown, ArrowUpRight, Compass, MapPin } from 'lucide-react';
import { detailPath, qualities, queryParams, withQuery, type CatalogQuery } from '@/lib/catalog-query';
import type { CatalogPage, Entry } from '@/lib/catalog-types';
import { entryLanguage, entryName, qualityNames, regionName, text, yen } from '@/lib/i18n';

type Card = { entry: Entry; originCursor?: string };

export function CatalogList({ initial, query }: { initial: CatalogPage; query: CatalogQuery }) {
  const { locale } = query;
  const t = text(locale);
  const [cards, setCards] = useState<Card[]>(() => initial.items.map((entry) => ({ entry, originCursor: query.cursor })));
  const [nextCursor, setNextCursor] = useState(initial.nextCursor);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const coordinateCredits = new Map(cards.flatMap(({ entry }) =>
    entry.coordinate_source_url && entry.coordinate_attribution
      ? [[entry.coordinate_attribution, entry.coordinate_source_url] as const] : []));

  async function loadMore() {
    if (!nextCursor || busy) return;
    setBusy(true);
    setError(undefined);
    try {
      const href = withQuery('/api/v1/onsen-entries', queryParams({ ...query, cursor: nextCursor }, { api: true }));
      const response = await fetch(href, { cache: 'no-store' });
      if (!response.ok) {
        setError(response.status === 409 ? t('expired') : t('unavailable'));
        return;
      }
      const page: CatalogPage = await response.json();
      if (page.releaseId !== initial.releaseId) { setError(t('expired')); return; }
      setCards((current) => {
        const known = new Set(current.map(({ entry }) => entry.entity_id));
        return [...current, ...page.items.filter((entry) => !known.has(entry.entity_id))
          .map((entry) => ({ entry, originCursor: nextCursor }))];
      });
      setNextCursor(page.nextCursor);
    } catch {
      setError(t('unavailable'));
    } finally { setBusy(false); }
  }

  return <div className="browse-grid">
    <section className="directory" aria-labelledby="results-heading">
      <div className="section-heading list-heading">
        <div><span className="eyebrow"><ArrowDown size={14} aria-hidden="true" />{t('northSouth')}</span><h2 id="results-heading">{t('results')}</h2></div>
        <span className="result-count" aria-live="polite">{t('count', { count: cards.length })}</span>
      </div>
      {cards.length ? <ol className="entry-list">
        {cards.map(({ entry, originCursor }, index) => {
          const target = withQuery(detailPath(locale, entry.kind, entry.slug), queryParams({ ...query, cursor: originCursor }, { release: entry.release_id }));
          const name = entryName(entry, locale);
          return <li key={entry.entity_id} id={`entry-${entry.slug}`}>
            <Link className="entry-card" href={target}>
              <div className="entry-index" aria-hidden="true">{String(index + 1).padStart(2, '0')}</div>
              <div className="entry-body">
                <div className="entry-meta"><span className="region-label"><MapPin size={13} aria-hidden="true" />{regionName(entry.prefecture_code, locale)}</span>
                  <span className="latitude" dir="ltr">{entry.latitude.toFixed(3)}° N</span></div>
                <h3 lang={entryLanguage(entry, locale)}>{name}</h3>
                {name !== entry.name_ja && <p className="original-name" lang="ja">{entry.name_ja}</p>}
                <div className="entry-facts">
                  {entry.quality_codes.map((code) => <span className="tag" key={code}>{qualityNames[locale][qualities.indexOf(code)]}</span>)}
                  {entry.day_admission_jpy !== null && <span className="tag">{yen(entry.day_admission_jpy, locale)}</span>}
                </div>
              </div>
              <span className="entry-action"><span>{entry.kind === 'facility' ? t('view') : t('areaView')}</span><ArrowUpRight size={19} aria-hidden="true" /></span>
            </Link>
          </li>;
        })}
      </ol> : <p className="empty-panel">{query.kind === 'area' && !query.prefecture && !query.quality ? t('noAreas') : t('noResults')}</p>}
      {nextCursor && <button className="button more-button" onClick={loadMore} disabled={busy}>{busy ? t('loading') : t('more')}</button>}
      {error && <p className="fetch-error" role="alert">{error}</p>}
    </section>
    <aside className="map-panel" aria-labelledby="map-heading">
      <div className="map-heading"><Compass size={21} aria-hidden="true" /><h2 id="map-heading">{t('mapTitle')}</h2></div>
      <p>{t('mapNote')}</p>
      <svg viewBox="0 0 350 360" className="atlas-map" aria-label={t('mapTitle')}>
        <image href="/japan.svg" width="350" height="360" aria-hidden="true" />
        {cards.map(({ entry }, index) => {
          const x = (entry.longitude - 126.5) * 17;
          const y = (46.5 - entry.latitude) * 17;
          if (x < 0 || y < 0 || x > 350 || y > 360) return null;
          return <a key={entry.entity_id} href={`#entry-${entry.slug}`} aria-label={entryName(entry, locale)}>
            <circle cx={x} cy={y} r="25" fill="transparent" />
            <circle cx={x} cy={y} r="12" className="map-pin" />
            <text x={x} y={y} dy=".33em" textAnchor="middle" className="map-number" aria-hidden="true">{index + 1}</text>
          </a>;
        })}
      </svg>
      <div className="map-caption"><span className="map-dot" aria-hidden="true" />{t('northSouth')}<span className="map-credit">{t('mapCredit')}</span></div>
      {coordinateCredits.size > 0 && <ul className="map-attributions">
        {[...coordinateCredits].map(([label, url]) => <li key={label}>
          <a href={url} target="_blank" rel="noopener noreferrer">{label}</a></li>)}
      </ul>}
    </aside>
  </div>;
}
