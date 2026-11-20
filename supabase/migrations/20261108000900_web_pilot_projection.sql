-- This approval covers the three pilot identities and their reviewed reference positions.
-- It does not approve the rest of the facility catalog or require an exact entrance pin.
create table core.web_pilot_scope (
    slug text primary key,
    name_ja text not null,
    address_ja text not null,
    node_code text not null unique,
    latitude numeric(8,6) not null,
    longitude numeric(9,6) not null,
    source_url text not null,
    approved_at timestamptz not null
);

insert into core.web_pilot_scope values
    ('wakkanai-onsen-domu', '稚内温泉童夢', '〒097-0027 北海道稚内市富士見4丁目1487番',
        'WAKKANAI_DOMU_ACCESS', 45.421978, 141.639374, 'https://onsen-domu.com/access', '2026-11-08 00:00:00+09'),
    ('daiichi-takimotokan', '第一滝本館', '北海道登別市登別温泉町55番地',
        'TAKIMOTOKAN_ACCESS', 42.494759, 141.145325, 'https://takimotokan.co.jp/ja/access/', '2026-11-08 00:00:00+09'),
    ('takegawara-onsen', '竹瓦温泉', '〒874-0944 別府市元町16番23号',
        'TAKEGAWARA_ACCESS', 33.277480, 131.505980, 'https://www.city.beppu.oita.jp/sisetu/shieionsen/detail4.html', '2026-11-08 00:00:00+09');

create view api.web_pilot_entries with (security_barrier = true) as
select 'pilot-2026-11-08'::text as release_id, entity.id as entity_id, entity.kind, entity.prefecture_code,
    scope.slug, scope.name_ja, scope.address_ja as location_ja, scope.latitude, scope.longitude,
    facility.facility_type, true as in_journey, scope.source_url as public_source_url,
    scope.approved_at as verified_at, node.coordinate_accuracy
from core.web_pilot_scope scope
join core.catalog_entities entity on entity.slug = scope.slug and entity.kind = 'facility'
join core.facilities facility on facility.entity_id = entity.id
join core.transport_nodes node on node.code = scope.node_code and node.facility_id = entity.id
join ingest.source_documents coord_doc on coord_doc.id = node.coordinate_source_document_id
join ingest.source_policy_versions coord_policy on coord_policy.id = coord_doc.policy_version_id
join ingest.source_registry coord_source on coord_source.id = coord_policy.source_id
where not entity.test_only and entity.review_state in ('in_review', 'approved')
  and entity.name_ja = scope.name_ja and node.latitude = scope.latitude and node.longitude = scope.longitude
  and node.coordinate_accuracy in ('address_reference', 'facility_location')
  and coord_source.active and coord_policy.revoked_at is null and coord_policy.store_facts = 'allowed'
  and coord_policy.publish_facts in ('allowed', 'conditional')
  and exists (
      select 1 from ingest.source_documents doc
      join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
      join ingest.source_registry source on source.id = policy.source_id
      where doc.source_url = scope.source_url and source.active and policy.revoked_at is null and policy.store_facts = 'allowed'
        and policy.publish_facts in ('allowed', 'conditional')
  );

-- Invoker views preserve the existing releases and published_entries RLS for both readers.
create view api.web_catalog_versions with (security_invoker = true) as
select id::text as release_id, status, published_at as as_of from api.releases
where status in ('active', 'retained')
union all
select 'pilot-2026-11-08', 'active', max(verified_at) from api.web_pilot_entries
where not exists (select 1 from api.releases where status = 'active') having count(*) > 0;

create view api.web_catalog_entries with (security_invoker = true) as
with eligible as (
    select release_id::text as release_id, entity_id, kind, prefecture_code, slug, name_ja, location_ja,
        latitude, longitude, facility_type, in_journey, public_source_url, verified_at,
        'catalog_location'::text as coordinate_accuracy
    from api.published_entries
    union all
    select * from api.web_pilot_entries
    where not exists (select 1 from api.releases where status = 'active')
)
select eligible.*, coalesce(quality.codes, '{}'::text[]) as quality_codes,
    null::integer as day_admission_jpy
from eligible
left join lateral (
    select array_agg(distinct codes.code order by codes.code) as codes
    from api.published_spring_analyses analysis cross join lateral unnest(analysis.quality_codes) codes(code)
    where eligible.kind = 'facility' and analysis.facility_slug = eligible.slug
) quality on true;

create view api.web_pilot_route_legs with (security_barrier = true) as
select entry.slug as facility_slug, route.route_key, route.travel_mode, route.verified_at, route.valid_until,
    route.duration_minutes, route.fare_jpy, route.transfers, route_doc.source_url as route_source_url,
    leg.seq, leg.mode, departure.code as from_code, departure.name_ja as from_name_ja,
    arrival.code as to_code, arrival.name_ja as to_name_ja, leg.operator_name, leg.service_name,
    leg.duration_minutes as leg_duration_minutes, leg.fare_jpy as leg_fare_jpy,
    leg.reservation_required, leg_doc.source_url as leg_source_url
from api.web_pilot_entries entry
join core.current_verified_routes route on route.facility_id = entry.entity_id
join (values ('wakkanai-onsen-domu', 'wakkanai-domu-transit'),
    ('daiichi-takimotokan', 'noboribetsu-takimotokan-transit'),
    ('takegawara-onsen', 'beppu-takegawara-walk'), ('takegawara-onsen', 'beppu-takegawara-bus16')) as scope(slug, route_key)
    on scope.slug = entry.slug and scope.route_key = route.route_key
join core.route_legs leg on leg.route_id = route.id
join core.transport_nodes departure on departure.id = leg.departure_node_id
join core.transport_nodes arrival on arrival.id = leg.arrival_node_id
join ingest.source_documents route_doc on route_doc.id = route.source_document_id
join ingest.source_documents leg_doc on leg_doc.id = leg.source_document_id
where exists (select 1 from core.route_verification_sources proof
        where proof.route_id = route.id and proof.source_document_id = route_doc.id)
  and exists (select 1 from core.route_verification_sources proof
        where proof.route_id = route.id and proof.source_document_id = leg_doc.id)
  and not exists (
      select 1 from core.route_verification_sources proof
      join ingest.source_documents doc on doc.id = proof.source_document_id
      join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
      where proof.route_id = route.id and policy.publish_facts not in ('allowed', 'conditional')
  )
  and not exists (
      select 1 from (
          select edge.*, row_number() over (order by seq) as ordinal, count(*) over () as edge_count,
              lag(arrival_node_id) over (order by seq) as previous_arrival
          from core.route_legs edge where edge.route_id = route.id
      ) chain
      where chain.seq <> chain.ordinal
         or chain.departure_node_id <> coalesce(chain.previous_arrival, route.departure_node_id)
         or (chain.ordinal = chain.edge_count and chain.arrival_node_id is distinct from route.arrival_node_id)
         or not exists (select 1 from core.route_verification_sources proof
             where proof.route_id = route.id and proof.source_document_id = chain.source_document_id)
  );

revoke all on core.web_pilot_scope, api.web_pilot_entries, api.web_catalog_versions, api.web_catalog_entries,
    api.web_pilot_route_legs from public, anon, authenticated, service_role;
grant select on api.web_pilot_entries, api.web_catalog_versions, api.web_catalog_entries, api.web_pilot_route_legs
    to anon, authenticated;
