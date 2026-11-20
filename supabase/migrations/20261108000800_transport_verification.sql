alter table core.transport_nodes
    alter column latitude drop not null, alter column longitude drop not null,
    add column facility_id uuid references core.facilities,
    add column coordinate_source_document_id uuid references ingest.source_documents,
    add column coordinate_accuracy text not null default 'unverified' check (coordinate_accuracy in (
        'unverified', 'station_representative', 'stop_representative', 'address_reference',
        'facility_location', 'gtfs_boarding_point'
    )),
    add constraint transport_node_coordinate_pair check ((latitude is null) = (longitude is null)),
    add constraint transport_node_geocoded_candidate check (not is_hub_candidate or latitude is not null),
    add constraint transport_node_coordinate_source check (
        coordinate_accuracy = 'unverified' or (latitude is not null and coordinate_source_document_id is not null)
    ),
    add constraint transport_node_entrance_facility check (facility_id is null or kind = 'entrance'),
    add unique (id, facility_id);

create table ingest.gtfs_feed_checks (
    source_document_id uuid primary key references ingest.source_documents,
    feed_version text not null,
    timezone text not null,
    valid_from date not null,
    valid_until date not null check (valid_until >= valid_from),
    checked_on date not null,
    stop_count integer not null check (stop_count > 0),
    trip_count integer not null check (trip_count > 0),
    validation jsonb not null check (jsonb_typeof(validation) = 'object')
);

create table ingest.gtfs_stop_links (
    feed_document_id uuid not null references ingest.gtfs_feed_checks,
    stop_id text not null,
    transport_node_id uuid not null references core.transport_nodes,
    primary key (feed_document_id, stop_id),
    unique (feed_document_id, transport_node_id)
);

create table ingest.gtfs_service_day_checks (
    feed_document_id uuid not null,
    board_stop_id text not null,
    alight_stop_id text not null,
    service_on date not null,
    status text not null check (status in ('service', 'no_service', 'out_of_range')),
    eligible_trip_count integer,
    active_service_ids text[] not null,
    primary key (feed_document_id, board_stop_id, alight_stop_id, service_on),
    foreign key (feed_document_id, board_stop_id) references ingest.gtfs_stop_links,
    foreign key (feed_document_id, alight_stop_id) references ingest.gtfs_stop_links,
    check (board_stop_id <> alight_stop_id),
    check ((status = 'out_of_range' and eligible_trip_count is null and cardinality(active_service_ids) = 0)
        or (status = 'no_service' and eligible_trip_count is not null and eligible_trip_count = 0)
        or (status = 'service' and eligible_trip_count is not null and eligible_trip_count > 0
            and cardinality(active_service_ids) > 0))
);

alter table core.routes
    add column route_key text unique check (route_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    add column arrival_node_id uuid,
    add column gtfs_feed_document_id uuid references ingest.gtfs_feed_checks,
    add foreign key (arrival_node_id, facility_id) references core.transport_nodes (id, facility_id);

create table core.route_verification_sources (
    route_id uuid not null references core.routes,
    source_document_id uuid not null references ingest.source_documents,
    primary key (route_id, source_document_id)
);

create view core.current_verified_routes as
select route.* from core.routes route
left join ingest.gtfs_feed_checks feed on feed.source_document_id = route.gtfs_feed_document_id
where route.review_state = 'approved'
  and (route.valid_from is null or route.valid_from <= (now() at time zone 'Asia/Tokyo')::date)
  and (route.valid_until is null or route.valid_until >= (now() at time zone 'Asia/Tokyo')::date)
  and (route.gtfs_feed_document_id is null or (now() at time zone 'Asia/Tokyo')::date between feed.valid_from and feed.valid_until)
  and not exists (
      select 1 from core.route_verification_sources evidence
      join ingest.source_documents document on document.id = evidence.source_document_id
      join ingest.source_policy_versions policy on policy.id = document.policy_version_id
      join ingest.source_registry source on source.id = policy.source_id
      where evidence.route_id = route.id and (not source.active or policy.revoked_at is not null or policy.store_facts <> 'allowed')
  );

revoke all on ingest.gtfs_feed_checks, ingest.gtfs_stop_links, ingest.gtfs_service_day_checks
    from public, anon, authenticated, service_role;
revoke all on core.route_verification_sources, core.current_verified_routes from public, anon, authenticated, service_role;
grant select, insert on ingest.gtfs_feed_checks to onsen_ingestor;
grant select on ingest.gtfs_feed_checks to onsen_reviewer;
grant select, insert on ingest.gtfs_stop_links, ingest.gtfs_service_day_checks to onsen_reviewer;
grant select, insert on core.route_verification_sources to onsen_reviewer;
grant select on core.current_verified_routes to onsen_reviewer;

with evidence(source_key, publisher, prefecture_code, source_url, terms_url, license_label, digest) as (values
    ('wakkanai_terminal_map', '稚内市', '01', 'https://www.city.wakkanai.hokkaido.jp/files/00012100/00012140/20240712094429.pdf', 'https://www.city.wakkanai.hokkaido.jp/disclaimer.html', 'Manual factual reference', null),
    ('domu_operator', '稚内温泉童夢', '01', 'https://onsen-domu.com/access', null, 'Manual factual reference', null),
    ('north_hokkaido_tourism', '稚内観光協会', '01', 'https://www.north-hokkaido.com/feature/detail_83.html', null, 'Manual factual reference', null),
    ('donan_bus', '道南バス', '01', 'https://www.donanbus.co.jp/map/noboribetsu_ashiyu/', null, 'Manual factual reference', null),
    ('takimotokan', '第一滝本館', '01', 'https://takimotokan.co.jp/ja/access/', null, 'Manual factual reference', null),
    ('beppu_city', '別府市', '44', 'https://www.city.beppu.oita.jp/sisetu/shieionsen/detail4.html', 'https://www.city.beppu.oita.jp/about.html', 'Manual factual reference', null),
    ('mlit_rail_points', '国土交通省 国土数値情報', null, 'https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html', 'https://creativecommons.org/licenses/by/4.0/', 'CC BY 4.0', null),
    ('mlit_bus_points', '国土交通省 国土数値情報', '01', 'https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-P11-2022.html', 'https://creativecommons.org/licenses/by/4.0/', 'CC BY 4.0', null),
    ('gsi_address_points', '国土地理院', null, 'https://msearch.gsi.go.jp/address-search/AddressSearch?q=%E7%A8%9A%E5%86%85%E5%B8%82%E5%AF%8C%E5%A3%AB%E8%A6%8B%E5%9B%9B%E4%B8%81%E7%9B%AE1487%E7%95%AA%E5%9C%B0', 'https://web1.gsi.go.jp/kikakuchousei/kikakuchousei40182.html', 'Public Data License 1.0', null),
    ('gsi_address_points', '国土地理院', null, 'https://msearch.gsi.go.jp/address-search/AddressSearch?q=%E7%99%BB%E5%88%A5%E5%B8%82%E7%99%BB%E5%88%A5%E6%B8%A9%E6%B3%89%E7%94%BA55%E7%95%AA%E5%9C%B0', 'https://web1.gsi.go.jp/kikakuchousei/kikakuchousei40182.html', 'Public Data License 1.0', null),
    ('beppu_facility_points', '別府市', '44', 'https://data.bodik.jp/dataset/442020_public/resource/ded14bf6-bd5a-4925-8e52-8f088d581194', 'https://creativecommons.org/licenses/by/4.0/', 'CC BY 4.0', null),
    ('oita_kamenoibus_gtfs', '大分県・亀の井バス', '44', 'https://data.bodik.jp/dataset/b9319381-3841-4a1c-a796-33e7953b193a/resource/8d18cbd7-eef0-48c6-9fa3-eae936d56f40/download/gtfs08_kamenoibus.zip', 'https://creativecommons.org/licenses/by/4.0/', 'CC BY 4.0', '4a666380b31525fe2dee928bc0c966fb06741acf7400617d9fe8e18809516601'),
    ('kamenoibus_operator', '亀の井バス', '44', 'https://kamenoibus.com/scheduled_howto/', null, 'Manual factual reference', null),
    ('kamenoibus_operator', '亀の井バス', '44', 'https://kamenoibus.com/scheduled_tt/pdf/202603/16d.pdf', null, 'Manual factual reference', null),
    ('kamenoibus_operator', '亀の井バス', '44', 'https://kamenoibus.com/scheduled_tt/pdf/202603/16e.pdf', null, 'Manual factual reference', null)
), registered as (
    insert into ingest.source_registry (source_key, publisher, prefecture_code, homepage_url, active)
    select distinct on (source_key) source_key, publisher, prefecture_code, source_url, true
    from evidence order by source_key, source_url
    on conflict (source_key) do update set source_key = excluded.source_key
    returning id, source_key
), policies as (
    insert into ingest.source_policy_versions (source_id, version, terms_url, license_label, reviewed_at, reviewed_by,
        auto_fetch, archive_raw, store_facts, publish_facts, robots_status, robots_http_status,
        max_requests_per_minute, attribution, conditions)
    select distinct on (registered.id) registered.id, 1, evidence.terms_url, evidence.license_label,
        '2026-11-08 00:00:00+09'::timestamptz, 'phase4_source_review',
        (case when evidence.digest is not null then 'allowed' else 'pending' end)::ingest.permission_decision,
        'denied', 'allowed', 'conditional',
        case when evidence.digest is not null then 'allowed' else 'unverified' end,
        case when evidence.digest is not null then 200 end,
        case when evidence.digest is not null then 30 end,
        evidence.publisher || ' / ' || evidence.license_label,
        'Exact reviewed transport facts and source links only. Exclude site copies, timetable PDFs and raw feed archival.'
    from registered join evidence using (source_key)
    order by registered.id, evidence.source_url
    on conflict (source_id, version) do update set version = excluded.version
    returning id, source_id
)
insert into ingest.source_policy_urls (policy_version_id, source_url, approved_content_sha256)
select policies.id, evidence.source_url, evidence.digest
from policies join registered on registered.id = policies.source_id join evidence using (source_key)
on conflict (policy_version_id, source_url) do nothing;
