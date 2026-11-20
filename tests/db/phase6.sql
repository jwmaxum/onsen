-- Against the expanded local sample. All changes below roll back.
begin;
set local plpgsql.check_asserts = on;

set local role anon;
do $$
begin
    assert (select count(*) from api.prefecture_coverage) = 94, '47 prefectures per unit';
    assert (select count(*) from api.prefecture_coverage where kind = 'facility' and status = 'unresearched') = 45;
    assert (select row(candidates, reviewed, published, withdrawn, checked_on) =
        row(7, 5, 5, 0, date '2026-11-08') from api.prefecture_coverage where prefecture_code = '01' and kind = 'facility');
    assert (select published = 1 from api.prefecture_coverage where prefecture_code = '44' and kind = 'facility');
    assert (select published = 0 and checked_on is null and gap_codes = array['source_review_pending']
        from api.prefecture_coverage where prefecture_code = '02' and kind = 'facility');
    assert (select array_agg(slug order by latitude desc, longitude desc, entity_id) from api.web_catalog_entries) =
        array['wakkanai-onsen-domu', 'wakkanai-minato-no-yu', 'rebun-usuyuki-no-yu', 'rishiri-fureai-onsen', 'daiichi-takimotokan', 'takegawara-onsen'];
    assert not exists (select 1 from api.web_catalog_versions where release_id = 'pilot-2026-11-08');
    assert (select release_id from api.web_catalog_versions where status = 'active') = 'pilot-2026-11-08-r2';
    assert (select count(*) from api.web_catalog_entries where coordinate_source_url is not null) = 3;
    assert (select count(*) from api.published_spring_analyses) = 12;
    assert (select count(*) from api.web_pilot_route_legs) = 9;
    assert not has_table_privilege(current_user, 'api.prefecture_coverage', 'INSERT');
    assert not has_schema_privilege(current_user, 'core', 'USAGE');
end;
$$;
reset role;

savepoint revoked_coordinate_source;
update ingest.source_policy_versions policy set revoked_at = now()
from ingest.source_registry source where policy.source_id = source.id and source.source_key = 'mlit_minato_polygon';
set local role anon;
do $$
begin
    assert (select published from api.prefecture_coverage where prefecture_code = '01' and kind = 'facility') = 2;
    assert (select count(*) from api.web_catalog_entries) = 3;
    assert (select release_id from api.web_catalog_versions where status = 'active') = 'pilot-2026-11-08-r2';
end;
$$;
rollback to revoked_coordinate_source;

savepoint closed_facility;
update core.catalog_entities set operating_status = 'temporarily_closed' where slug = 'rebun-usuyuki-no-yu';
set local role anon;
do $$
begin
    assert not exists (select 1 from api.web_catalog_entries where slug = 'rebun-usuyuki-no-yu');
    assert exists (select 1 from api.web_catalog_entries where slug = 'rishiri-fureai-onsen');
end;
$$;
rollback to closed_facility;

savepoint rolled_back_release;
update core.web_reference_publications set withdrawn_at = now();
set local role anon;
do $$
begin
    assert (select count(*) from api.web_catalog_entries) = 3, 'Withdraw expansion without losing legacy pilot';
    assert (select published from api.prefecture_coverage where prefecture_code = '44' and kind = 'facility') = 1;
end;
$$;
rollback to rolled_back_release;
rollback;
