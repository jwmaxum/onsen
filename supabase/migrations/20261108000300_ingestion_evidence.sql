create type ingest.permission_decision as enum ('pending', 'conditional', 'allowed', 'denied');

create table ingest.source_registry (
    id uuid primary key default gen_random_uuid(),
    source_key text not null unique check (source_key ~ '^[a-z0-9]+(_[a-z0-9]+)*$'),
    publisher text not null,
    prefecture_code char(2) references core.prefectures,
    homepage_url text not null check (homepage_url ~ '^https://[^[:space:]]+$'),
    active boolean not null default false
);

create table ingest.source_policy_versions (
    id uuid primary key default gen_random_uuid(),
    source_id uuid not null references ingest.source_registry,
    version integer not null check (version > 0),
    terms_url text check (terms_url ~ '^https://[^[:space:]]+$'),
    license_label text,
    reviewed_at timestamptz,
    reviewed_by text,
    revoked_at timestamptz,
    auto_fetch ingest.permission_decision not null default 'pending',
    archive_raw ingest.permission_decision not null default 'pending',
    store_facts ingest.permission_decision not null default 'pending',
    publish_facts ingest.permission_decision not null default 'pending',
    translate_content ingest.permission_decision not null default 'pending',
    publish_images ingest.permission_decision not null default 'pending',
    robots_status text not null default 'unverified'
        check (robots_status in ('unverified', 'allowed', 'blocked')),
    retention_days integer check (retention_days > 0),
    max_requests_per_minute integer check (max_requests_per_minute > 0),
    attribution text,
    conditions text,
    unique (source_id, version),
    unique (id, source_id),
    check (auto_fetch <> 'allowed' or (robots_status = 'allowed' and max_requests_per_minute is not null)),
    check (archive_raw <> 'allowed' or retention_days is not null),
    check (publish_facts <> 'allowed' or store_facts = 'allowed'),
    check (not ('allowed' = any (array[auto_fetch, archive_raw, store_facts, publish_facts,
        translate_content, publish_images])) or (reviewed_at is not null and nullif(btrim(reviewed_by), '') is not null))
);

-- Use exact document URLs so a grant for a file never extends to general HTML on the same host.
create table ingest.source_policy_urls (
    policy_version_id uuid not null references ingest.source_policy_versions,
    source_url text not null check (source_url ~ '^https://[^[:space:]]+$'),
    primary key (policy_version_id, source_url)
);

create table ingest.harvest_runs (
    id uuid primary key default gen_random_uuid(),
    source_id uuid not null,
    policy_version_id uuid not null,
    mode text not null check (mode in ('manual', 'file', 'api', 'html')),
    status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed', 'blocked')),
    checkpoint jsonb not null default '{}' check (jsonb_typeof(checkpoint) = 'object'),
    started_at timestamptz not null default now(),
    finished_at timestamptz,
    unique (id, policy_version_id),
    foreign key (policy_version_id, source_id) references ingest.source_policy_versions (id, source_id),
    check (finished_at >= started_at)
);
create unique index harvest_runs_running_idx on ingest.harvest_runs (source_id) where status = 'running';

create table ingest.source_documents (
    id uuid primary key default gen_random_uuid(),
    run_id uuid not null,
    policy_version_id uuid not null,
    source_url text not null check (source_url ~ '^https://[^[:space:]]+$'),
    fetched_at timestamptz not null default now(),
    content_sha256 text check (content_sha256 ~ '^[a-f0-9]{64}$'),
    parser_version text,
    raw_object_key text,
    raw_expires_at timestamptz,
    unique nulls not distinct (policy_version_id, source_url, content_sha256),
    foreign key (run_id, policy_version_id) references ingest.harvest_runs (id, policy_version_id),
    check ((raw_object_key is null) = (raw_expires_at is null)),
    check (raw_expires_at > fetched_at)
);

create function ingest.check_document_permissions() returns trigger
language plpgsql set search_path = '' as $$
declare
    policy ingest.source_policy_versions%rowtype;
    network_mode boolean;
    source_active boolean;
    approved_url boolean;
begin
    select * into strict policy from ingest.source_policy_versions where id = new.policy_version_id;
    select mode <> 'manual' into strict network_mode from ingest.harvest_runs where id = new.run_id;
    select active into strict source_active from ingest.source_registry where id = policy.source_id;
    select exists (select 1 from ingest.source_policy_urls
        where policy_version_id = policy.id and source_url = new.source_url) into approved_url;

    if network_mode and (not source_active or policy.revoked_at is not null
        or policy.auto_fetch <> 'allowed' or not approved_url) then
        raise check_violation using message = 'Automated fetch lacks an active permission and approved URL';
    end if;
    if new.raw_object_key is not null and (not source_active or policy.revoked_at is not null
        or policy.archive_raw <> 'allowed' or not approved_url
        or new.raw_expires_at > new.fetched_at + pg_catalog.make_interval(days => policy.retention_days)) then
        raise check_violation using message = 'Raw archival lacks permission or exceeds retention';
    end if;
    return new;
end;
$$;
create trigger check_document_permissions before insert or update of run_id, policy_version_id, source_url, fetched_at,
    raw_object_key, raw_expires_at on ingest.source_documents for each row
    execute function ingest.check_document_permissions();

create table ingest.external_records (
    id uuid primary key default gen_random_uuid(),
    source_id uuid not null references ingest.source_registry,
    external_id text not null check (btrim(external_id) <> ''),
    entity_id uuid references core.catalog_entities,
    first_seen_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    unique (source_id, external_id),
    check (last_seen_at >= first_seen_at)
);

create table ingest.field_observations (
    id uuid primary key default gen_random_uuid(),
    external_record_id uuid not null references ingest.external_records,
    source_document_id uuid not null references ingest.source_documents,
    field_key text not null check (field_key ~ '^[a-z][a-z0-9_.]*$'),
    source_locator text not null check (btrim(source_locator) <> ''),
    value jsonb,
    unit text,
    observed_at timestamptz not null,
    value_state core.value_state not null,
    unique (external_record_id, source_document_id, field_key, source_locator),
    check ((value is not null and value <> 'null'::jsonb) = (value_state = 'confirmed'))
);
create index field_observations_document_idx on ingest.field_observations (source_document_id, external_record_id);

create function ingest.check_observation_permissions() returns trigger
language plpgsql set search_path = '' as $$
begin
    if not exists (
        select 1 from ingest.source_documents doc
        join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
        join ingest.source_registry source on source.id = policy.source_id
        join ingest.source_policy_urls allowed on allowed.policy_version_id = policy.id and allowed.source_url = doc.source_url
        join ingest.external_records record on record.source_id = source.id
        where doc.id = new.source_document_id and record.id = new.external_record_id
          and source.active and policy.store_facts = 'allowed' and policy.revoked_at is null
    ) then
        raise check_violation using message = 'Observation needs an approved document from its own source';
    end if;
    return new;
end;
$$;
create trigger check_observation_permissions before insert or update on ingest.field_observations
    for each row execute function ingest.check_observation_permissions();

create table ingest.review_tasks (
    id uuid primary key default gen_random_uuid(),
    entity_id uuid references core.catalog_entities,
    observation_id uuid references ingest.field_observations,
    state text not null default 'open' check (state in ('open', 'accepted', 'rejected')),
    reason text not null,
    created_at timestamptz not null default now(),
    check (num_nonnulls(entity_id, observation_id) = 1)
);

create table ingest.review_audit (
    id uuid primary key default gen_random_uuid(),
    task_id uuid not null references ingest.review_tasks,
    actor text not null default session_user,
    action text not null,
    rationale text not null check (btrim(rationale) <> ''),
    recorded_at timestamptz not null default now()
);

alter table core.spring_analyses add column source_document_id uuid references ingest.source_documents;
alter table core.price_observations add column source_document_id uuid references ingest.source_documents;

create table core.official_coverage_benchmarks (
    prefecture_code char(2) not null references core.prefectures,
    fiscal_year smallint not null check (fiscal_year >= 1900),
    unit text not null check (unit in ('area_with_lodging', 'spring', 'lodging', 'public_bath')),
    counted integer not null check (counted >= 0),
    as_of date not null,
    counting_definition text not null,
    source_document_id uuid not null references ingest.source_documents,
    primary key (prefecture_code, fiscal_year, unit)
);
