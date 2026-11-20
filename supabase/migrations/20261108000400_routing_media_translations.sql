set search_path = pg_catalog, extensions, public;

create table core.hub_cities (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    prefecture_code char(2) not null references core.prefectures,
    name_ja text not null
);

create table core.transport_nodes (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    hub_city_id uuid references core.hub_cities,
    kind text not null check (kind in ('station', 'airport', 'bus_terminal', 'port', 'stop', 'entrance')),
    name_ja text not null,
    latitude numeric(8,6) not null check (latitude between -90 and 90),
    longitude numeric(9,6) not null check (longitude between -180 and 180),
    geog geography(point, 4326) generated always as
        (st_setsrid(st_makepoint(longitude, latitude), 4326)::geography) stored,
    is_hub_candidate boolean not null default false,
    check (not is_hub_candidate or (hub_city_id is not null and kind in ('station', 'airport', 'bus_terminal', 'port')))
);
create index transport_nodes_geog_idx on core.transport_nodes using gist (geog) where is_hub_candidate;

create table core.routes (
    id uuid primary key default gen_random_uuid(),
    facility_id uuid not null references core.facilities,
    departure_node_id uuid not null references core.transport_nodes,
    source_document_id uuid references ingest.source_documents,
    travel_mode text not null check (travel_mode in ('transit', 'car', 'walk')),
    duration_minutes integer check (duration_minutes > 0),
    fare_jpy integer check (fare_jpy >= 0),
    transfers integer check (transfers >= 0),
    timetable_notes_ja text,
    valid_from date,
    valid_until date,
    verified_at timestamptz,
    review_state core.review_state not null default 'draft',
    check (valid_until >= valid_from),
    check (review_state <> 'approved' or (source_document_id is not null and verified_at is not null))
);

create table core.route_legs (
    id uuid primary key default gen_random_uuid(),
    route_id uuid not null references core.routes,
    seq integer not null check (seq > 0),
    departure_node_id uuid not null references core.transport_nodes,
    arrival_node_id uuid not null references core.transport_nodes,
    mode text not null check (mode in ('rail', 'bus', 'shuttle', 'ferry', 'walk', 'car', 'taxi', 'air', 'wait')),
    operator_name text,
    service_name text,
    duration_minutes integer check (duration_minutes > 0),
    fare_jpy integer check (fare_jpy >= 0),
    reservation_required boolean,
    notes_ja text,
    source_document_id uuid references ingest.source_documents,
    unique (route_id, seq),
    check (mode = 'wait' or departure_node_id <> arrival_node_id)
);

create table core.entity_translations (
    entity_id uuid not null references core.catalog_entities,
    locale text not null references core.locales,
    name text not null check (btrim(name) <> ''),
    introduction text,
    display_address text,
    source_revision text not null,
    review_state core.review_state not null default 'draft',
    reviewed_by text,
    reviewed_at timestamptz,
    primary key (entity_id, locale),
    check (review_state <> 'approved' or (reviewed_by is not null and reviewed_at is not null))
);

create table core.route_leg_translations (
    leg_id uuid not null references core.route_legs,
    locale text not null references core.locales,
    notes text not null,
    source_revision text not null,
    review_state core.review_state not null default 'draft',
    reviewed_by text,
    reviewed_at timestamptz,
    primary key (leg_id, locale),
    check (review_state <> 'approved' or (reviewed_by is not null and reviewed_at is not null))
);

create table core.media_assets (
    id uuid primary key default gen_random_uuid(),
    source_document_id uuid references ingest.source_documents,
    origin_url text check (origin_url ~ '^https://[^[:space:]]+$'),
    object_key text unique,
    license_label text,
    author_name text,
    attribution text,
    rights_evidence text,
    allowed_uses text,
    allow_derivatives boolean,
    expires_at timestamptz,
    rights_reviewed_at timestamptz,
    review_state core.review_state not null default 'draft',
    check (review_state <> 'approved' or (object_key is not null and license_label is not null
        and rights_evidence is not null and allowed_uses is not null and rights_reviewed_at is not null))
);

create table core.media_translations (
    media_id uuid not null references core.media_assets,
    locale text not null references core.locales,
    alt_text text not null check (btrim(alt_text) <> ''),
    source_revision text not null,
    review_state core.review_state not null default 'draft',
    reviewed_by text,
    reviewed_at timestamptz,
    primary key (media_id, locale),
    check (review_state <> 'approved' or (reviewed_by is not null and reviewed_at is not null))
);

create table core.entity_media (
    entity_id uuid not null references core.catalog_entities,
    media_id uuid not null references core.media_assets,
    category text not null check (category in ('exterior', 'room', 'indoor_bath', 'outdoor_bath', 'area', 'other')),
    display_order integer not null default 0 check (display_order >= 0),
    primary key (entity_id, media_id),
    unique (entity_id, category, display_order)
);

create table core.slug_redirects (
    kind core.entity_kind not null check (kind <> 'spring'),
    old_slug text not null check (old_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    entity_id uuid not null,
    primary key (kind, old_slug),
    foreign key (entity_id, kind) references core.catalog_entities (id, kind)
);

reset search_path;
