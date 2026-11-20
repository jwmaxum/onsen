"""Validate the approved Kamenoi snapshot and the Beppu route 16 stop pair."""

import csv
import hashlib
from collections import defaultdict
from datetime import date
from decimal import Decimal
from io import BytesIO, TextIOWrapper
from zipfile import BadZipFile, ZipFile

from ingest.takegawara import ImportBlocked

BOARD = "100099 1"
ALIGHT = "235 2"
ROUTES = {"161", "162"}
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
MAX_ARCHIVE_BYTES = 5_000_000
MAX_EXPANDED_BYTES = 32_000_000


def csv_rows(archive, filename, fields):
    with TextIOWrapper(archive.open(filename), encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        headers = reader.fieldnames or []
        if len(headers) != len(set(headers)) or not set(fields) <= set(headers):
            raise ValueError(f"Invalid GTFS headers in {filename}")
        rows = list(reader)
    if any(None in row or None in row.values() for row in rows):
        raise ValueError(f"Malformed CSV row in {filename}")
    return rows


def index_rows(rows, key):
    result = {}
    for row in rows:
        identifier = row[key]
        if not identifier or identifier in result:
            raise ValueError(f"Missing or duplicate GTFS {key}")
        result[identifier] = row
    return result


def gtfs_date(value):
    if len(value) != 8 or not value.isascii() or not value.isdecimal():
        raise ValueError("Invalid GTFS date")
    return date.fromisoformat(value)


def service_day(on, valid_from, valid_until, calendars, exceptions, rides):
    result = {"date": on.isoformat(), "active_service_ids": [], "eligible_trip_count": None, "status": "out_of_range"}
    if not valid_from <= on <= valid_until:
        return result

    active = {service for service, (start, end, days) in calendars.items()
              if start <= on <= end and days[on.weekday()] == "1"}
    for service, change in exceptions.get(on, {}).items():
        if change == "1":
            active.add(service)
        else:
            active.discard(service)
    count = sum(len(rides.get(service, ())) for service in active)
    return {"date": on.isoformat(), "active_service_ids": sorted(active), "eligible_trip_count": count,
            "status": "service" if count else "no_service"}


def read_calendar(archive, trip_services):
    calendars = {}
    if "calendar.txt" in archive.namelist():
        required = ("service_id", "start_date", "end_date", *WEEKDAYS)
        for service, row in index_rows(csv_rows(archive, "calendar.txt", required), "service_id").items():
            start, end = gtfs_date(row["start_date"]), gtfs_date(row["end_date"])
            days = tuple(row[day] for day in WEEKDAYS)
            if start > end or not set(days) <= {"0", "1"}:
                raise ValueError("Invalid GTFS weekly calendar")
            calendars[service] = (start, end, days)

    exceptions = defaultdict(dict)
    if "calendar_dates.txt" in archive.namelist():
        for row in csv_rows(archive, "calendar_dates.txt", ("service_id", "date", "exception_type")):
            on, service, change = gtfs_date(row["date"]), row["service_id"], row["exception_type"]
            if not service or service in exceptions[on] or change not in {"1", "2"}:
                raise ValueError("Invalid or duplicate GTFS calendar exception")
            exceptions[on][service] = change
    known_services = set(calendars) | {service for changes in exceptions.values() for service in changes}
    if not trip_services <= known_services:
        raise ValueError("Trip references an unknown GTFS service")
    return calendars, exceptions


def gtfs_seconds(value):
    hour, minute, second = map(int, value.split(":"))
    if hour < 0 or not 0 <= minute < 60 or not 0 <= second < 60:
        raise ValueError("Invalid GTFS trip time")
    return hour * 3600 + minute * 60 + second


def ride_minutes(ordered_stop_times):
    departure = None
    for row in ordered_stop_times:
        if row["stop_id"] == BOARD and row.get("pickup_type", "") in {"", "0"}:
            departure = gtfs_seconds(row["departure_time"])
        if departure is not None and row["stop_id"] == ALIGHT and row.get("drop_off_type", "") in {"", "0"}:
            seconds = gtfs_seconds(row["arrival_time"]) - departure
            if seconds <= 0:
                raise ValueError("Non-positive GTFS ride duration")
            return (seconds + 59) // 60
    return None


def read_rides(rows, stops, trips):
    sequences = set()
    candidates = defaultdict(list)
    for row in rows:
        trip, stop, sequence = row["trip_id"], row["stop_id"], int(row["stop_sequence"])
        key = (trip, sequence)
        if trip not in trips or stop not in stops or sequence < 0 or key in sequences:
            raise ValueError("Invalid trip, stop or sequence reference in stop_times.txt")
        sequences.add(key)
        if trips[trip]["route_id"] in ROUTES and stop in {BOARD, ALIGHT}:
            candidates[trip].append((sequence, row))

    rides = defaultdict(list)
    for trip, calls in candidates.items():
        duration = ride_minutes(row for _, row in sorted(calls))
        if duration is not None:
            rides[trips[trip]["service_id"]].append(duration)
    return rides


def read_fare(archive, stops):
    if not {"fare_attributes.txt", "fare_rules.txt"} <= set(archive.namelist()):
        return None
    fares = index_rows(csv_rows(archive, "fare_attributes.txt", ("fare_id", "price", "currency_type")), "fare_id")
    rules = csv_rows(archive, "fare_rules.txt", ("fare_id", "route_id", "origin_id", "destination_id"))
    prices = set()
    for route in ROUTES:
        match = {row["fare_id"] for row in rules if row["route_id"] == route
                 and row["origin_id"] == stops[BOARD]["zone_id"] and row["destination_id"] == stops[ALIGHT]["zone_id"]}
        if len(match) != 1:
            return None
        fare = fares[next(iter(match))]
        price = Decimal(fare["price"])
        if fare["currency_type"] != "JPY" or price < 0 or price != price.to_integral_value():
            return None
        prices.add(int(price))
    return prices.pop() if len(prices) == 1 else None


def inspect_feed(path, expected_sha256, check_dates):
    try:
        with path.open("rb") as stream:
            content = stream.read(MAX_ARCHIVE_BYTES + 1)
        if len(content) > MAX_ARCHIVE_BYTES or hashlib.sha256(content).hexdigest() != expected_sha256:
            raise ImportBlocked("GTFS ZIP is larger than allowed or differs from the reviewed SHA-256")
        with ZipFile(BytesIO(content)) as archive:
            members = archive.infolist()
            if len(members) > 64 or len(members) != len(set(archive.namelist())) or sum(x.file_size for x in members) > MAX_EXPANDED_BYTES:
                raise ValueError("Unexpected GTFS ZIP size or duplicated members")
            return inspect_tables(archive, check_dates)
    except (BadZipFile, OSError, UnicodeError, KeyError, ValueError, ArithmeticError) as error:
        raise ImportBlocked(f"GTFS validation failed ({type(error).__name__}): {error}") from None


def inspect_tables(archive, check_dates):
    feed, = csv_rows(archive, "feed_info.txt", ("feed_start_date", "feed_end_date", "feed_version"))
    start, end = gtfs_date(feed["feed_start_date"]), gtfs_date(feed["feed_end_date"])
    timezone = {row["agency_timezone"] for row in csv_rows(archive, "agency.txt", ("agency_timezone",))}
    if start > end or not feed["feed_version"] or timezone != {"Asia/Tokyo"}:
        raise ValueError("Invalid Kamenoi feed validity or timezone")
    stops = index_rows(csv_rows(archive, "stops.txt", ("stop_id", "stop_name", "stop_lat", "stop_lon", "zone_id")), "stop_id")
    routes = index_rows(csv_rows(archive, "routes.txt", ("route_id", "route_short_name")), "route_id")
    trips = index_rows(csv_rows(archive, "trips.txt", ("trip_id", "route_id", "service_id")), "trip_id")
    if any(trip["route_id"] not in routes for trip in trips.values()) or any(routes[key]["route_short_name"] != "16" for key in ROUTES):
        raise ValueError("Unexpected route references for Kamenoi route 16")
    selected = {}
    for stop_id, expected_name in ((BOARD, "別府駅前"), (ALIGHT, "流川ゆめタウン前")):
        stop = stops[stop_id]
        lat, lon = Decimal(stop["stop_lat"]), Decimal(stop["stop_lon"])
        if stop["stop_name"] != expected_name or not -90 <= lat <= 90 or not -180 <= lon <= 180:
            raise ValueError("Approved GTFS stop name or coordinates do not match")
        selected[stop_id] = {"name": expected_name, "coordinates": [str(lat), str(lon)]}
    stop_times = csv_rows(archive, "stop_times.txt", ("trip_id", "stop_id", "stop_sequence", "arrival_time", "departure_time"))
    rides = read_rides(stop_times, stops, trips)
    if not rides:
        raise ValueError("No trip boards and alights at the approved stop pair in order")
    calendars, exceptions = read_calendar(archive, {trip["service_id"] for trip in trips.values()})
    durations = [value for service_rides in rides.values() for value in service_rides]
    return {
        "feed_version": feed["feed_version"], "timezone": "Asia/Tokyo", "valid_from": start.isoformat(), "valid_until": end.isoformat(),
        "stop_count": len(stops), "route_count": len(routes), "trip_count": len(trips), "stop_time_count": len(stop_times),
        "exception_count": sum(map(len, exceptions.values())),
        "exceptions_outside_feed": sum(len(changes) for on, changes in exceptions.items() if not start <= on <= end),
        "stops": selected, "route_ids": sorted(ROUTES), "ride_minutes": [min(durations), max(durations)],
        "fare_jpy": read_fare(archive, stops), "checks": [service_day(on, start, end, calendars, exceptions, rides) for on in check_dates],
    }
