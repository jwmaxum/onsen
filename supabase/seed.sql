-- Local-only fixtures. These names, addresses and coordinates are synthetic.
insert into core.catalog_entities (id, kind, prefecture_code, name_ja, slug, latitude, longitude,
    location_accuracy, operating_status, test_only) values
    ('00000000-0000-4000-8000-000000000101', 'facility', '01', '合成施設 A', 'test-north-a', 45, 142, 'building', 'open', true),
    ('00000000-0000-4000-8000-000000000102', 'facility', '01', '合成施設 B', 'test-north-b', 45, 142, 'building', 'open', true),
    ('00000000-0000-4000-8000-000000000103', 'facility', '01', '合成施設 C', 'test-north-c', 45, 142, 'building', 'open', true),
    ('00000000-0000-4000-8000-000000000104', 'facility', '44', '合成施設 D', 'test-south', 33, 131, 'building', 'open', true),
    ('00000000-0000-4000-8000-000000000201', 'area', '01', '合成温泉地', 'test-area', 45, 142, 'verified_area', 'unknown', true),
    ('00000000-0000-4000-8000-000000000301', 'spring', '01', '合成源泉', null, null, null, 'unknown', 'unknown', true);

insert into core.facilities (entity_id, facility_type, address_ja) values
    ('00000000-0000-4000-8000-000000000101', 'public_bath', '合成住所 A'),
    ('00000000-0000-4000-8000-000000000102', 'ryokan', '合成住所 B'),
    ('00000000-0000-4000-8000-000000000103', 'day_spa', '合成住所 C'),
    ('00000000-0000-4000-8000-000000000104', 'hotel', '合成住所 D');
insert into core.onsen_areas (entity_id, location_ja) values
    ('00000000-0000-4000-8000-000000000201', '合成地域');
insert into core.spring_sources (entity_id) values ('00000000-0000-4000-8000-000000000301');
insert into core.area_facilities (area_id, facility_id, is_primary) values
    ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000101', true);
insert into core.facility_specs (facility_id, rooms, rooms_state) values
    ('00000000-0000-4000-8000-000000000101', 0, 'confirmed'),
    ('00000000-0000-4000-8000-000000000102', null, 'unknown');
