begin;
set local plpgsql.check_asserts = on;
do $$
begin
    assert (select count(*) from core.official_coverage_benchmarks where fiscal_year = 2024) = 188;
    assert (select sum(counted) from core.official_coverage_benchmarks where unit = 'spring' and fiscal_year = 2024) = 27899;
    assert (select sum(counted) from core.official_coverage_benchmarks where unit = 'lodging' and fiscal_year = 2024) = 13425;
    assert (select sum(counted) from core.official_coverage_benchmarks where unit = 'public_bath' and fiscal_year = 2024) = 7721;
    assert (select count(*) from core.national_area_designations) = 79;
    assert (select count(*) from core.national_area_designation_jurisdictions) = 80;
    assert (select count(*) from core.national_area_designation_jurisdictions j
        join core.catalog_entities e on e.id = j.entity_id where e.name_ja = '八幡平温泉郷' and j.prefecture_code in ('03', '05')) = 2;
    assert (select count(*) from ingest.area_inventory_candidates) = 2095;
    assert (select count(*) from ingest.area_inventory_candidates where reference_url like 'https://www.wikidata.org/wiki/Q%') = 1818;
    assert (select count(*) from ingest.area_inventory_candidates where prefecture_code is null) = 768;
end;
$$;

set local role anon;
do $$
begin
    assert (select count(*) from api.area_inventory_progress) = 47;
    assert (select sum(official_areas_with_lodging) from api.area_inventory_progress where fiscal_year = 2024) = 2839;
    assert (select official_areas_with_lodging = 226 from api.area_inventory_progress where prefecture_code = '01');
    assert (select official_areas_with_lodging = 120 from api.area_inventory_progress where prefecture_code = '02');
    assert (select count(*) from api.area_inventory_progress where reconciliation_gap = 'official_roster_unavailable') = 47;
    assert not exists (select 1 from api.web_catalog_entries where kind = 'area'), 'Area source evidence alone cannot publish a map listing';
    assert (select published from api.prefecture_coverage where kind = 'facility' and prefecture_code = '02') = 2;
    assert (select published from api.prefecture_coverage where kind = 'facility' and prefecture_code = '04') = 1;
    assert (select count(*) from api.web_catalog_entries where prefecture_code in ('02','04')
        and coordinate_source_url is not null and coordinate_attribution is not null) = 3;
    assert (select release_id from api.web_catalog_versions where status = 'active') = 'pilot-2026-11-08-r3';
    assert (select count(*) from api.published_spring_analyses) = 12;
    assert (select count(*) from api.web_pilot_route_legs) = 9;
    assert not has_schema_privilege(current_user, 'ingest', 'USAGE');
    assert not has_table_privilege(current_user, 'api.area_inventory_progress', 'INSERT');
end;
$$;
reset role;
update ingest.source_policy_versions policy set revoked_at = now()
from ingest.source_registry source where source.id = policy.source_id and source.source_key = 'moe_usage';
set local role anon;
do $$
begin
    assert not exists (select 1 from api.area_inventory_progress where official_areas_with_lodging is not null);
    assert (select count(*) from api.area_inventory_progress) = 47;
    assert (select sum(designated_areas) from api.area_inventory_progress) = 80;
end;
$$;
rollback;
