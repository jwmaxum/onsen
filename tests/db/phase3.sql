-- Run against the published Takegawara pilot. Each attempted change rolls back.
begin;
set local plpgsql.check_asserts = on;

select set_config('onsen.test_analysis_id', analysis_id::text, true)
from core.analysis_source_facts where facility_slug = 'takegawara-onsen' and bath_name_ja = '男湯';
select set_config('onsen.test_publish_oid', 'core.publish_spring_analysis(uuid)'::regprocedure::oid::text, true);

set local role anon;
do $$
begin
    assert (select count(*) from api.published_spring_analyses where facility_slug = 'takegawara-onsen') = 12,
        'Three reviewed analyses in four locales';
    assert not exists (select 1 from api.published_entries where slug = 'takegawara-onsen'),
        'Scoped analysis publication cannot publish the facility catalog entry';
    assert not has_schema_privilege(current_user, 'core', 'USAGE'), 'Private review schema is inaccessible';
    assert not has_table_privilege(current_user, 'api.published_spring_analyses', 'INSERT'), 'Projection is read only';
    assert not has_function_privilege(current_user, current_setting('onsen.test_publish_oid')::oid, 'EXECUTE'), 'Anonymous cannot publish';
    assert not exists (select 1 from api.published_spring_analyses where facility_slug = 'takegawara-onsen'
        and (source_url is null or source_accessed_on is null or source_modified is not true
            or source_attribution is null or source_transformation is null)), 'Every row includes provenance and transformation';
end;
$$;
reset role;

savepoint revised_facts;
update core.spring_analyses set ph_onsite = ph_onsite + 0.1 where id = current_setting('onsen.test_analysis_id')::uuid;
set local role anon;
do $$
begin
    assert (select count(*) from api.published_spring_analyses where facility_slug = 'takegawara-onsen') = 8,
        'A fact correction hides all locales of the affected analysis';
end;
$$;
rollback to revised_facts;

savepoint revised_translation;
set local role onsen_reviewer;
update core.analysis_translations set sample_name = 'edited draft', review_state = 'approved'
    where analysis_id = current_setting('onsen.test_analysis_id')::uuid and locale = 'en';
do $$
begin
    assert (select review_state = 'draft' and reviewed_at is null from core.analysis_translations
        where analysis_id = current_setting('onsen.test_analysis_id')::uuid and locale = 'en'),
        'Editing approved text clears its approval';
    assert not has_function_privilege(current_user, 'core.publish_spring_analysis(uuid)', 'EXECUTE'), 'Reviewer cannot publish';
end;
$$;
reset role;
set local role onsen_publisher;
do $$
begin
    begin
        perform core.publish_spring_analysis(current_setting('onsen.test_analysis_id')::uuid);
        raise exception 'A draft translation was accepted for publication';
    exception when check_violation then null;
    end;
end;
$$;
reset role;
set local role onsen_reviewer;
update core.analysis_translations set review_state = 'approved', reviewed_at = statement_timestamp(), reviewed_by = 'test'
    where analysis_id = current_setting('onsen.test_analysis_id')::uuid and locale = 'en';
reset role;
set local role anon;
do $$
begin
    assert (select count(*) from api.published_spring_analyses where facility_slug = 'takegawara-onsen') = 8,
        'A new review revision needs explicit republication';
end;
$$;
rollback to revised_translation;

savepoint withdrawn_source;
update ingest.source_policy_versions policy set revoked_at = now()
    from ingest.source_registry source where policy.source_id = source.id and source.source_key = 'beppu_open_data'
      and policy.version = 2;
set local role anon;
do $$
begin
    assert (select count(*) from api.published_spring_analyses where facility_slug = 'takegawara-onsen') = 0,
        'Source revocation immediately hides all pilot analyses';
end;
$$;
rollback to withdrawn_source;

savepoint withdrawn_publication;
set local role onsen_publisher;
select core.withdraw_spring_analysis(current_setting('onsen.test_analysis_id')::uuid);
reset role;
set local role authenticated;
do $$
begin
    assert (select count(*) from api.published_spring_analyses where facility_slug = 'takegawara-onsen') = 8,
        'Publisher withdrawal hides one analysis from authenticated clients too';
end;
$$;
rollback to withdrawn_publication;

rollback;
