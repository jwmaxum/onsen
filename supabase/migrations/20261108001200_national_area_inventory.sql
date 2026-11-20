-- Extracted numeric cells from the Ministry of the Environment FY2024 PDF.
insert into ingest.source_registry (source_key, publisher, homepage_url, active)
values ('moe_usage', '環境省', 'https://www.env.go.jp/nature/onsen/data/', true);

with policy as (
    insert into ingest.source_policy_versions
        (source_id, version, terms_url, license_label, reviewed_at, reviewed_by, auto_fetch, archive_raw,
         store_facts, publish_facts, translate_content, publish_images, robots_status, attribution, conditions)
    select id, 1, 'https://www.env.go.jp/mail.html', 'PDL 1.0', '2026-11-08', 'national-inventory-review',
        'denied', 'denied', 'allowed', 'allowed', 'denied', 'denied', 'allowed',
        '環境省「令和6年度温泉利用状況」から都道府県別の数値を抽出',
        'Manual review of one PDF. Publish transformed numerical cells with original source and extraction disclosure.'
    from ingest.source_registry where source_key = 'moe_usage'
    returning id, source_id
), allowlist as (
    insert into ingest.source_policy_urls
    select id, 'https://www.env.go.jp/nature/onsen/pdf/6-7_p_1.pdf' from policy
), run as (
    insert into ingest.harvest_runs (source_id, policy_version_id, mode, status, started_at, finished_at)
    select source_id, id, 'manual', 'succeeded', '2026-11-08', '2026-11-08' from policy returning id, policy_version_id
), doc as (
    insert into ingest.source_documents (run_id, policy_version_id, source_url, fetched_at, content_sha256, parser_version)
    select id, policy_version_id, 'https://www.env.go.jp/nature/onsen/pdf/6-7_p_1.pdf', '2026-11-08',
        '54f4099f2ac828bdaf73fb0f2ef54958b8b8a48f1e6d7aed879abb2c2c85c794', 'pdf-table-normalized-v1'
    from run returning id
)
insert into core.official_coverage_benchmarks
    (prefecture_code, fiscal_year, unit, counted, as_of, counting_definition, source_document_id)
select stats.code, 2024, metric.unit, metric.counted, date '2025-03-31', metric.definition, doc.id
from (values
    ('01', 226, 2249, 740, 437),
    ('02', 120, 1089, 216, 249),
    ('03', 81, 393, 227, 104),
    ('04', 39, 740, 252, 172),
    ('05', 104, 616, 203, 215),
    ('06', 67, 412, 252, 131),
    ('07', 122, 799, 474, 187),
    ('08', 39, 157, 74, 74),
    ('09', 66, 633, 414, 273),
    ('10', 98, 459, 631, 250),
    ('11', 31, 117, 53, 80),
    ('12', 95, 144, 188, 150),
    ('13', 22, 168, 41, 142),
    ('14', 36, 602, 586, 199),
    ('15', 135, 536, 490, 176),
    ('16', 61, 169, 115, 66),
    ('17', 48, 330, 191, 112),
    ('18', 38, 158, 125, 59),
    ('19', 29, 304, 208, 84),
    ('20', 193, 955, 998, 718),
    ('21', 55, 506, 331, 59),
    ('22', 118, 2185, 2397, 535),
    ('23', 35, 133, 90, 80),
    ('24', 74, 214, 363, 137),
    ('25', 27, 86, 56, 18),
    ('26', 37, 146, 182, 71),
    ('27', 17, 173, 42, 77),
    ('28', 78, 443, 322, 229),
    ('29', 34, 77, 73, 57),
    ('30', 50, 506, 364, 148),
    ('31', 15, 363, 100, 47),
    ('32', 41, 267, 106, 98),
    ('33', 32, 221, 81, 94),
    ('34', 56, 374, 75, 96),
    ('35', 40, 404, 131, 107),
    ('36', 25, 82, 29, 39),
    ('37', 28, 200, 55, 64),
    ('38', 37, 192, 97, 115),
    ('39', 37, 96, 73, 47),
    ('40', 46, 422, 97, 147),
    ('41', 21, 187, 86, 122),
    ('42', 37, 203, 94, 118),
    ('43', 55, 1339, 392, 337),
    ('44', 63, 5094, 914, 392),
    ('45', 29, 199, 67, 94),
    ('46', 87, 2735, 311, 485),
    ('47', 15, 22, 19, 30)
) stats(code, areas, springs, lodging, baths)
cross join doc
cross join lateral (values
    ('area_with_lodging', stats.areas, '温泉地数は宿泊施設数のある場所を計上'),
    ('spring', stats.springs, '源泉総数（利用・未利用の合計）'),
    ('lodging', stats.lodging, '宿泊施設数'),
    ('public_bath', stats.baths, '温泉利用の公衆浴場数')
) metric(unit, counted, definition);

create table core.national_area_designations (
    entity_id uuid primary key references core.onsen_areas,
    source_document_id uuid not null references ingest.source_documents,
    list_position integer not null check (list_position > 0),
    as_of_month date not null,
    unique (source_document_id, list_position)
);

create table core.national_area_designation_jurisdictions (
    entity_id uuid not null references core.national_area_designations,
    prefecture_code char(2) not null references core.prefectures,
    primary key (entity_id, prefecture_code)
);

create table ingest.area_inventory_candidates (
    source_document_id uuid not null references ingest.source_documents,
    external_id text not null check (btrim(external_id) <> ''),
    name_ja text check (btrim(name_ja) <> ''),
    prefecture_code char(2) references core.prefectures,
    location_note text,
    reference_url text check (reference_url ~ '^https://[^[:space:]]+$'),
    latitude numeric(8,6) check (latitude between -90 and 90),
    longitude numeric(9,6) check (longitude between -180 and 180),
    primary key (source_document_id, external_id),
    check ((latitude is null) = (longitude is null))
);

create view api.area_inventory_progress with (security_barrier = true) as
with live_docs as (
    select doc.id, doc.source_url, policy.attribution
    from ingest.source_documents doc
    join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
    join ingest.source_registry source on source.id = policy.source_id
    join ingest.source_policy_urls allowed on allowed.policy_version_id = policy.id and allowed.source_url = doc.source_url
    where source.active and policy.revoked_at is null and policy.publish_facts = 'allowed'
), latest_benchmark as (
    select distinct on (bench.prefecture_code) bench.prefecture_code, bench.fiscal_year, bench.as_of,
        bench.counted, doc.source_url, doc.attribution
    from core.official_coverage_benchmarks bench
    join live_docs doc on doc.id = bench.source_document_id
    where bench.unit = 'area_with_lodging'
    order by bench.prefecture_code, bench.fiscal_year desc
), designated as (
    select jurisdiction.prefecture_code, count(*)::integer as counted
    from core.national_area_designations designation
    join core.national_area_designation_jurisdictions jurisdiction on jurisdiction.entity_id = designation.entity_id
    join core.catalog_entities area on area.id = designation.entity_id
    join live_docs doc on doc.id = designation.source_document_id
    where not area.test_only and area.review_state <> 'withdrawn'
    group by jurisdiction.prefecture_code
), candidates as (
    select candidate.prefecture_code, count(*)::integer as counted
    from ingest.area_inventory_candidates candidate
    join live_docs doc on doc.id = candidate.source_document_id
    group by candidate.prefecture_code
)
select prefecture.code as prefecture_code, benchmark.fiscal_year, benchmark.as_of,
    benchmark.counted as official_areas_with_lodging, benchmark.source_url, benchmark.attribution,
    coalesce(designated.counted, 0) as designated_areas,
    coalesce(candidates.counted, 0) as discovery_records,
    'official_roster_unavailable'::text as reconciliation_gap
from core.prefectures prefecture
left join latest_benchmark benchmark on benchmark.prefecture_code = prefecture.code
left join designated on designated.prefecture_code = prefecture.code
left join candidates on candidates.prefecture_code = prefecture.code;

revoke all on core.national_area_designations, core.national_area_designation_jurisdictions,
    ingest.area_inventory_candidates, api.area_inventory_progress
    from public, anon, authenticated, service_role;
grant select on api.area_inventory_progress to anon, authenticated;
