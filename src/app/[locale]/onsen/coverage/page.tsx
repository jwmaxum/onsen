import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Shell } from '@/components/shell';
import { getAreaInventoryProgress, getCoverage } from '@/lib/catalog';
import { isLocale } from '@/lib/catalog-query';
import { coverageText } from '@/lib/coverage-copy';
import { localDate, text } from '@/lib/i18n';
import { pageMetadata } from '@/lib/metadata';

type Props = { params: Promise<{ locale: string }>; searchParams: Promise<{ kind?: string | string[] }> };

export async function generateMetadata({ params }: Props) {
  const { locale } = await params;
  if (!isLocale(locale)) return {};
  const copy = coverageText(locale);
  return pageMetadata(locale, (value) => `/${value}/onsen/coverage`, copy.title, copy.intro);
}

export default async function CoveragePage({ params, searchParams }: Props) {
  const [{ locale }, query] = await Promise.all([params, searchParams]);
  if (!isLocale(locale)) notFound();
  const kind = query.kind === 'area' ? 'area' : 'facility';
  const copy = coverageText(locale);
  const path = `/${locale}/onsen/coverage`;
  const suffix = kind === 'area' ? '?kind=area' : '';
  const [rows, inventory] = await Promise.all([
    getCoverage(kind).catch(() => null),
    kind === 'area' ? getAreaInventoryProgress().catch(() => null) : null,
  ]);
  const areaProgress = new Map(inventory?.map((row) => [row.prefecture_code, row]));
  const benchmark = inventory?.find((row) => row.source_url);
  const completeBenchmark = inventory?.length === 47 && inventory.every((row) =>
    row.official_areas_with_lodging !== null && row.fiscal_year === benchmark?.fiscal_year && row.as_of === benchmark?.as_of);
  const officialTotal = completeBenchmark
    ? inventory.reduce((total, row) => total + (row.official_areas_with_lodging ?? 0), 0) : null;
  const registered = completeBenchmark && inventory.every((row) => typeof row.registered_official_areas === 'number')
    ? inventory.reduce((total, row) => total + row.registered_official_areas, 0) : null;
  const number = new Intl.NumberFormat(locale);
  return <Shell locale={locale} hrefFor={(value) => `/${value}/onsen/coverage${suffix}`}>
    <div className="container coverage-page">
      <Link className="back-link" href={`/${locale}/onsen`}>{copy.directory}</Link>
      <h1>{copy.title}</h1>
      <p className="coverage-intro">{copy.intro}</p>
      <nav className="segmented" aria-label={copy.counts}>
        <Link href={path} aria-current={kind === 'facility' ? 'page' : undefined}>{copy.facility}</Link>
        <Link href={`${path}?kind=area`} aria-current={kind === 'area' ? 'page' : undefined}>{copy.area}</Link>
      </nav>
      {kind === 'area' && <div className="coverage-intro">
        {officialTotal !== null && <p><strong>{copy.officialAreas} · {number.format(officialTotal)}</strong>
          {benchmark?.as_of && <> · <time dateTime={benchmark.as_of}>{localDate(benchmark.as_of, locale)}</time></>}</p>}
        {registered !== null && <p>{copy.registeredOfficial} · {number.format(registered)}</p>}
        {officialTotal !== null && registered !== null && <p>{copy.officialRemaining} · {number.format(officialTotal - registered)}</p>}
        <p>{copy.benchmarkNote}</p>
        {benchmark?.source_url && <p className="source-links">
          <a href={benchmark.source_url} lang="ja">{benchmark.attribution}</a>
          <a href="https://www.env.go.jp/council/content/12nature08/000360911.pdf">{copy.designatedAreas}</a>
          <a href="https://tsunagu.japanrealtor.jp/onsen/index.html" lang="ja">出典：TSUNAGU（ジャパンリアルター株式会社）</a>
          <a href="https://www.wikidata.org/wiki/Q655311">Wikidata · CC0</a>
        </p>}
      </div>}
      {rows ? <div className="coverage-table-wrap" tabIndex={0} role="region" aria-label={copy.title}>
        <table className="coverage-table">
          <thead><tr><th scope="col">{copy.prefecture}</th><th scope="col">{copy.status}</th>
            <th scope="col">{copy.counts}</th><th scope="col">{copy.gap}</th></tr></thead>
          <tbody>{rows.map((row) => {
            const progress = areaProgress.get(row.prefecture_code);
            return <tr key={row.prefecture_code} data-prefecture={row.prefecture_code}>
            <th scope="row" lang={locale === 'en' ? 'en' : 'ja'}>{locale === 'en' ? row.name_en : row.name_ja}</th>
            <td>{row.status === 'published' ? copy.partial_publication : copy[row.status]}</td>
            <td><dl>{(['sources', 'candidates', 'reviewed', 'published', 'withdrawn'] as const).map((field) => <div key={field}>
              <dt>{copy[field]}</dt><dd>{field === 'sources' ? row.registered_sources : row[field]}</dd>
            </div>)}
              {progress && <>
                <div><dt>{copy.officialAreas}</dt><dd>{progress.official_areas_with_lodging ?? '—'}</dd></div>
                {registered !== null && <>
                  <div><dt>{copy.registeredOfficial}</dt><dd>{progress.registered_official_areas}</dd></div>
                  <div><dt>{copy.officialRemaining}</dt><dd>{progress.official_areas_remaining ?? '—'}</dd></div>
                </>}
                <div><dt>{copy.designatedAreas}</dt><dd>{progress.designated_areas}</dd></div>
                <div><dt>{copy.discoveryRecords}</dt><dd>{progress.discovery_records}</dd></div>
              </>}
            </dl></td>
            <td><div>{row.gap_codes.map((code) => copy[code]).filter(Boolean).join(' · ') || '—'}</div>
              {progress && <div>{copy[progress.reconciliation_gap]}</div>}
              {row.checked_on ? <time dateTime={row.checked_on}>{localDate(row.checked_on, locale)}</time> : <small>{copy.unknown}</small>}</td>
          </tr>;
          })}</tbody>
        </table>
      </div> : <p role="alert" className="empty-panel">{text(locale)('unavailable')}</p>}
    </div>
  </Shell>;
}
