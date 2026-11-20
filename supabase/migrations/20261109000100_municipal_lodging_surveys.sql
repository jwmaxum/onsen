-- Administrative tracking for lodging inventories. Kept outside the public API.
create table ingest.municipal_lodging_surveys (
    municipality_code char(5) primary key references core.municipalities,
    permit_source_id uuid not null references ingest.source_registry,
    permit_document_id uuid references ingest.source_documents,
    permit_as_of date,
    permit_records integer check (permit_records >= 0),
    review_status text not null default 'pending'
        check (review_status in ('pending', 'partial', 'reconciled')),
    reviewed_on date not null,
    remaining_work text not null check (btrim(remaining_work) <> ''),
    check (num_nonnulls(permit_document_id, permit_as_of, permit_records) in (0, 3)),
    check (review_status <> 'reconciled' or permit_document_id is not null),
    check (permit_as_of <= reviewed_on)
);
revoke all on ingest.municipal_lodging_surveys from public, anon, authenticated, service_role;
grant select, insert, update on ingest.municipal_lodging_surveys to onsen_reviewer;
