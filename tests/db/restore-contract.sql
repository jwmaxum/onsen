begin read only;
set local timezone = 'UTC';
set local datestyle = 'ISO, YMD';
set local plpgsql.check_asserts = on;

select 'catalog|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), '' order by id), ''))
from core.catalog_entities record_data;
select 'documents|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), '' order by id), ''))
from ingest.source_documents record_data;
select 'observations|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), '' order by id), ''))
from ingest.field_observations record_data;
select 'policies|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), '' order by id), ''))
from ingest.source_policy_versions record_data;
select 'releases|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), '' order by id), ''))
from api.releases record_data;
select 'benchmarks|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by prefecture_code, fiscal_year, unit), '')) from core.official_coverage_benchmarks record_data;
select 'designations|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by entity_id, prefecture_code), '')) from core.national_area_designation_jurisdictions record_data;
select 'discovery|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by source_document_id, external_id), '')) from ingest.area_inventory_candidates record_data;
select 'official_rosters|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by prefecture_code, fiscal_year), '')) from ingest.official_area_rosters record_data;
select 'official_roster_names|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by roster_id, source_row), '')) from ingest.official_area_roster_entries record_data;
select 'municipal_lodging_surveys|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by municipality_code), '')) from ingest.municipal_lodging_surveys record_data;
select 'lodging_permit_reconciliation|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by source_document_id, source_sheet, source_row), '')) from ingest.lodging_permit_reconciliation record_data;
select 'review_audit|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by id), '')) from ingest.review_audit record_data;
do $$
begin
    -- Resolve private objects as the restore operator; verify anon's privileges.
    assert not has_table_privilege('anon', 'ingest.lodging_permit_rows', 'SELECT');
    assert not has_function_privilege('anon', 'ingest.register_lodging_permits(uuid,date,text[],text,jsonb)', 'EXECUTE');
end;
$$;

set local role anon;
do $$
begin
    assert not has_schema_privilege(current_user, 'core', 'USAGE');
    assert not has_schema_privilege(current_user, 'ingest', 'USAGE');
    assert not has_table_privilege(current_user, 'api.releases', 'INSERT');
    assert not has_table_privilege(current_user, 'api.prefecture_coverage', 'INSERT');
    assert (select count(*) from api.prefecture_coverage) = 94;
    assert (select count(*) from api.area_inventory_progress) = 47;
end;
$$;
select 'visible|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by release_id, entity_id), '')) from api.web_catalog_entries record_data;
select 'analyses|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by analysis_id, locale), '')) from api.published_spring_analyses record_data;
select 'routes|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by route_key, seq), '')) from api.web_pilot_route_legs record_data;
select 'coverage|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by prefecture_code, kind), '')) from api.prefecture_coverage record_data;
select 'area_progress|' || count(*) || '|' || md5(coalesce(string_agg(md5(to_jsonb(record_data)::text), ''
    order by prefecture_code), '')) from api.area_inventory_progress record_data;
rollback;
