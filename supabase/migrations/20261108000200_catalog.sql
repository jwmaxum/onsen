set search_path = pg_catalog, extensions, public;

create type core.entity_kind as enum ('area', 'facility', 'spring');
create type core.review_state as enum ('draft', 'in_review', 'approved', 'withdrawn');
create type core.value_state as enum ('confirmed', 'unknown', 'not_applicable', 'conflicting');
create type core.operating_status as enum ('open', 'seasonal', 'temporarily_closed', 'closed', 'unknown');

create table core.catalog_entities (
    id uuid primary key default gen_random_uuid(),
    kind core.entity_kind not null,
    prefecture_code char(2) not null references core.prefectures,
    municipality_code char(5),
    name_ja text not null check (btrim(name_ja) <> ''),
    slug text check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    latitude numeric(8,6) check (latitude between -90 and 90),
    longitude numeric(9,6) check (longitude between -180 and 180),
    location_accuracy text not null default 'unknown'
        check (location_accuracy in ('entrance', 'building', 'verified_area', 'approximate', 'unknown')),
    geog geography(point, 4326) generated always as
        (st_setsrid(st_makepoint(longitude, latitude), 4326)::geography) stored,
    review_state core.review_state not null default 'draft',
    operating_status core.operating_status not null default 'unknown',
    test_only boolean not null default false,
    verified_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, kind),
    unique (kind, slug),
    foreign key (municipality_code, prefecture_code) references core.municipalities (code, prefecture_code),
    check ((latitude is null) = (longitude is null)),
    check ((latitude is null) = (location_accuracy = 'unknown')),
    check (location_accuracy <> 'verified_area' or kind = 'area'),
    check (review_state <> 'approved' or verified_at is not null)
);
create index catalog_entities_geog_idx on core.catalog_entities using gist (geog);
create index catalog_entities_region_idx on core.catalog_entities (prefecture_code, kind);

create function core.set_catalog_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
    new.updated_at := statement_timestamp();
    return new;
end;
$$;
create trigger set_catalog_updated_at before update on core.catalog_entities
    for each row execute function core.set_catalog_updated_at();

create table core.onsen_areas (
    entity_id uuid primary key,
    kind core.entity_kind generated always as ('area'::core.entity_kind) stored,
    location_ja text check (btrim(location_ja) <> ''),
    foreign key (entity_id, kind) references core.catalog_entities (id, kind)
);

create table core.facilities (
    entity_id uuid primary key,
    kind core.entity_kind generated always as ('facility'::core.entity_kind) stored,
    facility_type text not null check (facility_type in
        ('ryokan', 'hotel', 'public_bath', 'day_spa', 'outdoor', 'footbath', 'other')),
    address_ja text check (btrim(address_ja) <> ''),
    normalized_address_ja text,
    official_url text check (official_url ~ '^https://[^[:space:]]+$'),
    foreign key (entity_id, kind) references core.catalog_entities (id, kind)
);

create table core.spring_sources (
    entity_id uuid primary key,
    kind core.entity_kind generated always as ('spring'::core.entity_kind) stored,
    registry_authority text,
    registry_number text,
    sampling_address_ja text,
    unique (registry_authority, registry_number),
    foreign key (entity_id, kind) references core.catalog_entities (id, kind),
    check ((registry_authority is null) = (registry_number is null))
);

create table core.area_facilities (
    area_id uuid not null references core.onsen_areas,
    facility_id uuid not null references core.facilities,
    is_primary boolean not null default false,
    primary key (area_id, facility_id)
);
create unique index area_facilities_primary_idx on core.area_facilities (facility_id) where is_primary;

create table core.journey_memberships (
    entity_id uuid primary key references core.catalog_entities,
    included boolean not null,
    rationale text not null check (btrim(rationale) <> ''),
    reviewed_at timestamptz not null
);

create table core.baths (
    id uuid primary key default gen_random_uuid(),
    facility_id uuid not null references core.facilities,
    name_ja text not null,
    setting text not null check (setting in ('indoor', 'outdoor', 'unknown')),
    access_type text not null check (access_type in ('shared', 'rental', 'in_room', 'unknown')),
    unique (id, facility_id)
);

create table core.spring_usages (
    id uuid primary key default gen_random_uuid(),
    spring_id uuid not null references core.spring_sources,
    facility_id uuid not null references core.facilities,
    bath_id uuid,
    flow_type text not null default 'unknown' check (flow_type in ('flow_through', 'recirculated', 'mixed', 'unknown')),
    is_diluted boolean,
    is_heated boolean,
    valid_from date,
    valid_until date,
    foreign key (bath_id, facility_id) references core.baths (id, facility_id),
    unique nulls not distinct (spring_id, facility_id, bath_id, valid_from),
    check (valid_until >= valid_from)
);

create table core.spring_analyses (
    id uuid primary key default gen_random_uuid(),
    spring_id uuid references core.spring_sources,
    bath_id uuid references core.baths,
    sample_kind text not null check (sample_kind in ('source', 'bath', 'mixed')),
    sampled_on date,
    analyzed_on date,
    ph_onsite numeric check (ph_onsite between 0 and 14),
    ph_laboratory numeric check (ph_laboratory between 0 and 14),
    source_temp_celsius numeric,
    quality_state text not null default 'unknown' check (quality_state in ('classified', 'unclassified', 'unknown')),
    quality_label_ja text,
    check ((sample_kind = 'source' and spring_id is not null and bath_id is null)
        or (sample_kind in ('bath', 'mixed') and spring_id is null and bath_id is not null)),
    check (source_temp_celsius is null or sample_kind = 'source'),
    check (analyzed_on >= sampled_on)
);

create table core.analysis_quality_codes (
    analysis_id uuid not null references core.spring_analyses,
    quality_code text not null references core.quality_codes,
    primary key (analysis_id, quality_code)
);

create table core.facility_specs (
    facility_id uuid primary key references core.facilities,
    rooms integer check (rooms >= 0),
    rooms_state core.value_state not null default 'unknown',
    rooms_with_private_bath integer check (rooms_with_private_bath >= 0),
    rooms_with_private_bath_state core.value_state not null default 'unknown',
    indoor_baths integer check (indoor_baths >= 0),
    indoor_baths_state core.value_state not null default 'unknown',
    outdoor_baths integer check (outdoor_baths >= 0),
    outdoor_baths_state core.value_state not null default 'unknown',
    rental_baths integer check (rental_baths >= 0),
    rental_baths_state core.value_state not null default 'unknown',
    counting_basis text,
    check ((rooms is not null) = (rooms_state = 'confirmed')),
    check ((rooms_with_private_bath is not null) = (rooms_with_private_bath_state = 'confirmed')),
    check (rooms_with_private_bath <= rooms),
    check ((indoor_baths is not null) = (indoor_baths_state = 'confirmed')),
    check ((outdoor_baths is not null) = (outdoor_baths_state = 'confirmed')),
    check ((rental_baths is not null) = (rental_baths_state = 'confirmed'))
);

create table core.price_observations (
    id uuid primary key default gen_random_uuid(),
    facility_id uuid not null references core.facilities,
    price_kind text not null check (price_kind in ('day_admission', 'stay', 'private_bath')),
    price_state core.value_state not null default 'unknown',
    min_jpy integer check (min_jpy >= 0),
    max_jpy integer check (max_jpy >= min_jpy),
    billing_unit text not null check (billing_unit in ('person', 'room', 'session')),
    visitor_category text,
    residency_rule text,
    party_size integer check (party_size > 0),
    meal_plan text,
    tax_included boolean,
    service_on date,
    observed_at timestamptz not null,
    valid_from date,
    valid_until date,
    check (max_jpy is null or min_jpy is not null),
    check ((min_jpy is not null) = (price_state = 'confirmed')),
    check (valid_until >= valid_from)
);

reset search_path;
