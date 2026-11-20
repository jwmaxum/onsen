-- Post-import contract for the reviewed 2026-09-30 workbook.
do $contract$
declare
    source_doc uuid;
    followup_links integer;
begin
    select id into strict source_doc from ingest.source_documents
    where content_sha256 = '163a0a1f6069ffb1cf14caae7a2bffb513aca369d096edf3daf7ae3175d4948f';
    select count(*) into followup_links
    from ingest.lodging_permit_rows p
    join ingest.external_records r on r.id = p.external_record_id
    join ingest.field_observations o on o.external_record_id = p.external_record_id
      and o.source_document_id = p.source_document_id and o.field_key = 'facility.permit_name'
      and o.source_locator = p.source_sheet || ' row ' || p.source_row
    join ingest.review_tasks t on t.observation_id = o.id
    join ingest.review_audit a on a.task_id = t.id and a.action = 'lodging_rechecked_20261109'
    where p.source_document_id = source_doc and r.entity_id is not null;
    assert (select count(*) = 3 and sum(imported_rows) = 264 and sum(linked_rows) = 38 + followup_links
        and sum(excluded_rows) = 2 and bool_and(imported_rows = permit_records and review_status = 'partial')
        from ingest.municipal_lodging_reconciliation where municipality_code in ('01457','01458','01459'));
    assert (select count(*) = 264 and count(permit_number) = 264 and count(permit_issued_on) = 264
        and count(distinct external_record_id) = 264
        from ingest.lodging_permit_rows where source_document_id = source_doc);
    assert not exists (
        select 1 from ingest.lodging_permit_reconciliation
        where source_document_id = source_doc and disposition in ('linked_pending','unlinked_pending','excluded')
          and coalesce(cardinality(review_reasons), 0) = 0
    );
    assert (select count(*) = 4 from ingest.lodging_permit_reconciliation r
        left join core.catalog_entities e on e.id = r.facility_id
        where r.source_document_id = source_doc and (
            (r.source_row = 91 and r.permit_rooms = 85 and e.slug = 'la-vista-daisetsuzan')
            or (r.source_row = 205 and r.permit_rooms = 17 and e.slug = 'mori-no-ryotei-biei')
            or (r.source_row = 85 and r.disposition = 'linked_pending')
            or (r.source_row = 55 and r.disposition = 'unlinked_pending')
        ));
    assert not has_table_privilege('anon','ingest.lodging_permit_rows','select')
        and not has_table_privilege('authenticated','ingest.lodging_permit_reconciliation','select')
        and not has_function_privilege('anon','ingest.register_lodging_permits(uuid,date,text[],text,jsonb)','execute');
end;
$contract$;
