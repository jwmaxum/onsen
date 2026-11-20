-- After one or more live Takegawara imports. This checks stored facts without changing them.
begin;
set local plpgsql.check_asserts = on;

do $$
declare
    approved_id uuid;
    latest_run_id uuid;
    document_url text;
begin
    select policy.id into strict approved_id
    from ingest.source_policy_versions policy
    join ingest.source_registry source on source.id = policy.source_id
    where source.source_key = 'beppu_open_data' and policy.version = 2 and policy.robots_http_status = 404;

    assert (select count(*) from ingest.source_policy_urls where policy_version_id = approved_id) = 3,
        'Only the three reviewed PDF URLs may be imported';
    assert (select count(*) from ingest.source_documents where policy_version_id = approved_id) = 3,
        'Exactly three distinct documents are stored after reimport';
    assert not exists (select 1 from ingest.source_documents where policy_version_id = approved_id
        and (raw_object_key is not null or raw_expires_at is not null)), 'No raw PDF archive';
    assert (select count(*) from ingest.field_observations obs join ingest.source_documents doc on doc.id = obs.source_document_id
        where doc.policy_version_id = approved_id) = 24, 'Eight reviewed facts per report';
    assert (select count(*) from core.spring_analyses analysis join ingest.source_documents doc on doc.id = analysis.source_document_id
        where doc.policy_version_id = approved_id) = 3, 'Exactly three source analyses';

    assert (
        select count(*) from core.spring_analyses analysis
        join ingest.source_documents doc on doc.id = analysis.source_document_id
        join core.spring_usages usage on usage.spring_id = analysis.spring_id
        join core.baths bath on bath.id = usage.bath_id and bath.facility_id = usage.facility_id
        join core.catalog_entities facility on facility.id = usage.facility_id
        join (values ('男湯', 48.8, 7.5, 7.5), ('女湯', 48.9, 7.7, 7.8), ('砂湯', 52.1, 7.3, 7.4))
            expected (bath_name, temperature, ph_onsite, ph_laboratory) on expected.bath_name = bath.name_ja
        where doc.policy_version_id = approved_id and facility.slug = 'takegawara-onsen'
          and facility.review_state = 'in_review' and analysis.sample_kind = 'source'
          and analysis.sampled_on = date '2019-02-20' and analysis.analyzed_on = date '2019-03-04'
          and (analysis.source_temp_celsius, analysis.ph_onsite, analysis.ph_laboratory) =
              (expected.temperature, expected.ph_onsite, expected.ph_laboratory)
    ) = 3, 'Three historical reservoir readings are linked to their own bath';

    select id into strict latest_run_id from ingest.harvest_runs where policy_version_id = approved_id
        and status = 'succeeded' order by started_at desc limit 1;
    select source_url into strict document_url from ingest.source_policy_urls where policy_version_id = approved_id
        and source_url like '%/bunseki_men.pdf';
    begin
        insert into ingest.source_documents (run_id, policy_version_id, source_url, content_sha256)
            values (latest_run_id, approved_id, document_url, repeat('0', 64));
        raise exception 'A changed document hash was accepted';
    exception when check_violation then null;
    end;
    begin
        insert into ingest.source_documents (run_id, policy_version_id, source_url, content_sha256)
            values (latest_run_id, approved_id, document_url || '?unreviewed=1', repeat('0', 64));
        raise exception 'An unreviewed URL was accepted';
    exception when check_violation then null;
    end;
end;
$$;

set local role anon;
do $$
begin
    assert not exists (select 1 from api.published_entries where slug = 'takegawara-onsen'),
        'The sample remains out of the public API';
end;
$$;
rollback;
