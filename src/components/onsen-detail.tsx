import { ArrowRight, BusFront, Footprints, TestTubeDiagonal } from 'lucide-react';
import type { Locale } from '@/lib/catalog-query';
import type { Analysis, RouteLeg } from '@/lib/catalog-types';
import { localDate, routeLabel, routeNote, stopLabel, text, yen } from '@/lib/i18n';

export function AnalysisCards({ rows, locale }: { rows: Analysis[]; locale: Locale }) {
  const t = text(locale);
  const number = new Intl.NumberFormat(locale, { maximumFractionDigits: 2 });
  return <section className="detail-section" aria-labelledby="analysis-heading">
    <div className="section-heading"><div><span className="eyebrow"><TestTubeDiagonal size={16} aria-hidden="true" />{t('source')}</span>
      <h2 id="analysis-heading">{t('analyses')}</h2><p>{t('analysisNote')}</p></div></div>
    {rows.length ? <div className="analysis-grid">{rows.map((row) => <article className="analysis-card" key={row.analysis_id}>
      <div lang={row.locale}>
        {row.locale !== locale && <span className="tag">{t('original')}</span>}
        <h3>{row.sample_name}</h3><p className="analysis-type">{row.quality_name}</p>
        <p className="analysis-note">{row.sample_note}</p>
      </div>
      <dl className="measurements">
        <div><dt>{t('temperature')}</dt><dd>{number.format(row.source_temp_celsius)} °C</dd></div>
        <div><dt>{t('fieldPh')}</dt><dd>{number.format(row.ph_onsite)}</dd></div>
        <div><dt>{t('labPh')}</dt><dd>{number.format(row.ph_laboratory)}</dd></div>
      </dl>
      <dl className="analysis-dates">
        <div><dt>{t('sampled')}</dt><dd><time dateTime={row.sampled_on}>{localDate(row.sampled_on, locale)}</time></dd></div>
        <div><dt>{t('analyzed')}</dt><dd><time dateTime={row.analyzed_on}>{localDate(row.analyzed_on, locale)}</time></dd></div>
      </dl>
      <div className="provenance">
        <p lang={row.locale}>{row.source_attribution}</p>
        {row.source_modified && <p><strong>{t('processed')}</strong> <span lang={row.locale}>{row.source_transformation}</span></p>}
        <p>{t('accessed')} <time dateTime={row.source_accessed_on}>{localDate(row.source_accessed_on, locale)}</time></p>
        <div className="source-links"><a href={row.source_url}>{t('source')} · <span lang="ja">{row.source_publisher}</span></a>
          <a href={row.source_terms_url} title={row.source_license}>{t('terms')}</a></div>
      </div>
    </article>)}</div> : <p className="empty-panel">{t('noAnalysis')}</p>}
  </section>;
}

export function RouteCards({ legs, locale }: { legs: RouteLeg[]; locale: Locale }) {
  const t = text(locale);
  const routes = new Map<string, RouteLeg[]>();
  for (const leg of legs) {
    const previous = routes.get(leg.route_key);
    if (previous) previous.push(leg);
    else routes.set(leg.route_key, [leg]);
  }
  return <section className="detail-section" aria-labelledby="transport-heading">
    <div className="section-heading"><div><span className="eyebrow"><BusFront size={16} aria-hidden="true" />{t('verified')}</span>
      <h2 id="transport-heading">{t('transport')}</h2><p>{t('transportNote')}</p></div></div>
    {routes.size ? <div className="route-grid">{[...routes].map(([key, route]) => {
      const first = route[0];
      const note = routeNote(key, locale);
      return <article className="route-card" key={key}>
        <div className="route-head"><div className="route-icon">{first.travel_mode === 'walk' ? <Footprints aria-hidden="true" /> : <BusFront aria-hidden="true" />}</div>
          <div><h3>{routeLabel(key, locale)}</h3><p>{t('verified')} <time dateTime={first.verified_at}>{localDate(first.verified_at, locale)}</time></p></div>
        </div>
        <div className="route-summary">
          <span className="tag">{t('total')} · {first.duration_minutes === null ? t('pending') : t('minutes', { minutes: first.duration_minutes })}</span>
          <span className="tag">{t('fare')} · {first.fare_jpy === null ? t('pending') : yen(first.fare_jpy, locale)}</span>
          {first.transfers !== null && <span className="tag">{t('transfers', { count: first.transfers })}</span>}
        </div>
        <ol className="legs">
          {route.map((leg) => <li key={leg.seq} className="leg">
            <span className="leg-number" aria-hidden="true">{leg.seq}</span>
            <div>
              <p className="leg-mode">{t(leg.mode)}{leg.leg_duration_minutes !== null && <> · {t('minutes', { minutes: leg.leg_duration_minutes })}</>}</p>
              <p className="leg-points"><span>{stopLabel(leg.from_code, leg.from_name_ja, locale)}</span>
                <ArrowRight size={15} aria-hidden="true" /><span>{stopLabel(leg.to_code, leg.to_name_ja, locale)}</span></p>
              {(leg.operator_name || leg.service_name) && <p lang="ja" className="leg-operator">{[leg.operator_name, leg.service_name].filter(Boolean).join(' · ')}</p>}
              {leg.reservation_required !== null && <p className="leg-operator">{t(leg.reservation_required ? 'reservationYes' : 'reservationNo')}</p>}
              {leg.leg_source_url !== first.route_source_url && <a className="leg-source" href={leg.leg_source_url}>{t('legSource')}</a>}
            </div>
          </li>)}
        </ol>
        {note && <p className="route-note">{note}</p>}
        <div className="source-links route-sources"><a href={first.route_source_url}>{t('routeSource')}</a>
          {first.valid_until && <span>{t('validUntil')} <time dateTime={first.valid_until}>{localDate(first.valid_until, locale)}</time></span>}</div>
      </article>;
    })}</div> : <p className="empty-panel">{t('noRoute')}</p>}
  </section>;
}
