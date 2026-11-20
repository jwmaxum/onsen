-- Run against the reviewed phase 4 pilot with no active nationwide release.
begin;
set local plpgsql.check_asserts = on;

do $$
begin
    if to_regclass('core.web_reference_publications') is not null then
        update core.web_reference_publications set withdrawn_at = greatest(now(), reviewed_at);
    end if;
end;
$$;

set local role anon;
do $$
begin
    assert (select array_agg(slug order by latitude desc, longitude desc, entity_id) from api.web_catalog_entries) =
        array['wakkanai-onsen-domu', 'daiichi-takimotokan', 'takegawara-onsen'], 'Pilot latitude order';
    assert (select count(*) from api.web_catalog_versions where status = 'active' and release_id like 'pilot-%') = 1,
        'Exactly one pilot version';
    assert (select count(*) from api.web_pilot_route_legs) = 9, 'Only the nine approved pilot legs';
    assert (select quality_codes from api.web_catalog_entries where slug = 'takegawara-onsen') = array['bicarbonate','chloride'],
        'Facets come from published analyses';
    assert not exists (select 1 from api.web_catalog_entries where day_admission_jpy is not null), 'Unapproved admission prices stay null';
    assert not has_schema_privilege(current_user, 'core', 'USAGE')
        and not has_schema_privilege(current_user, 'ingest', 'USAGE'), 'Private schemas stay hidden';
end;
$$;
reset role;

savepoint tied_positions;
update core.web_pilot_scope set latitude = 45, longitude = 141;
update core.transport_nodes node set latitude = 45, longitude = 141
    from core.web_pilot_scope scope where node.code = scope.node_code;
set local role anon;
do $$
declare
    first_id uuid;
    ids uuid[];
begin
    select entity_id into strict first_id from api.web_catalog_entries order by latitude desc, longitude desc, entity_id asc limit 1;
    select array_agg(entity_id order by latitude desc, longitude desc, entity_id asc) into ids
    from api.web_catalog_entries where latitude < 45 or (latitude = 45 and longitude < 141)
        or (latitude = 45 and longitude = 141 and entity_id > first_id);
    assert cardinality(ids) = 2 and ids[1] < ids[2] and ids[1] > first_id, 'A page boundary crosses three identical coordinates';
end;
$$;
rollback to tied_positions;

savepoint source_revoked;
update ingest.source_policy_versions policy set revoked_at = now()
from ingest.source_registry source where policy.source_id = source.id and source.source_key = 'domu_operator';
set local role anon;
do $$
begin
    assert not exists (select 1 from api.web_catalog_entries where slug = 'wakkanai-onsen-domu'), 'Revoked identity source hides the card';
    assert not exists (select 1 from api.web_pilot_route_legs where facility_slug = 'wakkanai-onsen-domu'), 'Revocation hides its legs';
end;
$$;
rollback to source_revoked;

savepoint publication_denied;
update ingest.source_policy_versions policy set publish_facts = 'denied'
from ingest.source_registry source where policy.source_id = source.id and source.source_key = 'oita_kamenoibus_gtfs';
set local role anon;
do $$
begin
    assert not exists (select 1 from api.web_pilot_route_legs where route_key = 'beppu-takegawara-bus16'), 'Publication denial hides the bus route';
    assert exists (select 1 from api.web_pilot_route_legs where route_key = 'beppu-takegawara-walk'), 'Unaffected municipal walk stays available';
end;
$$;
rollback to publication_denied;

savepoint feed_expired;
update ingest.gtfs_feed_checks set valid_until = valid_from where feed_version = '20261001';
set local role anon;
do $$
begin
    assert not exists (select 1 from api.web_pilot_route_legs where route_key = 'beppu-takegawara-bus16'), 'Expired feed is excluded';
    assert exists (select 1 from api.web_pilot_route_legs where route_key = 'beppu-takegawara-walk'), 'Walk option is still available';
end;
$$;
rollback to feed_expired;

savepoint nationwide_active;
insert into api.releases (status, published_at) values ('active', now());
set local role anon;
do $$
begin
    assert not exists (select 1 from api.web_catalog_entries where release_id like 'pilot-%'), 'Active publication supersedes pilot cards';
    assert not exists (select 1 from api.web_catalog_versions where release_id like 'pilot-%'), 'Superseded pilot cursor expires';
end;
$$;
rollback to nationwide_active;

rollback;
