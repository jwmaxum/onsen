alter table ingest.source_policy_versions add column robots_http_status integer
    check (robots_http_status between 100 and 599);
alter table ingest.source_policy_urls add column approved_content_sha256 text
    check (approved_content_sha256 ~ '^[a-f0-9]{64}$');

create function ingest.check_approved_document_hash() returns trigger
language plpgsql set search_path = '' as $$
begin
    if exists (
        select 1 from ingest.source_policy_urls approved
        where approved.policy_version_id = new.policy_version_id
          and approved.source_url = new.source_url
          and approved.approved_content_sha256 is not null
          and approved.approved_content_sha256 is distinct from new.content_sha256
    ) then
        raise check_violation using message = 'Document bytes differ from the reviewed source version';
    end if;
    return new;
end;
$$;
revoke execute on function ingest.check_approved_document_hash() from public, anon, authenticated, service_role;
create trigger check_approved_document_hash before insert or update of policy_version_id, source_url, content_sha256
    on ingest.source_documents for each row execute function ingest.check_approved_document_hash();

insert into ingest.source_registry (source_key, publisher, prefecture_code, homepage_url, active)
values ('beppu_open_data', '別府市', '44', 'https://www.city.beppu.oita.jp/sisei/df/henkaku/list.html', true)
on conflict (source_key) do nothing;

with reviewed_policy as (
    insert into ingest.source_policy_versions (
        source_id, version, terms_url, license_label, reviewed_at, reviewed_by,
        auto_fetch, archive_raw, store_facts, publish_facts, translate_content, publish_images,
        robots_status, robots_http_status, max_requests_per_minute, attribution, conditions
    )
    select id, 2, 'https://www.city.beppu.oita.jp/doc/sisei/df/henkaku/opendata/riyoukiyaku.pdf',
        '別府市オープンデータ利用規約 (CC BY 4.0 compatible)', '2026-11-08 12:07:18+09', 'phase2_source_review',
        'allowed', 'denied', 'allowed', 'conditional', 'conditional', 'denied', 'allowed', 404, 30,
        '別府市公開の温泉分析書をもとに測定値を転記・整理。原本URL、利用日と加工の明示が必要。',
        'Exact reviewed PDFs only. Origin robots.txt returned HTTP 404. Store normalized facts and provenance only. Exclude scans, personal names, seals, health wording and source parcel addresses.'
    from ingest.source_registry where source_key = 'beppu_open_data'
    returning id
)
insert into ingest.source_policy_urls (policy_version_id, source_url, approved_content_sha256)
select reviewed_policy.id, 'https://www.city.beppu.oita.jp/doc/sisetu/sieionsen/04/' || documents.file_name, documents.sha256
from reviewed_policy cross join (values
    ('bunseki_men.pdf', '15a2557c93c0182a766db7ec01474344a61bc6f9e0746c9e8285ca462d2a83a7'),
    ('bunseki_women.pdf', '5ff7abdc717a7a23c6b5548d029884dcd46b7a797738af41e82f56021bafcdcd'),
    ('bunseki_suna.pdf', '9e2e4d99335bc0bfd69fac0c59106cffe039701fc93132674b799f76f8d62924')
) as documents (file_name, sha256);
