-- Named national designations are tracked separately from the utilization-survey totals.
do $$
declare
    registry_id uuid;
    policy_id uuid;
    run_id uuid;
    doc_id uuid;
    area_id uuid;
    sample record;
    url constant text := 'https://www.env.go.jp/council/content/12nature08/000360911.pdf';
    review_date constant date := '2026-11-08';
begin
    insert into ingest.source_registry (source_key, publisher, homepage_url, active)
    values ('moe_designated_areas', '環境省', 'https://www.env.go.jp/nature/onsen/area/', true)
    returning id into registry_id;
    insert into ingest.source_policy_versions
        (source_id, version, terms_url, license_label, reviewed_at, reviewed_by, auto_fetch, archive_raw,
         store_facts, publish_facts, translate_content, publish_images, robots_status, attribution, conditions)
    values (registry_id, 1, 'https://www.env.go.jp/mail.html', 'PDL 1.0', review_date, 'national-inventory-review',
        'denied', 'denied', 'allowed', 'allowed', 'denied', 'denied', 'allowed',
        '環境省「国民保養温泉地一覧表（令和7年12月現在）」を加工して作成',
        'Names and administrative geography extracted from page 2. No maps, photos or facility claims.')
    returning id into policy_id;
    insert into ingest.source_policy_urls values (policy_id, url);
    insert into ingest.harvest_runs (source_id, policy_version_id, mode, status, started_at, finished_at)
    values (registry_id, policy_id, 'manual', 'succeeded', review_date, review_date)
    returning id into run_id;
    insert into ingest.source_documents (run_id, policy_version_id, source_url, fetched_at, content_sha256, parser_version)
    values (run_id, policy_id, url, review_date,
        '10b9e672699cf03e93bc3b22c173f414bee3336c1b7012863fba0cb79a9a5fec', 'pdf-two-column-designations-v1')
    returning id into doc_id;

    for sample in select * from (values
        (1, '01', '01', 'カルルス温泉', '登別市'),
        (2, '01', '01', 'ニセコ温泉郷', '磯谷郡蘭越町、虻田郡ニセコ町'),
        (3, '01', '01', '芦別温泉', '芦別市'),
        (4, '01', '01', 'ながぬま温泉', '夕張郡長沼町'),
        (5, '01', '01', '豊富温泉', '天塩郡豊富町'),
        (6, '02', '02', '酸ヶ湯温泉', '青森市'),
        (7, '03', '03;05', '八幡平温泉郷', '八幡平市;仙北市、鹿角市'),
        (8, '05', '05', '大館ぐるみ温泉郷', '大館市'),
        (9, '03', '03', '金田一温泉', '二戸市'),
        (10, '04', '04', '鳴子温泉郷', '大崎市'),
        (11, '05', '05', '田沢湖高原温泉郷', '仙北市'),
        (12, '05', '05', '秋ノ宮温泉', '湯沢市'),
        (13, '06', '06', '蔵王温泉', '山形市'),
        (14, '06', '06', '銀山温泉', '尾花沢市'),
        (15, '06', '06', '碁点温泉', '村山市'),
        (16, '06', '06', '肘折温泉郷', '最上郡大蔵村'),
        (17, '06', '06', '湯田川温泉', '鶴岡市'),
        (18, '06', '06', '湯野浜温泉', '鶴岡市'),
        (19, '06', '06', 'あつみ温泉', '鶴岡市'),
        (20, '06', '06', '由良温泉', '鶴岡市'),
        (21, '07', '07', '岳温泉', '二本松市'),
        (22, '07', '07', '新甲子温泉', '西白河郡西郷村'),
        (23, '07', '07', '土湯・高湯温泉郷', '福島市'),
        (24, '07', '07', '二岐・岩瀬湯本・天栄温泉', '岩瀬郡天栄村'),
        (25, '09', '09', '奥日光湯元温泉', '日光市'),
        (26, '09', '09', '板室温泉', '那須塩原市'),
        (27, '10', '10', '四万温泉', '吾妻郡中之条町'),
        (28, '10', '10', '鹿沢温泉', '吾妻郡嬬恋村'),
        (29, '10', '10', 'みなかみ町国民保養温泉地', '利根郡みなかみ町'),
        (30, '14', '14', '芦之湯温泉', '足柄下郡箱根町'),
        (31, '15', '15', '岩室温泉', '新潟市'),
        (32, '15', '15', '六日町温泉', '南魚沼市'),
        (33, '15', '15', '関・燕温泉', '妙高市'),
        (34, '15', '15', '五頭温泉郷', '阿賀野市'),
        (35, '17', '17', '白山温泉郷', '白山市'),
        (36, '19', '19', '下部温泉', '南巨摩郡身延町'),
        (37, '19', '19', '増富温泉', '北杜市'),
        (38, '20', '20', '丸子温泉郷', '上田市'),
        (39, '20', '20', '田沢・沓掛温泉', '小県郡青木村'),
        (40, '20', '20', '小谷温泉', '北安曇郡小谷村'),
        (41, '20', '20', '白骨温泉', '松本市'),
        (42, '20', '20', '美ケ原温泉', '松本市'),
        (43, '21', '21', '奥飛騨温泉郷', '高山市'),
        (44, '21', '21', '白川郷平瀬温泉', '大野郡白川村'),
        (45, '21', '21', '小坂温泉郷', '下呂市'),
        (46, '22', '22', '畑毛・奈古谷温泉', '伊豆の国市、田方郡函南町'),
        (47, '22', '22', '梅ヶ島温泉郷', '静岡市'),
        (48, '26', '26', '久美の浜温泉郷', '京丹後市'),
        (49, '26', '26', 'るり渓高原温泉', '南丹市'),
        (50, '28', '28', '浜坂温泉郷', '美方郡新温泉町'),
        (51, '29', '29', '十津川温泉郷', '吉野郡十津川村'),
        (52, '30', '30', '熊野本宮温泉郷', '田辺市'),
        (53, '30', '30', '龍神温泉郷', '田辺市'),
        (54, '31', '31', '鹿野・吉岡温泉', '鳥取市'),
        (55, '31', '31', '関金温泉', '倉吉市'),
        (56, '31', '31', '岩井温泉', '岩美郡岩美町'),
        (57, '32', '32', '三瓶温泉', '大田市'),
        (58, '32', '32', '鷺の湯温泉', '安来市'),
        (59, '33', '33', '湯原温泉', '真庭市'),
        (60, '33', '33', '奥津温泉', '苫田郡鏡野町'),
        (61, '33', '33', '湯郷温泉', '美作市'),
        (62, '34', '34', '湯来・湯の山温泉', '広島市'),
        (63, '34', '34', '矢野温泉', '府中市'),
        (64, '35', '35', '俵山温泉', '長門市'),
        (65, '35', '35', '三丘温泉', '周南市'),
        (66, '37', '37', '塩江温泉郷', '高松市'),
        (67, '38', '38', '湯ノ浦温泉', '今治市'),
        (68, '40', '40', '筑後川温泉', 'うきは市'),
        (69, '40', '40', '吉井温泉', 'うきは市'),
        (70, '42', '42', '雲仙・小浜温泉', '雲仙市（雲仙）;（小浜）'),
        (71, '42', '42', '壱岐湯本温泉', '壱岐市'),
        (72, '43', '43', '天草下田温泉', '天草市'),
        (73, '43', '43', '南小国温泉郷', '阿蘇郡南小国町'),
        (74, '43', '43', '湯の児・湯の鶴温泉', '水俣市'),
        (75, '44', '44', '湯布院温泉郷', '由布市'),
        (76, '44', '44', '竹田温泉群', '竹田市'),
        (77, '44', '44', '鉄輪･明礬･柴石温泉', '別府市'),
        (78, '46', '46', '霧島温泉', '霧島市'),
        (79, '46', '46', '隼人・新川渓谷温泉郷', '霧島市')
    ) records(list_position, prefecture_code, prefectures, name_ja, location_ja)
    loop
        insert into core.catalog_entities (kind, prefecture_code, name_ja, slug, review_state, verified_at)
        values ('area', sample.prefecture_code, sample.name_ja, 'moe-designation-' || sample.list_position,
            'in_review', review_date)
        returning id into area_id;
        insert into core.onsen_areas (entity_id, location_ja) values (area_id, sample.location_ja);
        insert into core.national_area_designations values (area_id, doc_id, sample.list_position, date '2025-12-01');
        insert into core.national_area_designation_jurisdictions
        select area_id, code from unnest(string_to_array(sample.prefectures, ';')) code;
    end loop;
end;
$$;
