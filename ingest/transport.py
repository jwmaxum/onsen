"""Connect the reviewed transport pilot and an approved Kamenoi GTFS ZIP to the local DB."""

import argparse
import json
import sys
from datetime import date
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5

from ingest.kamenoibus_gtfs import ALIGHT, BOARD, inspect_feed
from ingest.takegawara import ImportBlocked, connect_local_db

SNAPSHOT = Path(__file__).resolve().parents[1] / "sources" / "transport-pilot.json"
EXERCISE_DATES = (date(2026, 11, 8), date(2026, 11, 9), date(2026, 11, 23), date(2027, 10, 1), date(2027, 10, 11))


def source_document(connection, evidence):
    digest = evidence.get("sha256")
    policy = connection.execute("""
        select source.id, policy.id from ingest.source_registry source
        join ingest.source_policy_versions policy on policy.source_id = source.id
        join ingest.source_policy_urls allowed on allowed.policy_version_id = policy.id
        where source.source_key = %s and source.active and policy.version = 1
          and policy.revoked_at is null and policy.store_facts = 'allowed' and policy.archive_raw = 'denied'
          and allowed.source_url = %s and allowed.approved_content_sha256 is not distinct from %s
          and (allowed.approved_content_sha256 is null or policy.auto_fetch = 'allowed')
    """, (evidence["key"], evidence["url"], digest)).fetchone()
    if policy is None:
        raise ImportBlocked(f"Transport evidence is not approved: {evidence['key']}")
    source_id, policy_id = policy
    existing = connection.execute("""
        select id from ingest.source_documents where policy_version_id = %s and source_url = %s
            and content_sha256 is not distinct from %s
    """, (policy_id, evidence["url"], digest)).fetchone()
    if existing:
        return existing[0]
    run_id, = connection.execute("""
        insert into ingest.harvest_runs (source_id, policy_version_id, mode, status, finished_at)
        values (%s, %s, %s, 'succeeded', now()) returning id
    """, (source_id, policy_id, "file" if digest else "manual")).fetchone()
    return connection.execute("""
        insert into ingest.source_documents (run_id, policy_version_id, source_url, content_sha256, parser_version)
        values (%s, %s, %s, %s, 'transport-phase4-v1') returning id
    """, (run_id, policy_id, evidence["url"], digest)).fetchone()[0]


def bind_facility(connection, record, snapshot):
    identifier = uuid5(NAMESPACE_URL, snapshot["sources"][record["source"]]["url"])
    connection.execute("""
        insert into core.catalog_entities (id, kind, prefecture_code, municipality_code, name_ja, slug, review_state)
        values (%s, 'facility', %s, %s, %s, %s, 'in_review') on conflict (kind, slug) do nothing
    """, (identifier, record["prefecture"], record["municipality"], record["name"], record["slug"]))
    identifier, prefecture = connection.execute("""
        select id, prefecture_code from core.catalog_entities where kind = 'facility' and slug = %s
    """, (record["slug"],)).fetchone()
    if prefecture != record["prefecture"]:
        raise ImportBlocked(f"Facility belongs to another prefecture: {record['slug']}")
    connection.execute("""
        insert into core.facilities (entity_id, facility_type) values (%s, %s) on conflict (entity_id) do nothing
    """, (identifier, record["type"]))
    return identifier


def bind_nodes(connection, snapshot, documents, feed):
    hubs = {}
    for hub in snapshot["hubs"]:
        connection.execute("""
            insert into core.hub_cities (code, prefecture_code, name_ja) values (%s, %s, %s) on conflict (code) do nothing
        """, (hub["code"], hub["prefecture"], hub["name"]))
        hub_id, prefecture = connection.execute("select id, prefecture_code from core.hub_cities where code = %s",
                                                (hub["code"],)).fetchone()
        if prefecture != hub["prefecture"]:
            raise ImportBlocked(f"Hub belongs to another prefecture: {hub['code']}")
        hubs[hub["code"]] = hub_id
    facilities = {row["slug"]: bind_facility(connection, row, snapshot) for row in snapshot["facilities"]}
    nodes = {}
    for row in snapshot["nodes"]:
        hub_id = hubs.get(row.get("hub"))
        facility_id = facilities.get(row.get("facility"))
        stop_id = row.get("gtfs_stop_id")
        coordinates = feed["stops"][stop_id]["coordinates"] if stop_id else row.get("coordinates", (None, None))
        document_id = documents.get(row.get("source"))
        connection.execute("""
            insert into core.transport_nodes (code, hub_city_id, kind, name_ja, latitude, longitude, is_hub_candidate,
                facility_id, coordinate_source_document_id, coordinate_accuracy)
            values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s) on conflict (code) do nothing
        """, (row["code"], hub_id, row["kind"], row["name"], *coordinates, row.get("candidate", False),
              facility_id, document_id, row["accuracy"]))
        node_id, bound_hub, bound_kind, bound_facility, bound_source = connection.execute("""
            select id, hub_city_id, kind, facility_id, coordinate_source_document_id from core.transport_nodes where code = %s
        """, (row["code"],)).fetchone()
        if (bound_hub, bound_kind, bound_facility, bound_source) != (hub_id, row["kind"], facility_id, document_id):
            raise ImportBlocked(f"Transport node already has another identity or source: {row['code']}")
        nodes[row["code"]] = node_id
        if stop_id:
            connection.execute("""
                insert into ingest.gtfs_stop_links (feed_document_id, stop_id, transport_node_id) values (%s, %s, %s)
                on conflict (feed_document_id, stop_id) do nothing
            """, (documents["kamenoi_feed"], stop_id, node_id))
    return nodes, facilities


def route_legs(route, snapshot, feed):
    node_by_code = {node["code"]: node for node in snapshot["nodes"]}
    departure = route["from"]
    legs = []
    for leg in route["legs"]:
        if departure == leg["to"] or leg["to"] not in node_by_code:
            raise ImportBlocked(f"Disconnected transport leg in {route['key']}")
        leg = {**leg, "from": departure}
        if leg.get("gtfs"):
            if (node_by_code[departure].get("gtfs_stop_id"), node_by_code[leg["to"]].get("gtfs_stop_id")) != (BOARD, ALIGHT):
                raise ImportBlocked("The Beppu bus leg does not match the verified stop pair")
            leg.update(minutes=max(feed["ride_minutes"]), fare=feed["fare_jpy"],
                       notes="GTFSで確認した乗車時間の目安。時刻と運賃は最新の案内を確認。")
        legs.append(leg)
        departure = leg["to"]
    if not legs or not node_by_code[route["from"]].get("hub") or node_by_code[departure].get("facility") != route["facility"]:
        raise ImportBlocked(f"Route does not connect its hub to its facility: {route['key']}")
    return legs


def store_route(connection, route, legs, nodes, facilities, documents, snapshot, feed):
    departure, arrival = nodes[route["from"]], nodes[legs[-1]["to"]]
    facility_id = facilities[route["facility"]]
    feed_id = documents["kamenoi_feed"] if route.get("feed") else None
    fares = [leg.get("fare") for leg in legs]
    fare = sum(fares) if None not in fares else None
    inserted = connection.execute("""
        insert into core.routes (route_key, facility_id, departure_node_id, arrival_node_id, source_document_id,
            gtfs_feed_document_id, travel_mode, duration_minutes, fare_jpy, transfers, timetable_notes_ja,
            valid_from, valid_until, verified_at, review_state)
        values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
            %s::date::timestamp at time zone 'Asia/Tokyo', 'approved') on conflict (route_key) do nothing
    """, (route["key"], facility_id, departure, arrival, documents[route["source"]], feed_id, route["mode"],
          route.get("minutes"), fare, route["transfers"], route["notes"],
          feed["valid_from"] if feed_id else route.get("valid_from"), feed["valid_until"] if feed_id else None,
          snapshot["checked_on"])).rowcount
    identifier, bound_facility, bound_departure, bound_arrival, bound_feed = connection.execute("""
        select id, facility_id, departure_node_id, arrival_node_id, gtfs_feed_document_id
        from core.routes where route_key = %s
    """, (route["key"],)).fetchone()
    if (bound_facility, bound_departure, bound_arrival, bound_feed) != (facility_id, departure, arrival, feed_id):
        raise ImportBlocked(f"Route key already has other endpoints or feed: {route['key']}")
    for sequence, leg in enumerate(legs, 1):
        connection.execute("""
            insert into core.route_legs (route_id, seq, departure_node_id, arrival_node_id, mode, operator_name,
                service_name, duration_minutes, fare_jpy, reservation_required, notes_ja, source_document_id)
            values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) on conflict (route_id, seq) do nothing
        """, (identifier, sequence, nodes[leg["from"]], nodes[leg["to"]], leg["mode"], leg.get("operator"),
              leg.get("service"), leg.get("minutes"), leg.get("fare"), leg.get("reservation"), leg.get("notes"),
              documents[leg["source"]]))

    current = connection.execute("""
        select seq, departure_node_id, arrival_node_id, mode from core.route_legs where route_id = %s order by seq
    """, (identifier,)).fetchall()
    expected = [(sequence, nodes[leg["from"]], nodes[leg["to"]], leg["mode"]) for sequence, leg in enumerate(legs, 1)]
    if current != expected:
        raise ImportBlocked(f"Existing route leg chain differs: {route['key']}")

    sources = {route["source"], *(leg["source"] for leg in legs), *route.get("corroboration", ())}
    for source in sorted(sources):
        connection.execute("""
            insert into core.route_verification_sources (route_id, source_document_id) values (%s, %s) on conflict do nothing
        """, (identifier, documents[source]))
    return inserted


def apply_snapshot(connection, snapshot, feed):
    from psycopg.types.json import Jsonb

    routes = [(route, route_legs(route, snapshot, feed)) for route in snapshot["routes"]]
    with connection.transaction():
        connection.execute("select pg_advisory_xact_lock(179101, 4)")
        connection.execute("set local role onsen_ingestor")
        documents = {name: source_document(connection, entry) for name, entry in snapshot["sources"].items()}
        feed_id = documents["kamenoi_feed"]
        connection.execute("""
            insert into ingest.gtfs_feed_checks (source_document_id, feed_version, timezone, valid_from, valid_until,
                checked_on, stop_count, trip_count, validation)
            values (%s, %s, %s, %s, %s, %s, %s, %s, %s) on conflict (source_document_id) do nothing
        """, (feed_id, feed["feed_version"], feed["timezone"], feed["valid_from"], feed["valid_until"], snapshot["checked_on"],
              feed["stop_count"], feed["trip_count"], Jsonb({key: value for key, value in feed.items() if key != "checks"})))

        connection.execute("set local role onsen_reviewer")
        nodes, facilities = bind_nodes(connection, snapshot, documents, feed)
        for check in feed["checks"]:
            connection.execute("""
                insert into ingest.gtfs_service_day_checks (feed_document_id, board_stop_id, alight_stop_id, service_on,
                    status, eligible_trip_count, active_service_ids)
                values (%s, %s, %s, %s, %s, %s, %s) on conflict do nothing
            """, (feed_id, BOARD, ALIGHT, check["date"], check["status"], check["eligible_trip_count"], check["active_service_ids"]))
        return sum(store_route(connection, route, legs, nodes, facilities, documents, snapshot, feed) for route, legs in routes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gtfs", type=Path, required=True, help="Path to the approved Kamenoi ZIP")
    parser.add_argument("--on", type=date.fromisoformat, action="append", default=[], help="Add a service-date check (YYYY-MM-DD)")
    parser.add_argument("--apply", action="store_true", help="Write the verified snapshot to a loopback DB")
    args = parser.parse_args()
    try:
        snapshot = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
        check_dates = sorted(set(EXERCISE_DATES) | set(args.on))
        feed = inspect_feed(args.gtfs, snapshot["sources"]["kamenoi_feed"]["sha256"], check_dates)
        if args.apply:
            import psycopg

            try:
                with connect_local_db() as connection:
                    changed = apply_snapshot(connection, snapshot, feed)
            except psycopg.Error as error:
                print(f"Transport import failed at the database (SQLSTATE {error.sqlstate or 'unavailable'})", file=sys.stderr)
                return 1
            print(f"Transport snapshot verified. New routes: {changed}")
        print(json.dumps(feed, ensure_ascii=False, indent=2))
    except (ImportBlocked, OSError, ValueError, KeyError, ImportError) as error:
        print(f"Transport validation blocked: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
