-- Rights and observations for named facilities are independent of the area inventory.
create function pg_temp.followup_source(
    source_key text, publisher text, prefecture char(2), url text, version integer,
    terms text, license text, attribution text, contents_hash text, scope_note text
) returns uuid language plpgsql set search_path = '' as $$
declare
    registry_id uuid;
    policy_id uuid;
    run_id uuid;
    doc_id uuid;
    checked constant timestamptz := '2026-11-08 12:00:00+09';
begin
    insert into ingest.source_registry (source_key, publisher, prefecture_code, homepage_url, active)
    values (source_key, publisher, prefecture, url, true) on conflict on constraint source_registry_source_key_key do nothing;
    select s.id into strict registry_id from ingest.source_registry s
    where s.source_key = followup_source.source_key and s.active;
    insert into ingest.source_policy_versions
        (source_id, version, terms_url, license_label, reviewed_at, reviewed_by,
         auto_fetch, archive_raw, store_facts, publish_facts, translate_content, publish_images, attribution, conditions)
    values (registry_id, version, terms, license, checked, 'national-followup-review',
        'denied', 'denied', 'allowed', 'allowed', 'denied', 'denied', attribution, scope_note)
    returning id into policy_id;
    insert into ingest.source_policy_urls values (policy_id, url);
    insert into ingest.harvest_runs (source_id, policy_version_id, mode, status, started_at, finished_at)
    values (registry_id, policy_id, 'manual', 'succeeded', checked, checked)
    returning id into run_id;
    insert into ingest.source_documents (run_id, policy_version_id, source_url, fetched_at, content_sha256, parser_version)
    values (run_id, policy_id, url, checked, contents_hash, 'manual-facility-followup-v1')
    returning id into doc_id;
    return doc_id;
end;
$$;

create function pg_temp.followup_observe(
    entity_id uuid, document_id uuid, external_id text, field_key text, locator text, observation_value jsonb
) returns uuid language plpgsql set search_path = '' as $$
declare
    record_id uuid;
    observation_id uuid;
begin
    insert into ingest.external_records (source_id, external_id, entity_id)
    select policy.source_id, followup_observe.external_id, followup_observe.entity_id
    from ingest.source_documents doc join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
    where doc.id = document_id
    on conflict on constraint external_records_source_id_external_id_key do update
        set last_seen_at = excluded.last_seen_at
        where ingest.external_records.entity_id = excluded.entity_id
    returning id into record_id;

    insert into ingest.field_observations
        (external_record_id, source_document_id, field_key, source_locator, value, observed_at, value_state)
    values (record_id, document_id, field_key, locator, observation_value, '2026-11-08 12:00:00+09', 'confirmed')
    returning id into observation_id;
    return observation_id;
end;
$$;

insert into core.municipalities (code, prefecture_code, name_ja) values
    ('02210', '02', '平川市'), ('04102', '04', '仙台市宮城野区');

do $$
declare
    checked constant timestamptz := '2026-11-08 12:00:00+09';
    hirakawa_doc uuid;
    sendai_doc uuid;
    source_doc uuid;
    geo_doc uuid;
    entity uuid;
    sample record;
    identity_proof uuid;
    location_proof uuid;
begin
    hirakawa_doc := pg_temp.followup_source('hirakawa_open_facilities', '平川市', '02',
        'https://opendata.pref.aomori.lg.jp/dataset/2032/resource/24651/%E8%A6%B3%E5%85%89%E6%96%BD%E8%A8%AD%E4%B8%80%E8%A6%A7_%E5%B9%B3%E5%B7%9D%E5%B8%82.csv',
        1, 'https://opendata.pref.aomori.lg.jp/privacy.html', 'CC BY 4.0',
        '平川市「観光施設一覧」 CC BY 4.0 · 座標欄を抽出',
        '6bb58a46025086b16e1b50a0d5a1cd397179e54a8c6da66c1ec4bd582b32d1a2',
        'Exact IDs 403000010 and 403000019. Publish the facility points with credit, cross-checked against operator evidence.');
    sendai_doc := pg_temp.followup_source('mlit_minato_polygon', '国土交通省港湾局', null,
        'https://cyberjapandata.gsi.go.jp/xyz/minato_polygon/2/3/1.geojson',
        2, 'https://www.mlit.go.jp/link.html', 'Government Standard Terms of Use v2.0',
        '国土交通省港湾局 · 施設ポリゴンの重心を算出',
        '9b15faa1b788e25b043e1881df0aec1c1be7b84b57826aeaa09c29a2bb2386c8',
        'Single reviewed Dormy Inn Sendai Seaside facility polygon from the Minato Oasis layer. Publish its calculated centroid.');

    for sample in select * from (values
        ('hirakawa-fukuya', '02', '02210', '津軽おのえ温泉 日帰りの宿 福家', '青森県平川市新屋町道ノ下35-2',
            'public_bath', 'hirakawa_fukuya_operator', '日帰りの宿 福家', 'https://fukuya-spa.com/information/',
            40.604330, 140.567470, '403000019'),
        ('ikarigaseki-okariya-goten', '02', '02210', '平川市温泉交流館 御仮屋御殿', '青森県平川市碇ヶ関阿原23-2',
            'public_bath', 'ikarigaseki_okariya_operator', '道の駅 いかりがせき', 'https://ikarigaseki.com/hot_spring/',
            40.481289, 140.621937, '403000010'),
        ('sendai-seaside-kaijin-no-yu', '04', '04102', '天然温泉 海神の湯 ドーミーインEXPRESS仙台シーサイド',
            '宮城県仙台市宮城野区中野3-4-9', 'hotel', 'sendai_seaside_operator', 'ドーミーイン',
            'https://dormy-hotels.com/dormyinn/hotels/sendai_ex/spa/',
            38.270308, 140.990684, '天然温泉海神の湯 ドーミーインEXPRESS仙台シーサイド')
    ) batch(slug, prefecture, municipality, name, address, facility_type, source_key, publisher, url, latitude, longitude, locator)
    loop
        source_doc := pg_temp.followup_source(sample.source_key, sample.publisher, sample.prefecture::char(2),
            sample.url, 1, null, null, sample.publisher, null, 'Manual review of individual identity and operating facts only.');
        geo_doc := case when sample.prefecture = '02' then hirakawa_doc else sendai_doc end;
        insert into core.catalog_entities
            (kind, prefecture_code, municipality_code, name_ja, slug, latitude, longitude,
             location_accuracy, review_state, operating_status, verified_at)
        values ('facility', sample.prefecture, sample.municipality, sample.name, sample.slug, sample.latitude, sample.longitude,
            'approximate', 'approved', 'open', checked)
        returning id into entity;
        insert into core.facilities (entity_id, facility_type, address_ja, official_url)
        values (entity, sample.facility_type, sample.address, sample.url);
        insert into core.journey_memberships values (entity, true, 'Verified Tohoku facility in north–south journey.', checked);
        identity_proof := pg_temp.followup_observe(entity, source_doc, sample.slug, 'facility_identity',
            'Operator operating information and official address cross-check',
            jsonb_build_object('name', sample.name, 'address', sample.address, 'operating_status', 'open'));
        location_proof := pg_temp.followup_observe(entity, geo_doc, sample.slug, 'facility_reference_position',
            sample.locator, jsonb_build_array(sample.latitude, sample.longitude));
        insert into core.web_reference_publications (entity_id, identity_observation_id, position_observation_id, reviewed_at)
        values (entity, identity_proof, location_proof, checked);
    end loop;
end;
$$;

insert into core.prefecture_survey values
    ('02', '2026-11-08', 'partial', array['inventory_pending','optional_fields_pending']),
    ('04', '2026-11-08', 'partial', array['inventory_pending','optional_fields_pending']),
    ('05', '2026-11-08', 'partial', array['inventory_pending','other_rights_pending']),
    ('06', '2026-11-08', 'partial', array['inventory_pending','other_rights_pending']),
    ('07', '2026-11-08', 'partial', array['inventory_pending','other_rights_pending']);

update ingest.review_tasks task
set reason = 'Facility and operating information confirmed. Published tourism pin lacks a verified reuse grant; government address matches are district-level and open-data facility extracts do not identify this building.'
from core.catalog_entities entity
where task.entity_id = entity.id and task.state = 'open'
  and entity.slug in ('toyotomi-fureai-center', 'rishirifuji-onsen');

create or replace view api.web_pilot_entries with (security_barrier = true) as
with version as (
    select case
        when exists (select 1 from core.web_reference_publications where reviewed_at >= '2026-11-08 12:00:00+09')
        then 'pilot-2026-11-08-r3'
        when exists (select 1 from core.web_reference_publications)
        then 'pilot-2026-11-08-r2' else 'pilot-2026-11-08' end as release_id
)
select version.release_id, entity.id as entity_id, entity.kind, entity.prefecture_code,
    scope.slug, scope.name_ja, scope.address_ja as location_ja, scope.latitude, scope.longitude,
    facility.facility_type, true as in_journey, scope.source_url as public_source_url,
    scope.approved_at as verified_at, node.coordinate_accuracy,
    null::text as coordinate_source_url, null::text as coordinate_attribution
from core.web_pilot_scope scope
cross join version
join core.catalog_entities entity on entity.slug = scope.slug and entity.kind = 'facility'
join core.facilities facility on facility.entity_id = entity.id
join core.transport_nodes node on node.code = scope.node_code and node.facility_id = entity.id
join ingest.source_documents coord_doc on coord_doc.id = node.coordinate_source_document_id
join ingest.source_policy_versions coord_policy on coord_policy.id = coord_doc.policy_version_id
join ingest.source_registry coord_source on coord_source.id = coord_policy.source_id
where not entity.test_only and entity.review_state in ('in_review', 'approved')
  and entity.operating_status not in ('temporarily_closed', 'closed') and entity.name_ja = scope.name_ja
  and node.latitude = scope.latitude and node.longitude = scope.longitude
  and node.coordinate_accuracy in ('address_reference', 'facility_location')
  and coord_source.active and coord_policy.revoked_at is null and coord_policy.store_facts = 'allowed'
  and coord_policy.publish_facts in ('allowed', 'conditional')
  and exists (
      select 1 from ingest.source_documents doc
      join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
      join ingest.source_registry source on source.id = policy.source_id
      where doc.source_url = scope.source_url and source.active and policy.revoked_at is null and policy.store_facts = 'allowed'
        and policy.publish_facts in ('allowed', 'conditional')
  )
union all
select version.release_id, entry.* from core.web_reference_entries entry cross join version
where not exists (select 1 from core.web_pilot_scope scope where scope.slug = entry.slug);

drop function pg_temp.followup_observe(uuid, uuid, text, text, text, jsonb);
drop function pg_temp.followup_source(text, text, character, text, integer, text, text, text, text, text);
