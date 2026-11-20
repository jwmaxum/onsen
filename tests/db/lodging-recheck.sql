-- Post-review contract. The manifest must already have been applied.
do $contract$
begin
    assert (select count(*) = 213 and count(distinct task_id) = 213
        from ingest.review_audit where action = 'lodging_rechecked_20261109');
    assert (select count(*) = 213 and bool_and(
            p.municipality_code in ('01458','01459')
            and p.permit_as_of = date '2026-09-30'
            and t.reason like '2026-11-09 再照合。%'
            and ((p.facility_id is not null and t.state in ('open','accepted'))
                 or (p.facility_id is null and t.state = 'open'))
        )
        from ingest.review_audit a join ingest.review_tasks t on t.id = a.task_id
        join ingest.field_observations o on o.id = t.observation_id
        join ingest.lodging_permit_reconciliation p on p.external_record_id = o.external_record_id
          and p.source_document_id = o.source_document_id
        where a.action = 'lodging_rechecked_20261109');
    assert not exists (select 1 from core.catalog_entities e
        where e.slug ~ '^lodging-0145[89]-20260930-[0-9]+$'
          and (e.review_state <> 'draft' or e.latitude is not null or e.longitude is not null));
    assert not exists (
        select 1 from api.web_catalog_entries e
        where e.slug ~ '^lodging-0145[89]-20260930-[0-9]+$'
    );
    assert (select count(*) = 2 and count(distinct o.value) = 2
        from core.catalog_entities e
        join ingest.external_records r on r.entity_id = e.id
        join ingest.field_observations o on o.external_record_id = r.id
        where o.field_key = 'facility.on_site_onsen'
          and ((e.slug = 'lodging-01459-20260930-242' and o.value = 'false'::jsonb)
              or (e.slug = 'lodging-01459-20260930-243' and o.value = 'true'::jsonb)));
    assert (select count(*) = 1 from core.area_facilities l
        join core.catalog_entities a on a.id = l.area_id
        join core.catalog_entities e on e.id = l.facility_id
        where a.slug = 'shirogane-onsen' and e.slug = 'lodging-01459-20260930-243');
    assert not exists (
        select 1 from ingest.source_registry s
        join ingest.source_policy_versions p on p.source_id = s.id
        where s.source_key like 'lodging_recheck_evidence_%' and (
            p.archive_raw <> 'denied' or p.auto_fetch <> 'denied' or p.publish_facts <> 'pending'
        )
    );
    assert not has_schema_privilege('anon','ingest','usage')
        and not has_table_privilege('anon','ingest.lodging_permit_reconciliation','select');
end;
$contract$;
