-- Run with ON_ERROR_STOP. All test writes, including temporarily publishable synthetic rows, roll back.
begin;
set local plpgsql.check_asserts = on;
set local search_path = pg_catalog, extensions, public;

do $$
begin
    assert (select count(*) from core.prefectures) = 47, '47 prefecture codes';
    assert (select count(*) from core.locales) = 4, 'Four locales';
    assert (select count(*) from core.quality_codes) = 10, 'Ten quality codes';
    assert (select count(*) from core.catalog_entities where test_only) = 6, 'Local seed is test only';
    assert (select st_x(geog::geometry) = 142
        and st_y(geog::geometry) = 45 from core.catalog_entities where slug = 'test-north-a'),
        'PostGIS uses longitude as X and latitude as Y';
    assert (select rooms = 0 and rooms_state = 'confirmed' from core.facility_specs
        where facility_id = '00000000-0000-4000-8000-000000000101'), 'Confirmed zero';
    assert (select rooms is null and rooms_state = 'unknown' from core.facility_specs
        where facility_id = '00000000-0000-4000-8000-000000000102'), 'Unknown remains NULL';

    begin
        update core.catalog_entities set latitude = 91 where slug = 'test-north-a';
        raise exception 'Latitude bounds were not enforced';
    exception when check_violation then null;
    end;
    begin
        update core.catalog_entities set longitude = null where slug = 'test-north-a';
        raise exception 'Partial coordinates were accepted';
    exception when check_violation then null;
    end;
    begin
        insert into core.facilities (entity_id, facility_type)
            values ('00000000-0000-4000-8000-000000000201', 'ryokan');
        raise exception 'An area was accepted as a facility';
    exception when foreign_key_violation then null;
    end;
    begin
        update core.facility_specs set rooms_with_private_bath = 1, rooms_with_private_bath_state = 'confirmed'
            where facility_id = '00000000-0000-4000-8000-000000000101';
        raise exception 'Private room count exceeded total';
    exception when check_violation then null;
    end;
    begin
        update core.facility_specs set rooms = 0
            where facility_id = '00000000-0000-4000-8000-000000000102';
        raise exception 'Unknown count could be persisted as zero';
    exception when check_violation then null;
    end;
end;
$$;

insert into core.baths (id, facility_id, name_ja, setting, access_type) values
    ('00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-000000000101', '合成浴槽', 'outdoor', 'rental');
do $$
begin
    begin
        insert into core.spring_usages (spring_id, facility_id, bath_id) values (
            '00000000-0000-4000-8000-000000000301', '00000000-0000-4000-8000-000000000102',
            '00000000-0000-4000-8000-000000000401');
        raise exception 'A bath from a different facility was accepted';
    exception when foreign_key_violation then null;
    end;
end;
$$;

insert into ingest.source_registry (id, source_key, publisher, homepage_url, active) values
    ('00000000-0000-4000-8000-000000000501', 'synthetic_example', 'Synthetic fixture', 'https://example.invalid/', true);
insert into ingest.source_policy_versions (
    id, source_id, version, reviewed_at, reviewed_by, store_facts, publish_facts
) values (
    '00000000-0000-4000-8000-000000000502', '00000000-0000-4000-8000-000000000501', 1,
    now(), 'test', 'allowed', 'allowed'
);
insert into ingest.source_policy_urls values ('00000000-0000-4000-8000-000000000502', 'https://example.invalid/facts');

set local role onsen_ingestor;
insert into ingest.harvest_runs (id, source_id, policy_version_id, mode) values
    ('00000000-0000-4000-8000-000000000503', '00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-000000000502', 'manual'),
    ('00000000-0000-4000-8000-000000000504', '00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-000000000502', 'html');
insert into ingest.source_documents (id, run_id, policy_version_id, source_url) values
    ('00000000-0000-4000-8000-000000000505', '00000000-0000-4000-8000-000000000503', '00000000-0000-4000-8000-000000000502', 'https://example.invalid/facts'),
    ('00000000-0000-4000-8000-000000000506', '00000000-0000-4000-8000-000000000503', '00000000-0000-4000-8000-000000000502', 'https://example.invalid/unapproved');
insert into ingest.external_records (source_id, external_id) values
    ('00000000-0000-4000-8000-000000000501', 'one');

do $$
begin
    assert not has_schema_privilege(current_user, 'api', 'USAGE'), 'Ingestor cannot publish';
    assert not has_column_privilege(current_user, 'ingest.external_records', 'entity_id', 'UPDATE'),
        'Ingestor cannot link records to public entities';
    assert not has_column_privilege(current_user, 'ingest.source_documents', 'source_url', 'UPDATE'),
        'Ingestor cannot redirect the source of existing evidence';
    begin
        insert into ingest.external_records (source_id, external_id) values ('00000000-0000-4000-8000-000000000501', 'one');
        raise exception 'Duplicate external identifier was accepted';
    exception when unique_violation then null;
    end;
    begin
        insert into ingest.source_documents (run_id, policy_version_id, source_url, raw_object_key, raw_expires_at)
            values ('00000000-0000-4000-8000-000000000503', '00000000-0000-4000-8000-000000000502',
                'https://example.invalid/facts', 'unapproved/example.pdf', now() + interval '1 day');
        raise exception 'Unlicensed raw archival was accepted';
    exception when check_violation then null;
    end;
    begin
        insert into ingest.source_documents (run_id, policy_version_id, source_url)
            values ('00000000-0000-4000-8000-000000000504', '00000000-0000-4000-8000-000000000502', 'https://example.invalid/facts');
        raise exception 'Unlicensed automatic fetch result was accepted';
    exception when check_violation then null;
    end;
    begin
        insert into ingest.field_observations (external_record_id, source_document_id, field_key, source_locator, value, observed_at, value_state)
            select id, '00000000-0000-4000-8000-000000000506', 'name', 'row 1', '"example"', now(), 'confirmed'
            from ingest.external_records where external_id = 'one';
        raise exception 'Observation from unapproved URL was accepted';
    exception when check_violation then null;
    end;
end;
$$;
reset role;

insert into ingest.external_records (source_id, external_id, entity_id)
    select '00000000-0000-4000-8000-000000000501', slug, id
    from core.catalog_entities where test_only and kind <> 'spring';
insert into ingest.field_observations (external_record_id, source_document_id, field_key, source_locator, value, observed_at, value_state)
    select id, '00000000-0000-4000-8000-000000000505', 'name', 'row 1', to_jsonb(external_id), now(), 'confirmed'
    from ingest.external_records where source_id = '00000000-0000-4000-8000-000000000501' and entity_id is not null;
update core.catalog_entities set verified_at = now(), test_only = (kind = 'area'), review_state = 'approved'
    where test_only and kind <> 'spring';
update core.catalog_entities set review_state = 'draft' where slug = 'test-south';

set local role onsen_reviewer;
do $$
begin
    assert not has_schema_privilege(current_user, 'api', 'USAGE'), 'Reviewer cannot activate releases';
    assert not has_table_privilege(current_user, 'ingest.source_policy_versions', 'UPDATE'), 'Reviewer cannot grant source rights';
end;
$$;
reset role;

set local role onsen_publisher;
insert into api.releases (id) values ('00000000-0000-4000-8000-000000000601'), ('00000000-0000-4000-8000-000000000602');
do $$
begin
    assert not has_schema_privilege(current_user, 'ingest', 'USAGE'), 'Publisher cannot read raw ingestion';
    begin
        perform core.stage_public_entry('00000000-0000-4000-8000-000000000601',
            '00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000505');
        raise exception 'Test-only area could be staged';
    exception when check_violation then null;
    end;
    begin
        perform core.stage_public_entry('00000000-0000-4000-8000-000000000601',
            '00000000-0000-4000-8000-000000000104', '00000000-0000-4000-8000-000000000505');
        raise exception 'Draft facility could be staged';
    exception when check_violation then null;
    end;
end;
$$;
select core.stage_public_entry('00000000-0000-4000-8000-000000000601', id, '00000000-0000-4000-8000-000000000505')
    from unnest(array['00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102',
        '00000000-0000-4000-8000-000000000103']::uuid[]) as fixture(id);
reset role;

set local role anon;
do $$
begin
    assert not has_schema_privilege(current_user, 'core', 'USAGE'), 'Core schema must stay private';
    assert not has_schema_privilege(current_user, 'ingest', 'USAGE'), 'Ingestion schema must stay private';
    assert (select count(*) from api.published_entries) = 0, 'Draft releases must be invisible';
    begin
        insert into api.releases default values;
        raise exception 'Anonymous role could write releases';
    exception when insufficient_privilege then null;
    end;
end;
$$;
reset role;

set local role onsen_publisher;
select core.activate_release('00000000-0000-4000-8000-000000000601');
reset role;

set local role anon;
do $$
declare
    cursor_entry api.published_entries%rowtype;
    next_ids uuid[];
begin
    assert (select count(*) from api.published_entries) = 3, 'Published facilities are visible';
    select * into strict cursor_entry from api.published_entries
        order by latitude desc, longitude desc, entity_id asc offset 1 limit 1;
    assert cursor_entry.entity_id = '00000000-0000-4000-8000-000000000102'::uuid, 'Stable UUID tie-breaker';
    select array_agg(entity_id order by latitude desc, longitude desc, entity_id asc) into next_ids
        from api.published_entries where release_id = cursor_entry.release_id and (
            latitude < cursor_entry.latitude
            or (latitude = cursor_entry.latitude and longitude < cursor_entry.longitude)
            or (latitude = cursor_entry.latitude and longitude = cursor_entry.longitude and entity_id > cursor_entry.entity_id)
        );
    assert next_ids = array['00000000-0000-4000-8000-000000000103']::uuid[], 'Cursor crosses identical coordinates';
end;
$$;
reset role;

set local role onsen_publisher;
select core.stage_public_entry('00000000-0000-4000-8000-000000000602',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000505');
select core.activate_release('00000000-0000-4000-8000-000000000602');
reset role;

set local role authenticated;
do $$
begin
    assert (select count(*) from api.releases where status = 'active') = 1, 'One active release';
    assert (select count(*) from api.published_entries) = 4, 'Retained release stays visible';
end;
$$;
reset role;

update core.catalog_entities set review_state = 'withdrawn' where slug = 'test-north-a';
set local role anon;
do $$
begin
    assert (select count(*) from api.published_entries) = 2, 'Withdrawal hides the entity across releases';
end;
$$;
reset role;

update ingest.external_records set entity_id = null where external_id = 'test-north-b';
set local role anon;
do $$
begin
    assert (select count(*) from api.published_entries) = 1, 'Unlinked evidence hides the affected entry';
end;
$$;
reset role;

update ingest.source_policy_versions set revoked_at = now() where version = 1;
update api.releases set retained_until = published_at where status = 'retained';
set local role anon;
do $$
begin
    assert (select count(*) from api.published_entries) = 0, 'Source revocation hides remaining entries';
    assert (select count(*) from api.releases) = 1, 'Expired retained release is hidden';
end;
$$;
reset role;

rollback;
