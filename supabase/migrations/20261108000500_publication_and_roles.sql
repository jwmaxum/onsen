do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'onsen_ingestor') then
        create role onsen_ingestor nologin nobypassrls;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'onsen_reviewer') then
        create role onsen_reviewer nologin nobypassrls;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'onsen_publisher') then
        create role onsen_publisher nologin nobypassrls;
    end if;
end;
$$;

create table api.releases (
    id uuid primary key default gen_random_uuid(),
    status text not null default 'draft' check (status in ('draft', 'active', 'retained')),
    published_at timestamptz,
    retained_until timestamptz,
    check ((status = 'draft' and published_at is null and retained_until is null)
        or (status = 'active' and published_at is not null and retained_until is null)
        or (status = 'retained' and published_at is not null and retained_until >= published_at
            and retained_until is not null))
);
create unique index releases_one_active_idx on api.releases (status) where status = 'active';

create table api.published_entries (
    release_id uuid not null references api.releases,
    entity_id uuid not null,
    kind core.entity_kind not null check (kind in ('area', 'facility')),
    prefecture_code char(2) not null references core.prefectures,
    slug text not null,
    name_ja text not null,
    location_ja text not null,
    latitude numeric(8,6) not null,
    longitude numeric(9,6) not null,
    facility_type text,
    in_journey boolean not null,
    public_source_url text not null,
    verified_at timestamptz not null,
    primary key (release_id, entity_id),
    unique (release_id, kind, slug),
    foreign key (entity_id, kind) references core.catalog_entities (id, kind),
    check ((facility_type is not null) = (kind = 'facility'))
);
create index published_entries_order_idx
    on api.published_entries (release_id, kind, latitude desc, longitude desc, entity_id asc);
create index published_entries_journey_order_idx
    on api.published_entries (release_id, kind, latitude desc, longitude desc, entity_id asc) where in_journey;
create index published_entries_region_order_idx
    on api.published_entries (release_id, kind, prefecture_code, latitude desc, longitude desc, entity_id asc);

create table ingest.publication_evidence (
    release_id uuid not null,
    entity_id uuid not null,
    source_document_id uuid not null references ingest.source_documents,
    primary key (release_id, entity_id),
    foreign key (release_id, entity_id) references api.published_entries (release_id, entity_id)
);

-- The public RLS predicate checks only live eligibility and the selected policy. Snapshot values remain immutable.
create function core.can_read_entry(p_release_id uuid, p_entity_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (
        select 1 from ingest.publication_evidence evidence
        join core.catalog_entities entity on entity.id = evidence.entity_id
        join ingest.source_documents doc on doc.id = evidence.source_document_id
        join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
        join ingest.source_registry source on source.id = policy.source_id
        join ingest.source_policy_urls allowed on allowed.policy_version_id = policy.id and allowed.source_url = doc.source_url
        where evidence.release_id = p_release_id and evidence.entity_id = p_entity_id
          and entity.review_state = 'approved' and not entity.test_only
          and (entity.kind = 'area' or entity.operating_status in ('open', 'seasonal'))
          and source.active and policy.publish_facts = 'allowed' and policy.revoked_at is null
          and exists (
              select 1 from ingest.field_observations observation
              join ingest.external_records record on record.id = observation.external_record_id
              where observation.source_document_id = doc.id and observation.value_state = 'confirmed'
                and record.entity_id = entity.id
          )
    );
$$;

create function core.stage_public_entry(p_release_id uuid, p_entity_id uuid, p_source_document_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
    perform 1 from api.releases where id = p_release_id and status = 'draft' for update;
    if not found then
        raise check_violation using message = 'Only a draft release accepts entries';
    end if;

    insert into api.published_entries (
        release_id, entity_id, kind, prefecture_code, slug, name_ja, location_ja,
        latitude, longitude, facility_type, in_journey, public_source_url, verified_at
    )
    select p_release_id, entity.id, entity.kind, entity.prefecture_code, entity.slug, entity.name_ja,
        coalesce(facility.address_ja, area.location_ja), entity.latitude, entity.longitude,
        facility.facility_type, coalesce(journey.included, false), doc.source_url, entity.verified_at
    from core.catalog_entities entity
    left join core.facilities facility on facility.entity_id = entity.id
    left join core.onsen_areas area on area.entity_id = entity.id
    left join core.journey_memberships journey on journey.entity_id = entity.id
    join ingest.source_documents doc on doc.id = p_source_document_id
    where entity.id = p_entity_id and entity.slug is not null
      and entity.verified_at is not null
      and entity.location_accuracy in ('entrance', 'building', 'verified_area')
      and coalesce(facility.address_ja, area.location_ja) is not null;

    if not found then
        raise check_violation using message = 'Entry requires a subtype and verified location';
    end if;

    insert into ingest.publication_evidence values (p_release_id, p_entity_id, p_source_document_id);
    if not core.can_read_entry(p_release_id, p_entity_id) then
        raise check_violation using message = 'Entry needs approval and an eligible linked source observation';
    end if;
end;
$$;

create function core.activate_release(p_release_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
    perform pg_catalog.pg_advisory_xact_lock(179101, 1);
    perform 1 from api.releases where id = p_release_id and status = 'draft' for update;
    if not found or not exists (select 1 from api.published_entries where release_id = p_release_id)
        or exists (select 1 from api.published_entries entry where entry.release_id = p_release_id
            and not core.can_read_entry(entry.release_id, entry.entity_id)) then
        raise check_violation using message = 'Release must be a populated, eligible draft';
    end if;

    update api.releases set status = 'retained', retained_until = statement_timestamp() + interval '1 day'
        where status = 'active';
    update api.releases set status = 'active', published_at = statement_timestamp() where id = p_release_id;
end;
$$;

revoke all on all tables in schema core, ingest, api from public, anon, authenticated, service_role;
revoke execute on all functions in schema core, ingest, api from public, anon, authenticated, service_role;
alter default privileges in schema core, ingest, api revoke all on tables from public, anon, authenticated, service_role;

grant usage on schema api to anon, authenticated, onsen_publisher;
grant select on api.releases, api.published_entries to anon, authenticated, onsen_publisher;
grant insert (id) on api.releases to onsen_publisher;
grant execute on function core.can_read_entry(uuid, uuid) to anon, authenticated;
grant usage on schema core to onsen_reviewer, onsen_publisher;
grant usage on schema ingest to onsen_ingestor, onsen_reviewer;
grant execute on function core.stage_public_entry(uuid, uuid, uuid), core.activate_release(uuid) to onsen_publisher;

grant select on ingest.source_registry, ingest.source_policy_versions, ingest.source_policy_urls to onsen_ingestor;
grant select, insert on ingest.harvest_runs, ingest.source_documents to onsen_ingestor;
grant update (status, checkpoint, finished_at) on ingest.harvest_runs to onsen_ingestor;
grant update (parser_version, raw_object_key, raw_expires_at) on ingest.source_documents to onsen_ingestor;
grant select, insert (id, source_id, external_id, first_seen_at, last_seen_at),
    update (last_seen_at) on ingest.external_records to onsen_ingestor;
grant select, insert on ingest.field_observations to onsen_ingestor;

grant select on all tables in schema core to onsen_reviewer;
grant insert, update on core.catalog_entities, core.onsen_areas, core.facilities, core.spring_sources,
    core.area_facilities, core.journey_memberships, core.baths, core.spring_usages, core.spring_analyses,
    core.analysis_quality_codes, core.facility_specs, core.price_observations, core.official_coverage_benchmarks,
    core.hub_cities, core.transport_nodes, core.routes, core.route_legs, core.entity_translations,
    core.route_leg_translations, core.media_assets, core.media_translations, core.entity_media, core.slug_redirects
    to onsen_reviewer;
grant select on all tables in schema ingest to onsen_reviewer;
grant update (entity_id) on ingest.external_records to onsen_reviewer;
grant insert, update on ingest.review_tasks to onsen_reviewer;
grant insert (id, task_id, action, rationale) on ingest.review_audit to onsen_reviewer;

alter table api.releases enable row level security;
alter table api.published_entries enable row level security;

create policy releases_public_read on api.releases for select to anon, authenticated
    using (status = 'active' or (status = 'retained' and retained_until > statement_timestamp()));
create policy releases_publisher_read on api.releases for select to onsen_publisher using (true);
create policy releases_publisher_insert on api.releases for insert to onsen_publisher with check (status = 'draft');
create policy entries_publisher_read on api.published_entries for select to onsen_publisher using (true);
create policy entries_public_read on api.published_entries for select to anon, authenticated using (
    exists (select 1 from api.releases release where release.id = published_entries.release_id)
    and core.can_read_entry(release_id, entity_id)
);
