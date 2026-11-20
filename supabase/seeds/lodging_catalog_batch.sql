-- The importer injects only UTF-8 hex bytes and a SHA-256. Review data stays private.
do $lodging_batch$
declare
    payload constant jsonb := convert_from(decode('__BATCH_HEX__', 'hex'), 'UTF8')::jsonb;
    payload_hash constant text := '__BATCH_HASH__';
    source_key constant text := 'onsen_private_lodging_catalog_review';
    evidence_url constant text := 'https://github.com/jwmaxum/onsen';
    checked constant timestamptz := ((payload->>'checked_on') || ' 12:00:00+09')::timestamptz;
    source_uuid uuid;
    policy_uuid uuid;
    document_uuid uuid;
    run_uuid uuid;
    area_uuid uuid;
    target_uuid uuid;
    record_uuid uuid;
    observation_uuid uuid;
    candidate jsonb;
    facility jsonb;
    hits uuid[];
    added_condition text;
begin
    perform pg_advisory_xact_lock(179101, 20261120);
    insert into ingest.source_registry (source_key, publisher, homepage_url, active)
    values (source_key, 'Onsen Atlas internal factual review', evidence_url, true)
    on conflict on constraint source_registry_source_key_key do nothing;
    select r.id into strict source_uuid from ingest.source_registry r
        where r.source_key = 'onsen_private_lodging_catalog_review' and r.active;
    insert into ingest.source_policy_versions (source_id, version, reviewed_at, reviewed_by,
        auto_fetch, archive_raw, store_facts, publish_facts, translate_content, publish_images, conditions)
    values (source_uuid, 1, checked, 'lodging catalog factual review',
        'denied', 'denied', 'allowed', 'pending', 'pending', 'denied',
        'Independent facts and evidence links for private comparison; public channels require separate review. No map data or applicant details.')
    on conflict (source_id, version) do nothing;
    select p.id into strict policy_uuid from ingest.source_policy_versions p
        where p.source_id = source_uuid and p.version = 1 and p.revoked_at is null
          and p.store_facts = 'allowed' and p.publish_facts <> 'allowed';
    insert into ingest.source_policy_urls values (policy_uuid, evidence_url) on conflict do nothing;
    select d.id into document_uuid from ingest.source_documents d where d.policy_version_id = policy_uuid
        and d.source_url = evidence_url and d.content_sha256 = payload_hash;
    if document_uuid is null then
        insert into ingest.harvest_runs (source_id, policy_version_id, mode, status, started_at, finished_at)
        values (source_uuid, policy_uuid, 'manual', 'succeeded', checked, checked) returning id into run_uuid;
        insert into ingest.source_documents (run_id, policy_version_id, source_url, fetched_at, content_sha256, parser_version)
        values (run_uuid, policy_uuid, evidence_url, checked, payload_hash, 'lodging-facts-v1') returning id into document_uuid;
    end if;
    insert into core.municipalities (code, name_ja, prefecture_code) values ('44213', '由布市', '44')
    on conflict (code) do nothing;
    if not exists (select 1 from core.municipalities where code = '44213' and prefecture_code = '44' and name_ja = '由布市') then
        raise check_violation using message = 'Yufuin municipality identity differs';
    end if;
    select array_agg(e.id order by e.id) into hits from core.catalog_entities e where e.kind = 'area'
        and e.prefecture_code = '44' and e.name_ja = '由布院温泉' and e.review_state <> 'withdrawn';
    if coalesce(cardinality(hits), 0) > 1 then
        raise check_violation using message = 'Yufuin area requires identity review';
    elsif cardinality(hits) = 1 then
        area_uuid := hits[1];
    else
        insert into core.catalog_entities (kind, prefecture_code, municipality_code, name_ja, slug)
        values ('area', '44', '44213', '由布院温泉', 'yufuin-onsen') returning id into area_uuid;
        insert into core.onsen_areas (entity_id, location_ja) values (area_uuid, '大分県由布市湯布院町');
    end if;
    for candidate in select value from jsonb_array_elements(payload->'entries') loop
        facility := candidate->'facility';
        target_uuid := null;
        added_condition := 'Confirm facility identity, current operation, area and public reuse before publishing.';
        if facility is not null then
            select array_agg(e.id order by e.id) into hits
            from core.catalog_entities e join core.municipalities m on m.code = e.municipality_code
            where e.kind = 'facility' and e.review_state <> 'withdrawn'
              and e.prefecture_code = facility->>'prefecture_code' and m.name_ja = facility->>'municipality_ja'
              and (e.slug = facility->>'key' or regexp_replace(normalize(e.name_ja, NFKC), '[[:space:]]+', '', 'g') =
                  regexp_replace(normalize(facility->>'name_ja', NFKC), '[[:space:]]+', '', 'g'));
            if cardinality(hits) = 1 then
                target_uuid := hits[1];
            elsif cardinality(hits) > 1 then
                added_condition := 'Multiple locale/name matches; resolve facility identity before publication.';
            elsif candidate->>'yufuin' = 'true' then
                insert into core.catalog_entities (kind, prefecture_code, municipality_code, name_ja, slug)
                values ('facility', '44', '44213', facility->>'name_ja', facility->>'key') returning id into target_uuid;
                insert into core.facilities (entity_id, facility_type, address_ja, official_url)
                values (target_uuid, facility->>'facility_type', facility->>'address_ja', facility->'sources'->0->>'url');
            end if;
            if candidate->>'yufuin' = 'true' and target_uuid is not null then
                insert into core.area_facilities (area_id, facility_id, is_primary)
                select area_uuid, target_uuid, true where not exists (
                    select 1 from core.area_facilities where facility_id = target_uuid and is_primary)
                on conflict do nothing;
                candidate := candidate || jsonb_build_object('area_evidence', payload->'area', 'permit_source', payload->'permit_source');
            end if;
        end if;
        insert into ingest.external_records (source_id, external_id, entity_id, first_seen_at, last_seen_at)
        values (source_uuid, candidate->>'key', target_uuid, checked, checked)
        on conflict (source_id, external_id) do nothing;
        select e.id into strict record_uuid from ingest.external_records e where e.source_id = source_uuid
            and e.external_id = candidate->>'key';
        observation_uuid := null;
        insert into ingest.field_observations (external_record_id, source_document_id, field_key, source_locator,
            value, observed_at, value_state)
        values (record_uuid, document_uuid, 'lodging.review.batch', candidate->>'key', candidate, checked, 'confirmed')
        on conflict do nothing returning id into observation_uuid;
        if observation_uuid is not null then
            insert into ingest.review_tasks (observation_id, reason) values (observation_uuid, added_condition);
        end if;
    end loop;
end;
$lodging_batch$;
