begin;
set local plpgsql.check_asserts = on;

do $$
declare
    reviewed ingest.official_area_rosters%rowtype;
begin
    select * into strict reviewed from ingest.official_area_rosters where prefecture_code = '16' and fiscal_year = 2024;
    assert reviewed.coverage = 'complete';
    assert (select count(*) from ingest.official_area_roster_entries where roster_id = reviewed.id) = 61;
    assert (select count(distinct municipality_ja) from ingest.official_area_roster_entries where roster_id = reviewed.id) = 11;
    assert (select count(*) from ingest.official_area_roster_entries where roster_id = reviewed.id
        and source_row ~ '^Sheet2!C([5-9]|[1-5][0-9]|6[0-5])$') = 61;
    assert not exists (select 1 from ingest.official_area_roster_entries where roster_id = reviewed.id
        and (name_ja ~ '[\n\r]' or source_row = 'Sheet2!C66'));
    assert exists (select 1 from ingest.source_documents d
        join ingest.source_policy_versions p on p.id = d.policy_version_id
        where d.id = reviewed.source_document_id
          and d.content_sha256 = 'f901056a91f941ada014c8dbae0d6aaa0f52667bc154570d6d766ff1f734e00b'
          and d.raw_object_key is null and p.publish_facts = 'allowed' and p.store_facts = 'allowed'
          and p.translate_content = 'allowed' and p.archive_raw = 'denied' and p.publish_images = 'denied'
          and p.attribution like '%加工：%');
    assert (select count(*) from ingest.source_registry where source_key = 'toyama_fy2024_supplied_area_roster') = 1;
    assert (select count(*) from ingest.source_documents where id = reviewed.source_document_id) = 1;
    assert not has_table_privilege('anon', 'ingest.official_area_roster_entries', 'select');
    assert not has_function_privilege('anon',
        'ingest.register_official_area_roster(character,smallint,date,uuid,text,jsonb)', 'execute');
end;
$$;
set local role anon;

do $$
begin
    assert (select registered_official_areas = 61 and official_areas_remaining = 0
        and reconciliation_gap = 'official_roster_reconciled' from api.area_inventory_progress where prefecture_code = '16');
    assert (select sum(registered_official_areas) from api.area_inventory_progress) = 302;
    assert (select sum(official_areas_remaining) from api.area_inventory_progress) = 2537;
    assert not exists (select 1 from api.area_inventory_progress where source_url like '%mail.google.com%');
    assert not exists (select 1 from api.web_catalog_entries where kind = 'area');
end;
$$;
rollback;
