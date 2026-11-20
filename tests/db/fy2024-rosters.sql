begin;
set local plpgsql.check_asserts = on;
do $$
declare
    yamagata ingest.official_area_rosters%rowtype;
    roster_rows jsonb;
    ministry_benchmark_doc uuid;
begin
    assert (select count(*) from ingest.official_area_roster_entries) = 241 + (
        select count(*) from ingest.official_area_roster_entries e join ingest.official_area_rosters r on r.id = e.roster_id
        where r.prefecture_code = '16' and r.fiscal_year = 2024);
    assert (select count(*) from ingest.official_area_rosters where coverage = 'complete' and prefecture_code <> '16') = 2;
    assert (select count(*) from ingest.official_area_roster_source_approvals where coverage = 'partial') = 2;
    select * into strict yamagata from ingest.official_area_rosters where prefecture_code = '06' and fiscal_year = 2024;
    select jsonb_agg(jsonb_build_object('source_row', entry.source_row, 'name_ja', entry.name_ja,
        'municipality_ja', entry.municipality_ja) order by entry.source_row)
    into roster_rows from ingest.official_area_roster_entries entry where entry.roster_id = yamagata.id;
    assert ingest.register_official_area_roster('06', 2024::smallint, '2025-03-31', yamagata.source_document_id,
        'complete', roster_rows) = yamagata.id, 'An identical retry is idempotent';
    begin
        perform ingest.register_official_area_roster('06', 2024::smallint, '2025-03-30', yamagata.source_document_id,
            'complete', roster_rows);
        raise exception 'Wrong date accepted';
    exception when check_violation then null;
    end;
    begin
        perform ingest.register_official_area_roster('06', 2024::smallint, '2025-03-31', yamagata.source_document_id,
            'complete', roster_rows - 0);
        raise exception 'Wrong name count accepted';
    exception when check_violation then null;
    end;
    select source_document_id into strict ministry_benchmark_doc from core.official_coverage_benchmarks
    where prefecture_code = '06' and fiscal_year = 2024 and unit = 'area_with_lodging';
    begin
        perform ingest.register_official_area_roster('06', 2024::smallint, '2025-03-31', ministry_benchmark_doc,
            'complete', roster_rows);
        raise exception 'The national count table was accepted as a name source';
    exception when check_violation then null;
    end;
    assert exists (select 1 from ingest.official_roster_candidate_matches where prefecture_code = '06');
end;
$$;
set local role anon;
do $$
begin
    assert (select count(*) from api.area_inventory_progress) = 47;
    assert (select sum(registered_official_areas) from api.area_inventory_progress) = 241 + (
        select registered_official_areas from api.area_inventory_progress where prefecture_code = '16');
    assert (select sum(official_areas_remaining) from api.area_inventory_progress) = 2598 - (
        select registered_official_areas from api.area_inventory_progress where prefecture_code = '16');
    assert (select registered_official_areas = 67 and official_areas_remaining = 0
        and reconciliation_gap = 'official_roster_reuse_pending' from api.area_inventory_progress where prefecture_code = '06');
    assert (select registered_official_areas = 38 and official_areas_remaining = 0
        and reconciliation_gap = 'official_roster_reuse_pending' from api.area_inventory_progress where prefecture_code = '18');
    assert (select registered_official_areas = 2 and official_areas_remaining = 102
        and reconciliation_gap = 'official_roster_partial' from api.area_inventory_progress where prefecture_code = '05');
    assert (select registered_official_areas = 134 and official_areas_remaining = 1
        and reconciliation_gap = 'official_roster_partial' from api.area_inventory_progress where prefecture_code = '15');
    assert not has_schema_privilege(current_user, 'ingest', 'USAGE');
    assert not exists (select 1 from api.web_catalog_entries where kind = 'area');
end;
$$;
reset role;
update ingest.source_policy_versions policy set revoked_at = statement_timestamp()
from ingest.source_registry source where source.id = policy.source_id and source.source_key = 'yamagata_fy2024_area_roster';
set local role anon;
do $$
begin
    assert (select registered_official_areas = 0 and official_areas_remaining = 67
        from api.area_inventory_progress where prefecture_code = '06');
end;
$$;
rollback;
