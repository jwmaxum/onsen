create table core.web_reference_publications (
    entity_id uuid primary key references core.facilities,
    identity_observation_id uuid not null unique references ingest.field_observations,
    position_observation_id uuid not null unique references ingest.field_observations,
    reviewed_at timestamptz not null,
    withdrawn_at timestamptz,
    check (withdrawn_at is null or withdrawn_at >= reviewed_at)
);

create view core.web_reference_proofs as
select observation.id, observation.field_key, observation.value, record.entity_id,
    doc.source_url, policy.attribution
from ingest.field_observations observation
join ingest.external_records record on record.id = observation.external_record_id
join ingest.source_documents doc on doc.id = observation.source_document_id
join ingest.source_policy_versions policy on policy.id = doc.policy_version_id and policy.source_id = record.source_id
join ingest.source_registry source on source.id = policy.source_id
join ingest.source_policy_urls allowed on allowed.policy_version_id = policy.id and allowed.source_url = doc.source_url
where source.active and policy.revoked_at is null and policy.store_facts = 'allowed'
  and policy.publish_facts = 'allowed' and observation.value_state = 'confirmed';

create view core.web_reference_entries as
select entity.id as entity_id, entity.kind, entity.prefecture_code, entity.slug, entity.name_ja,
    facility.address_ja as location_ja, entity.latitude, entity.longitude, facility.facility_type,
    journey.included as in_journey, identity.source_url as public_source_url, publication.reviewed_at as verified_at,
    'facility_location'::text as coordinate_accuracy, position.source_url as coordinate_source_url,
    position.attribution as coordinate_attribution
from core.web_reference_publications publication
join core.facilities facility on facility.entity_id = publication.entity_id
join core.catalog_entities entity on entity.id = facility.entity_id
join core.journey_memberships journey on journey.entity_id = entity.id
join core.web_reference_proofs identity on identity.id = publication.identity_observation_id
    and identity.entity_id = entity.id and identity.field_key = 'facility_identity'
join core.web_reference_proofs position on position.id = publication.position_observation_id
    and position.entity_id = entity.id and position.field_key = 'facility_reference_position'
where publication.withdrawn_at is null and not entity.test_only and entity.review_state = 'approved'
  and entity.verified_at = publication.reviewed_at and entity.operating_status in ('open', 'seasonal')
  and entity.slug is not null and entity.latitude is not null and facility.address_ja is not null
  and identity.value = jsonb_build_object('name', entity.name_ja, 'address', facility.address_ja,
      'operating_status', entity.operating_status)
  and position.value = jsonb_build_array(entity.latitude, entity.longitude)
  and nullif(btrim(position.attribution), '') is not null;

-- Keep the original transport-linked pilot and add only individually reviewed evidence pairs.
create or replace view api.web_pilot_entries with (security_barrier = true) as
with version as (
    select case when exists (select 1 from core.web_reference_publications)
        then 'pilot-2026-11-08-r2' else 'pilot-2026-11-08' end as release_id
)
select version.release_id, entity.id as entity_id, entity.kind, entity.prefecture_code,
    scope.slug, scope.name_ja, scope.address_ja as location_ja, scope.latitude, scope.longitude,
    facility.facility_type, true as in_journey, scope.source_url as public_source_url,
    scope.approved_at as verified_at, node.coordinate_accuracy,
    null::text as coordinate_source_url, null::text as coordinate_attribution
from core.web_pilot_scope scope
cross join version
join core.catalog_entities entity on entity.slug = scope.slug and entity.kind = 'facility'
join core.facilities facility on facility.entity_id = entity.id
join core.transport_nodes node on node.code = scope.node_code and node.facility_id = entity.id
join ingest.source_documents coord_doc on coord_doc.id = node.coordinate_source_document_id
join ingest.source_policy_versions coord_policy on coord_policy.id = coord_doc.policy_version_id
join ingest.source_registry coord_source on coord_source.id = coord_policy.source_id
where not entity.test_only and entity.review_state in ('in_review', 'approved')
  and entity.operating_status not in ('temporarily_closed', 'closed') and entity.name_ja = scope.name_ja
  and node.latitude = scope.latitude and node.longitude = scope.longitude
  and node.coordinate_accuracy in ('address_reference', 'facility_location')
  and coord_source.active and coord_policy.revoked_at is null and coord_policy.store_facts = 'allowed'
  and coord_policy.publish_facts in ('allowed', 'conditional')
  and exists (
      select 1 from ingest.source_documents doc
      join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
      join ingest.source_registry source on source.id = policy.source_id
      where doc.source_url = scope.source_url and source.active and policy.revoked_at is null and policy.store_facts = 'allowed'
        and policy.publish_facts in ('allowed', 'conditional')
  )
union all
select version.release_id, entry.* from core.web_reference_entries entry cross join version
where not exists (select 1 from core.web_pilot_scope scope where scope.slug = entry.slug);

create or replace view api.web_catalog_versions with (security_invoker = true) as
select id::text as release_id, status, published_at as as_of from api.releases
where status in ('active', 'retained')
union all
select release_id, 'active', max(verified_at) from api.web_pilot_entries
where not exists (select 1 from api.releases where status = 'active')
group by release_id;

create or replace view api.web_catalog_entries with (security_invoker = true) as
with eligible as (
    select release_id::text as release_id, entity_id, kind, prefecture_code, slug, name_ja, location_ja,
        latitude, longitude, facility_type, in_journey, public_source_url, verified_at,
        'catalog_location'::text as coordinate_accuracy, null::text as coordinate_source_url, null::text as coordinate_attribution
    from api.published_entries
    union all
    select * from api.web_pilot_entries
    where not exists (select 1 from api.releases where status = 'active')
)
select eligible.release_id, eligible.entity_id, eligible.kind, eligible.prefecture_code, eligible.slug,
    eligible.name_ja, eligible.location_ja, eligible.latitude, eligible.longitude, eligible.facility_type,
    eligible.in_journey, eligible.public_source_url, eligible.verified_at, eligible.coordinate_accuracy,
    coalesce(quality.codes, '{}'::text[]) as quality_codes, null::integer as day_admission_jpy,
    eligible.coordinate_source_url, eligible.coordinate_attribution
from eligible
left join lateral (
    select array_agg(distinct codes.code order by codes.code) as codes
    from api.published_spring_analyses analysis cross join lateral unnest(analysis.quality_codes) codes(code)
    where eligible.kind = 'facility' and analysis.facility_slug = eligible.slug
) quality on true;

create table core.prefecture_survey (
    prefecture_code char(2) primary key references core.prefectures,
    checked_on date not null,
    inventory_state text not null check (inventory_state in ('partial', 'complete', 'no_facilities_verified')),
    gap_codes text[] not null
);

insert into core.prefecture_survey values
    ('01', '2026-11-08', 'partial', array['inventory_pending','optional_fields_pending']),
    ('44', '2026-11-08', 'partial', array['inventory_pending','other_rights_pending']);

-- This explicit aggregate is safe for public readers. The owner view duplicates the
-- live release predicate so ownership bypass cannot cause draft or withdrawn rows to count.
create view api.prefecture_coverage with (security_barrier = true) as
with active_release as (
    select id from api.releases where status = 'active'
), visible as (
    select entry.entity_id, entry.prefecture_code, entry.kind
    from active_release release
    join api.published_entries entry on entry.release_id = release.id
    where core.can_read_entry(entry.release_id, entry.entity_id)
    union all
    select entity_id, prefecture_code, kind from api.web_pilot_entries
    where not exists (select 1 from active_release)
), totals as (
    select entity.prefecture_code, entity.kind, count(*)::integer as candidates,
        count(*) filter (where entity.review_state = 'approved' or visible.entity_id is not null)::integer as reviewed,
        count(visible.entity_id)::integer as published,
        count(*) filter (where entity.review_state = 'withdrawn')::integer as withdrawn,
        max((entity.verified_at at time zone 'Asia/Tokyo')::date) as verified_on
    from core.catalog_entities entity
    left join visible on visible.entity_id = entity.id
    where not entity.test_only and entity.kind in ('facility', 'area')
    group by entity.prefecture_code, entity.kind
), source_totals as (
    select prefecture_code, count(*)::integer as registered_sources
    from ingest.source_registry group by prefecture_code
)
select prefecture.code as prefecture_code, prefecture.name_ja, prefecture.name_en, unit.kind,
    case
        when survey.inventory_state = 'no_facilities_verified' and unit.kind = 'facility'
            and coalesce(totals.candidates, 0) = 0 then 'none_verified'
        when totals.published > 0 then 'published'
        when totals.candidates > 0 then 'review_pending'
        when survey.prefecture_code is not null then 'insufficient_data'
        else 'unresearched'
    end as status,
    coalesce(sources.registered_sources, 0) as registered_sources,
    coalesce(totals.candidates, 0) as candidates, coalesce(totals.reviewed, 0) as reviewed,
    coalesce(totals.published, 0) as published, coalesce(totals.withdrawn, 0) as withdrawn,
    greatest(survey.checked_on, totals.verified_on) as checked_on,
    case
        when survey.inventory_state = 'no_facilities_verified' and unit.kind = 'facility'
            and coalesce(totals.candidates, 0) = 0 then survey.gap_codes
        when survey.prefecture_code is null then array['source_review_pending']
        when unit.kind = 'area' and coalesce(totals.published, 0) = 0
            then array_append(survey.gap_codes, 'area_review_pending')
        else survey.gap_codes
    end as gap_codes
from core.prefectures prefecture
cross join (values ('facility'::core.entity_kind), ('area'::core.entity_kind)) unit(kind)
left join totals on totals.prefecture_code = prefecture.code and totals.kind = unit.kind
left join core.prefecture_survey survey on survey.prefecture_code = prefecture.code
left join source_totals sources on sources.prefecture_code = prefecture.code;

revoke all on core.web_reference_publications, core.web_reference_proofs, core.web_reference_entries,
    core.prefecture_survey, api.prefecture_coverage from public, anon, authenticated, service_role;
grant select on api.prefecture_coverage to anon, authenticated;
