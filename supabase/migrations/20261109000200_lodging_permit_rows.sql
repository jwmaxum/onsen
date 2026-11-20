-- Private, typed extraction of an approved lodging permit workbook.
create table ingest.lodging_permit_rows (
    source_document_id uuid not null references ingest.source_documents,
    municipality_code char(5) not null references core.municipalities,
    permit_as_of date not null,
    source_sheet text not null check (btrim(source_sheet) <> ''),
    source_row integer not null check (source_row > 0),
    external_record_id uuid not null unique references ingest.external_records,
    permit_name text not null check (char_length(btrim(permit_name)) between 1 and 250),
    facility_address text not null check (char_length(btrim(facility_address)) between 1 and 250),
    permit_category text not null check (permit_category in ('旅館・ホテル','簡易宿所','下宿')),
    permit_rooms integer check (permit_rooms >= 0),
    permit_issued_on date,
    permit_number text check (char_length(btrim(permit_number)) between 1 and 100),
    check (permit_issued_on <= permit_as_of),
    primary key (source_document_id, source_sheet, source_row)
);
create index lodging_permit_rows_municipality_idx
    on ingest.lodging_permit_rows (municipality_code, source_document_id);

create function ingest.register_lodging_permits(
    document_id uuid, roster_date date, scope_codes text[], sheet text, rows_json jsonb
) returns void
language plpgsql set search_path = '' as $$
declare
    source_uuid uuid;
    fetched timestamptz;
    item record;
    external_uuid uuid;
    linked_uuid uuid;
    name_observation uuid;
    previous ingest.lodging_permit_rows%rowtype;
    row_key text;
    locator text;
    note text;
begin
    if roster_date is null or sheet is distinct from '旅館業法'
        or scope_codes is null or cardinality(scope_codes) = 0
        or cardinality(scope_codes) <> (select count(distinct s) from unnest(scope_codes) s)
        or jsonb_typeof(rows_json) is distinct from 'array'
        or jsonb_array_length(rows_json) not between 1 and 10000 then
        raise check_violation using message = 'Invalid lodging batch parameters';
    end if;

    select s.id, d.fetched_at into strict source_uuid, fetched
    from ingest.source_documents d
    join ingest.source_policy_versions p on p.id = d.policy_version_id
    join ingest.source_registry s on s.id = p.source_id
    join ingest.source_policy_urls u on u.policy_version_id = p.id and u.source_url = d.source_url
    where d.id = document_id and s.active and p.revoked_at is null and p.store_facts = 'allowed'
      and d.content_sha256 is not null and d.raw_object_key is null;

    perform pg_advisory_xact_lock(hashtextextended('lodging-permits/' || source_uuid::text, 0));
    if exists (
        select 1 from unnest(scope_codes) as scope(code)
        left join ingest.municipal_lodging_surveys survey
          on survey.municipality_code::text = scope.code
         and survey.permit_source_id = source_uuid
         and survey.permit_document_id = document_id and survey.permit_as_of = roster_date
        where survey.permit_records is null or survey.permit_records <> (
            select count(*) from jsonb_array_elements(rows_json) row_data
            where row_data->>'municipality_code' = scope.code)
    ) or exists (
        select 1 from jsonb_array_elements(rows_json) row_data
        where row_data->>'municipality_code' is null
           or not ((row_data->>'municipality_code') = any (scope_codes))
    ) or jsonb_array_length(rows_json) <> (
        select count(distinct (row_data->>'source_row')::integer)
        from jsonb_array_elements(rows_json) row_data
    ) then
        raise check_violation using message = 'Lodging rows do not match the approved municipal totals or contain duplicate rows';
    end if;

    for item in
        select * from jsonb_to_recordset(rows_json) as r(
            municipality_code text, source_row integer, permit_name text, facility_address text,
            permit_category text, permit_rooms integer, permit_issued_on date, permit_number text)
        order by source_row
    loop
        row_key := to_char(roster_date, 'YYYY-MM-DD') || '/' || sheet || '/' || item.source_row;
        locator := sheet || ' row ' || item.source_row;
        insert into ingest.external_records (source_id, external_id, first_seen_at, last_seen_at)
        values (source_uuid, row_key, fetched, fetched)
        on conflict (source_id, external_id) do nothing;
        select id, entity_id into strict external_uuid, linked_uuid
        from ingest.external_records where source_id = source_uuid and external_id = row_key;
        if linked_uuid is not null and not exists (
            select 1 from core.catalog_entities e join core.facilities f on f.entity_id = e.id
            where e.id = linked_uuid and e.municipality_code::text = item.municipality_code and not e.test_only
        ) then
            raise check_violation using message = 'Existing permit links to a different municipality or entity type';
        end if;

        insert into ingest.lodging_permit_rows
            (source_document_id, municipality_code, permit_as_of, source_sheet, source_row, external_record_id,
             permit_name, facility_address, permit_category, permit_rooms, permit_issued_on, permit_number)
        values (document_id, item.municipality_code, roster_date, sheet, item.source_row, external_uuid,
                item.permit_name, item.facility_address, item.permit_category, item.permit_rooms,
                item.permit_issued_on, item.permit_number)
        on conflict (source_document_id, source_sheet, source_row) do nothing;
        select * into strict previous from ingest.lodging_permit_rows r
        where r.source_document_id = document_id and r.source_sheet = sheet and r.source_row = item.source_row;
        if (previous.municipality_code::text, previous.permit_as_of, previous.external_record_id,
            previous.permit_name, previous.facility_address, previous.permit_category,
            previous.permit_rooms, previous.permit_issued_on, previous.permit_number)
            is distinct from
            (item.municipality_code, roster_date, external_uuid, item.permit_name, item.facility_address,
             item.permit_category, item.permit_rooms, item.permit_issued_on, item.permit_number) then
            raise check_violation using message = 'Lodging permit facts changed for an existing workbook row';
        end if;

        insert into ingest.field_observations
            (external_record_id, source_document_id, field_key, source_locator, value, observed_at, value_state)
        select external_uuid, document_id, f.key, locator, f.value, fetched, 'confirmed'
        from (values
            ('facility.permit_name', to_jsonb(item.permit_name)),
            ('facility.permit_address', to_jsonb(item.facility_address)),
            ('facility.permit_category', to_jsonb(item.permit_category)),
            ('facility.permit_rooms', to_jsonb(item.permit_rooms)),
            ('facility.permit_issued_on', to_jsonb(item.permit_issued_on)),
            ('facility.permit_number', to_jsonb(item.permit_number))
        ) as f(key, value)
        where f.value is not null
        on conflict (external_record_id, source_document_id, field_key, source_locator) do nothing;

        select o.id into strict name_observation from ingest.field_observations o
        where o.external_record_id = external_uuid and o.source_document_id = document_id
          and o.field_key = 'facility.permit_name' and o.source_locator = locator;
        if linked_uuid is null and not exists (
            select 1 from ingest.review_tasks t where t.observation_id = name_observation
        ) then
            select case
                when count(*) > 1 then '同じ町内に名称一致の施設候補が複数ある。現行の営業、同一性、施設内の温泉利用は未確認。'
                when count(*) = 1 and bool_or(
                    regexp_replace(normalize(f.address_ja, NFKC), '^北海道(上川郡)?', '') =
                    normalize(item.facility_address, NFKC)
                ) then '町内に名称と所在地が一致する候補がある。許可番号との接続、現行の営業、施設内の温泉利用は未確認。'
                when count(*) = 1 then '同じ町内に名称一致の施設候補がある。現行の営業、同一性、施設内の温泉利用は未確認。'
                else '旅館業許可台帳に掲載。町内の既存施設との同一性、現行の宿泊営業、施設内の温泉利用を確認できる根拠が未確認。'
            end into note
            from core.catalog_entities e join core.facilities f on f.entity_id = e.id
            where e.municipality_code::text = item.municipality_code and not e.test_only
              and lower(regexp_replace(normalize(e.name_ja, NFKC), '[[:space:]]+', '', 'g')) =
                  lower(regexp_replace(normalize(item.permit_name, NFKC), '[[:space:]]+', '', 'g'));
            insert into ingest.review_tasks (observation_id, reason) values (name_observation, note);
        end if;
    end loop;
end;
$$;

create view ingest.lodging_permit_reconciliation with (security_invoker = true) as
select p.*, x.entity_id as facility_id,
    case when x.entity_id is not null and t.open_reasons is not null then 'linked_pending'
         when x.entity_id is not null then 'linked'
         when t.open_reasons is not null then 'unlinked_pending'
         when t.excluded_reasons is not null then 'excluded'
         else 'unlinked_pending'
    end as disposition,
    coalesce(t.open_reasons, case when x.entity_id is null then t.excluded_reasons end,
        case when x.entity_id is null then array['既存施設との接続を確認中。'] end) as review_reasons
from ingest.lodging_permit_rows p
join ingest.external_records x on x.id = p.external_record_id
left join ingest.field_observations o on o.external_record_id = p.external_record_id
    and o.source_document_id = p.source_document_id and o.field_key = 'facility.permit_name'
    and o.source_locator = p.source_sheet || ' row ' || p.source_row
left join lateral (
    select array_agg(distinct task.reason order by task.reason) filter (where task.state = 'open') as open_reasons,
           array_agg(distinct task.reason order by task.reason) filter (where task.state = 'rejected') as excluded_reasons
    from ingest.review_tasks task where task.observation_id = o.id or task.entity_id = x.entity_id
) t on true;

create view ingest.municipal_lodging_reconciliation with (security_invoker = true) as
select s.municipality_code, s.permit_as_of, s.permit_records, s.review_status,
    count(p.source_row)::integer as imported_rows,
    count(*) filter (where p.facility_id is not null)::integer as linked_rows,
    count(*) filter (where p.disposition = 'linked_pending')::integer as linked_pending_rows,
    count(*) filter (where p.disposition = 'unlinked_pending')::integer as unlinked_pending_rows,
    count(*) filter (where p.disposition = 'excluded')::integer as excluded_rows
from ingest.municipal_lodging_surveys s
left join ingest.lodging_permit_reconciliation p on p.source_document_id = s.permit_document_id
    and p.municipality_code = s.municipality_code and p.permit_as_of = s.permit_as_of
group by s.municipality_code, s.permit_as_of, s.permit_records, s.review_status;

revoke all on ingest.lodging_permit_rows, ingest.lodging_permit_reconciliation,
    ingest.municipal_lodging_reconciliation from public, anon, authenticated, service_role;
revoke execute on function ingest.register_lodging_permits(uuid, date, text[], text, jsonb)
    from public, anon, authenticated, service_role;
grant select on ingest.lodging_permit_rows, ingest.lodging_permit_reconciliation,
    ingest.municipal_lodging_reconciliation to onsen_reviewer;
