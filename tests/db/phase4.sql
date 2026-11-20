-- Run after ingest.transport --apply. The simulated expiry and revocation roll back.
begin;
set local plpgsql.check_asserts = on;

do $$
begin
    assert (select count(*) from core.routes where route_key in ('wakkanai-domu-transit',
        'noboribetsu-takimotokan-transit', 'beppu-takegawara-walk', 'beppu-takegawara-bus16')) = 4,
        'Three facilities and the Beppu alternative have reviewed routes';
    assert (select count(distinct facility_id) from core.routes where route_key in ('wakkanai-domu-transit',
        'noboribetsu-takimotokan-transit', 'beppu-takegawara-walk', 'beppu-takegawara-bus16')) = 3,
        'Exactly three linked pilot facilities';
    assert (select count(*) from core.route_legs leg join core.routes route on route.id = leg.route_id
        where route.route_key in ('wakkanai-domu-transit', 'noboribetsu-takimotokan-transit',
            'beppu-takegawara-walk', 'beppu-takegawara-bus16')) = 9, 'Repeat import does not duplicate nine legs';
    assert not exists (
        select 1 from core.routes route
        join lateral (
            select leg.seq, leg.departure_node_id, leg.arrival_node_id,
                lag(leg.arrival_node_id) over (order by leg.seq) as previous_arrival,
                row_number() over (order by leg.seq) as ordinal, count(*) over () as leg_count
            from core.route_legs leg where leg.route_id = route.id
        ) chain on true
        where route.route_key in ('wakkanai-domu-transit', 'noboribetsu-takimotokan-transit',
            'beppu-takegawara-walk', 'beppu-takegawara-bus16')
          and (chain.seq <> chain.ordinal
            or chain.departure_node_id <> coalesce(chain.previous_arrival, route.departure_node_id)
            or (chain.ordinal = chain.leg_count and chain.arrival_node_id <> route.arrival_node_id))
    ), 'Route legs must form one continuous hub-to-facility chain';
    assert (select fare_jpy is null and duration_minutes is null from core.routes where route_key = 'wakkanai-domu-transit'),
        'Missing fare and end-to-end time are not guessed';
    assert (select fare_jpy = 450 and duration_minutes is null from core.routes where route_key = 'noboribetsu-takimotokan-transit'),
        'Verified adult fare, unverified wait-inclusive duration';
    assert (select duration_minutes = 10 and fare_jpy = 0 from core.routes where route_key = 'beppu-takegawara-walk'),
        'Municipal Beppu walk estimate';
    assert (select fare_jpy = 170 and valid_from = date '2026-10-01' and valid_until = date '2027-10-01'
        from core.routes where route_key = 'beppu-takegawara-bus16'), 'GTFS fare and validity attached to the bus option';
    assert (select count(*) from core.route_verification_sources evidence join core.routes route on route.id = evidence.route_id
        where route.route_key = 'beppu-takegawara-bus16') = 5, 'Operator platform, weekday and weekend sources are retained';
    assert (select count(*) from core.transport_nodes where is_hub_candidate and code in ('WAKKANAI_JR', 'NOBORIBETSU_JR', 'BEPPU_JR')
        and coordinate_source_document_id is not null) = 3, 'All three station reference points have provenance';
    assert (select count(*) from ingest.gtfs_feed_checks where feed_version = '20261001' and stop_count = 522 and trip_count = 1206
        and validation->>'stop_time_count' = '38836' and validation->>'exceptions_outside_feed' = '9') = 1,
        'Pinned GTFS stop/trip references and date metadata';
    assert (select count(*) from ingest.gtfs_stop_links where stop_id in ('100099 1', '235 2')) = 2,
        'Specific boarding and alighting stop IDs are linked';
    assert (select count(*) from ingest.gtfs_service_day_checks where service_on in (date '2026-11-08', date '2026-11-23')
        and status = 'service' and eligible_trip_count = 17 and active_service_ids = array['土曜']) = 2,
        'Sunday and holiday are overridden by the Saturday service';
    assert (select count(*) from ingest.gtfs_service_day_checks where service_on = date '2027-10-11'
        and status = 'out_of_range' and eligible_trip_count is null) = 1, 'Out-of-range exception cannot imply service';
end;
$$;

savepoint feed_expired;
update ingest.gtfs_feed_checks set valid_until = valid_from where feed_version = '20261001';
do $$
begin
    assert not exists (select 1 from core.current_verified_routes where route_key = 'beppu-takegawara-bus16'),
        'Expired feed removes the bus option from current verified routes';
    assert exists (select 1 from core.current_verified_routes where route_key = 'beppu-takegawara-walk'),
        'Independent walking route survives feed expiry';
end;
$$;
rollback to feed_expired;

set local role anon;
do $$
begin
    assert not has_schema_privilege(current_user, 'core', 'USAGE'), 'Phase 4 route details stay in the private schema';
    assert not has_schema_privilege(current_user, 'ingest', 'USAGE'), 'GTFS review records stay private';
end;
$$;
rollback;
