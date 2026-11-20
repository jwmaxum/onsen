-- Source scope only. Name rows are loaded privately from reviewed extracts.
do $$
declare
    sample record;
    registry_id uuid;
    policy_id uuid;
    run_id uuid;
    doc_id uuid;
    review_date constant date := '2026-11-08';
begin
    for sample in select * from (values
        ('akita_north_fy2024_area_roster', '秋田県', '05',
         'https://www.pref.akita.lg.jp/uploads/public/archive_0000094788_00/%E4%B8%BB%E8%A6%81%E4%BA%8B%E6%A5%AD%E5%AE%9F%E6%96%BD%E7%8A%B6%E6%B3%81.pdf',
         'https://www.pref.akita.lg.jp/pages/about-copyright',
         '3f35eb73edc3d47742aa2c14ca4b92eb1e94a51e4f87a02b3edec3e0a62371cd',
         'partial', 'Printed p. 34: two independently named lodging areas; the third local count spans a merged cell and needs its official group name.'),
        ('yamagata_fy2024_area_roster', '山形県', '06',
         'https://www.pref.yamagata.jp/documents/48413/yamagatanoonsen2025.pdf',
         'https://www.pref.yamagata.jp/kensei/shoukai/aboutthissite/mensekijikou.html',
         '88931495b533b00917beaf0bd89f7d3cc417b9f48da3b2cae49c14a3b897e964',
         'complete', 'Printed p. 2. Shaded lodging areas: 67 in 31 municipalities, aligned to the Ministry FY2024 totals.'),
        ('niigata_fy2024_area_roster', '新潟県', '15',
         'https://www.pref.niigata.lg.jp/uploaded/attachment/491354.pdf',
         'https://www.pref.niigata.lg.jp/site/userguide/chosakuken.html',
         '4e7c8b8ad63fb5113f5a7da3712320096ac4eec56d6b5c67023afbb47ffc3c7e',
         'partial', 'PDF pp. 2–10: 134 names with positive lodging facility counts sum to 490 lodgings. A guest-positive row with blank lodging count awaits confirmation.'),
        ('fukui_fy2024_area_roster', '福井県', '18',
         'https://www.pref.fukui.lg.jp/doc/iei/jigyogaiyou06_d/fil/jigyogaiyo06.pdf',
         'https://www.pref.fukui.lg.jp/doc/dx-suishin/intro.html',
         '69c71077da9fed3d8a8c92fdaed63f260065203481616677fd3912a0d391331c',
         'complete', 'Printed pp. 38–39. Positive lodging column: 38 rows; sources, lodging, capacity, visitors and bath totals align.')
    ) src(source_key, publisher, prefecture, url, terms, sha256, coverage, proof)
    loop
        insert into ingest.source_registry (source_key, publisher, prefecture_code, homepage_url, active)
        values (sample.source_key, sample.publisher, sample.prefecture, sample.url, true)
        returning id into registry_id;
        insert into ingest.source_policy_versions
            (source_id, version, terms_url, license_label, reviewed_at, reviewed_by, auto_fetch, archive_raw,
             store_facts, publish_facts, translate_content, publish_images, attribution, conditions)
        values (registry_id, 1, sample.terms, 'Private factual reconciliation; web reuse pending',
            review_date, 'fy2024-roster-review', 'denied', 'denied', 'allowed', 'pending', 'denied', 'denied',
            sample.publisher, sample.proof || ' Store only factual names, municipality and row references for private reconciliation.')
        returning id into policy_id;
        insert into ingest.source_policy_urls values (policy_id, sample.url);
        insert into ingest.harvest_runs (source_id, policy_version_id, mode, status, started_at, finished_at)
        values (registry_id, policy_id, 'manual', 'succeeded', review_date, review_date)
        returning id into run_id;
        insert into ingest.source_documents (run_id, policy_version_id, source_url, fetched_at, content_sha256, parser_version)
        values (run_id, policy_id, sample.url, review_date, sample.sha256, 'fy2024-reviewed-roster-v1')
        returning id into doc_id;
        insert into ingest.official_area_roster_source_approvals
        values (sample.prefecture, 2024, date '2025-03-31', doc_id, sample.coverage, sample.proof);
    end loop;
end;
$$;
