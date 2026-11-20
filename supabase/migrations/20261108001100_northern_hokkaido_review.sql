-- Manually reviewed identity facts; no website text, photos or raw files are stored.
insert into core.municipalities (code, prefecture_code, name_ja) values
    ('01516', '01', '豊富町'), ('01517', '01', '礼文町'), ('01518', '01', '利尻町'), ('01519', '01', '利尻富士町');

do $$
declare
    batch_reviewed constant timestamptz := '2026-11-08 00:00:00+09';
    geo_url constant text := 'https://cyberjapandata.gsi.go.jp/xyz/minato_polygon/2/3/1.geojson';
    geo_source_id uuid;
    geo_policy_id uuid;
    geo_run_id uuid;
    geo_doc_id uuid;
    sample record;
    entity_id uuid;
    official_source_id uuid;
    official_policy_id uuid;
    official_run_id uuid;
    official_doc_id uuid;
    official_record_id uuid;
    identity_id uuid;
    geo_record_id uuid;
    position_id uuid;
begin
    insert into ingest.source_registry (source_key, publisher, prefecture_code, homepage_url, active)
    values ('mlit_minato_polygon', '国土交通省港湾局', '01',
        'https://maps.gsi.go.jp/development/ichiran.html', true)
    returning id into geo_source_id;
    insert into ingest.source_policy_versions (source_id, version, terms_url, license_label, reviewed_at, reviewed_by,
        auto_fetch, archive_raw, store_facts, publish_facts, translate_content, publish_images, attribution, conditions)
    values (geo_source_id, 1, 'https://www.mlit.go.jp/link.html', 'Government Standard Terms of Use v2.0',
        batch_reviewed, 'phase6-source-review', 'denied', 'denied', 'allowed', 'allowed', 'denied', 'denied',
        '国土交通省港湾局 · 施設ポリゴンの重心を算出',
        'Exact zoom-2 tile and three reviewed facility footprints. Each published point is a calculated centroid.')
    returning id into geo_policy_id;
    insert into ingest.source_policy_urls values (geo_policy_id, geo_url);
    insert into ingest.harvest_runs (source_id, policy_version_id, mode, status, started_at, finished_at)
    values (geo_source_id, geo_policy_id, 'manual', 'succeeded', batch_reviewed, batch_reviewed)
    returning id into geo_run_id;
    insert into ingest.source_documents (run_id, policy_version_id, source_url, fetched_at, content_sha256, parser_version)
    values (geo_run_id, geo_policy_id, geo_url, batch_reviewed,
        '9b15faa1b788e25b043e1881df0aec1c1be7b84b57826aeaa09c29a2bb2386c8', 'geojson-ring-centroid-v1')
    returning id into geo_doc_id;

    for sample in
        select * from (values
            ('wakkanai-minato-no-yu', '01214', 'ヤムワッカナイ温泉 港のゆ', '北海道稚内市港1丁目6-28 稚内副港市場2階',
                'wakkanai_minato_official', '稚内副港市場', 'https://fukkoichiba.hokkaido.jp/relax/',
                'open', 45.408447, 141.676517, '【代表施設】稚内副港市場'),
            ('rebun-usuyuki-no-yu', '01517', '礼文島温泉うすゆきの湯', '北海道礼文郡礼文町香深村ベッシュ961-1',
                'rebun_bath_official', '礼文町', 'https://www.town.rebun.hokkaido.jp/hotnews/detail/00001701.html',
                'open', 45.300253, 141.047461, '礼文町総合交流促進施設（うすゆきの湯）'),
            ('rishiri-fureai-onsen', '01518', '利尻ふれあい温泉', '北海道利尻郡利尻町沓形字富士見町94',
                'rishiri_bath_official', '北海道開発局', 'https://www.hkd.mlit.go.jp/ky/kk/kou_kei/splaat0000011loi.html',
                'open', 45.184776, 141.133724, '利尻町ふれあい保養センター（利尻ふれあい温泉）'),
            ('toyotomi-fureai-center', '01516', '豊富町ふれあいセンター', '北海道天塩郡豊富町字温泉',
                'toyotomi_bath_official', '豊富町', 'https://www.town.toyotomi.hokkaido.jp/section/syoukoukankouka/a7cug60000001fqi.html',
                'open', null, null, null),
            ('rishirifuji-onsen', '01519', '利尻富士温泉保養施設', '北海道利尻郡利尻富士町鴛泊字栄町',
                'rishirifuji_bath_official', '利尻富士町', 'https://www.town.rishirifuji.hokkaido.jp/rishirifuji/1204.htm',
                'unknown', null, null, null)
        ) as batch(slug, municipality, name_ja, address_ja, source_key, publisher, identity_url,
            operating_status, latitude, longitude, feature_name)
    loop
        insert into core.catalog_entities (kind, prefecture_code, municipality_code, name_ja, slug, latitude, longitude,
            location_accuracy, review_state, operating_status, verified_at)
        values ('facility', '01', sample.municipality, sample.name_ja, sample.slug, sample.latitude, sample.longitude,
            case when sample.latitude is null then 'unknown' else 'approximate' end,
            case when sample.latitude is null then 'in_review'::core.review_state else 'approved'::core.review_state end,
            sample.operating_status::core.operating_status, case when sample.latitude is not null then batch_reviewed end)
        returning id into entity_id;
        insert into core.facilities (entity_id, facility_type, address_ja, official_url)
        values (entity_id, 'public_bath', sample.address_ja, sample.identity_url);

        insert into ingest.source_registry (source_key, publisher, prefecture_code, homepage_url, active)
        values (sample.source_key, sample.publisher, '01', sample.identity_url, true)
        returning id into official_source_id;
        insert into ingest.source_policy_versions (source_id, version, reviewed_at, reviewed_by, auto_fetch, archive_raw,
            store_facts, publish_facts, translate_content, publish_images, attribution, conditions)
        values (official_source_id, 1, batch_reviewed, 'phase6-source-review', 'denied', 'denied',
            'allowed', 'allowed', 'denied', 'denied', sample.publisher,
            'Manual identity and operating facts only. Excludes website copy, media, pricing and automated collection.')
        returning id into official_policy_id;
        insert into ingest.source_policy_urls values (official_policy_id, sample.identity_url);
        insert into ingest.harvest_runs (source_id, policy_version_id, mode, status, started_at, finished_at)
        values (official_source_id, official_policy_id, 'manual', 'succeeded', batch_reviewed, batch_reviewed)
        returning id into official_run_id;
        insert into ingest.source_documents (run_id, policy_version_id, source_url, fetched_at, parser_version)
        values (official_run_id, official_policy_id, sample.identity_url, batch_reviewed, 'manual-facility-review-v1')
        returning id into official_doc_id;
        insert into ingest.external_records (source_id, external_id, entity_id, first_seen_at, last_seen_at)
        values (official_source_id, sample.slug, entity_id, batch_reviewed, batch_reviewed)
        returning id into official_record_id;
        insert into ingest.field_observations (external_record_id, source_document_id, field_key, source_locator,
            value, value_state, observed_at)
        values (official_record_id, official_doc_id, 'facility_identity', 'Manual review of official facility information',
            jsonb_build_object('name', sample.name_ja, 'address', sample.address_ja, 'operating_status', sample.operating_status),
            'confirmed', batch_reviewed)
        returning id into identity_id;

        if sample.latitude is not null then
            insert into ingest.external_records (source_id, external_id, entity_id, first_seen_at, last_seen_at)
            values (geo_source_id, sample.slug, entity_id, batch_reviewed, batch_reviewed)
            returning id into geo_record_id;
            insert into ingest.field_observations (external_record_id, source_document_id, field_key, source_locator,
                value, value_state, observed_at)
            values (geo_record_id, geo_doc_id, 'facility_reference_position', sample.feature_name,
                jsonb_build_array(sample.latitude, sample.longitude), 'confirmed', batch_reviewed)
            returning id into position_id;
            insert into core.journey_memberships values (entity_id, true, 'Northern Hokkaido expansion in the north–south journey.', batch_reviewed);
            insert into core.web_reference_publications (entity_id, identity_observation_id, position_observation_id, reviewed_at)
            values (entity_id, identity_id, position_id, batch_reviewed);
        else
            insert into ingest.review_tasks (entity_id, reason)
            values (entity_id, 'Facility-level coordinates and current operations require further review before publication.');
        end if;
    end loop;
end;
$$;

update core.prefecture_survey set gap_codes = array_append(gap_codes, 'position_pending')
where prefecture_code = '01';
